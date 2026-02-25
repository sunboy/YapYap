# YapYap

**You yap. It writes.**

An open-source, offline, macOS voice-to-text app with AI-powered cleanup. A cozy creature lives in your menu bar, listens when you speak, and pastes clean, formatted text into any app.

> **100% offline** — your voice never leaves your Mac
> **AI cleanup** — removes filler words, fixes grammar, matches your style
> **Open source** — MIT licensed, no subscriptions, no tracking
> **A little creature** — because software should have soul

---

## Features

- **Push-to-Talk**: Hold Option+Space, speak, release — clean text appears where your cursor is
- **Hands-Free Mode**: Toggle recording with Option+Shift+Space, auto-stops on silence
- **Multiple STT Models**: Choose between Whisper (Large/Medium/Small), Parakeet TDT v3, or Voxtral
- **Multiple LLM Models**: Qwen 2.5, Llama 3.2, or Gemma 2 for text cleanup — all running locally
- **Context-Aware**: Auto-detects your app and adjusts formatting (casual for iMessage, formal for email, backticks for code editors)
- **Writing Styles**: Casual, neutral, or formal. Custom prompts. Per-app style overrides
- **Command Mode**: Highlight text, speak a command ("make this more professional") — AI rewrites
- **Floating Bar**: A cozy creature companion that shows recording status without stealing focus
- **Transcription History**: Browse, search, and copy past transcriptions
- **Analytics**: Track your yapping stats — words, time saved, daily trends

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1 or later) — required for on-device ML inference
- 8GB RAM minimum (16GB recommended for larger models)
- ~2-4GB disk space for AI models

## Installation

### Download
Get the latest release from [GitHub Releases](https://github.com/sunboy/yapyap/releases).

### Homebrew
```bash
brew install --cask yapyap
```

### Build from Source
See [BUILDING.md](BUILDING.md) for detailed instructions.

```bash
git clone https://github.com/sunboy/yapyap.git
cd yapyap
brew install xcodegen
xcodegen generate
make build
open build/Debug/YapYap.app
```

## How It Works

```
You speak → YapYap captures audio
         → VAD filters silence/noise (Silero)
         → Speech-to-Text (Whisper/Parakeet, on-device)
         → AI Cleanup (Qwen/Llama/Gemma, on-device)
         → Clean text pasted into your active app
```

Everything runs locally on your Mac. No cloud. No API keys. No internet required after model download.

## STT Models

| Model | Size | Speed | Best For |
|-------|------|-------|----------|
| Parakeet TDT v3 | ~600MB | Fast | Fastest, runs on Neural Engine |
| Whisper Large v3 Turbo | ~1.5GB | Good | Best accuracy, multilingual |
| Whisper Medium | ~769MB | Fast | Good balance |
| Whisper Small | ~244MB | Fast | Low-spec machines |

## LLM Cleanup Models

| Model | Size | Speed | Best For |
|-------|------|-------|----------|
| Qwen 2.5 3B | ~2.0GB | Fast | Default — fast, multilingual |
| Qwen 2.5 7B | ~4.7GB | Good | Higher quality rewrites |
| Llama 3.2 3B | ~2.0GB | Fast | Great for English |
| Llama 3.1 8B | ~4.7GB | Good | Best rewrite quality |

## Architecture

Native Swift + SwiftUI app. No Electron, no web views.

- **STT**: WhisperKit (CoreML) + FluidAudio (Parakeet/ANE) + whisper.cpp
- **LLM**: MLX Swift with 4-bit quantized models from HuggingFace
- **Audio**: AVAudioEngine with 16kHz mono capture + Silero VAD
- **Data**: SwiftData (SQLite) for settings, history, analytics
- **UI**: SwiftUI + AppKit (NSStatusItem, NSPopover, NSPanel, NSWindow)

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full system design.

## Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

1. Fork the repo
2. Create a feature branch
3. Open an issue to discuss before large changes
4. Submit a PR with clear description

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — On-device Whisper inference
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet CoreML models
- [MLX Swift](https://github.com/ml-explore/mlx-swift) — Apple's ML framework
- [VoiceInk](https://github.com/Beingpax/VoiceInk) — Inspiration for the native macOS approach
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Global hotkeys
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Auto-updates

---

*Made with love and too much coffee*
