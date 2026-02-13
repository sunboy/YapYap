# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YapYap is an open-source, offline macOS voice-to-text app with AI-powered cleanup. It's a native Swift + SwiftUI application that uses on-device ML models for speech-to-text (Whisper, Parakeet) and LLM-based text cleanup (Qwen, Llama, Gemma). Everything runs locally on Apple Silicon Macs with no cloud dependencies.

**Key Differentiator**: 100% offline, context-aware text formatting that adapts to the active app (iMessage vs Slack vs email vs code editors).

## Build System & Common Commands

### Project Generation
The project uses **XcodeGen** to generate the Xcode project from `project.yml`. If the Xcode project doesn't exist or needs regeneration:

```bash
xcodegen generate
```

### Building and Running

```bash
# Build the app (Debug configuration)
make build

# Build and run the app
make run

# Run all tests
make test

# Run a specific test
xcodebuild -project YapYap.xcodeproj -scheme YapYap -only-testing:YapYapTests/TestClassName test

# Build release archive
make archive

# Create DMG for distribution
make dmg

# Clean build artifacts
make clean
```

### Development Workflow

1. Install XcodeGen: `brew install xcodegen`
2. Generate the Xcode project: `xcodegen generate`
3. Open in Xcode: `open YapYap.xcodeproj` or use `make run`
4. Make changes to source files in `YapYap/`
5. Run tests with `make test`

## Architecture Overview

### Core Pipeline: Audio → VAD → STT → LLM → Paste

The main transcription flow is orchestrated by `TranscriptionPipeline.swift`:

1. **Audio Capture** (`AudioCaptureManager`): Captures 16kHz mono audio via AVAudioEngine
2. **VAD Filtering** (`VADManager`): Silero VAD (CoreML) strips silence/noise to prevent hallucinations
3. **Speech-to-Text** (`STTEngine` protocol): Multiple backends available:
   - **WhisperKit** for Whisper models (Large/Medium/Small v3) via CoreML
   - **FluidAudio** for Parakeet TDT v3 via ANE (Apple Neural Engine)
   - **whisper.cpp** for GGML models like Voxtral
4. **LLM Cleanup** (`LLMEngine` protocol): MLX Swift runs 4-bit quantized models (Qwen/Llama/Gemma) to remove fillers, fix grammar, apply context-aware formatting
5. **Paste** (`PasteManager`): Injects text via clipboard + synthetic Cmd+V or Accessibility API

### Context-Aware Formatting System

**App Detection** (`AppContextDetector.swift`):
- Detects active app via NSWorkspace and classifies into categories: personal messaging, work messaging, email, code editor, browser, documents, AI chat
- Uses Accessibility APIs to read window titles, focused text fields, and selected text
- Browser tabs are classified by URL patterns (e.g., gmail.com → email category)

**Output Formatting** (`OutputFormatter.swift`, `CleanupPromptBuilder.swift`):
- Builds LLM system prompts with category-specific formatting rules
- Post-processes LLM output with deterministic rules:
  - Code editor: wraps variables in backticks, converts "at file.py" to "@file.py"
  - Very casual style: removes capitalization and trailing periods
  - Email/docs: ensures proper paragraph breaks

**User Settings** (`StyleSettings.swift`):
- Per-category output styles: very casual / casual / excited / formal
- Controls punctuation, capitalization, and structure (not word choice)

### Multi-Model Architecture

**STT Models** are registered in `STTModelRegistry.swift`:
- Parakeet TDT v3 (~600MB, fastest, runs on ANE)
- Whisper Large v3 Turbo (~1.5GB, best accuracy)
- Whisper Medium (~769MB, balanced)
- Whisper Small (~244MB, lightweight)

**LLM Models** are registered in `LLMModelRegistry.swift`:
- Qwen 2.5 1.5B/3B/7B (multilingual, default)
- Llama 3.2 1B/3B (English-focused)
- Gemma 2 2B (instruction-following)

Models are downloaded from HuggingFace to `~/Library/Application Support/YapYap/Models/` on first use.

### UI Architecture

**Three-Layer UI**:
1. **Menu bar icon** (`StatusBarController.swift`): NSStatusItem with animated creature
2. **Popover menu** (`PopoverView.swift`): Quick actions, history preview, settings access
3. **Floating bar** (`FloatingBarPanel.swift`): NSPanel with waveform and creature during recording

**SwiftUI + AppKit Hybrid**:
- UI views are SwiftUI (`FloatingBarView.swift`, `SettingsView.swift`)
- Window management uses AppKit (NSStatusItem, NSPopover, NSPanel, NSWindow)
- Creature animations use SwiftUI's `.animation()` modifiers with easing

### Data Layer

**SwiftData** (SQLite) models in `YapYap/Data/`:
- Settings are stored per-user (no iCloud sync)
- Transcription history with metadata (STT model, LLM model, source app, word count)
- Analytics tracked locally only (daily stats, word counts)
- Personal dictionary for auto-learning corrections
- Voice snippets for template expansion

All data stored in `~/Library/Application Support/YapYap/`.

## Key Design Patterns

### Protocol-Based Engine Abstraction

Both STT and LLM use protocols for multi-backend support:

```swift
protocol STTEngine {
    var isLoaded: Bool { get }
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws
    func transcribe(audio: AVAudioPCMBuffer) async throws -> String
}

protocol LLMEngine {
    var isLoaded: Bool { get }
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws
    func cleanup(rawText: String, context: CleanupContext) async throws -> String
}
```

Factory pattern in `STTEngineFactory.swift` selects the correct backend based on model ID.

### VAD Pre-Processing (Critical)

