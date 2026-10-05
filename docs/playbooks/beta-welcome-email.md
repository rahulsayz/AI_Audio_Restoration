# Sangeet AI Beta Welcome Email Template

*   **Subject**: Testing Sangeet AI: Read this first
*   **From**: Rahul Chaturvedi (rahul@sangeet.app)
*   **To**: (Beta Tester Email)
*   **Format**: Plain Text or Basic Markdown (No marketing HTML headers or tracking pixel fluff)

---

Hi there,

Thanks for joining the Sangeet AI private beta. You are one of exactly 30 Indian music collectors and archivists who have early access to this build. 

If you are like me, you are tired of modern "restoration" tools that flatten the gorgeous, distinct signatures of Indian recordings. Standard software classifies sitar resonance as noise, dampens the sharp transient attack of a tabla sam, and aggressively "warms up" classical vocals that were intentionally recorded close-miked and nasal. Sangeet is our labor of love to change this.

Sangeet runs 100% locally on your Mac. Your audio files and filenames never leave your device.

Here is what you need to know before you start.

### 1. Download and Install
1. Download the beta DMG from your private link: `[YOUR_PERSONAL_SIGNED_URL]`
2. Open the DMG and drag **Sangeet AI** to your `/Applications` folder.
3. Launch it. On first launch, Sangeet will walk you through a brief 5-screen tour.

### 2. Try the Samples First
Inside the onboarding tour, we have pre-loaded three short, highly degraded archival reference tracks (a 1957 Mohammed Rafi vocal segment, a Pandit Ravi Shankar sitar performance, and a 1972 RD Burman film orchestra segment). 

Select one, click "Restore", and watch the progress bar. Once it finishes, hit Play, toggle the **Original** and **Restored** buttons back and forth, and turn on **Volume Matching** to hear the exact spectral corrections at identical volume levels. This is the magic moment.

### 3. What to Expect (and What Will Break)
This is a Phase 1 release. The code is fast, but it is early.
*   **Daemon Crashing**: If you feed Sangeet an extremely large WAV file (longer than 20 minutes) or a very weird audio format, the localized Python inference daemon might crash. If this happens, Sangeet will show a dialog asking to restart the engine.
*   **Unusual Artifacts**: If a recording is heavily clipped, the bandwidth extension model (NVSR) might hallucinate harmonics that sound slightly metallic. If you hear this, please turn the bandwidth extension slider down in the settings or report it to us.

### 4. How to Report Bugs and Send Feedback
We want Sangeet to be perfect for historical Indian music. If a restoration smears a transient or introduces digital phase artifacts, tell me.

*   In the bottom-left corner of the sidebar, you will see a persistent **Feedback** button.
*   Click it to open the native feedback form.
*   Check the box to **"Attach last restoration audio + analysis YAML"**. This matches your system diagnostic state and the processed audio file so our team can immediately inspect the spectral breakdown.
*   Click **Send**. Sangeet will package and route it directly to my inbox at `beta@sangeet.app`. 
*   If you are offline, Sangeet will queue it and sync automatically the next time you connect.

We are pair-programming this product together. Thank you for your ears, your catalog, and your time.

Best,

Rahul Chaturvedi
Founder, Sangeet AI
rahul@sangeet.app
