"""
Sangeet AI Python Inference Daemon.
Manages the gRPC server lifecycle, receives incoming commands, and orchestrates pipeline execution.
"""
import os
import queue
import signal
import sys
import threading
import time
import uuid
from collections.abc import Iterator
from concurrent import futures
from typing import Any

import grpc
import structlog
import torch

# Ensure the parent and proto generated folders are resolved correctly on direct execution
SELF_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.abspath(os.path.join(SELF_DIR, ".."))
PROTO_DIR = os.path.join(SELF_DIR, "proto")

for d in [PARENT_DIR, PROTO_DIR]:
    if d not in sys.path:
        sys.path.insert(0, d)

from sangeet.v1 import restoration_pb2, restoration_pb2_grpc

from sangeet_inference.features import extract_audio_features
from sangeet_inference.logging_setup import configure_logging
from sangeet_inference.pipeline import RestorationPipeline
from sangeet_inference.router import route_features

logger = structlog.get_logger()

class SangeetRestorationServicer(restoration_pb2_grpc.RestorationServiceServicer):
    """
    gRPC Servicer implementing the RestorationService contract.
    Coordinates audio analysis, restoration tasks, progress updates, and graceful cancellations.
    """

    def __init__(self) -> None:
        self.pipeline = RestorationPipeline()
        self.active_jobs: dict[str, threading.Event] = {}
        self.lock = threading.Lock()

    def GetCapabilities(
        self,
        request: restoration_pb2.Empty,
        context: grpc.ServicerContext
    ) -> restoration_pb2.Capabilities:
        """
        Retrieves daemon versions, hardware acceleration status, and capabilities.
        """
        logger.info("GetCapabilities called")
        return restoration_pb2.Capabilities(
            daemon_version="0.1.0",
            supported_audio_formats=["WAV", "FLAC", "MP3", "M4A"],
            mps_available=torch.backends.mps.is_available(),
            requires_user_consent=False
        )

    def ListModels(
        self,
        request: restoration_pb2.Empty,
        context: grpc.ServicerContext
    ) -> restoration_pb2.ModelList:
        """
        Lists all available local ML models and their statuses.
        """
        logger.info("ListModels called")
        models = [
            restoration_pb2.Model(
                name="passthrough",
                version="1.0.0",
                status="LOADED",
                sha256=""
            ),
            restoration_pb2.Model(
                name="deep_filter_net",
                version="0.5.6",
                status="LOADED",
                sha256=""
            )
        ]
        return restoration_pb2.ModelList(models=models)

    def PrepareModels(
        self,
        request: restoration_pb2.PrepareRequest,
        context: grpc.ServicerContext
    ) -> Iterator[restoration_pb2.PrepareProgress]:
        """
        Simulates preparing/downloading ML models. Passthrough is loaded instantly.
        """
        logger.info("PrepareModels called", model_names=list(request.model_names))
        for model in request.model_names:
            yield restoration_pb2.PrepareProgress(
                model_name=model,
                percent_complete=100.0,
                status="LOADED"
            )

    def AnalyzeAudio(
        self,
        request: restoration_pb2.AnalyzeRequest,
        context: grpc.ServicerContext
    ) -> restoration_pb2.AnalysisResult:
        """
        Extracts structural features and returns a tailored restoration recipe.
        """
        logger.info("AnalyzeAudio called", input_path=request.input_path)
        try:
            features = extract_audio_features(request.input_path)
            recipe = route_features(features)
            return restoration_pb2.AnalysisResult(
                features=features,
                suggested_recipe=recipe
            )
        except FileNotFoundError as e:
            logger.error("AnalyzeAudio failed: file not found", input_path=request.input_path)
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details(str(e))
            raise
        except Exception as e:
            logger.error("AnalyzeAudio failed with internal error", input_path=request.input_path, error=str(e))
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Internal analysis failure: {e}")
            raise

    def StartRestoration(
        self,
        request: restoration_pb2.RestorationRequest,
        context: grpc.ServicerContext
    ) -> Iterator[restoration_pb2.RestorationProgress]:
        """
        Orchestrates an audio restoration job inside a background thread,
        streaming progress reports throttled to at least 500ms intervals.
        """
        request_id = str(uuid.uuid4())
        structlog.contextvars.bind_contextvars(request_id=request_id)
        
        logger.info(
            "StartRestoration job initialized",
            input_path=request.input_path,
            output_path=request.output_path
        )

        cancel_event = threading.Event()
        with self.lock:
            self.active_jobs[request_id] = cancel_event

        # Safe client stream termination handler
        context.add_callback(lambda: cancel_event.set())

        q: queue.Queue = queue.Queue()
        start_time = time.time()
        
        # Throttling state
        last_emitted_time = 0.0

        def progress_callback(stage_name: str, percent_complete: float) -> None:
            nonlocal last_emitted_time
            current_time = time.time()
            # Enforce throttling: emit if >= 500ms elapsed since last emit, or exactly finished (100.0%)
            if (current_time - last_emitted_time) >= 0.5 or percent_complete >= 100.0:
                elapsed = current_time - start_time
                # Estimate simple linear ETA
                eta = None
                if percent_complete > 0:
                    eta = (elapsed / (percent_complete / 100.0)) - elapsed

                progress_update = restoration_pb2.RestorationProgress(
                    request_id=request_id,
                    stage_name=stage_name,
                    percent_complete=percent_complete,
                    elapsed_s=elapsed,
                    eta_s=eta
                )
                q.put(progress_update)
                last_emitted_time = current_time

        def run_pipeline() -> None:
            try:
                self.pipeline.process_audio(
                    input_path=request.input_path,
                    output_path=request.output_path,
                    recipe=request.recipe,
                    cancel_event=cancel_event,
                    progress_callback=progress_callback,
                    request_id=request_id
                )
                # Indicate successful pipeline completion
                q.put(None)
            except Exception as e:
                # Propagate the error through the queue
                q.put(e)

        # Execute restoration pipeline inside a separate worker thread
        t = threading.Thread(target=run_pipeline)
        t.start()

        try:
            # Yield progress values as they accumulate
            while t.is_alive() or not q.empty():
                if not context.is_active():
                    logger.info("Client aborted restoration stream connection")
                    cancel_event.set()
                    break

                try:
                    # Timeout periodically to assess if the gRPC context remains alive
                    msg = q.get(timeout=0.1)
                    if msg is None:
                        # Success complete
                        break
                    elif isinstance(msg, Exception):
                        # Propagate background exception to gRPC client
                        logger.error("Restoration task thread raised exception", error=str(msg))
                        context.set_code(grpc.StatusCode.INTERNAL)
                        context.set_details(f"Restoration failed: {msg}")
                        raise msg
                    else:
                        yield msg
                except queue.Empty:
                    continue
        finally:
            t.join()
            with self.lock:
                self.active_jobs.pop(request_id, None)
            structlog.contextvars.clear_contextvars()
            logger.info("StartRestoration job ended", request_id=request_id)

    def CancelJob(
        self,
        request: restoration_pb2.JobId,
        context: grpc.ServicerContext
    ) -> restoration_pb2.Empty:
        """
        Manually cancels a running task.
        """
        job_id = request.job_id
        logger.info("CancelJob called", target_job_id=job_id)
        
        with self.lock:
            if job_id in self.active_jobs:
                self.active_jobs[job_id].set()
                logger.info("Job cancellation flag set successfully", job_id=job_id)
                return restoration_pb2.Empty()
            logger.warning("CancelJob failed: active job not found", job_id=job_id)
            context.set_code(grpc.StatusCode.NOT_FOUND)
            context.set_details(f"No active job found with ID: {job_id}")
            raise KeyError(f"Job {job_id} not found")

    def Shutdown(
        self,
        request: restoration_pb2.Empty,
        context: grpc.ServicerContext
    ) -> restoration_pb2.Empty:
        """
        Gracefully terminates the daemon server.
        """
        logger.info("Shutdown RPC invoked. Preparing to terminate daemon.")

        # Set cancellation flag for all running jobs
        with self.lock:
            for _job_id, event in self.active_jobs.items():
                event.set()

        def trigger_exit() -> None:
            time.sleep(0.5)
            logger.info("Process terminating gracefully now.")
            os._exit(0)

        # Launch process killer in background so RPC successfully returns Empty response first
        threading.Thread(target=trigger_exit).start()
        return restoration_pb2.Empty()

