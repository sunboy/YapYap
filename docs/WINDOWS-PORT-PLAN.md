# YapYap Windows Port: Architecture & Implementation Plan

## Executive Summary

This document outlines the plan to port YapYap from a native macOS (Swift + SwiftUI) app to Windows while maintaining feature parity: offline voice-to-text with AI-powered cleanup, context-aware formatting, and push-to-talk operation. The core challenge is replacing Apple-specific frameworks (CoreML, MLX, AVAudioEngine, Accessibility APIs, AppKit) with Windows equivalents while preserving the <3-second end-to-end latency target.

---

## 1. Framework Decision: Why Tauri 2.0 (Rust + Web Frontend)

### Options Evaluated

| Framework | Binary Size | Memory (Idle) | Win32 Access | ML FFI | Dev Speed | Future Cross-Platform |
|-----------|-------------|---------------|--------------|--------|-----------|----------------------|
| **Tauri 2.0 (Rust + React/Svelte)** | ~15-20 MB | ~50-80 MB | Excellent (windows-rs) | Zero-cost C FFI | High | Yes (Linux, macOS) |
| WinUI 3 / WPF (C#) | ~10-15 MB | ~60-100 MB | Native | P/Invoke (good) | High | No (Windows-only) |
| Electron (Node.js + Chromium) | ~100+ MB | ~200+ MB | Poor (native addons) | N-API overhead | Highest | Yes |
| Flutter (Dart) | ~20-30 MB | ~80-120 MB | Limited (FFI clunky) | Dart FFI overhead | Medium | Yes |
| Qt (C++) | ~30-50 MB | ~40-60 MB | Excellent | Native (same lang) | Low | Yes |
| Native C++ (Win32) | ~5-10 MB | ~30-50 MB | Native | Native | Very Low | No |

### Recommendation: Tauri 2.0

**Primary reasons:**

1. **Rust backend = near-C performance with memory safety.** The performance-critical path (audio capture, VAD, ML inference orchestration) runs in compiled Rust. Zero-cost FFI to whisper.cpp and llama.cpp (both C/C++) means no overhead calling ML inference.

2. **Small footprint matches YapYap's ethos.** Tauri uses the OS webview (WebView2 on Windows, pre-installed on Windows 10/11) instead of bundling Chromium. Binary size ~15-20 MB vs Electron's 100+ MB. Idle memory ~50-80 MB vs Electron's 200+ MB.

3. **Built-in native features.** Tauri 2.0 provides system tray, global shortcuts, window management (borderless/floating/always-on-top), file system access, and auto-updater out of the box. These map directly to YapYap's needs.

4. **Web frontend is fast to develop.** The UI layer (settings panel, popover, floating bar, creature animation) is straightforward to build with React/Svelte + Tailwind CSS. CSS animations can replicate the creature movements. The UI is NOT the performance bottleneck.

5. **Future cross-platform potential.** Tauri 2.0 supports Windows, macOS, and Linux from a single codebase. If we want to unify the codebase later, the Rust backend + web frontend architecture enables that. The macOS Swift version could eventually be replaced.

6. **Strong Windows ecosystem in Rust.** The `windows-rs` crate provides safe bindings to the entire Win32 API surface. WASAPI audio, UIAutomation, SendInput, RegisterHotKey -- all accessible with type-safe Rust wrappers.

### Why NOT the alternatives

- **Electron**: Too heavy. 200+ MB memory idle is unacceptable for a utility app that runs in the background. The Chromium process model adds latency to IPC between the renderer and native code.

- **WinUI 3 / WPF (C#)**: Excellent Windows integration, but locks us into Windows forever. C# garbage collector introduces unpredictable pauses (bad for real-time audio). P/Invoke to whisper.cpp/llama.cpp works but adds marshaling overhead vs Rust's zero-cost FFI.

- **Flutter**: Windows support is mature but FFI to C libraries requires Dart FFI bindings that are clunky. No built-in system tray or global hotkey support. Would need platform channel plugins for most native features.

- **Qt**: Great performance and cross-platform, but the Qt licensing model (LGPL/commercial) adds complexity. C++ development velocity is lower than Rust + web frontend. UI development in QML/Widgets is slower than web technologies.

- **Swift on Windows**: Experimental, limited tooling, no AppKit equivalent, tiny community. Not viable for production.

---

## 2. Architecture Overview

```
+-------------------------------------------------------------------+
|                        YapYap Windows                              |
|                                                                    |
|  +--------------------+     +----------------------------------+   |
|  |   Web Frontend     |     |        Rust Backend              |   |
|  |   (Tauri WebView)  |     |                                  |   |
|  |                    |     |  +----------------------------+  |   |
|  |  - Settings UI     |<--->|  | Pipeline Orchestrator      |  |   |
|  |  - Floating Bar    |IPC  |  | (same logic as macOS)      |  |   |
|  |  - Popover Menu    |     |  +----------------------------+  |   |
|  |  - Creature Anim   |     |       |         |         |      |   |
|  |  - History View    |     |  +----v--+ +----v---+ +---v---+  |   |
|  |  - Onboarding      |     |  | Audio | | STT    | | LLM   |  |   |
|  |                    |     |  | WASAPI| |whisper |  |llama  |  |   |
|  +--------------------+     |  |       | |.cpp   | |.cpp   |  |   |
|                              |  +-------+ +-------+ +-------+  |   |
|                              |       |                    |      |   |
|                              |  +----v--------+  +-------v---+  |   |
|                              |  | VAD Filter  |  | Context   |  |   |
|                              |  | (Silero/    |  | Detector  |  |   |
|                              |  |  energy)    |  | (Win32)   |  |   |
|                              |  +-------------+  +-----------+  |   |
|                              |                                  |   |
|                              |  +----------------------------+  |   |
|                              |  | Paste Manager              |  |   |
|                              |  | (SendInput + Clipboard)    |  |   |
|                              |  +----------------------------+  |   |
|                              |                                  |   |
|                              |  +----------------------------+  |   |
|                              |  | System Integration         |  |   |
|                              |  | - Tray Icon (built-in)     |  |   |
|                              |  | - Global Hotkey            |  |   |
|                              |  | - Auto-updater             |  |   |
|                              |  +----------------------------+  |   |
|                              +----------------------------------+   |
|                                                                    |
|  +--------------------------------------------------------------+  |
|  |                    SQLite (rusqlite)                          |  |
|  |  Settings | History | Analytics | Personal Dictionary        |  |
|  +--------------------------------------------------------------+  |
+-------------------------------------------------------------------+
```

### Component Mapping: macOS -> Windows

| Component | macOS (Current) | Windows (Planned) |
|-----------|-----------------|-------------------|
| **Language** | Swift | Rust (backend) + TypeScript (frontend) |
| **UI Framework** | SwiftUI + AppKit | Tauri WebView + React/Svelte |
| **Audio Capture** | AVAudioEngine | WASAPI (via `windows-rs` or `cpal` crate) |
| **Audio Format** | AVAudioPCMBuffer | Raw f32 PCM buffers |
| **Mic Permission** | AVCaptureDevice.requestAccess | Windows Settings prompt (automatic on first use) |
| **Device Enumeration** | CoreAudio kAudioHardwarePropertyDevices | IMMDeviceEnumerator (WASAPI) |
| **VAD** | Energy-based (CPU) | Same algorithm, Rust port (trivial) |
| **STT Engine** | WhisperKit (CoreML) / whisper.cpp | whisper.cpp only (via `whisper-rs` crate) |
| **LLM Engine** | MLX Swift / llama.cpp | llama.cpp only (via `llama-cpp-rs` crate) |
| **GPU Acceleration** | Metal (Apple Silicon) | CUDA (NVIDIA) / Vulkan (AMD/Intel) / CPU fallback |
| **Hotkey** | KeyboardShortcuts package | RegisterHotKey Win32 API |
| **System Tray** | NSStatusItem | Tauri system tray plugin (wraps Shell_NotifyIcon) |
| **Floating Window** | NSPanel (non-activating) | Tauri window: decorations=false, always_on_top=true, skip_taskbar=true, focusable=false |
| **Popover** | NSPopover | Tauri window anchored to tray icon position |
| **Text Injection** | AXUIElement + CGEvent Cmd+V | UIAutomation + SendInput Ctrl+V |
| **Clipboard** | NSPasteboard | Win32 Clipboard API (SetClipboardData) |
| **App Detection** | NSWorkspace.frontmostApplication | GetForegroundWindow + GetWindowText + GetModuleFileNameEx |
| **Selected Text** | SelectedTextKit (Accessibility) | UIAutomation ITextPattern |
| **Window Title** | AXUIElement getWindowTitle | GetWindowText Win32 |
| **Data Storage** | SwiftData (SQLite) | rusqlite (SQLite) |
| **Auto-Update** | Sparkle | Tauri updater plugin |
| **Launch at Login** | LaunchAtLogin package | Registry HKCU\Software\Microsoft\Windows\CurrentVersion\Run |
| **Crash Reporting** | Sentry (Swift) | Sentry (Rust) -- `sentry` crate |

---

## 3. Performance Analysis & Windows Considerations

### 3.1 ML Inference Performance

**The critical question: Can we match macOS Apple Silicon performance on Windows?**

On macOS (Apple Silicon M1+):
- WhisperKit (CoreML, ANE): ~0.3-0.5s for 10s of audio
- MLX (Metal GPU): ~200-500 tok/s for 1-3B models

On Windows, the story depends heavily on hardware:

**whisper.cpp performance (Windows):**

| Hardware | 10s Audio | Engine |
|----------|-----------|--------|
| NVIDIA RTX 3060+ (CUDA) | ~0.3-0.5s | whisper.cpp + cuBLAS |
| NVIDIA RTX 4060+ (CUDA) | ~0.2-0.3s | whisper.cpp + cuBLAS |
| AMD RX 7600+ (Vulkan) | ~0.5-0.8s | whisper.cpp + Vulkan |
| Intel Arc A770 (SYCL) | ~0.6-1.0s | whisper.cpp + SYCL |
| CPU-only (i7-12700+) | ~1.5-3.0s | whisper.cpp + OpenBLAS |
| CPU-only (Ryzen 7 5800X+) | ~1.5-2.5s | whisper.cpp + OpenBLAS |

**llama.cpp performance (Windows, 4-bit quantized):**

| Hardware | Qwen 1.5B Q4 | Qwen 3B Q4 | Engine |
|----------|---------------|-------------|--------|
| NVIDIA RTX 3060+ | ~400-600 tok/s | ~200-350 tok/s | CUDA |
| NVIDIA RTX 4060+ | ~600-900 tok/s | ~350-500 tok/s | CUDA |
| AMD RX 7600+ | ~200-400 tok/s | ~100-200 tok/s | Vulkan |
| CPU (i7-12700+) | ~80-150 tok/s | ~40-80 tok/s | AVX2 |
| CPU (Ryzen 7 5800X+) | ~100-180 tok/s | ~50-100 tok/s | AVX2 |

**Key takeaway:** With a discrete GPU (NVIDIA), Windows can match or exceed Apple Silicon performance. Without a GPU, CPU-only inference is 2-5x slower. The app MUST support CPU-only mode since many Windows users don't have discrete GPUs.

### 3.2 Latency Budget (3-Second Target)

```
macOS:   VAD(50ms) + STT(400ms) + LLM(200ms) + Paste(50ms) = ~700ms
Windows (GPU):  VAD(50ms) + STT(500ms) + LLM(250ms) + Paste(100ms) = ~900ms
Windows (CPU):  VAD(50ms) + STT(2000ms) + LLM(800ms) + Paste(100ms) = ~2950ms
```

CPU-only is tight but achievable with optimizations:
- Use Whisper Small or Medium instead of Large for CPU-only users
- Use Qwen 1.5B (smallest LLM) as default for CPU-only
- Consider offering a "fast mode" that skips LLM cleanup on CPU-only systems
- Pre-warm models aggressively (same strategy as macOS)

### 3.3 Memory Considerations

Windows users have more varied RAM configurations than Mac users:

| Config | Recommendation |
|--------|---------------|
| 8 GB RAM | Whisper Small + Qwen 1.5B Q4 (~1.5 GB total) |
| 16 GB RAM | Whisper Medium + Qwen 3B Q4 (~2.5 GB total) |
| 32+ GB RAM | Whisper Large + Qwen 7B Q4 (~5 GB total) |

The app should detect available RAM and recommend appropriate models during onboarding. On macOS, Apple Silicon's unified memory makes this simpler; on Windows, we need to handle discrete GPU VRAM vs system RAM separately.

### 3.4 GPU Backend Strategy

Unlike macOS (Metal-only), Windows has multiple GPU compute backends:

```
                    +-------------------+
                    |   YapYap Windows  |
                    +--------+----------+
                             |
                    +--------v----------+
                    | whisper.cpp /      |
                    | llama.cpp          |
                    +--------+----------+
                             |
              +--------------+--------------+
              |              |              |
        +-----v-----+ +-----v-----+ +------v------+
        |   CUDA    | |  Vulkan   | |    CPU      |
        | (NVIDIA)  | | (AMD/Intel| | (AVX2/AVX512|
        |           | |  /NVIDIA) | |  fallback)  |
        +-----------+ +-----------+ +-------------+
```

**Build strategy:** Ship pre-built binaries for each backend:
- `yapyap-cuda.exe` -- For NVIDIA GPU users (best performance)
- `yapyap-vulkan.exe` -- For AMD/Intel GPU users
- `yapyap.exe` -- CPU-only fallback (always works)

Or better: single binary that detects GPU at runtime and loads the appropriate backend dynamically (whisper.cpp and llama.cpp both support this via shared library loading).

### 3.5 Windows-Specific Limitations

1. **No Neural Engine equivalent.** Apple's ANE provides dedicated ML inference hardware. Windows PCs rely on GPU (CUDA/Vulkan) or CPU. No equivalent to the ANE's power efficiency.

2. **Audio latency.** WASAPI in exclusive mode provides ~3ms latency (comparable to CoreAudio). Shared mode adds ~10-30ms. Use shared mode (exclusive mode would lock out other apps).

3. **Text injection reliability.** SendInput (Windows equivalent of CGEvent) can be blocked by:
   - UAC-elevated windows (admin apps)
   - Games with anti-cheat
   - Some security software
   - UWP apps with input restrictions

   Mitigation: Fall back to clipboard + WM_PASTE message if SendInput fails.

4. **Global hotkey conflicts.** RegisterHotKey is system-wide but first-come-first-served. If another app registers the same hotkey, we lose. Need a fallback hotkey and clear error messaging.

5. **No unified memory.** On Apple Silicon, the GPU and CPU share the same memory pool. On Windows, models must be loaded into GPU VRAM separately. A 3B model needs ~2 GB VRAM. If VRAM is insufficient, fall back to CPU.

6. **Background process management.** Windows more aggressively kills background processes under memory pressure. The app needs to handle graceful degradation when models are evicted.

7. **Antivirus interference.** Some antivirus software flags apps that use SendInput, clipboard injection, or low-level keyboard hooks. We may need to code-sign the binary and work with major AV vendors for whitelisting.

---

## 4. Detailed Component Design

### 4.1 Audio Capture (Rust + WASAPI)

Replace `AudioCaptureManager.swift` with a Rust module using the `cpal` crate (cross-platform audio I/O) or raw WASAPI via `windows-rs`.

```
Recommendation: Use `cpal` crate
- Cross-platform (useful if we unify codebase later)
- Abstracts WASAPI on Windows, CoreAudio on macOS, ALSA on Linux
- Supports device enumeration, format negotiation, real-time capture
- Well-maintained, used by many Rust audio projects
```

Key implementation details:
- Capture at native sample rate, resample to 16kHz mono in software
- Use `rubato` crate for high-quality resampling
- Ring buffer for accumulating audio chunks (same pattern as macOS)
- Device hot-plug detection via WASAPI device notifications

### 4.2 VAD (Voice Activity Detection)

The macOS version uses energy-based VAD (simple RMS threshold). This is pure math -- no platform dependencies. Direct Rust port.

Optionally integrate Silero VAD via ONNX Runtime (`ort` crate) for better accuracy. The ONNX model is ~2 MB and runs on CPU with negligible latency.

### 4.3 STT Engine (whisper.cpp)

Use `whisper-rs` crate (Rust bindings to whisper.cpp). This is the same engine already supported on macOS via `WhisperCppEngine.swift`.

Model format: GGML (same `.bin` files, cross-platform).

GPU acceleration:
- CUDA: Link against cuBLAS at build time
- Vulkan: Use Vulkan compute shaders (whisper.cpp supports this)
- CPU: AVX2/AVX-512 SIMD (automatic via compiler flags)

Model download: Same HuggingFace Hub URLs. Store in `%APPDATA%\YapYap\models\`.

### 4.4 LLM Engine (llama.cpp)

Use `llama-cpp-rs` crate (Rust bindings to llama.cpp).

Model format: GGUF (quantized, cross-platform). Same Qwen/Llama/Gemma models.

The prompt building logic (`CleanupPromptBuilder`) is entirely platform-agnostic -- it's just string construction based on app context. This can be ported line-for-line from Swift to Rust.

### 4.5 App Context Detection (Win32 API)

Replace `AppContextDetector.swift` with Win32 API calls:

```rust
// Get foreground window
let hwnd = unsafe { GetForegroundWindow() };

// Get window title
let mut title = [0u16; 256];
unsafe { GetWindowTextW(hwnd, &mut title) };

// Get process name
let mut pid = 0u32;
unsafe { GetWindowThreadProcessId(hwnd, &mut pid) };
let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
let mut path = [0u16; MAX_PATH];
QueryFullProcessImageNameW(process, 0, &mut path, &mut len);
```

**App classification mapping:**
- macOS uses bundle identifiers (e.g., `com.apple.iChat`)
- Windows uses executable names (e.g., `slack.exe`, `outlook.exe`, `code.exe`)
- Maintain a mapping table: `exe name -> app category`
- Browser tab detection: parse window title (most browsers show tab title in window title)

### 4.6 Text Injection / Paste Manager

Replace `PasteManager.swift` with two strategies:

**Strategy 1: Clipboard + SendInput (primary)**
```rust
// 1. Save current clipboard
// 2. Set cleaned text to clipboard
// 3. Simulate Ctrl+V
let inputs = [
    INPUT { ki: KEYBDINPUT { wVk: VK_CONTROL, dwFlags: 0 } },
    INPUT { ki: KEYBDINPUT { wVk: 0x56 /* V */, dwFlags: 0 } },
    INPUT { ki: KEYBDINPUT { wVk: 0x56, dwFlags: KEYEVENTF_KEYUP } },
    INPUT { ki: KEYBDINPUT { wVk: VK_CONTROL, dwFlags: KEYEVENTF_KEYUP } },
];
SendInput(&inputs);
// 4. Restore original clipboard after short delay
```

**Strategy 2: UIAutomation (fallback)**
```rust
// Use IUIAutomation to find focused text element
// Set value directly via IValueProvider::SetValue
```

### 4.7 Global Hotkeys

Tauri 2.0 has a built-in global shortcut plugin (`@tauri-apps/plugin-global-shortcut`). Use this rather than raw Win32 API.

Default bindings:
- macOS: Option+Space (push-to-talk), Option+Shift+Space (hands-free)
- Windows: Alt+Space (push-to-talk), Alt+Shift+Space (hands-free)

Note: Alt+Space conflicts with the Windows system menu (window move/resize/close). We may need a different default, such as:
- Ctrl+Shift+Space (push-to-talk)
- Ctrl+Shift+S (hands-free)
- Or let the user pick during onboarding

### 4.8 System Tray & Floating Window

**System Tray:** Tauri's built-in tray plugin. Shows the YapYap creature icon. Click opens a popover-style window anchored near the tray.

**Floating Bar:** A Tauri window configured as:
```json
{
  "label": "floating-bar",
  "decorations": false,
  "alwaysOnTop": true,
  "skipTaskbar": true,
  "focusable": false,
  "transparent": true,
  "width": 300,
  "height": 60
}
```

This matches the macOS NSPanel behavior: always visible, never steals focus, borderless.

### 4.9 UI Layer (React or Svelte)

The UI is the least performance-critical component. Recommend **Svelte** for its small bundle size and reactive simplicity, but React works too.

Key views to implement:
1. **Floating Bar**: Waveform visualization + creature animation + status text
2. **Tray Popover**: Quick actions, last transcription preview, settings shortcut
3. **Settings Window**: Tabbed settings (General, Models, Style, History, Advanced)
4. **Onboarding Flow**: Permission requests, model download, hotkey setup
5. **Creature Animation**: SVG-based with CSS animations (replaces SwiftUI animation modifiers)

### 4.10 Data Persistence

Use `rusqlite` crate (Rust SQLite bindings). Same schema as macOS SwiftData models:

- `app_settings` -- User preferences
- `transcription_history` -- Raw + cleaned text, metadata
- `daily_stats` -- Usage analytics (local only)
- `personal_dictionary` -- Auto-learned corrections
- `voice_snippets` -- Template expansion

Storage location: `%APPDATA%\YapYap\yapyap.db`

### 4.11 Auto-Updater

Tauri's built-in updater plugin. Ships update manifests as JSON on GitHub Releases. Supports differential updates (binary patching) to minimize download size.

### 4.12 Installer & Distribution

- **Installer**: NSIS or WiX via `tauri-bundler` (built into Tauri CLI)
- **Portable**: Also offer a portable `.zip` (no install required)
- **Distribution**: GitHub Releases + winget package
- **Code signing**: Required for Windows SmartScreen trust. Use a code signing certificate (EV cert removes SmartScreen warning entirely).

---

## 5. Project Structure

```
yapyap-windows/
├── src-tauri/                          # Rust backend
│   ├── Cargo.toml                      # Rust dependencies
│   ├── src/
│   │   ├── main.rs                     # Tauri app entry point
│   │   ├── pipeline/
│   │   │   ├── mod.rs                  # Pipeline orchestrator
│   │   │   ├── audio_capture.rs        # WASAPI/cpal audio capture
│   │   │   ├── vad.rs                  # Voice activity detection
│   │   │   ├── resampler.rs            # Audio resampling (16kHz mono)
│   │   │   └── buffer.rs              # Ring buffer for audio chunks
│   │   ├── stt/
│   │   │   ├── mod.rs                  # STT engine trait + factory
│   │   │   ├── whisper_engine.rs       # whisper.cpp wrapper
│   │   │   └── model_registry.rs       # Available STT models
│   │   ├── llm/
│   │   │   ├── mod.rs                  # LLM engine trait + factory
│   │   │   ├── llama_engine.rs         # llama.cpp wrapper
│   │   │   ├── model_registry.rs       # Available LLM models
│   │   │   ├── prompt_builder.rs       # Context-aware prompt construction
│   │   │   └── output_formatter.rs     # Deterministic post-processing
│   │   ├── context/
│   │   │   ├── mod.rs                  # App context detection
│   │   │   ├── app_detector.rs         # Win32 foreground app detection
│   │   │   ├── app_classifier.rs       # Exe name -> category mapping
│   │   │   └── browser_detector.rs     # Browser tab classification
│   │   ├── paste/
│   │   │   ├── mod.rs                  # Paste strategy selector
│   │   │   ├── clipboard.rs            # Win32 clipboard operations
│   │   │   ├── send_input.rs           # SendInput Ctrl+V injection
│   │   │   └── ui_automation.rs        # UIAutomation fallback
│   │   ├── system/
│   │   │   ├── hotkey.rs               # Global hotkey management
│   │   │   ├── tray.rs                 # System tray setup
│   │   │   ├── autostart.rs            # Launch at login (registry)
│   │   │   └── permissions.rs          # Permission checks
│   │   ├── data/
│   │   │   ├── database.rs             # SQLite via rusqlite
│   │   │   ├── settings.rs             # App settings model
│   │   │   ├── history.rs              # Transcription history model
│   │   │   └── dictionary.rs           # Personal dictionary
│   │   ├── models/
│   │   │   └── downloader.rs           # HuggingFace model download
│   │   └── commands.rs                 # Tauri IPC command handlers
│   ├── build.rs                        # Build script (link whisper.cpp, llama.cpp)
│   └── tauri.conf.json                 # Tauri configuration
│
├── src/                                # Web frontend (Svelte/React)
│   ├── App.svelte                      # Root component
│   ├── lib/
│   │   ├── stores/                     # Reactive state (Svelte stores)
│   │   ├── components/
│   │   │   ├── FloatingBar.svelte      # Recording UI with waveform
│   │   │   ├── TrayPopover.svelte      # Quick actions popover
│   │   │   ├── Creature.svelte         # Animated creature (SVG + CSS)
│   │   │   ├── Waveform.svelte         # Audio waveform visualization
│   │   │   └── ModelProgress.svelte    # Download progress indicator
│   │   ├── pages/
│   │   │   ├── Settings.svelte         # Settings window (tabbed)
│   │   │   ├── Onboarding.svelte       # First-run setup wizard
│   │   │   └── History.svelte          # Transcription history
│   │   └── utils/
│   │       └── ipc.ts                  # Tauri IPC helpers
│   ├── styles/                         # Tailwind CSS
│   └── assets/                         # Icons, sounds, creature SVG
│
├── package.json                        # Frontend dependencies
├── vite.config.ts                      # Vite bundler config
├── tailwind.config.js                  # Tailwind config
└── README.md
```

---

## 6. Rust Dependencies (Cargo.toml)

```toml
[dependencies]
# Tauri framework
tauri = { version = "2", features = ["tray-icon", "image-png"] }
tauri-plugin-global-shortcut = "2"
tauri-plugin-updater = "2"
tauri-plugin-shell = "2"

# Audio
cpal = "0.15"           # Cross-platform audio I/O (WASAPI on Windows)
rubato = "0.15"         # Audio resampling

# ML inference
whisper-rs = "0.12"     # whisper.cpp Rust bindings
llama-cpp-rs = "0.4"    # llama.cpp Rust bindings

# Windows APIs
windows = { version = "0.58", features = [
    "Win32_UI_WindowsAndMessaging",
    "Win32_UI_Accessibility",
    "Win32_UI_Input_KeyboardAndMouse",
    "Win32_System_Threading",
    "Win32_Foundation",
    "Win32_Graphics_Gdi",
] }

# Data
rusqlite = { version = "0.32", features = ["bundled"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Utilities
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.12", features = ["stream"] }   # Model downloads
indicatif = "0.17"                                        # Progress bars (CLI)
sentry = "0.34"                                           # Crash reporting
log = "0.4"
env_logger = "0.11"
```

---

## 7. Migration Strategy: What Can Be Reused

### Direct Logic Port (platform-agnostic, translate Swift -> Rust)
These modules contain pure business logic with no platform dependencies:

| macOS File | Windows Equivalent | Effort |
|---|---|---|
| `CleanupPromptBuilder.swift` | `prompt_builder.rs` | Low -- string logic only |
| `CleanupPromptBuilder+Categories.swift` | Same file | Low |
| `CleanupPromptBuilder+SmallModel.swift` | Same file | Low |
| `OutputFormatter.swift` | `output_formatter.rs` | Low -- regex + string ops |
| `StyleSettings.swift` | `settings.rs` (partial) | Low |
| `STTModelRegistry.swift` | `stt/model_registry.rs` | Low -- data declarations |
| `LLMModelRegistry.swift` | `llm/model_registry.rs` | Low -- data declarations |
| `GGUFModelRegistry.swift` | Merged into above | Low |
| `VADManager.swift` (energy VAD) | `vad.rs` | Low -- pure math |
| `TranscriptionPipeline.swift` | `pipeline/mod.rs` | Medium -- orchestration logic is same, API calls differ |
| `FillerFilter.swift` | Part of `output_formatter.rs` | Low -- regex |

### Must Rewrite (platform-specific)

| macOS File | Windows Equivalent | Effort |
|---|---|---|
| `AudioCaptureManager.swift` | `audio_capture.rs` (WASAPI/cpal) | Medium |
| `PasteManager.swift` | `paste/mod.rs` (SendInput + Clipboard) | Medium-High |
| `AppContextDetector.swift` | `context/app_detector.rs` (Win32) | Medium |
| `Permissions.swift` | `permissions.rs` (Win32) | Low |
| `HotkeyManager.swift` | Tauri plugin (minimal code) | Low |
| `StatusBarController.swift` | Tauri tray config | Low |
| `FloatingBarPanel.swift` | Tauri window config + Svelte component | Medium |
| All SwiftUI views | Svelte/React components | Medium-High |
| `WhisperKitEngine.swift` | Not needed (whisper.cpp only) | N/A |
| `MLXEngine.swift` | Not needed (llama.cpp only) | N/A |
| `DataManager.swift` (SwiftData) | `database.rs` (rusqlite) | Medium |

### Can Drop Entirely

| macOS Component | Reason |
|---|---|
| WhisperKit / CoreML | Replaced by whisper.cpp |
| MLX Swift / Metal | Replaced by llama.cpp |
| FluidAudio / Parakeet CoreML | Replaced by whisper.cpp (or ONNX Parakeet if desired) |
| Sparkle (auto-updater) | Replaced by Tauri updater |
| LaunchAtLogin | Replaced by registry write |
| KeyboardShortcuts | Replaced by Tauri global shortcut plugin |
| SelectedTextKit | Replaced by UIAutomation |
| HapticManager | Windows has no haptic feedback for desktop |
| SoundManager (NSSound) | Replace with web Audio API or rodio crate |

---

## 8. Implementation Phases

### Phase 1: Foundation (Weeks 1-3)
- [ ] Set up Tauri 2.0 project scaffold
- [ ] Implement audio capture with cpal/WASAPI
- [ ] Port VAD (energy-based) to Rust
- [ ] Integrate whisper.cpp via whisper-rs
- [ ] Basic CLI test: record -> VAD -> transcribe -> print
- [ ] System tray icon with basic menu

### Phase 2: LLM & Pipeline (Weeks 4-5)
- [ ] Integrate llama.cpp via llama-cpp-rs
- [ ] Port CleanupPromptBuilder logic to Rust
- [ ] Port OutputFormatter to Rust
- [ ] Wire up full pipeline: audio -> VAD -> STT -> LLM -> output
- [ ] Model download manager (HuggingFace)

### Phase 3: System Integration (Weeks 6-7)
- [ ] Implement paste manager (SendInput + Clipboard)
- [ ] App context detection (Win32 foreground window)
- [ ] App classification mapping (exe -> category)
- [ ] Global hotkey registration (push-to-talk)
- [ ] SQLite persistence layer

### Phase 4: UI (Weeks 8-10)
- [ ] Floating bar with waveform and creature animation
- [ ] Tray popover with quick actions
- [ ] Settings window (all tabs)
- [ ] Onboarding flow (permissions, model download, hotkey setup)
- [ ] History view

### Phase 5: Polish & Release (Weeks 11-12)
- [ ] GPU backend detection and auto-selection
- [ ] Model recommendation based on hardware
- [ ] Auto-updater configuration
- [ ] NSIS/WiX installer
- [ ] Code signing
- [ ] Performance profiling and optimization
- [ ] Beta testing

---

## 9. Open Questions & Decisions Needed

1. **Default hotkey.** Alt+Space conflicts with Windows system menu. What should the default be? Ctrl+Shift+Space?

2. **GPU backend shipping.** Ship separate builds (CUDA, Vulkan, CPU) or single binary with runtime detection? Runtime detection is better UX but more complex to build.

3. **Minimum Windows version.** Windows 10 21H2+ (WebView2 pre-installed) or Windows 11 only? Recommend Windows 10 21H2+ for maximum reach.

4. **Code sharing with macOS.** Keep Windows as a fully separate codebase (Rust) or explore sharing core logic? Separate codebase is simpler to start; unification can come later.

5. **Parakeet on Windows.** Port Parakeet via ONNX Runtime for ANE-less but still-fast inference? Or just use whisper.cpp for all STT on Windows? Whisper.cpp is simpler; Parakeet ONNX would require additional work but could be faster on CPU.

6. **Frontend framework.** Svelte (smaller bundle, simpler reactivity) vs React (larger ecosystem, more developers know it). Recommend Svelte for this project's scope.

---

## 10. Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| CPU-only performance too slow | High | Medium | Default to smaller models; offer "skip cleanup" mode |
| Antivirus blocks SendInput/hotkeys | High | Medium | Code signing; AV vendor outreach; document exceptions |
| WASAPI audio capture issues on some hardware | Medium | Low | cpal handles edge cases; fallback to DirectSound |
| WebView2 not installed (old Win10) | Medium | Low | Bundle WebView2 bootstrapper in installer |
| whisper.cpp quality differs from WhisperKit | Medium | Low | Same underlying Whisper models; quality should be identical |
| Memory pressure on 8 GB machines | Medium | Medium | Aggressive model size recommendations; unload when idle |
| Global hotkey conflicts | Low | Medium | Let user customize; detect conflicts at registration |

---

## 11. Summary

The Windows port is achievable with **Tauri 2.0 (Rust + Svelte)** as the framework. The core ML inference shifts from Apple-specific frameworks (CoreML, MLX, Metal) to cross-platform alternatives (whisper.cpp, llama.cpp) that are already partially integrated in the macOS codebase. The business logic (prompt building, output formatting, VAD, model registries) is platform-agnostic and can be ported line-for-line.

The main engineering challenges are:
1. **Text injection reliability** on Windows (SendInput limitations)
2. **GPU backend diversity** (CUDA vs Vulkan vs CPU, unlike macOS's Metal-only)
3. **Performance on CPU-only machines** (no Apple Silicon unified memory advantage)

Estimated total effort: **10-12 weeks** for a single developer, **6-8 weeks** for two developers working in parallel (one on Rust backend, one on Svelte frontend).
