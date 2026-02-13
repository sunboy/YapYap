# YapYap — Agent Task Breakdown

> Ordered implementation plan for a Claude agent team.
> Each task is self-contained with clear inputs, outputs, and acceptance criteria.
> Agents should work on tasks in order (dependencies are sequential).

---

## Phase 0: Project Scaffold

### Task 0.1 — Xcode Project Setup
**Agent**: Infrastructure
**Priority**: P0 (blocking everything)

**Actions:**
1. Create new Xcode project: macOS App, SwiftUI lifecycle
   - Product name: `YapYap`
   - Bundle ID: `dev.yapyap.app`
   - Deployment target: macOS 14.0 (Sonoma)
   - Language: Swift, Interface: SwiftUI
2. Add Swift Package Dependencies:
   ```
   WhisperKit: https://github.com/argmaxinc/WhisperKit.git (from: "0.9.0")
   FluidAudio: https://github.com/FluidInference/FluidAudio.git (from: "0.7.9")
   mlx-swift: https://github.com/ml-explore/mlx-swift.git (from: "0.21.0")
   mlx-swift-lm: https://github.com/ml-explore/mlx-swift-lm.git (from: "0.2.0")
   KeyboardShortcuts: https://github.com/sindresorhus/KeyboardShortcuts.git (from: "2.0.0")
   LaunchAtLogin: https://github.com/sindresorhus/LaunchAtLogin-Modern.git (from: "1.0.0")
   Sparkle: https://github.com/sparkle-project/Sparkle.git (from: "2.0.0")
   SelectedTextKit: https://github.com/tisfeng/SelectedTextKit.git (from: "0.3.0")
   ```
3. Create folder structure matching `00-ARCHITECTURE.md` Section 9
4. Add entitlements file per Section 10
5. Add .gitignore (Xcode standard + Models/ directory)
6. Create Makefile with build/run/test/archive targets
7. Verify project builds clean (empty app)

**Output**: Buildable Xcode project with all dependencies resolved
**Acceptance**: `xcodebuild build` succeeds with zero warnings

---

## Phase 1: Core Data Layer

### Task 1.1 — SwiftData Models
**Agent**: Data
**Priority**: P0

**Actions:**
1. Create all `@Model` classes per Architecture Section 7:
   - `Transcription.swift`
   - `AppSettings.swift` (with sensible defaults)
   - `PowerModeRule.swift`
   - `CustomDictionaryEntry.swift`
   - `DailyStats.swift`
2. Create `DataManager.swift`:
   - Configure `ModelContainer` with all models
   - Singleton access pattern for shared container
   - Migration handling (future-proof)
3. Create `AnalyticsTracker.swift`:
   - `recordTranscription(wordCount:, duration:)` method
   - Aggregates into `DailyStats` by date
   - `getStatsForWeek()`, `getTotalStats()` queries

**Output**: Complete data layer with CRUD operations
**Acceptance**: Unit tests pass for all model operations

---

## Phase 2: App Shell & Menu Bar

### Task 2.1 — App Lifecycle & Menu Bar Icon
**Agent**: UI-Core
**Priority**: P0

**Actions:**
1. Configure `YapYapApp.swift`:
   - `@main` SwiftUI App
   - `.menuBarExtra` modifier OR custom `NSApplicationDelegate` approach
   - Hide dock icon: `LSUIElement = YES` in Info.plist
   - Initialize SwiftData container
2. Create `AppState.swift` (ObservableObject):
   ```swift
   @Observable
   class AppState {
       var creatureState: CreatureState = .sleeping
       var isRecording: Bool = false
       var isProcessing: Bool = false
       var masterToggle: Bool = true
       var currentRMS: Float = 0.0
       var lastTranscription: String?
   }
   ```
3. Create `StatusBarController.swift`:
   - Setup `NSStatusItem` with custom button
   - 22×22pt button frame
   - Left click → toggle popover
   - Right click → context menu (Quit, Settings)
4. Create `CreatureState.swift` enum:
   ```swift
   enum CreatureState {
       case sleeping, recording, processing
   }
   ```

**Output**: App launches to menu bar only (no dock icon), shows static creature icon
**Acceptance**: App appears in menu bar, can be right-clicked to quit

### Task 2.2 — Creature SVG Rendering & Animation
**Agent**: UI-Animation
**Priority**: P1