def main() -> None:
    """
    Launches Sangeet AI inference daemon, binds UDS port, and sets signal handlers.
    """
    configure_logging(verbose=False)
    logger.info("Initializing Sangeet AI Inference Daemon", python_version=sys.version)

    # 1. Resolve socket path and ensure directories are present
    socket_path = os.path.expanduser("~/Library/Application Support/SangeetAI/inference.sock")
    if "--socket" in sys.argv:
        try:
            idx = sys.argv.index("--socket")
            if idx + 1 < len(sys.argv):
                socket_path = os.path.abspath(os.path.expanduser(sys.argv[idx + 1]))
        except Exception as e:
            logger.warning("Failed to parse --socket option", error=str(e))

    socket_dir = os.path.dirname(socket_path)
    os.makedirs(socket_dir, exist_ok=True)

    # 2. Safely remove pre-existing UDS socket file
    if os.path.exists(socket_path):
        try:
            os.unlink(socket_path)
            logger.info("Unlinked stale UDS socket file", socket_path=socket_path)
        except Exception as e:
            logger.error("Failed to remove stale socket file", socket_path=socket_path, error=str(e))
            sys.exit(1)

    # 3. Instantiate gRPC server
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    servicer = SangeetRestorationServicer()
    restoration_pb2_grpc.add_RestorationServiceServicer_to_server(servicer, server)

    # Bind UDS socket
    server.add_insecure_port(f"unix:{socket_path}")
    logger.info("gRPC server added insecure port", uds_path=socket_path)

    # Set up signal handlers for graceful cancellation
    def handle_signal(signum: int, frame: Any) -> None:
        logger.info("Received termination signal. Shutting down Sangeet AI server.", signum=signum)
        # Terminate all active jobs
        with servicer.lock:
            for _job_id, event in servicer.active_jobs.items():
                event.set()
        
        # Stop gRPC server with 5s grace and wait for thread termination
        stop_event = server.stop(5.0)
        stop_event.wait()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    # Start the server
    server.start()
    logger.info("Sangeet AI Inference Daemon successfully started")

    # Tighten file permissions on UDS socket
    try:
        os.chmod(socket_path, 0o700)
        logger.debug("Socket permissions set to 0700")
    except Exception as e:
        logger.warning("Failed to tighten socket permissions", error=str(e))

    # Keep server thread alive
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        logger.info("KeyboardInterrupt detected. Shutting down.")
        server.stop(0)

if __name__ == "__main__":
    main()
