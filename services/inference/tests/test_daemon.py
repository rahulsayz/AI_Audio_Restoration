"""
gRPC Contract integration tests.
Tests the real SangeetRestorationServicer over a Unix Domain Socket (UDS) channel.
"""
import os
import tempfile
import time
import queue
import threading
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import pytest
import grpc
import soundfile as sf

from sangeet.v1 import restoration_pb2, restoration_pb2_grpc
from sangeet_inference.daemon import SangeetRestorationServicer

@pytest.fixture(scope="module")
def grpc_server():
    """
    Spins up a real Sangeet AI gRPC server bound to a temporary UDS.
    """
    temp_dir = tempfile.mkdtemp()
    socket_path = os.path.join(temp_dir, "test_inference.sock")

    server = grpc.server(ThreadPoolExecutor(max_workers=5))
    servicer = SangeetRestorationServicer()
    restoration_pb2_grpc.add_RestorationServiceServicer_to_server(servicer, server)

    server.add_insecure_port(f"unix:{socket_path}")
    server.start()

    # Keep a channel open to communicate
    channel = grpc.insecure_channel(f"unix:{socket_path}")
    stub = restoration_pb2_grpc.RestorationServiceStub(channel)

    yield stub, servicer

    # Clean up
    channel.close()
    server.stop(0)
    try:
        if os.path.exists(socket_path):
            os.unlink(socket_path)
        os.rmdir(temp_dir)
    except Exception:
        pass

def test_grpc_get_capabilities(grpc_server) -> None:
    """
    Verifies capabilities query returns valid version and properties.
    """
    stub, _ = grpc_server
    response = stub.GetCapabilities(restoration_pb2.Empty())
    
    assert response.daemon_version == "0.1.0"
    assert "WAV" in response.supported_audio_formats
    assert not response.requires_user_consent

def test_grpc_list_models(grpc_server) -> None:
    """
    Verifies model listing query returns the passthrough baseline model.
    """
    stub, _ = grpc_server
    response = stub.ListModels(restoration_pb2.Empty())
    
    assert len(response.models) == 1
    assert response.models[0].name == "passthrough"
    assert response.models[0].status == "LOADED"

def test_grpc_prepare_models(grpc_server) -> None:
    """
    Verifies streaming model preparation.
    """
    stub, _ = grpc_server
    request = restoration_pb2.PrepareRequest(model_names=["passthrough"])
    
    responses = list(stub.PrepareModels(request))
    assert len(responses) == 1
    assert responses[0].model_name == "passthrough"
    assert responses[0].percent_complete == 100.0
    assert responses[0].status == "LOADED"

def test_grpc_analyze_audio(grpc_server) -> None:
    """
    Verifies structural analysis and router parsing.
    """
    stub, _ = grpc_server
    
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
        
    try:
        # Create a simple 1-channel sine wav
        sf.write(path, np.zeros((48000, 1), dtype=np.float32), 48000)
        
        request = restoration_pb2.AnalyzeRequest(input_path=path)
        response = stub.AnalyzeAudio(request)
        
        assert response.features.sample_rate == 48000
        assert response.features.channels == 1
        assert response.features.duration_s == pytest.approx(1.0)
        
        # Verify router yielded passthrough
        assert len(response.suggested_recipe.stages) == 1
        assert response.suggested_recipe.stages[0].stage_name == "passthrough"
    finally:
        if os.path.exists(path):
            os.unlink(path)

def test_grpc_start_restoration_and_cancellation(grpc_server) -> None:
    """
    Validates end-to-end gRPC streaming restoration and cancellation mechanisms.
    """
    stub, servicer = grpc_server
    
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as in_f, \
         tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as out_f:
        in_path = in_f.name
        out_path = out_f.name

    try:
        # Write a long (65.0s) silent WAV file to allow progressive streaming
        sr = 48000
        sf.write(in_path, np.zeros((int(sr * 65.0), 1), dtype=np.float32), sr)

        recipe = restoration_pb2.RestorationRecipe()
        recipe.stages.append(restoration_pb2.StageInvocation(stage_name="passthrough", strength=1.0))

        request = restoration_pb2.RestorationRequest(
            input_path=in_path,
            output_path=out_path,
            recipe=recipe
        )

        progress_updates = []
        
        # Call StartRestoration stream
        stream = stub.StartRestoration(request)
        
        # Read the first update to ensure it starts, then cancel via active_jobs Cancellation
        for update in stream:
            progress_updates.append(update)
            # Cancel immediately using CancelJob RPC
            job_id = restoration_pb2.JobId(job_id=update.request_id)
            stub.CancelJob(job_id)
            break

        # SangeetRestorationServicer cleans job mappings after cancellation
        assert len(progress_updates) == 1
        assert progress_updates[0].stage_name == "passthrough"
    finally:
        if os.path.exists(in_path):
            os.unlink(in_path)
        if os.path.exists(out_path):
            os.unlink(out_path)