**Actions:**
1. Create `CreatureView.swift`:
   - SwiftUI view that renders the creature using `Path` / `Shape` primitives
   - Body: ellipse (body) + circle (head) + ear ellipses
   - Eyes: parametric — closed curves for sleeping, circles+highlights for awake
   - Blush: ellipses at cheek positions, opacity animated
   - All proportions relative to container size (works at 18pt, 32pt, 72pt)
2. Create `CreatureAnimations.swift`:
   - `.sleeping`: breathing (scaleY), head drift (rotation), floating z's
   - `.recording`: pulse rings (2 expanding circles), blush fade-in
   - `.processing`: spinner ring, slight head tilt
3. Create `MenuBarCreatureView.swift` (NSView subclass for menu bar):
   - Hosts SwiftUI `CreatureView` via `NSHostingView`
   - 18×18pt rendering
   - Updates based on `AppState.creatureState`

**Output**: Animated creature in menu bar that transitions between 3 states
**Acceptance**: Call `appState.creatureState = .recording` → creature animates to recording with pulse rings

### Task 2.3 — Popover (Layer 2)
**Agent**: UI-Popover
**Priority**: P1

**Actions:**
1. Create `PopoverView.swift` (SwiftUI):
   - Header: creature (32pt) + "YapYap" + status + master toggle
   - Last transcription card (2-line clamp, tap to copy)
   - Stats row (3-column: today count, time saved, words)
   - Quick settings rows (STT model, LLM model, Language, Auto-paste toggle)
   - Footer (Settings, Quit)
2. Wire popover to `NSPopover`:
   - Width: 300pt, height auto
   - `.transient` behavior
   - Show/hide on status item click
3. Implement quick model switching:
   - Tapping model row → inline picker or submenu
   - Updates `AppSettings` immediately

**Output**: Fully functional popover matching mockup
**Acceptance**: All interactive elements work, data flows to/from AppSettings

---

## Phase 3: Settings Window

### Task 3.1 — Settings Window Shell
**Agent**: UI-Settings
**Priority**: P1

**Actions:**
1. Create `SettingsWindow.swift`:
   - NSWindow (780×540), transparent titlebar
   - Keyboard shortcut: ⌘, to open
2. Create `SettingsView.swift`:
   - HSplitView: Sidebar (200pt) + Content
   - Sidebar: brand header + navigation items + footer
   - Content area: switches between tab views

### Task 3.2 — Writing Style Tab
**Agent**: UI-Settings
**Inputs**: Data models from Task 1.1

**Actions:**
1. Implement `WritingStyleTab.swift` per UI-SPEC Section 4
2. Language dropdown, Formality dropdown, Style prompt textarea, Cleanup level dropdown
3. Live preview card showing before/after cleanup example
4. All values bound to `AppSettings` via SwiftData

### Task 3.3 — Models Tab
**Agent**: UI-Settings

**Actions:**
1. Implement `ModelsTab.swift` with card grids for STT and LLM models
2. Each card shows: name, description, size, selection state, download status
3. Download progress bar per model (visible during download)
4. **Delete model**: inactive downloaded models show trash icon; confirm dialog; frees disk; card reverts to "Download" state for re-download. Active model shows "In Use" badge and cannot be deleted.
5. Wire to `ModelDownloader` and `ModelStorage` (Task 5.1)
6. Toggle rows: auto-download, GPU acceleration

### Task 3.4 — Hotkeys Tab
**Agent**: UI-Settings

**Actions:**
1. Implement `HotkeysTab.swift` using `KeyboardShortcuts` library
2. Three shortcut recorders: Push-to-Talk, Hands-Free, Cancel
3. Default values: ⌥Space, ⌥⇧Space, Esc
4. Toggle rows: double-tap activation, sound feedback, haptic feedback

### Task 3.5 — General Tab
**Agent**: UI-Settings

**Actions:**
1. Implement `GeneralTab.swift` with toggle rows and dropdowns
2. Microphone picker populated from `AVCaptureDevice.DiscoverySession`
3. Floating bar position dropdown
4. History limit dropdown
5. Wire LaunchAtLogin package to toggle

### Task 3.6 — Analytics Tab
**Agent**: UI-Settings

**Actions:**
1. Implement `AnalyticsTab.swift`
2. Stats cards with numbers from `AnalyticsTracker`
3. Weekly bar chart (custom SwiftUI Shape or simple rectangles)
4. Privacy notice footer

