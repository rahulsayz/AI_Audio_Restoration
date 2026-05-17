# Playbook: Manual End-to-End Restoration Pipeline Test

This playbook guides you through verifying the complete **Sangeet AI** "walking skeleton" pipeline. We will start the background Python inference daemon manually, launch our SwiftUI application, drop a test audio file, trigger restoration, and verify the gRPC plumbing end-to-end.

---

## 1. Prerequisites

Before starting, ensure that you have initialized the Python virtual environment and successfully built the gRPC stubs:
```bash
# From the project root, compile the protobuf stubs
make proto
```

---

## 2. Step-by-Step Execution

### Step 1: Start the Background Python Daemon (Terminal 1)
Open a terminal, navigate to the `services/inference/` directory, activate your Python virtual environment, and launch the gRPC daemon manually.

```bash
cd services/inference
# Activate your environment (e.g. .venv or poetry shell)
source .venv/bin/activate

# Launch the daemon
python -m sangeet_inference.daemon
```

#### Expected Output
You should see structurally logged messages indicating that the gRPC server is successfully running and bound to the local Unix Domain Socket (UDS) file:
```json
{"event": "Starting gRPC server on unix:///Users/rahulchaturvedi/Library/Application Support/SangeetAI/inference.sock", "level": "info", "timestamp": "2026-05-17T08:20:00Z"}
{"event": "gRPC server started successfully", "level": "info", "timestamp": "2026-05-17T08:20:00Z"}
```

---

### Step 2: Generate a Test Sine Signal (Optional)
If you don't have a test audio signal ready in `eval/corpus/test_signals/sine_440hz.wav`, you can quickly generate a 5-second 440 Hz sine wave using this Python one-liner:

```bash
python -c "import numpy as np, soundfile as sf; t = np.linspace(0, 5, 48000 * 5, endpoint=False); s = np.sin(2 * np.pi * 440 * t).astype(np.float32); sf.write('sine_440hz.wav', s, 48000)"
```
*Note: Keep this file in a convenient location (like your Desktop or `eval/corpus/`) for the drag-and-drop step.*

---

### Step 3: Launch the SwiftUI Application (Terminal 2)
In a new terminal window, open our pre-configured Xcode project:

```bash
open apps/macos/SangeetAI.xcodeproj
```

#### Verification in Xcode
1. Press `Cmd + <` (or navigate to **Product** > **Scheme** > **Edit Scheme...**).
2. Ensure **Run (Debug)** is selected on the left.
3. Click the **Arguments** tab and verify under **Environment Variables** that `SANGEET_DAEMON_PATH` is checked and points to your dev daemon location:
   - **Name**: `SANGEET_DAEMON_PATH`
   - **Value**: `/Users/rahulchaturvedi/AI_Audio_Restoration/services/inference/dist/sangeet-inference`
4. Press `Cmd + R` to compile and run the application.

*A beautiful space-dark glassmorphic window titled **SANGEET AI** will open at a fixed size of `800x600`.*

---

### Step 4: Drop the Audio File & Verify Metadata
1. Locate your generated `sine_440hz.wav` in Finder.
2. Drag the file and hover over the dashed drop zone area inside the Sangeet AI window. 
3. *Observe: The drop zone border glows in neon-teal as you drag over it.*
4. Drop the file.

#### Expected UI Feedback
The drop zone will disappear and instantly animate into a metadata card showing:
- **File Name**: `sine_440hz.wav`
- **Duration**: `0:05`
- **Sample Rate**: `48.0 kHz`

---

### Step 5: Click "Restore" & Monitor Progress
Click the saffron-gold **Restore Audio** button.

#### Expected Pipeline Lifecycle
1. The app will state: `"Initializing audio engine..."` as it communicates via UDS.
2. The UI will update to: `"Analyzing audio signal..."`.
3. The progress bar will transition through `"Deepfilternet 3"` as the server processes chunks.
4. Terminal 1 (Daemon logs) will print gRPC status stream logs showing receipt of the restoration payload and processing stages.
5. On completion, the progress bar will fill to `100%` and show: `"Restoration complete"`.

---

### Step 6: Verify Output File Creation
1. Under **Completion Actions**, click the **Show in Finder** button.
2. Finder will open and automatically highlight the newly created sibling file:
   - `sine_440hz-restored.wav` (located in the same directory as your input file).

---

### Step 7: QuickLook Waveform Verification
1. Click the highlighted `sine_440hz-restored.wav` in Finder.
2. Press the **Spacebar** to trigger **QuickLook**.
3. Confirm that the audio player loads successfully and that the waveform signature is present, clean, and matches the original sine wave structure!
