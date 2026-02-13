# YapYap Testing Guide

This document describes how to run tests, validate models, and verify the complete pipeline.

## Quick Start

```bash
# Run all unit tests
make test

# Run specific test class
xcodebuild -project YapYap.xcodeproj -scheme YapYap \
  -only-testing:YapYapTests/CleanupPromptBuilderTests test

# Generate coverage report
xcodebuild -project YapYap.xcodeproj -scheme YapYap \
  -enableCodeCoverage YES test
```

## Unit Tests (147 tests)

### Test Suites by Category

**Design & Configuration (Simple)**
- `DesignTokensTests.swift` (18 tests) — Color, font, animation token validation
- `YapYapErrorTests.swift` (7 tests) — Error enum descriptions
- `VADConfigTests.swift` (4 tests) — Voice Activity Detection presets
- `DataModelTests.swift` (14 tests) — SwiftData model initialization

**Text Processing (Medium)**
- `FillerFilterTests.swift` (15 tests) — Filler word regex patterns
- `OutputFormatterTests.swift` (19 tests) — Post-LLM text formatting rules
- `AppContextDetectorTests.swift` (8 tests) — App category classification
- `PersonalDictionaryTests.swift` (6 tests) — Custom word corrections
- `SnippetManagerTests.swift` (8 tests) — Voice snippet expansion

**AI Integration (Complex)**
- `CleanupPromptBuilderTests.swift` (4 tests) — LLM prompt construction
- `CommandModeTests.swift` (6 tests) — Voice command parsing
- `ModelRegistryTests.swift` (19 tests) — STT/LLM model metadata

### Running Tests

```bash
# All tests (fast, ~0.4 seconds)
make test

# Watch mode (re-run on file change)
fswatch -o YapYap/**/*.swift | xargs -n1 -I{} make test

# Coverage report location
~/Library/Developer/Xcode/DerivedData/YapYap-*/Logs/Test/*.xcresult
```

### Test Coverage Targets

- **Core Pipeline**: >80% (TranscriptionPipeline, AudioCaptureManager, VADManager)
- **STT Engines**: >70% (WhisperKitEngine, FluidAudioEngine, WhisperCppEngine)
- **LLM Engine**: >70% (MLXEngine, CleanupPromptBuilder)
- **Context Detection**: >85% (AppContextDetector, OutputFormatter)
- **UI Components**: Manual validation (see UI Testing below)

## Integration Testing (Manual)

Integration tests require actual model downloads and runtime execution. Run these manually after code changes to the pipeline.

### Prerequisites

1. Build and run the app:
   ```bash
   make build
   make run
   ```

2. Complete onboarding:
   - Grant microphone permission (System Settings → Privacy & Security → Microphone)
   - Grant accessibility permission (System Settings → Privacy & Security → Accessibility)
   - Select initial STT model (recommend Whisper Small for testing)
   - Select initial LLM model (recommend Qwen 1.5B for testing)

### Test Matrix: STT Engines

Test one engine at a time to manage disk space. Delete models before switching.

#### Round 1: WhisperKit (Whisper Small)

**Model Download** (~244MB):
- Open Settings → Models
- Select "Whisper Small" card
- Click "Download" button
- Wait for progress to complete

**Pipeline Test**:
1. Open TextEdit (or any text editor)
2. Click in text field
3. Hold Option+Space
4. Say: "Hello, this is a test of the Whisper small model"
5. Release Option+Space
6. Verify:
   - ✅ Floating bar appears with waveform
   - ✅ Creature shows recording state (pulse rings, blush)
   - ✅ After release, creature shows processing state (spinner)
   - ✅ Text appears in TextEdit: "Hello, this is a test of the Whisper small model."
   - ✅ Text is cleaned (no "um", "uh", proper punctuation)

**VAD Test** (silence detection):
1. Hold Option+Space
2. Say: "One" ... (2 seconds silence) ... "two" ... (2 seconds silence) ... "three"
3. Release
4. Verify: Only "One two three" appears (silence stripped)