### Task 3.7 — About Tab
**Agent**: UI-Settings

**Actions:**
1. Implement `AboutTab.swift` centered layout
2. Large creature (72pt) with happy expression
3. Version info from Bundle
4. Links to GitHub, website, license (open in browser)
5. Caveat font tagline

---

## Phase 4: Audio Pipeline

### Task 4.1 — Audio Capture Manager
**Agent**: Core-Audio
**Priority**: P0

**Actions:**
1. Create `AudioCaptureManager.swift`:
   - AVAudioEngine setup with input tap
   - Convert to 16kHz mono Float32 (required by all STT models)
   - Ring buffer for accumulated audio
   - RMS calculation for waveform visualization (publish to AppState)
   - Start/stop recording methods
2. Handle microphone permission:
   - Check `AVCaptureDevice.authorizationStatus(for: .audio)`
   - Request if needed
3. Handle microphone selection:
   - Read from AppSettings
   - Switch input device via `AVAudioSession`

**Output**: Can record audio and provide buffer + RMS values
**Acceptance**: Record 5s of speech → get valid Float32 buffer at 16kHz

### Task 4.2 — Hotkey Manager
**Agent**: Core-Input
**Priority**: P0

**Actions:**
1. Create `HotkeyManager.swift`:
   - Register global hotkeys via `KeyboardShortcuts` package
   - Push-to-Talk: key down → start recording, key up → stop recording
   - Hands-Free: key down → toggle recording
   - Cancel: key down → abort recording
2. Connect to `TranscriptionPipeline` (Task 6.1)
3. Respect `masterToggle` — no hotkey action when off

**Output**: Global hotkeys trigger recording start/stop
**Acceptance**: ⌥Space held → recording starts, released → recording stops (visible in logs)

---

## Phase 5: ML Engines

### Task 5.0 — Silero VAD Manager
**Agent**: Core-Audio
**Priority**: P0
**Depends on**: 4.1

**Actions:**
1. Create `VADManager.swift`:
   - Uses FluidAudio's Silero VAD CoreML model (via `FluidInference/silero-vad-coreml`)
   - Process 32ms audio chunks, return speech probability per chunk
   - Configurable `VADConfig` struct with presets: `default`, `noisyPreset`, `quietPreset`
2. Create `VADConfig.swift` with parameters:
   - `threshold: Float` (0.25–0.5 depending on environment)
   - `minSpeechDurationMs`, `minSilenceDurationMs`, `speechPadMs`, `maxSpeechDurationS`
3. Implement `filterSpeechSegments(from: AVAudioPCMBuffer) -> [AudioSegment]`:
   - Runs Silero VAD on full audio buffer
   - Returns only speech segments with padding
   - Strips leading/trailing silence and mid-speech noise gaps
4. Implement auto-environment detection (optional v0.2):
   - Monitor ambient RMS during idle
   - Auto-switch between quiet/noisy presets
5. Integrate with Settings → General → "Environment Mode" toggle

**Output**: Given raw audio → returns only speech segments, noise stripped
**Acceptance**: Record 10s with 3s speech + 7s silence → outputs only 3s of audio; test with background music → music segments excluded

### Task 5.1 — Model Download & Storage Manager
**Agent**: Core-ML
**Priority**: P0

**Actions:**
1. Create `ModelStorage.swift`:
   - Base path: `~/Library/Application Support/YapYap/Models/`
   - Subdirectories: `stt/` and `llm/`
   - Check if model exists locally
   - Delete model, get model size
2. Create `ModelDownloader.swift`:
   - Download from HuggingFace Hub
   - Progress callback (0.0 → 1.0)
   - Resume interrupted downloads
   - Verify download integrity (file size check)
3. Create `ModelStorage.swift` methods:
   - `isDownloaded(modelId:) -> Bool`
   - `diskSize(modelId:) -> Int64`  
   - `deleteModel(modelId:) throws` — removes model files, frees disk space
   - `canDelete(modelId:) -> Bool` — returns false if model is currently active in STT or LLM engine
   - `downloadedModels() -> [STTModelInfo]` / `[LLMModelInfo]`
4. Create `STTModelRegistry.swift`:
   - Static catalog of available STT models (name, HF repo, backend, size, description)
4. Create `LLMModelRegistry.swift`:
   - Static catalog of available LLM models

**Output**: Can download any registered model with progress, store locally, verify
**Acceptance**: Download Parakeet model → verify file exists at correct path

