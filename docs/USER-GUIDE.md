# YapYap User Guide

> **You yap. It writes.**
> 100% offline, AI-powered voice-to-text for macOS.

---

## Table of Contents

1. [FAQ](#faq)
2. [How It Works](#how-it-works)
3. [Architecture Overview](#architecture-overview)
4. [Switching Speech-to-Text Models](#switching-speech-to-text-models)
5. [Switching LLM Cleanup Models](#switching-llm-cleanup-models)
6. [Switching Inference Backends](#switching-inference-backends)
7. [Context-Aware Formatting](#context-aware-formatting)
8. [Customizing Prompts](#customizing-prompts)
9. [VAD Tuning](#vad-tuning)
10. [Recommendations by Hardware](#recommendations-by-hardware)
11. [Using Mintlify for Docs](#using-mintlify-for-docs)

---

## FAQ

### General

**Q: Does YapYap send audio or text to any server?**
No. All transcription and AI cleanup runs on your Mac using on-device ML models. No cloud AI, no subscription, no audio leaves your machine. Models are downloaded once from HuggingFace; after that, no internet connection is required.

**Q: What Mac do I need?**
macOS 14.0 (Sonoma) or later, Apple Silicon (M1 or later). Intel Macs are not supported — the app relies on Apple's Neural Engine and MLX framework.

**Q: How much disk space do the models take?**
- STT models: 244MB (Whisper Small) up to 1.5GB (Whisper Large)
- LLM cleanup models: 700MB (Llama 1B) up to 4.7GB (Qwen 7B)
- Running Parakeet + Gemma 4B (the recommended combo): ~3.5GB total

**Q: I have 8GB of RAM. What should I use?**
- STT: Parakeet TDT v3 (fastest, runs on Neural Engine, not GPU/RAM)
- LLM: Qwen 2.5 1.5B or Llama 3.2 1B — both are fast and fit comfortably in 8GB
- Or disable LLM cleanup entirely — raw Parakeet/Whisper output is already pretty clean

**Q: YapYap isn't pasting text after I speak. What's wrong?**
You need to grant Accessibility permission. Go to **System Settings → Privacy & Security → Accessibility** and toggle YapYap on. After every app rebuild (if you're a developer), this permission must be re-granted — macOS silently revokes it when the code signature changes.

**Q: Whisper is hallucinating random text when I'm silent.**
This is a known Whisper behavior — it generates text even from background noise or silence. YapYap runs Silero VAD (Voice Activity Detection) before Whisper to strip silence. If you still see hallucinations:
1. Switch to the Noisy VAD preset in Settings → Advanced
2. Increase the VAD threshold slider
3. Consider switching to Parakeet TDT v3, which doesn't hallucinate on silence

**Q: The transcription has `[BLANK_AUDIO]` or `[Music]` in it.**
These are Whisper artifact strings from YouTube subtitle training data. YapYap strips them automatically in the post-STT pipeline. If they appear, file a bug.

**Q: Can I use YapYap in languages other than English?**
Yes. Parakeet handles 6 languages. Whisper Large handles 10+. Gemma 3 handles 140+ languages for cleanup. For best multilingual results: Whisper Large + Gemma 3 (4B or 1B).

**Q: Can I disable the LLM cleanup and just get raw transcription?**
Yes. In **Settings → Cleanup**, set cleanup to "Off" or select "None" as the LLM model. Raw STT output will be pasted directly.

**Q: What's Command Mode?**
Highlight text in any app, hold the hotkey, and speak a command: "make this more professional" or "translate this to Spanish." YapYap sends both the highlighted text and your spoken command to the LLM and pastes the result.

**Q: My LLM model is echoing back example sentences or garbage text.**
This is a known issue with very small models (1B params) when the prompt contains memorable examples. YapYap uses model-size-aware prompting — small models get ultra-minimal prompts without few-shot examples. If you see this with a 3B+ model, try resetting prompt overrides in Settings → Advanced → Prompts.

**Q: App startup hangs for a long time.**
If startup hangs inside CoreML model loading, it may be an ANE compiler queue backup (`ANECompilerService` at 100% CPU). This can happen after multiple fresh builds. You can either wait it out, or switch to CPU+GPU compute in the WhisperKit settings. Another cause: models stored in `~/Documents/` can be evicted by iCloud to the cloud — YapYap stores models in `~/Library/Application Support/YapYap/models/` to avoid this.

**Q: How do I update YapYap?**
YapYap uses Sparkle for auto-updates. You'll see a notification in the menu bar popover when an update is available. Or check **About → Check for Updates**.

---

### Models

**Q: Which STT model is most accurate?**
Whisper Large v3 Turbo. For English only, Parakeet TDT v3 is competitive and significantly faster. Whisper Medium is a good balance.

**Q: Which LLM model gives the best output quality?**
For 8GB machines: Qwen 2.5 1.5B or Gemma 3 1B.
For 16GB machines: Gemma 3 4B (recommended default) or Llama 3.2 3B.
For 32GB+ machines: Qwen 2.5 7B or Llama 3.1 8B.

**Q: What's the difference between MLX and llama.cpp backends?**
- **MLX**: Apple's own ML framework, best GPU utilization on M-series chips. Uses safetensors format models from HuggingFace. Fastest option.
- **llama.cpp**: Embedded C++ engine, uses GGUF format. Broader model compatibility. No extra software needed.
- **Ollama**: Delegates to an externally-running Ollama server. Lets you bring any model Ollama supports, including ones not in YapYap's registry.

**Q: Can I use a model not in YapYap's registry?**
Yes, with the Ollama backend. Install Ollama, pull any model (`ollama pull mistral`), then in YapYap's Settings → Models → LLM Backend, select Ollama and type the model name.

**Q: The LLM is slow — prefill takes 10+ seconds.**
This usually means the model has been swapped to disk (memory pressure). On 8GB machines, running a browser, Slack, and a 3B model simultaneously can cause this. Use a smaller model (1.5B), or close memory-heavy apps. The prefill time is the canary: <1s = warm, 5-10s+ = swapped.

---

### Prompts & Formatting

**Q: Can I control how YapYap formats output for specific apps?**
Yes. Settings → Styles lets you set per-app-category styles (Very Casual / Casual / Excited / Formal). YapYap also has built-in formatting rules per category — e.g., code editors get backtick-wrapped file names, email gets paragraph structure.

**Q: Can I write custom LLM prompts?**
Yes. Settings → Advanced → Prompts lets you override:
- System prompts (per model size tier: Small / Medium+Large)
- Few-shot examples (input/output pairs)
- Per-category app rules

**Q: How do I teach YapYap to spell my company/product names correctly?**
Settings → Personal Dictionary. Add entries like `yapyap → YapYap` or `kube → Kubernetes`. These are injected into the LLM prompt as a REPLACEMENTS block.

---

## How It Works

```
Hold hotkey
    ↓
Audio Capture (AVAudioEngine, 16kHz mono)
    ↓
VAD Filtering (Silero — strips silence & noise)
    ↓
Speech-to-Text (Parakeet / Whisper / whisper.cpp)
    ↓
Artifact stripping (removes [BLANK_AUDIO], etc.)
    ↓
LLM Cleanup (Qwen / Llama / Gemma via MLX / llama.cpp / Ollama)
    ↓
Post-processing (deterministic regex: backticks, paragraph breaks)
    ↓
Paste into active app (clipboard + synthetic Cmd+V)
Release hotkey
```

The pipeline is push-to-talk by default: hold `Option+Space` to record, release to transcribe and paste. `Option+Shift+Space` toggles hands-free mode (records until silence).

Context is captured at the moment you press the hotkey — your active app, window title, and focused text are read then so the LLM can format appropriately even if you switch apps while speaking.

---

## Architecture Overview

### The Three Layers

**1. STT Layer** — Converts audio to raw text
- `STTEngine` protocol with three backends: WhisperKit, FluidAudio, whisper.cpp
- Selected by `STTEngineFactory` based on model ID
- VAD preprocessing is mandatory — always runs before STT

**2. LLM Layer** — Cleans up and formats raw text
- `LLMEngine` protocol with three backends: MLX, llama.cpp, Ollama
- Selected by `LLMEngineFactory` based on settings
- Optional — user can disable cleanup entirely

**3. Context Layer** — Makes formatting app-aware
- `AppContextDetector` reads the frontmost app (NSWorkspace + AX APIs)
- Maps to one of 11 app categories
- `CleanupPromptBuilderV2` injects the category keyword and cleanup level into the system prompt

### Data Flow Detail

```
AudioCaptureManager → PCM audio buffer (16kHz, mono)
VADManager          → strips silence chunks
STTEngine           → raw transcript string
TranscriptionPipeline → stripWhisperArtifacts()
LLMEngine           → cleanup(rawText:context:)
OutputFormatter     → deterministic post-processing
PasteManager        → inject into active app
```

### Key Protocols

```swift
protocol STTEngine {
    func loadModel(id: String, progressHandler: (Double) -> Void) async throws
    func transcribe(audio: AVAudioPCMBuffer) async throws -> String
}

protocol LLMEngine {
    func loadModel(id: String, progressHandler: (Double) -> Void) async throws
    func cleanup(rawText: String, context: CleanupContext) async throws -> String
}
```

Both protocols allow hot-swapping backends without touching the pipeline.

### Model Storage

All models live in `~/Library/Application Support/YapYap/models/`:
- STT/WhisperKit: `.../models/whisperkit/`
- LLM/MLX: `.../models/llm/`
- GGUF: `.../models/gguf/`

**Never move models to `~/Documents/`** — iCloud will evict large binary files when disk is low, causing hangs.

---

## Switching Speech-to-Text Models

**Where**: Settings → Models → Speech Recognition

### Available Models

| Model | Size | Backend | Languages | Best For |
|-------|------|---------|-----------|----------|
| Parakeet TDT v3 | ~600MB | FluidAudio (ANE) | 6 | Fastest, English-focused, default |
| Whisper Large v3 Turbo | ~1.5GB | WhisperKit (CoreML) | 10+ | Best accuracy, multilingual |
| Whisper Medium | ~769MB | WhisperKit (CoreML) | 8 | Balanced speed/accuracy |
| Whisper Small | ~244MB | WhisperKit (CoreML) | 4 | Minimal RAM footprint |
| Apple Built-in | System | SpeechAnalyzer | 9 | macOS 26+ only, no download |
| Voxtral Mini 3B | ~9.5GB | whisper.cpp | 13 | Coming soon, SOTA multilingual |

### When to Use Each

- **Parakeet TDT v3**: Your everyday default. Runs on the Neural Engine (not CPU/GPU/RAM), so it doesn't compete with your LLM for resources. Fastest transcription.
- **Whisper Large v3 Turbo**: You need the best accuracy, or you're dictating in a language Parakeet doesn't cover (Chinese, Japanese, Korean, Hindi, Arabic, Russian).
- **Whisper Medium**: A middle ground if Large is too slow on your machine.
- **Whisper Small**: 8GB machines where every MB counts, or you want rock-bottom latency.
- **Apple Built-in**: macOS 26+ only. No download, zero RAM overhead, very fast. Good fallback.

### How to Switch

1. Open YapYap menu bar → Settings → Models
2. Under "Speech Recognition", click the model you want
3. If not downloaded, click Download — it will pull from HuggingFace automatically
4. The new model loads on your next recording

No restart required. The model is hot-swapped between recordings.

### Multilingual Tips

- Set the language in Settings → Models → Language for Whisper models to improve accuracy
- Leaving language as "Auto-detect" works well but is slightly slower
- Parakeet is English-first — for non-English, prefer Whisper Large

---

## Switching LLM Cleanup Models

**Where**: Settings → Models → AI Cleanup

### Available Models (MLX / GGUF)

| Model | Size | Tier | Languages | Best For |
|-------|------|------|-----------|----------|
| Qwen 2.5 1.5B | ~1.0GB | Small | 10 | 8GB machines, multilingual |
| Llama 3.2 1B | ~700MB | Small | English | Fastest English cleanup |
| Gemma 3 1B | ~733MB | Small | 140+ | Ultra-multilingual, tight disk |
| Qwen 2.5 3B | ~2.0GB | Medium | 10 | Good multilingual quality |
| Llama 3.2 3B | ~2.0GB | Medium | English | Great English, fast |
| Gemma 3 4B | ~3.0GB | Medium | 140+ | **Recommended default** |
| Qwen 2.5 7B | ~4.7GB | Large | 10 | 16GB+ machines, high quality |
| Llama 3.1 8B | ~4.7GB | Large | English | Best English rewrite quality |

### Model Size Tiers Matter for Prompting

YapYap automatically adjusts its LLM prompts based on model size:

- **Small (≤2B)**: Ultra-minimal prompts — no few-shot examples, just the core rule. Small models are prone to echoing detailed examples verbatim.
- **Medium (3B–4B)**: Full prompts with detailed formatting rules and chat-style few-shot examples.
- **Large (7B+)**: Rich prompts with persona, meta-commands, and the full rule set.

You don't need to tune this — it's automatic. But if you write custom prompts, keep this in mind.

### When to Use Each Family

- **Qwen 2.5**: Best default for multilingual use. Strong instruction-following at all sizes.
- **Llama 3.x**: Best for English-only workflows. Slightly better English grammar than Qwen at the same size.
- **Gemma 3**: Best for non-English languages (supports 140+ languages at both 1B and 4B). The 4B is the recommended default.

### Disabling LLM Cleanup

Settings → Cleanup → Off. Raw STT output will be pasted. Useful when:
- You want maximum speed
- You're dictating code snippets where the LLM might "helpfully" reformat
- Memory is tight and you'd rather not load a second model

---

## Switching Inference Backends

**Where**: Settings → Models → LLM Backend

YapYap supports three backends for running the LLM. The STT backend is fixed per model (Parakeet uses FluidAudio, Whisper uses WhisperKit).

### MLX (Default)

Apple's own ML framework. Uses safetensors model format.

**Pros**: Fastest on M-series. Best GPU utilization. No extra software.
**Cons**: Only runs MLX-formatted models (4-bit quantized safetensors from `mlx-community` on HuggingFace).

**Use when**: You want the best performance on Apple Silicon with no configuration.

### llama.cpp

Embedded C++ inference engine. Uses GGUF model format.

**Pros**: Broad model support (any GGUF from HuggingFace). No extra software. Slightly lower memory usage for some models.
**Cons**: Slightly slower than MLX on Apple Silicon. Different model files needed (separate download).

**Use when**: You want to run a model not available in MLX format, or you prefer GGUF models.

### Ollama

Delegates inference to an externally-running Ollama server.

**Pros**: Supports *any* model Ollama supports (hundreds). You manage the model lifecycle. Useful if you already run Ollama for other tools.
**Cons**: Requires Ollama to be installed and running separately. Extra latency from HTTP.

**Setup**:
1. Install Ollama: `brew install ollama`
2. Start server: `ollama serve`
3. Pull a model: `ollama pull gemma3:4b`
4. In YapYap: Settings → Models → LLM Backend → Ollama
5. Enter model name: `gemma3:4b`
6. Optionally change the endpoint URL if Ollama runs on a different port

The default endpoint is `http://localhost:11434`. YapYap will auto-pull the model if it's not already in Ollama's library.

### Custom Ollama Endpoint

You can point YapYap at a remote Ollama instance (e.g., a more powerful machine on your LAN):

Settings → Models → Ollama Endpoint → `http://192.168.1.100:11434`

Note: This sends your transcription text to that machine for processing. Only do this on a trusted network.

---

## Context-Aware Formatting

YapYap automatically detects your frontmost app and adjusts how it formats text. No configuration needed — it works out of the box.

### App Categories

| Category | Examples | Default Style | Special Rules |
|----------|----------|---------------|---------------|
| Personal Messaging | iMessage, WhatsApp, Telegram, Signal | Casual | Conversational, minimal punctuation |
| Work Messaging | Slack, Teams, Discord, Zoom | Casual | Professional but friendly |
| Email | Mail, Outlook, Gmail, Superhuman | Formal | Paragraph structure, proper greeting/closing |
| Code Editor | Cursor, VS Code, Xcode, Zed, Windsurf | Formal | File names → `@file.py`, backtick vars |
| Terminal | Terminal, iTerm2, Warp | Casual | Shell commands preserved literally |
| Notes | Notes, Obsidian, Bear | Casual | Paragraph-aware |
| Documents | Pages, Notion, Google Docs | Formal | Full paragraph structure |
| AI Chat | ChatGPT, Claude, Perplexity | Casual | Question structure preserved |
| Browser | Safari, Chrome, Firefox, Arc | Casual | URL-aware context (Gmail = email rules) |
| Social Media | Twitter/X, Reddit, Mastodon | Casual | Short form, hashtags preserved |
| Other | Everything else | Casual | Generic cleanup |

### Per-Category Style Override

You can set a different output style per category in **Settings → Styles**:

- **Very Casual**: `hey yeah that sounds good to me` — no capitalization, no punctuation
- **Casual**: `Hey, yeah that sounds good to me` — normal capitalization, minimal punctuation
- **Excited**: `Hey, yeah that sounds good to me!` — exclamation marks added
- **Formal**: `Hey, that sounds good to me.` — full stops, structured sentences

### Browser Tab Detection

When you're in a browser, YapYap reads the tab URL or title to pick the right category:
- Gmail / Outlook / Fastmail → email rules
- GitHub / GitLab → code editor rules
- LinkedIn → professional tone, short punchy paragraphs
- Twitter/X / Reddit → social media rules

### Code Editor Special Rules

When YapYap detects a code editor, it applies extra transformations:
- `open main dot py` → `Open @main.py`
- `check user underscore controller dot swift` → `Check @user_controller.swift`
- Variable names get backtick wrapping when appropriate
- Shell commands are preserved literally (no reordering into prose)

---

## Customizing Prompts

**Where**: Settings → Advanced → Prompts

### How the Prompt System Works

YapYap builds LLM prompts in three layers:

1. **System prompt** — the core instructions sent before any examples
2. **Few-shot examples** — user/assistant message pairs demonstrating desired behavior
3. **Category rules** — per-app-category formatting instructions appended to the system prompt

All three are overridable.

### The V2 Prompt Format

YapYap uses chat-style prompting (V2). A request looks like:

```
[system]    You are a deterministic STT refinement engine...
            CONTEXT: IDE
            HARD RULES: 1. Output ONLY the refined text...
            ...

[user]      Reformat: hey uh open the main dot py file
[assistant] Open the @main.py file.

[user]      Reformat: i think the bug is in user controller dot py line 45
[assistant] I think the bug is in @user_controller.py line 45.

[user]      Reformat: {your actual transcription}
```

The "Reformat:" prefix is what signals to the model that this is a transcription cleanup task, not a conversation.

### Cleanup Levels

Three cleanup levels are selectable in Settings → Cleanup:

- **Light**: Fix punctuation and capitalization only. Keep all words including fillers.
- **Medium** (default): Remove obvious fillers (uh, um, like, so). Fix grammar. Preserve meaning.
- **Heavy**: Full grammar fix, remove all fillers and hesitations. Self-corrections ("X no wait Y") collapse to just Y.

The cleanup level is injected into the system prompt as rule #3.

### Overriding the System Prompt

In Settings → Advanced → Prompts → System Prompts, you can replace the built-in system prompt for each tier:

| Variant | When Used |
|---------|-----------|
| Small Model — Light | ≤2B models, light cleanup |
| Small Model — Medium | ≤2B models, medium cleanup |
| Small Model — Heavy | ≤2B models, heavy cleanup |
| Medium / Large Model | 3B+ models, all cleanup levels |

Click "Edit" next to any variant, toggle "Custom enabled", and write your prompt. Click "Reset to Default" to revert.

**Tips for writing system prompts:**
- Keep small model prompts under 200 tokens — they can't follow long instruction lists reliably
- Start with: `You are a deterministic STT refinement engine, not a chatbot.`
- The single most important rule: `Output ONLY the refined text. No preface, no explanation.`
- Use `CONTEXT: {appContext}` — the app keyword is injected automatically if you use the placeholder

### Overriding Few-Shot Examples

In Settings → Advanced → Prompts → Few-Shot Examples, you can add, remove, or replace the example input/output pairs.

The examples are formatted as `Reformat: {input}` / `{output}` pairs. The model learns the format from these.

**Good few-shot examples:**
- Cover the edge cases you care about (code file names, technical jargon)
- Demonstrate the exact output style you want
- Keep inputs realistic — they should look like actual STT output (lowercase, no punctuation)

**Example for a medical professional:**
```
Input:  uh the patient presented with elevated bpm and uh uh shortness of breath
Output: The patient presented with elevated BPM and shortness of breath.
```

**Example for a developer who wants aggressive file tagging:**
```
Input:  check the docker file and the readme
Output: Check the @Dockerfile and the @README.
```

### Overriding Category Rules

In Settings → Advanced → Prompts → App Rules, you can customize the rules for each app category.

Select a category, toggle "Custom enabled", and write rules that will be appended to the system prompt when that app category is detected.

**Example custom rule for Work Messaging:**
```
Always use bullet points for lists.
Never use exclamation marks.
Keep messages under 3 sentences.
```

### Personal Dictionary

Settings → Personal Dictionary. Add custom vocabulary corrections and replacements.

**Vocabulary entries** (pronunciation → correct spelling):
- `yapyap` → `YapYap`
- `kube` → `Kubernetes`
- `gema` → `Gemma`

**Replacement entries** (exact match → replacement):
- `my company` → `Acme Corp`
- `the app` → `YapYap`

These are injected into the LLM prompt as rules 15 and 16 when present.

---

## VAD Tuning

Voice Activity Detection (VAD) runs before the STT model to strip silence and background noise. This prevents Whisper hallucinations and improves accuracy.

**Where**: Settings → Advanced → Microphone

### Presets

| Preset | Threshold | Best For |
|--------|-----------|----------|
| Default | 0.10 | Normal home/office environment |
| Quiet | 0.05 | Very quiet rooms, soft speakers |
| Noisy | 0.20 | Cafés, open offices, background music |

### Manual Tuning

If the presets don't work well, you can adjust the threshold slider:

- **Too high** (0.3+): YapYap misses the start of sentences, clips quiet words
- **Too low** (0.03): Background noise triggers false speech detection, Whisper hallucinates

Other settings:
- **Min speech duration**: Minimum length (ms) for a speech segment to be passed to STT. Increase to filter out coughs/clicks.
- **Min silence duration**: How long a silence must last to end a segment. Increase for natural pauses in speech.
- **Speech padding**: Extra audio added around detected speech segments to avoid clipping. Leave at 100ms unless you notice word-boundary issues.

---

## Recommendations by Hardware

### 8GB RAM (M1 / M2 base)

**STT**: Parakeet TDT v3 — runs on ANE, doesn't touch system RAM budget
**LLM**: Qwen 2.5 1.5B (MLX) or disable LLM entirely
**Backend**: MLX

If you want slightly better quality: Llama 3.2 1B (English) or Gemma 3 1B (multilingual). All three 1B models are in a similar RAM footprint (~700–800MB).

Avoid 3B+ models on 8GB — they may work but will slow down the rest of your system.

### 16GB RAM (M1 Pro / M2 Pro)

**STT**: Parakeet TDT v3
**LLM**: Gemma 3 4B (recommended) or Qwen 2.5 3B
**Backend**: MLX

Gemma 3 4B is the sweet spot at this tier — best instruction-following quality while still fitting comfortably in memory alongside other apps.

### 32GB+ RAM (M1 Max / M2 Max / M3 Pro+)

**STT**: Whisper Large v3 Turbo or Parakeet TDT v3
**LLM**: Qwen 2.5 7B or Llama 3.1 8B
**Backend**: MLX

At this tier you can comfortably run 7B–8B models. Qwen 2.5 7B is the best multilingual option; Llama 3.1 8B gives the best English rewrite quality.

---

## Using Mintlify for Docs

[Mintlify](https://mintlify.com) is an excellent open-source documentation platform well-suited for YapYap's docs. It supports MDX files, auto-generated API references, and a clean reading experience.

### What Mintlify Gives You

- Beautiful docs site with search, dark mode, and navigation
- MDX format (Markdown + JSX components)
- `mint.json` config for navigation, colors, branding
- Free for open-source projects
- GitHub integration — docs update on every push

### Setup

1. Install the Mintlify CLI:
   ```bash
   npm install -g mintlify
   ```

2. Create a `docs/` folder at the root of the repo with a `mint.json`:
   ```json
   {
     "name": "YapYap",
     "logo": {
       "light": "/logo/light.png",
       "dark": "/logo/dark.png"
     },
     "favicon": "/favicon.png",
     "colors": {
       "primary": "#6366f1",
       "light": "#818cf8",
       "dark": "#4f46e5"
     },
     "navigation": [
       {
         "group": "Getting Started",
         "pages": ["introduction", "installation", "quick-start"]
       },
       {
         "group": "Models",
         "pages": ["models/stt", "models/llm", "models/backends"]
       },
       {
         "group": "Customization",
         "pages": ["customization/prompts", "customization/styles", "customization/dictionary"]
       },
       {
         "group": "Advanced",
         "pages": ["advanced/vad", "advanced/architecture", "advanced/faq"]
       }
     ]
   }
   ```

3. Convert this USER-GUIDE.md into separate MDX files per section (each page in `mint.json` is one `.mdx` file).

4. Preview locally:
   ```bash
   mintlify dev
   ```

5. Deploy to Mintlify's hosting:
   ```bash
   mintlify deploy
   ```

### Alternative: Docusaurus

If you prefer a self-hosted option with no third-party dependency:

```bash
npx create-docusaurus@latest yapyap-docs classic
```

Docusaurus is React-based, supports MDX, and is well-maintained by Meta. Free, self-hosted, GitHub Pages friendly.

### Recommendation

For an open-source project at YapYap's stage, **Mintlify** is the fastest path to a polished docs site. The free tier covers all needs. The main tradeoff is hosting dependency on Mintlify's infrastructure — if that's a concern, Docusaurus on GitHub Pages is a fully self-hosted alternative with comparable quality.

---

*This guide covers YapYap as of v0.2.9. Architecture details: `files/00-ARCHITECTURE.md`. UI spec: `docs/UI-SPEC.md`.*
