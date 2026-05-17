#!/usr/bin/env python3
"""
Manual smoke test for the Sangeet AI Python Inference Daemon.
Validates subprocess lifecycle, UDS gRPC communication, analysis, restoration streams, and shutdown.
"""
import os
import subprocess
import sys
import time

import grpc
import numpy as np
import soundfile as sf

# 1. Setup path imports relative to script location
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
sys.path.insert(0, PROJECT_DIR)

from sangeet.v1 import restoration_pb2, restoration_pb2_grpc


def main() -> None:
    socket_path = os.path.expanduser("~/Library/Application Support/SangeetAI/inference.sock")
    in_file_path = os.path.abspath(os.path.join(SCRIPT_DIR, "smoke_input.wav"))
    out_file_path = os.path.abspath(os.path.join(SCRIPT_DIR, "smoke_output.wav"))

    # Cleanup any pre-existing socket or output files
    for path in [socket_path, in_file_path, out_file_path]:
        if os.path.exists(path):
            try:
                os.unlink(path)
            except Exception:
                pass

    print("=== Step 1: Spawning Daemon Subprocess ===")
    python_bin = sys.executable
    daemon_py = os.path.join(PROJECT_DIR, "sangeet_inference", "daemon.py")
    
    # Run daemon process with console pass-through to avoid PIPE buffer deadlocks
    daemon_process = subprocess.Popen(
        [python_bin, daemon_py]
    )
    print(f"Daemon process spawned with PID {daemon_process.pid}")

    # Wait for UDS socket file to be created by the daemon
    print("Waiting for UDS socket to bind...")
    for _ in range(50):
        if os.path.exists(socket_path):
            break
        time.sleep(0.1)
    else:
        print("Error: UDS socket was not created in time. Exiting.")
        daemon_process.terminate()
        sys.exit(1)
    print(f"Found active socket binding at: {socket_path}")

    # Connect client channel
    channel = grpc.insecure_channel(f"unix:{socket_path}")
    stub = restoration_pb2_grpc.RestorationServiceStub(channel)

    try:
        print("\n=== Step 2: Querying Capabilities ===")
        capabilities = stub.GetCapabilities(restoration_pb2.Empty())
        print(f"Daemon Version: {capabilities.daemon_version}")
        print(f"Supported Formats: {list(capabilities.supported_audio_formats)}")
        print(f"Requires Consent: {capabilities.requires_user_consent}")

        print("\n=== Step 3: Generating Test WAV (5s 440Hz Stereo Sine at 48kHz) ===")
        sr = 48000
        duration = 5.0
        num_samples = int(sr * duration)
        t = np.linspace(0, duration, num_samples, endpoint=False)
        # 440 Hz sine wave
        sine_wave = np.sin(2 * np.pi * 440.0 * t)
        # Combine channels first then transpose to [samples, channels] for soundfile write
        stereo_signal = np.column_stack((sine_wave, sine_wave)).astype(np.float32)
        sf.write(in_file_path, stereo_signal, sr)
        print(f"Wrote generated input file: {in_file_path}")

        print("\n=== Step 4: Invoking Audio Analysis ===")
        analysis_result = stub.AnalyzeAudio(restoration_pb2.AnalyzeRequest(input_path=in_file_path))
        features = analysis_result.features
        print(f"Parsed features: SR={features.sample_rate}, channels={features.channels}, duration={features.duration_s}s")
        print(f"Router suggested stages: {[s.stage_name for s in analysis_result.suggested_recipe.stages]}")

        print("\n=== Step 5: Invoking Restoration Stream ===")
        recipe = restoration_pb2.RestorationRecipe()
        recipe.stages.append(restoration_pb2.StageInvocation(stage_name="passthrough", strength=1.0))
        
        request = restoration_pb2.RestorationRequest(
            input_path=in_file_path,
            output_path=out_file_path,
            recipe=recipe
        )

        for progress in stub.StartRestoration(request):
            print(f"Restoration Progress: {progress.stage_name} -> {progress.percent_complete:.1f}%, elapsed={progress.elapsed_s:.2f}s")

        print("\n=== Step 6: Verifying Output Signal Integrity ===")
        assert os.path.exists(out_file_path), "Restoration output file was not written."
        
        in_data, in_sr = sf.read(in_file_path, dtype="float32")
        out_data, out_sr = sf.read(out_file_path, dtype="float32")
        
        assert in_sr == out_sr == 48000, f"Sample rates differ: in={in_sr}, out={out_sr}"
        assert in_data.shape == out_data.shape, f"Shapes differ: in={in_data.shape}, out={out_data.shape}"

        # Verify within -90 dB threshold
        atol_90db = 10 ** (-90 / 20)
        if np.allclose(out_data, in_data, rtol=0.0, atol=atol_90db):
            print("SUCCESS: Output equals input within the -90 dB bound.")
        else:
            print("FAILURE: Discrepancy between input and output exceeded -90 dB limit.")
            sys.exit(1)

        print("\n=== Step 7: Triggering Daemon Shutdown ===")
        stub.Shutdown(restoration_pb2.Empty())
        
        # Wait for daemon process to terminate
        print("Waiting for subprocess cleanup...")
        try:
            exit_code = daemon_process.wait(timeout=5)
            print(f"Daemon process exited cleanly with code: {exit_code}")
        except subprocess.TimeoutExpired:
            print("Warning: Daemon process did not exit within 5s grace period. Terminating.")
            daemon_process.terminate()

    except Exception as e:
        print(f"\n[ERROR] Smoke test encountered an exception: {e}")
        daemon_process.terminate()
        try:
            outs, errs = daemon_process.communicate(timeout=2)
            print("\n=== Daemon Subprocess STDOUT ===")
            print(outs)
            print("\n=== Daemon Subprocess STDERR ===")
            print(errs)
        except Exception as ex:
            print(f"Failed to read daemon outputs: {ex}")
        raise e

    finally:
        channel.close()
        # Clean up files
        for path in [in_file_path, out_file_path]:
            if os.path.exists(path):
                try:
                    os.unlink(path)
                except Exception:
                    pass
        print("\n=== Smoke Test Complete ===")

if __name__ == "__main__":
    main()