### Task 5.2 — WhisperKit STT Engine
**Agent**: Core-STT
**Priority**: P0

**Actions:**
1. Create `WhisperKitEngine.swift` implementing `STTEngine` protocol
2. Load model from local path using `WhisperKit(config:)`
3. Configure `DecodingOptions` with YapYap-optimized parameters (see 00-ARCHITECTURE.md § 5a):
   - `temperature: 0.0` with fallback count 3
   - `compressionRatioThreshold: 2.4` (anti-hallucination)
   - `logProbThreshold: -0.8` (tighter than default — reject low-confidence in noise)
   - `noSpeechThreshold: 0.5` (lower than default — Silero VAD handles silence)
   - `suppressBlank: true`, `withoutTimestamps: true`, `wordTimestamps: false`
4. Transcribe audio buffer via `pipe.transcribe(audioPath:)` or buffer API
5. Handle streaming transcription for real-time feedback
6. Error handling: model not found, OOM, hallucination fallback

**Output**: Given audio buffer → returns transcription text
**Acceptance**: Record "Hello, how are you?" → get back correct text; test with background music → no hallucinations

### Task 5.3 — FluidAudio/Parakeet STT Engine
**Agent**: Core-STT
**Priority**: P0

**Actions:**
1. Create `FluidAudioEngine.swift` implementing `STTEngine` protocol
2. Use FluidAudio Swift package for Parakeet inference
3. Load CoreML-converted model from local storage
4. Configure built-in Silero VAD with YapYap presets (see 00-ARCHITECTURE.md § 5a):
   - Default: `threshold: 0.35, chunkSize: 512`
   - Noisy preset: `threshold: 0.5, minSpeechDurationMs: 300`
   - Quiet preset: `threshold: 0.25, minSpeechDurationMs: 150`
5. Runs on ANE (Neural Engine) — verify minimal CPU/GPU usage
6. Note: Parakeet auto-adds punctuation/capitalization — no STT-level cleanup needed

**Output**: Given audio buffer → returns transcription text via Parakeet
**Acceptance**: Same test as 5.2 using Parakeet; test in noisy environment → no hallucinations, clean output

### Task 5.4 — whisper.cpp STT Engine (for Voxtral)
**Agent**: Core-STT
**Priority**: P2 (nice-to-have for v0.1)

**Actions:**
1. Create `WhisperCppEngine.swift` implementing `STTEngine` protocol
2. Bridge whisper.cpp C library to Swift
3. GGML model loading
4. Enable built-in Silero VAD (whisper.cpp supports `--vad` flag natively):
   - `vadThreshold: 0.35`, `vadMinSpeechDurationMs: 200`, `vadMinSilenceDurationMs: 300`
5. Configure decoding params: `beamSize: 5`, `temperature: 0.0`, `logprobThreshold: -0.8`, `noSpeechThreshold: 0.5`, `noTimestamps: true`
6. Used primarily for Voxtral model

### Task 5.5 — MLX LLM Engine
**Agent**: Core-LLM
**Priority**: P0

**Actions:**
1. Create `MLXEngine.swift` implementing `LLMEngine` protocol
2. Load 4-bit quantized model via `mlx-swift-lm`:
   ```swift
   import MLXLM
   let model = try await LLM.load(configuration: ModelConfiguration(id: modelId))
   ```
3. Create `CleanupPromptBuilder.swift`:
   - Construct system prompt from CleanupContext
   - Formality instructions per level
   - Cleanup level instructions per level (minimal/standard/aggressive)
   - **Filler removal instructions per cleanup level** (see 00-ARCHITECTURE.md § 5a):
     - Minimal: remove hesitation sounds only (um, uh, ah, er, hmm)
     - Standard: remove fillers + self-corrections + false starts (matches WisprFlow behavior)
     - Aggressive: full rewrite for polished prose
   - Inject user's custom style prompt
   - Self-correction handling: "meet Tuesday, no Wednesday" → "meet Wednesday"
4. Generate cleanup:
   ```swift
   let result = try await model.generate(
       prompt: builtPrompt,
       parameters: GenerateParameters(temperature: 0.3, maxTokens: 512)
   )
   ```
5. Parse response — extract cleaned text only

**Output**: Given raw transcription + context → returns cleaned text
**Acceptance**: Input "so basically I was thinking that maybe we should like revisit the whole onboarding thing" → Output "We should revisit the onboarding flow."