Silero VAD **must** run before all STT engines to prevent Whisper hallucinations during silence. The VAD strips non-speech segments and only feeds actual speech to the STT model.

Configuration presets in `VADConfig.swift`:
- **Quiet preset**: Lower threshold (0.25) for sensitive detection
- **Noisy preset**: Higher threshold (0.5) to filter background noise

### Filler Removal Strategy (3-Layer)

1. **STT-level**: Whisper naturally suppresses most "um"/"uh" (training artifact)
2. **LLM-level**: System prompt instructs removal of fillers + self-corrections
3. **Regex guard**: Post-LLM safety net for isolated hesitations (if enabled)

See `CleanupPromptBuilder.buildFillerRemovalInstruction()` for the detailed LLM instructions.

### Smart Formatting Rules

Context-aware formatting is split between:
- **LLM prompt injection**: Category-specific instructions (e.g., "Format for email: use paragraph structure")
- **Deterministic post-processing**: Regex-based fixes applied after LLM output

This hybrid approach ensures reliability (LLM handles semantic formatting, regex handles mechanical fixes).

## File Organization

```
YapYap/
├── App/                    # App lifecycle, global state
│   ├── YapYapApp.swift    # @main entry point
│   ├── AppDelegate.swift  # NSApplicationDelegate for menu bar
│   └── AppState.swift     # @Observable global state
│
├── Core/                   # Core business logic
│   ├── Pipeline/          # Orchestration
│   ├── STT/               # Speech-to-text engines
│   ├── LLM/               # Cleanup engines
│   └── Context/           # App detection & formatting
│
├── UI/                     # User interface
│   ├── MenuBar/           # NSStatusItem + popover
│   ├── FloatingBar/       # Recording UI (NSPanel)
│   ├── Settings/          # Settings window tabs
│   └── Creature/          # Animated creature SVG
│
├── Data/                   # Persistence
│   ├── DataManager.swift  # SwiftData container
│   └── AnalyticsTracker.swift
│
├── Utilities/              # Helpers
│   ├── Permissions.swift  # Mic/Accessibility checks
│   ├── HapticManager.swift
│   └── SoundManager.swift
│
└── Resources/              # Assets, sounds, localization

YapYapTests/                # Unit tests
```

## Testing Strategy

All tests in `YapYapTests/` are unit tests (no UI tests yet). Key test files:

- `CleanupPromptBuilderTests.swift`: Verifies LLM prompt construction for different contexts
- `OutputFormatterTests.swift`: Tests deterministic formatting rules
- `AppContextDetectorTests.swift`: Tests app classification logic
- `FillerFilterTests.swift`: Tests filler word regex patterns
- `ModelRegistryTests.swift`: Validates model metadata
- `VADConfigTests.swift`: Tests VAD threshold configurations

**Running specific tests**:
```bash
# Run all tests
make test

# Run a specific test class
xcodebuild -project YapYap.xcodeproj -scheme YapYap -only-testing:YapYapTests/CleanupPromptBuilderTests test
```

## Dependencies (Swift Packages)

Managed via `project.yml` and Swift Package Manager:

**STT**:
- WhisperKit (CoreML Whisper)
- FluidAudio (Parakeet + Silero VAD)

**LLM**:
- MLX Swift (Apple's ML framework)
- MLX-LM (Language model utilities)

**macOS Utilities**:
- KeyboardShortcuts (global hotkeys)
- LaunchAtLogin (startup configuration)
- Sparkle (auto-updates)
- SelectedTextKit (reading selected text via Accessibility)

All dependencies are fetched automatically during Xcode build. No manual installation needed.

## Performance Considerations

**Critical Performance Path**: User releases hotkey → text must appear in <3 seconds

- STT models are lazy-loaded (not at app startup)
- LLM models are kept in memory once loaded (avoid reload latency)
- VAD pre-processing reduces STT time by 40-60% by stripping silence
- MLX achieves ~200-500 tok/s on M1+ for 1-3B models
- Parakeet is faster than Whisper (runs on ANE, not GPU)

**Memory targets**:
- Idle: <60MB (no models loaded)
- Active: <2.5GB (Parakeet + Qwen 1.5B loaded)

## Permissions & Entitlements

App requires:
- **Microphone**: NSMicrophoneUsageDescription in Info.plist
- **Accessibility**: Required for reading selected text, pasting via synthetic key events
- **Not sandboxed**: Needs CGEvent and AXUIElement APIs

See `YapYap.entitlements` for full entitlement configuration.

## Common Pitfalls

1. **Don't modify project.yml without regenerating**: After changing `project.yml`, always run `xcodegen generate`
2. **VAD must run before STT**: Whisper will hallucinate on silence if VAD is skipped
3. **Accessibility permission required**: Paste will fail silently without it
4. **Model paths are user-specific**: Models go in `~/Library/Application Support/YapYap/Models/`, not bundled
5. **LLM cleanup is optional**: User can disable cleanup and get raw STT output

## Architecture Documents

Full technical details:
- `files/00-ARCHITECTURE.md`: Complete system design, VAD tuning, STT parameters, context-aware formatting
- `docs/UI-SPEC.md`: Full UI specification
- `docs/AGENT-TASKS.md`: Task breakdown for agents
- `README.md`: User-facing documentation

## Development Notes

- **Platform**: macOS 14.0+ (Sonoma), Apple Silicon required (M1+)
- **Swift Version**: 5.9
- **Xcode Version**: 15.0+
- **Deployment**: GitHub Releases + Homebrew cask

The app is MIT licensed and 100% open source. No telemetry, no analytics sent to servers.