**Delete Model**:
- Settings → Models → Whisper Small → Delete

#### Round 2: FluidAudio (Parakeet TDT v3)

**Model Download** (~600MB):
- Select "Parakeet TDT v3"
- Download

**Same Pipeline Test** as Round 1.

**Performance Check**:
- ✅ Transcription should be faster than Whisper (ANE acceleration)
- ✅ No GPU fans spinning (uses Neural Engine, not GPU)

**Delete Model** after testing.

#### Round 3: whisper.cpp (Optional)

Requires manual whisper.cpp model installation (GGML format). Skip unless testing whisper.cpp integration specifically.

### Test Matrix: LLM Cleanup

Test with Whisper Small + different LLM models.

#### Qwen 1.5B (Default, ~800MB)

**Filler Removal Test**:
- Say: "Um, so like, I think, you know, we should basically meet on, uh, Tuesday"
- Expected: "I think we should meet on Tuesday."

**Context-Aware Test** (Email):
1. Open Mail.app
2. Click in compose field
3. Record: "Hey can you send me the report I need it by Friday thanks"
4. Expected: "Hey, can you send me the report? I need it by Friday. Thanks!"
   - ✅ Proper sentence structure
   - ✅ Punctuation added
   - ✅ Paragraph breaks (if longer text)

**Context-Aware Test** (Code Editor):
1. Open VS Code
2. Record: "Create a function called get user by ID that takes a user ID parameter"
3. Expected: "Create a function called `getUserById` that takes a `userId` parameter"
   - ✅ CamelCase wrapped in backticks
   - ✅ Technical formatting

**Context-Aware Test** (Personal Messaging):
1. Open Messages.app
2. Record: "Yeah that sounds good to me let me know when you are free"
3. Expected (casual style): "yeah that sounds good to me, let me know when you're free"
   - ✅ Lowercase start (very casual style if selected)
   - ✅ Contractions preserved

#### Llama 3.2 1B (Optional)

Similar tests, compare cleanup quality.

### Cleanup Level Test

Test different cleanup levels (Settings → Writing Style):

| Level | Input | Expected Output |
|-------|-------|-----------------|
| Light | "Um, I went to the, uh, store yesterday" | "I went to the store yesterday" |
| Medium | "So basically I think we should like maybe meet on Tuesday or Wednesday" | "I think we should meet on Tuesday or Wednesday." |
| Heavy | "Um so yeah I was thinking that we could, you know, kind of restructure the whole thing" | "We could restructure the entire system." |

### Command Mode Test

1. Type in TextEdit: "the quick brown fox jumps over the lazy dog"
2. Select the text
3. Press Option+Command+Space
4. Say: "Make this more professional"
5. Expected: "The quick brown fox jumps over the lazy dog."
6. Say: "Turn this into bullet points"
7. Expected:
   ```
   - The quick brown fox
   - Jumps over the lazy dog
   ```

## UI Testing (Manual)

### Menu Bar Icon