---

## Phase 6: Pipeline Orchestration

### Task 6.1 — Transcription Pipeline
**Agent**: Core-Pipeline
**Priority**: P0
**Depends on**: Tasks 4.1, 4.2, 5.2/5.3, 5.5

**Actions:**
1. Create `TranscriptionPipeline.swift`:
   ```swift
   class TranscriptionPipeline {
       func startRecording() async
       func stopRecordingAndProcess() async throws -> String
       func cancelRecording()
   }
   ```
2. Orchestrate full flow:
   ```
   startRecording()
     → Update AppState: creatureState = .recording
     → Start AudioCaptureManager
     → Start waveform updates
   
   stopRecordingAndProcess()
     → Stop AudioCaptureManager
     → Get audio buffer
     → Update AppState: creatureState = .processing
     → STT: buffer → raw text
     → LLM: raw text + context → cleaned text
     → Paste: cleaned text → active app
     → Update AppState: creatureState = .sleeping
     → Save to history
     → Update analytics
     → Return cleaned text
   
   cancelRecording()
     → Stop AudioCaptureManager
     → Discard buffer
     → Update AppState: creatureState = .sleeping
   ```
3. Error handling at each stage with user-facing feedback
4. Timeout handling (max recording duration: 5 minutes)

### Task 6.2 — Paste Manager
**Agent**: Core-Pipeline
**Priority**: P0

**Actions:**
1. Create `PasteManager.swift` per Architecture Section 6
2. Primary strategy: clipboard + CGEvent (Cmd+V)
3. Clipboard restoration after paste
4. Fallback: Accessibility API paste via `SelectedTextKit`
5. Handle edge cases: no focused text field, permission denied

---

## Phase 7: Floating Bar

### Task 7.1 — Floating Bar Panel & View
**Agent**: UI-FloatingBar
**Priority**: P1
**Depends on**: Task 2.2 (creature), Task 6.1 (pipeline)

**Actions:**
1. Create `FloatingBarPanel.swift` (NSPanel subclass):
   - `.nonactivatingPanel` + `.borderless` style mask
   - `.floating` window level
   - `.canJoinAllSpaces, .fullScreenAuxiliary` collection behavior
   - Never steals focus from user's active app
   - Clear background with custom pill shape
2. Create `FloatingBarView.swift` (SwiftUI in NSHostingView):
   - Pill container with backdrop blur
   - Left: creature (42pt) matching current state
   - Right: waveform bars (5 bars, driven by AppState.currentRMS)
   - Spring animation for expand/contract
3. Create `WaveformView.swift`:
   - 5 vertical bars, 2.5pt wide, rounded caps
   - Height driven by RMS with sine wave modulation
   - ypWarm color during recording
4. Position management:
   - Read position from AppSettings
   - Calculate screen position (centered at bottom, with padding)
   - Handle multi-monitor

**Output**: Floating pill appears during recording, shows animated creature + waveform
**Acceptance**: Press hotkey → pill expands with spring → waveform animates → release → pill contracts

---

## Phase 8: Polish & First Launch

### Task 8.1 — Sound & Haptic Feedback
**Agent**: Polish
**Priority**: P2

**Actions:**
1. Create `SoundManager.swift`:
   - Bundle 2 short WAV files: start.wav, stop.wav (subtle, cozy chimes)
   - Play via `NSSound` or `AVAudioPlayer`
   - Respect `soundFeedback` setting
2. Create `HapticManager.swift`:
   - Trackpad haptic via `NSHapticFeedbackManager`
   - Brief tap on recording start/stop
   - Respect `hapticFeedback` setting

### Task 8.2 — Permissions Helper
**Agent**: Polish
**Priority**: P1

**Actions:**
1. Create `Permissions.swift`:
   - Check microphone, accessibility, screen recording permissions
   - Guide user to System Settings if needed
   - Show in-app alert with "Open System Settings" button

### Task 8.3 — Onboarding Flow
**Agent**: UI-Onboarding
**Priority**: P2

**Actions:**
1. Create `OnboardingView.swift` per UI-SPEC Section 7
2. 4-step wizard: Welcome → Permissions → Model Selection → Hotkey Setup → Done
3. Show only on first launch (check UserDefaults flag)
4. Model download with progress during onboarding

### Task 8.4 — App Context Detector (Full Context-Aware Formatting)
**Agent**: Core-Context
**Priority**: P1 (critical for WisprFlow parity)

