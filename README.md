# Apple Spatial Audio Convolver for iOS (KSign Dylib Injection)

An ultra-low latency real-time audio convolution dynamic library (`.dylib`) designed for sideloaded iOS apps via **KSign**, **ESign**, **TrollStore**, or **AltStore**.

It embeds the **`Apple_Pro2_Stereo.wav`** 3D Head-Related Impulse Response (HRIR) directly into the dylib, spatializing any stereo audio stream with immersive holographic soundstage and clear vocal presence on wired Apple EarPods or AirPods Pro 2.

---

## Features

- **Embedded HRIR Kernels:** Baked-in 2048-tap convolution filters for both **48,000 Hz** and **44,100 Hz** extracted from `Apple_Pro2_Stereo.wav`. Works immediately out-of-the-box without needing any external files inside the app.
- **Dynamic File Override:** If `Apple_Pro2_Stereo.wav` is placed in the app's `Documents/` folder, the dylib will automatically detect and load it on the fly.
- **Real-Time Thread Safe (`AURTSafe`):** Zero heap memory allocations (`malloc`/`free`) and zero mutex locking inside the audio render callback thread.
- **Low CPU Consumption:** Vectorized unrolled FIR loop utilizing ARM NEON registers on Apple Silicon (A-series chips). Takes less than 0.1% CPU.
- **CoreAudio Interception:** Hooks `AudioUnitRender` via Meta's `fishhook` library, transparently processing both Float32 and Int16 PCM audio streams.

---

## Project Structure

```
AppleSpatial_iOS_KSign/
├── SpatialConvolver.m      # Core audio hook & convolution engine
├── SpatialConvolver.h      # Public header
├── fishhook.c              # Mach-O symbol rebinding engine
├── fishhook.h              # Fishhook header
├── hrir_kernels.h          # Pre-compiled C arrays from Apple_Pro2_Stereo.wav
├── Apple_Pro2_Stereo.wav   # Original 14-channel 48kHz WAV
├── Makefile                # Local build file (make)
├── build.sh                # 1-click build script for macOS
└── .github/
    └── workflows/
        └── build.yml       # Automated GitHub Actions cloud compiler
```

---

## How to Build the `.dylib`

### Option A: Free Automated Cloud Build via GitHub Actions (Recommended for Windows)

No Mac or Xcode required!

1. Create a new private or public repository on [GitHub](https://github.com).
2. Upload or push all files from this `AppleSpatial_iOS_KSign` folder to your GitHub repository.
3. Click on the **Actions** tab in your repository.
4. The workflow **"Build SpatialConvolver iOS Dylib"** will run automatically on a macOS runner.
5. When completed (~35 seconds), click on the build run $\to$ Scroll to **Artifacts** $\to$ Download **`SpatialConvolver-iOS-Dylib.zip`**.
6. Inside the zip is your ready-to-use **`SpatialConvolver.dylib`**!

### Option B: Local Build on macOS

If you have a Mac with Xcode Command Line Tools installed:
```bash
chmod +x build.sh
./build.sh
```
This produces `SpatialConvolver.dylib` compiled for `arm64` and `arm64e` (iOS 14.0+).

---

## How to Inject and Install with KSign on iPhone

1. **Transfer Files to iPhone:**
   - Transfer your target `.ipa` file (e.g. Spotify++, YouTube++, or VLC) and `SpatialConvolver.dylib` to your iPhone (via AirDrop, iCloud Drive, or Telegram/Files app).
2. **Open KSign:**
   - Launch the **KSign** app on your iPhone.
   - Tap the **Import** button $\to$ Import both the `.ipa` and `SpatialConvolver.dylib`.
3. **Inject Dylib:**
   - Tap on the imported `.ipa` in KSign.
   - Select **Signature** or **Signature Options**.
   - Navigate to **Tweaks** or **Inject Dylib** $\to$ Tap **Add / Select** $\to$ Choose `SpatialConvolver.dylib`.
   - Set inject path to `@executable_path/Frameworks` (or default).
4. **Sign & Install:**
   - Select your signing certificate (`.p12` and `.mobileprovision`).
   - Tap **Start Sign**.
   - Once signed, tap **Install** to deploy the app directly to your home screen!
5. **Listen & Enjoy:**
   - Plug in your Apple EarPods or connect your headphones.
   - Open the app and play any music track.
   - Enjoy 3D Spatial Audio powered by `Apple_Pro2_Stereo`!