- [ ] Icon appears in menu bar (lavender creature)
- [ ] Sleeping animation plays (breathing, z's floating)
- [ ] Left-click opens popover
- [ ] Right-click shows quick menu

### Popover

- [ ] 300pt width, auto-height
- [ ] Header shows creature (32×32), status, toggle
- [ ] Last transcription appears after first recording
- [ ] Quick stats update (today count, words, time saved)
- [ ] STT model pill shows "Whisper" or "Parakeet"
- [ ] LLM model pill shows "Qwen 2.5"
- [ ] Settings button opens Settings window
- [ ] Quit button quits app

### Floating Bar

- [ ] Appears on first recording (if enabled)
- [ ] Positioned correctly (bottom center by default)
- [ ] Expands with spring animation when recording starts
- [ ] Waveform bars animate with microphone input
- [ ] Contracts when recording ends
- [ ] Creature state matches (sleeping → recording → processing)
- [ ] Never steals keyboard focus

### Settings Window

- [ ] 780×540pt window
- [ ] Sidebar width 200pt
- [ ] All 7 tabs accessible (Writing Style, Models, Hotkeys, General, Style, Analytics, About)
- [ ] Brand section shows creature + "yapyap v0.1.0"
- [ ] Footer shows handwritten text
- [ ] Window is movable by background
- [ ] Titlebar is transparent

#### Writing Style Tab

- [ ] Language dropdown works
- [ ] Formality selector (Casual/Neutral/Formal)
- [ ] Custom style prompt textarea
- [ ] Cleanup level dropdown
- [ ] Preview card shows before/after example

#### Models Tab

- [ ] STT models grid (2×2 or 2×3)
- [ ] LLM models grid
- [ ] Selected model shows checkmark + lavender border
- [ ] Download button appears for non-downloaded models
- [ ] Delete button appears for downloaded (non-active) models
- [ ] "In Use" badge on active model

#### Hotkeys Tab

- [ ] Push-to-Talk recorder (default: ⌥Space)
- [ ] Hands-Free recorder (default: ⌥⇧Space)
- [ ] Command Mode recorder (default: ⌥⌘Space)
- [ ] Cancel hotkey shown (Esc)
- [ ] Sound feedback toggle
- [ ] Haptic feedback toggle

#### General Tab

- [ ] Launch at login toggle
- [ ] Show floating bar toggle
- [ ] Auto-paste toggle
- [ ] Copy to clipboard toggle
- [ ] Remove filler words toggle
- [ ] Microphone dropdown (lists available inputs)
- [ ] Floating bar position dropdown
- [ ] History limit dropdown

#### About Tab

- [ ] Large creature (72×72) with smile
- [ ] Version number
- [ ] Description
- [ ] GitHub/Website/License buttons
- [ ] Footer text

## Performance Benchmarks

Target latencies (M1 MacBook Air, 8GB RAM):

| Stage | Target | Measured |
|-------|--------|----------|
| Audio capture start | <100ms | _____ |
| VAD processing | <50ms | _____ |
| STT (Parakeet, 5s audio) | <500ms | _____ |
| STT (Whisper Small, 5s) | <1000ms | _____ |
| LLM cleanup (Qwen 1.5B, 50 tokens) | <500ms | _____ |
| Total (speak → paste, 5s audio) | <2500ms | _____ |

**How to measure**:
1. Open Console.app
2. Filter for "YapYap"
3. Record a 5-second phrase
4. Check timestamps in logs

## Troubleshooting Tests

### "No audio detected"
- Check microphone permission (System Settings → Privacy)
- Check selected microphone (Settings → General)
- Try speaking louder or adjusting VAD threshold

### "Transcription failed"
- Verify model is downloaded (Settings → Models)
- Check disk space (models require 2-4GB)
- Check Console.app for error logs

### "Text not pasting"
- Check accessibility permission
- Verify "Auto-paste" is enabled (Settings → General)
- Try "Copy to clipboard" as fallback

### "App crashes on launch"
- Check macOS version (14.0+ required)
- Check architecture (Apple Silicon required)
- Delete `~/Library/Application Support/YapYap/` and relaunch

## CI/CD Testing

For GitHub Actions or similar:

```yaml
- name: Run unit tests
  run: make test

- name: Check test coverage
  run: |
    xcodebuild -project YapYap.xcodeproj -scheme YapYap \
      -enableCodeCoverage YES test
    xcrun xccov view --report \
      ~/Library/Developer/Xcode/DerivedData/YapYap-*/Logs/Test/*.xcresult
```

## Test Coverage Report

After running tests with coverage:

```bash
# View summary
xcrun xccov view --report DerivedData/.../Test/*.xcresult

# Export as JSON
xcrun xccov view --report --json DerivedData/.../Test/*.xcresult > coverage.json
```

Target: **>80% coverage for core components**.

---

*Last updated: 2026-02-13*