**Actions:**
1. Create `AppContextDetector.swift`:
   - Detect frontmost app via `NSWorkspace.shared.frontmostApplication`
   - Classify app into `AppCategory` (8 categories: personalMessaging, workMessaging, email, codeEditor, browser, documents, aiChat, other)
   - Bundle ID → Category mapping with 30+ pre-mapped apps
   - Browser special case: read window title via AX API to detect Gmail/Slack/ChatGPT in browser tabs
   - Get focused text field content via `AXUIElementCreateSystemWide()` + `kAXFocusedUIElementAttribute` + `kAXValueAttribute`
   - Detect IDE AI chat panel (Cursor Composer, Windsurf AI panel) from window title patterns
2. Create `AppCategory.swift` enum + `OutputStyle.swift` enum (veryCasual, casual, excited, formal)
3. Create `AppContext` struct (bundleId, appName, category, style, windowTitle, focusedFieldText, isIDEChatPanel)
4. Require Accessibility permission (already needed for paste) — add check in Permissions Helper (Task 8.2)

**Acceptance criteria:**
- `AppContextDetector.detect()` returns correct `AppContext` in <5ms
- Correctly classifies: iMessage → personalMessaging, Slack → workMessaging, Cursor → codeEditor
- Browser tabs: Gmail in Safari → email, ChatGPT in Chrome → aiChat
- Falls back to `.other` gracefully when app unknown

### Task 8.5 — Context-Aware LLM Prompt Builder
**Agent**: Core-Context
**Priority**: P1

**Actions:**
1. Expand `CleanupPromptBuilder.swift`:
   - `buildAppFormattingInstruction(context: AppContext) -> String`
   - Per-category formatting instructions (see § 5b in Architecture)
   - Per-style punctuation/capitalization rules (veryCasual strips periods/caps, formal adds full structure)
   - Inject focused field text as "Existing text in field" for continuation awareness
2. Create `OutputFormatter.swift`:
   - `format(_ text: String, for context: AppContext) -> String`
   - File tagging: "at main.py" → "@main.py" (regex: `\bat\s+(\w+\.(?:swift|py|ts|...))\b`)
   - Variable backtick wrapping: camelCase/snake_case identifiers → `` `identifier` ``
   - Very casual post-processing: strip trailing periods, lowercase sentence starts
   - Smart paragraph breaks for email/documents
3. Integrate into pipeline: `TranscriptionPipeline` calls `AppContextDetector.detect()` at recording start, passes `AppContext` through to `CleanupPromptBuilder` and `OutputFormatter`

**Acceptance criteria:**
- Email dictation includes proper paragraph structure and greeting/sign-off formatting
- Slack dictation is concise, no trailing periods in casual mode
- IDE chat: variable names wrapped in backticks, filenames tagged with @
- Very casual iMessage: no caps, no periods — "hey yeah sounds good"

### Task 8.6 — Style Settings Tab
**Agent**: UI-Settings
**Priority**: P1

**Actions:**
1. Create `StyleSettingsView.swift`:
   - Vertical list of 8 app categories with icon, name, example apps, style picker
   - Each row: `[Icon] Category Name [Style Dropdown]` + subtitle with example app names
   - Style preview on hover: show formatted example text
   - IDE section (visible when code editor apps detected): toggle for variable recognition + file tagging
   - "App overrides" disclosure group: shows running apps with their detected category, allows reclassification
2. Create `StyleSettings.swift` model (Codable, stored in UserDefaults):
   - Per-category `OutputStyle` properties with defaults
   - IDE-specific booleans (variableRecognition, fileTagging)
   - `appCategoryOverrides: [String: AppCategory]` for manual overrides
3. Add "Style" tab to SettingsWindow (between Hotkeys and General)

**Acceptance criteria:**
- All 8 categories show with correct defaults
- Changing a style immediately affects next dictation in that app type
- IDE toggles show/hide based on whether code editor apps are installed
- Overrides persist across app restarts

### Task 8.7 — Command Mode (v0.2)
**Agent**: Core-Pipeline
**Priority**: P2

**Actions:**
1. Create `CommandMode.swift`:
   - `isCommand(_ text: String) -> Bool` — detect command prefixes ("make this...", "turn into...", "shorten...", "summarize...")
   - `execute(command: String) async throws -> String` — read selected text via AX API, build LLM prompt with command + selected text, return rewritten text
   - Replace selected text in active app via AX `kAXSelectedTextAttribute` setter or clipboard + Cmd+V
