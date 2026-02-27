# Changelog

All notable changes to YapYap will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned Features
- Voice snippets with trigger phrases ("insert my email" → auto-expansion)
- Power Mode rules (per-app STT/LLM model overrides)
- Team snippet sharing
- Browser-specific URL detection for better context
- Export transcription history to CSV/JSON
- Custom keyboard shortcuts beyond default hotkeys
- Dark mode menu bar icon tinting option

## [0.2.1] - 2026-02-26

### Fixed
- Replaced single-shot correction learning with continuous polling for better accuracy
- Fixed echo bug in LLM output + improved prompt quality across all model sizes
- Explicit `\n\n` email structure enforced in prompts for all model sizes
- Retry notarytool polling on transient network errors during CI distribution
- Liquid glass UI redesign with updated app icon
- Continuous STT priming ("Speech-to-text input.") added to all small/medium model prompts
- Emoji name → emoji conversion (👍 🔥 ❤️) for messaging and social categories
- "Remember to X" / "Don't forget to X" → `- [ ] X` todo conversion in Notes/Documents
- Fixed `applyEmailFormatting()` early-return bug skipping transition-word paragraph breaks
- "Scratch that / delete that" meta-command stripping pre-LLM
- New few-shot examples for code editor and social media contexts
- Expanded file tagging (`@filename.ts`) to all code editor contexts (not just IDE chat panels)

### Changed
- Filler word detection uses word-boundary regex to prevent false positives (e.g. "ukulele")
- AboutTab now shows dynamic version from bundle (no longer hardcoded)

---

## [0.2.0] - 2026-02-22

### Added
- Voxtral via whisper.cpp backend (GGML models)
- Gemma 3 1B and 4B model support (replaces Gemma 2)
- IDE chat panel detection for Windsurf
- `notesTodoConversion` setting in StyleSettings (migration-safe, defaults on)
- Analytics: daily word counts, transcription streaks

### Changed
- Models tab now shows download progress per-model
- Floating bar position saved per-screen in settings
- Default LLM changed from Qwen 2.5 3B to Qwen 2.5 1.5B for 8GB machines

### Fixed
- Model hot-swap: `startRecording()` now always checks loaded model IDs against settings
- Hotkey reentrancy: `isStartingRecording` flag prevents duplicate keyDown events
- `pendingStop` flag handles hotkey release during model loading
- LLM stop token truncation for Gemma (`<end_of_turn>` stripped from output)
- Settings `onChange` handlers guarded with `didLoadSettings` to prevent spurious saves

### Known Issues
- First model download may take 5-10 minutes depending on connection
- Whisper Large v3 Turbo requires 16GB RAM for optimal performance
- Command Mode requires pre-selecting text

---

## [0.1.0] - 2026-02-13

### Added
- Initial public release
- **Speech-to-Text Engines**:
  - WhisperKit with Whisper Large v3 Turbo, Medium, Small
  - FluidAudio with Parakeet TDT v3
  - whisper.cpp support (GGML models)
- **LLM Cleanup Engines**:
  - MLX Swift with Qwen 2.5 (1.5B, 3B, 7B)
  - Llama 3.2 (1B, 3B) and Llama 3.1 8B
  - Gemma 2 2B
- **Core Features**:
  - Push-to-talk recording (Option+Space)
  - Hands-free mode with VAD auto-stop
  - Context-aware formatting (8 app categories)
  - Filler word removal (um, uh, like, you know)
  - Grammar and punctuation correction
  - Writing style presets (Very Casual, Casual, Excited, Formal)
  - Custom style prompts
  - Cleanup levels (Light, Medium, Heavy)
- **UI Components**:
  - Animated menu bar creature (sleeping, recording, processing states)
  - Popover menu with quick stats and settings
  - Floating bar with waveform visualization
  - Settings window (7 tabs: Writing Style, Models, Hotkeys, General, Style, Analytics, About)
  - Onboarding flow (5 steps)
- **Context Detection**:
  - App category classification: Personal Messaging, Work Messaging, Email, Code Editor, Documents, AI Chat, Browser, Other
  - Per-category output styles
  - IDE chat panel detection (Cursor, Windsurf)
  - Browser URL-based categorization
- **Command Mode**:
  - Voice-powered text transformation ("make this more professional")
  - Highlight text, speak command, get rewritten result
- **Data & Analytics**:
  - Local transcription history (SwiftData)
  - Daily stats (count, words, time saved)
  - Personal dictionary (auto-learning corrections)
  - Voice snippets (expandable trigger phrases)
- **Accessibility**:
  - Microphone permission handling
  - Accessibility permission for paste
  - Full keyboard navigation
  - VoiceOver support (basic)
- **Performance**:
  - Silero VAD for noise filtering
  - 4-bit quantized LLM models
  - Neural Engine utilization (Parakeet)
  - GPU acceleration toggle
- **Privacy**:
  - Transcription and AI cleanup run fully offline
  - Opt-out crash reporting (Sentry) and anonymous usage analytics (PostHog)
  - All transcription data stored locally
  - Privacy manifest (PrivacyInfo.xcprivacy)

### Technical Details
- **Platform**: macOS 14.0+ (Sonoma), Apple Silicon required
- **Language**: Swift 5.9, SwiftUI + AppKit
- **Dependencies**: 8 SPM packages (WhisperKit, FluidAudio, MLX Swift, etc.)
- **Architecture**: Native app, no Electron/web views
- **Build system**: XcodeGen + Makefile
- **Tests**: 147 unit tests, 96%+ pass rate

### Known Issues
- First model download may take 5-10 minutes depending on connection
- Whisper Large v3 Turbo requires 16GB RAM for optimal performance
- Command Mode requires pre-selecting text (no automatic selection)

### Migration Notes
- N/A (initial release)

---

## Release Notes Format

For future releases, use this template:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Features planned for removal

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security patches
```

---

*Last updated: 2026-02-26*