2. Add Command Mode hotkey (default: ⌥ + ⌘ + Space) to HotkeyManager
3. Update floating bar: show 🎯 icon during Command Mode (vs 🎙 for dictation)
4. Different audio feedback: ascending chime for Command Mode start

**Acceptance criteria:**
- User highlights text in any app, presses Command Mode hotkey, says "make this more professional" → text is rewritten
- "Turn this into bullet points" correctly reformats selected text
- "Summarize this" produces a shorter version
- Graceful error if no text selected: paste "⚠️ Select text first"

### Task 8.8 — Personal Dictionary (v0.2)
**Agent**: Core-Pipeline
**Priority**: P3

**Actions:**
1. Create `PersonalDictionary.swift`:
   - Stored in `~/Library/Application Support/YapYap/dictionary.json`
   - `entries: [String: String]` (spoken form → corrected form)
   - `applyCorrections(to text: String) -> String` — regex-based replacement before LLM
   - `monitorCorrections(pastedText:)` — after pasting, wait 5 seconds, read field text again, diff words, learn corrections
2. Manual dictionary editor in Settings → General (disclosure group):
   - Table: spoken word → correction
   - Add/remove/edit rows
   - Import/export as JSON
3. Integrate into pipeline: after STT, before LLM, apply dictionary corrections

### Task 8.9 — Voice Snippets (v0.2)
**Agent**: Core-Pipeline
**Priority**: P3

**Actions:**
1. Create `SnippetManager.swift`:
   - `VoiceSnippet` struct: id, trigger phrase, expansion text
   - `matchSnippet(from text: String) -> VoiceSnippet?` — exact match or "insert {trigger}" pattern
   - Stored in `~/Library/Application Support/YapYap/snippets.json`
2. Snippet editor in Settings → new "Snippets" tab:
   - List of snippets with trigger + preview of expansion
   - Add/edit/delete with sheet editor
   - Example built-in snippets: "my email" → user's email, "standup template" → formatted template
3. Integrate into pipeline: after STT, check for snippet match before LLM cleanup — if matched, insert expansion directly (skip LLM)

---

## Phase 9: Distribution

### Task 9.1 — README & Documentation
**Agent**: Docs
**Priority**: P1

**Actions:**
1. Write `README.md` with:
   - Hero screenshot/GIF
   - Feature list
   - Installation (download, Homebrew, build from source)
   - Quick start guide
   - Architecture overview
   - Contributing guide
2. Write `BUILDING.md` with step-by-step build instructions
3. Write `CONTRIBUTING.md` with PR guidelines
4. Add MIT `LICENSE`
5. Create GitHub Issue templates

### Task 9.2 — Build & Release
**Agent**: Infrastructure
**Priority**: P2

**Actions:**
1. Configure code signing (or document disabling for open source builds)
2. Create DMG builder script
3. Configure Sparkle for updates:
   - Generate EdDSA key pair
   - Create appcast.xml template
4. Create GitHub Actions workflow for CI:
   - Build on macOS runner
   - Run tests
   - Create release artifacts on tag push
5. Homebrew cask formula

---

## Execution Order Summary

```
Phase 0: Project scaffold (Task 0.1)
  ↓
Phase 1: Data layer (Task 1.1)
  ↓
Phase 2: App shell + menu bar (Tasks 2.1 → 2.2 → 2.3) — parallel with Phase 4
Phase 4: Audio pipeline (Tasks 4.1, 4.2) — parallel with Phase 2
  ↓
Phase 5: ML engines (Tasks 5.1, 5.2, 5.3, 5.5) — can start once 4.1 done
  ↓
Phase 6: Pipeline orchestration (Tasks 6.1, 6.2) — needs Phase 4 + 5
  ↓
Phase 3: Settings window (Tasks 3.1-3.7) — can start in parallel after Phase 2
Phase 7: Floating bar (Task 7.1) — needs Phase 2 + 6
  ↓
Phase 8: Polish (Tasks 8.1-8.4)
Phase 9: Distribution (Tasks 9.1-9.2)
```

**Critical path**: 0.1 → 1.1 → 4.1 → 5.1 → 5.2/5.3 → 5.5 → 6.1 → 6.2

**Parallelizable**: UI work (Phase 2, 3) can happen alongside ML work (Phase 5).
