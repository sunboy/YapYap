# YapYap — Architecture Decision Record & System Design

> **You yap. It writes.** — An open-source, offline, macOS voice-to-text app that rivals WisprFlow.
> Version: 0.1.0 | Platform: macOS 14+ (Sonoma) | Apple Silicon Required (M1+)

---

## 1. Architecture Decision: Native Swift (Not Tauri/Electron)

**Decision: Pure native Swift + SwiftUI**

**Rationale:**
- **Performance**: Menu bar apps need zero-overhead startup. Electron adds 150MB+ baseline RAM; we need <80MB idle.
- **NSStatusItem + NSPopover + NSPanel**: These are AppKit-specific APIs with no Electron equivalent. The floating bar (`NSPanel` with `.nonactivatingPanel`) literally cannot be built in web tech without focus-stealing hacks.
- **ML integration**: WhisperKit, FluidAudio, and MLX Swift are all native Swift packages. Bridging through Electron adds latency to the hot path (audio → transcription → LLM cleanup → paste).
- **Accessibility APIs**: `AXUIElement` for getting selected text, `CGEvent` for synthetic paste — these require native entitlements.
- **VoiceInk proves the model**: 2.6k GitHub stars, 99.6% Swift, native macOS, uses whisper.cpp + FluidAudio. We follow the same approach but with differentiated UX and multi-model LLM cleanup.
- **Distribution**: Native `.app` bundle, Sparkle for updates, Homebrew cask, GitHub Releases. No npm/node runtime dependency.

---

## 2. High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    YapYap.app (Swift)                        │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │  UI      │  │  Audio   │  │  STT     │  │  LLM       │  │
│  │  Layer   │  │  Engine  │  │  Engine  │  │  Engine    │  │
│  │          │  │          │  │          │  │            │  │
│  │ SwiftUI  │  │AVAudio-  │  │WhisperKit│  │MLX Swift   │  │
│  │ AppKit   │  │Engine    │  │FluidAudio│  │(Qwen/Llama │  │
│  │          │  │          │  │whisper.  │  │ /Gemma)    │  │
│  │          │  │          │  │cpp       │  │            │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬───────┘  │
│       │             │             │              │           │
│  ┌────┴─────────────┴─────────────┴──────────────┴───────┐  │
│  │              Core Pipeline (async/await)               │  │
│  │  AudioCapture → VAD → STT → LLM Cleanup → Paste      │  │
│  └───────────────────────┬───────────────────────────────┘  │
│                          │                                   │
│  ┌───────────────────────┴───────────────────────────────┐  │
│  │              Persistence Layer (SQLite + SwiftData)     │  │
│  │  Settings | History | Analytics | Model Registry       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. STT Engine Architecture

### Decision: Dual-Backend STT with Protocol Abstraction

We support multiple STT backends behind a single `STTEngine` protocol:

```swift
protocol STTEngine {
    var modelInfo: STTModelInfo { get }
    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult
    func transcribeStream(audio: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<PartialTranscription>
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws
    func unloadModel()
    var isLoaded: Bool { get }
}
```

### Supported STT Models

| Model | Backend | Size | Speed | Quality | Notes |
|-------|---------|------|-------|---------|-------|
| **Whisper Large v3 Turbo** | WhisperKit (CoreML) | ~800MB | ★★★★ | ★★★★★ | Best overall. CoreML optimized for Apple Silicon. Default. |
| **Whisper Medium** | WhisperKit (CoreML) | ~500MB | ★★★★★ | ★★★★ | Fast, good accuracy. Best for 8GB machines. |
| **Whisper Small** | WhisperKit (CoreML) | ~250MB | ★★★★★ | ★★★ | Lightest Whisper. Fallback for low-spec machines. |
| **Parakeet TDT v3 0.6B** | FluidAudio (CoreML/ANE) | ~600MB | ★★★★★ | ★★★★★ | NVIDIA's SOTA. Runs on ANE (Neural Engine) = minimal CPU/GPU. **Recommended.** |
| **Voxtral (Mistral STT)** | whisper.cpp (GGML) | ~650MB | ★★★★ | ★★★★ | Mistral's model. Good multilingual. Experimental. |

### STT Backend Details

**Backend 1: WhisperKit (Primary for Whisper models)**
- Swift Package: `github.com/argmaxinc/WhisperKit`
- Uses CoreML under the hood → runs on GPU/ANE automatically
- Pre-converted models from `argmaxinc/whisperkit-coreml` on HuggingFace
- Supports streaming transcription via `transcribeStream()`
- Handles VAD internally

**Backend 2: FluidAudio (Primary for Parakeet)**
- Swift Package: `github.com/FluidInference/FluidAudio`
- Runs on ANE (Apple Neural Engine) — avoids GPU/CPU contention entirely
- CoreML-converted Parakeet models from `FluidInference/parakeet-tdt-0.6b-v2-coreml`
- Built-in VAD + speaker diarization (future feature)
- **Best latency** — processes faster than real-time on M1+

**Backend 3: whisper.cpp (Fallback / Voxtral)**
- C library with Swift bridge: `github.com/ggerganov/whisper.cpp`
- GGML format models — more model variety, broader compatibility
- Used for Voxtral and any future GGML-format STT models
- Slightly more setup but maximum flexibility

### Model Download & Management

Models are NOT bundled with the app. On first launch:
1. User picks a model (default: Parakeet TDT v3)
2. App downloads from HuggingFace to `~/Library/Application Support/YapYap/Models/`
3. Progress shown in Settings → Models with download bar
4. Models can be switched, downloaded, or deleted from Settings

**Model lifecycle:** Users can delete any inactive (non-selected) model from Settings → Models to free disk space. Deleted models revert to a "Download" state and can be re-downloaded on demand. The active STT and LLM models cannot be deleted while selected — user must switch to another model first.

---

## 4. LLM Cleanup Engine Architecture

### Decision: MLX Swift for LLM inference

**Why MLX (not llama.cpp, not Ollama):**
- MLX achieves highest sustained throughput on Apple Silicon (benchmarked in academic papers)
- Zero-copy unified memory operations — no CPU↔GPU transfer overhead
- Native Swift API via `mlx-swift` and `mlx-swift-lm` packages
- 4-bit quantized models fit in ~1-2GB RAM for 1-3B parameter models
- Apple is actively investing: WWDC 2025 dedicated session, M5 Neural Accelerator support

**Why small models (1B-3B, not 7B+):**
- Cleanup task is narrow-scope: fix grammar, remove filler, apply style. Not general reasoning.
- 1B-3B models at 4-bit run at 100-500 tok/s on M1+ — fast enough for real-time
- Memory: 1B 4-bit ≈ 0.6GB, 3B 4-bit ≈ 1.8GB — leaves plenty for STT + app
- Users with 8GB RAM can run both STT + LLM simultaneously

### Supported LLM Models

| Model | HuggingFace ID (MLX) | Size (4-bit) | Speed (M1) | Quality | Notes |
|-------|----------------------|-------------|------------|---------|-------|
| **Qwen 2.5 1.5B Instruct** | `mlx-community/Qwen2.5-1.5B-Instruct-4bit` | ~0.9GB | ★★★★★ | ★★★★ | **Default.** Excellent multilingual. Fast. |
| **Qwen 2.5 3B Instruct** | `mlx-community/Qwen2.5-3B-Instruct-4bit` | ~1.8GB | ★★★★ | ★★★★★ | Better quality. 16GB+ RAM recommended. |
| **Llama 3.2 1B Instruct** | `mlx-community/Llama-3.2-1B-Instruct-4bit` | ~0.7GB | ★★★★★ | ★★★ | Fastest. Good English. |
| **Llama 3.2 3B Instruct** | `mlx-community/Llama-3.2-3B-Instruct-4bit` | ~1.8GB | ★★★★ | ★★★★ | Great tone-matching. |
| **Gemma 2 2B Instruct** | `mlx-community/gemma-2-2b-it-4bit` | ~1.4GB | ★★★★ | ★★★★ | Google's model. Good at instruction following. |

### LLM Cleanup Pipeline

```swift
protocol LLMEngine {
    func cleanup(rawTranscription: String, context: CleanupContext) async throws -> String
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws
    func unloadModel()
    var isLoaded: Bool { get }
}

struct CleanupContext {
    let stylePrompt: String      // User's custom style instructions
    let formality: Formality     // .casual / .neutral / .formal
    let language: String         // "en-US", "es", "fr", etc.
    let appContext: AppContext?   // Full app detection result (category, style, window title, etc.)
    let selectedText: String?    // Text already in the field (for context)
    let cleanupLevel: CleanupLevel // .light / .medium / .heavy
    let removeFillers: Bool      // User toggle from Settings
}
```

**System prompt template (injected at inference):**
```
You are a writing assistant that cleans up voice transcriptions.

Rules:
- Remove filler words (um, uh, like, you know, basically, so, I mean)
- Fix grammar and punctuation
- {formality_instruction}
- {cleanup_level_instruction}
- {app_formatting_instruction}   ← from AppContext (email paragraphs, Slack concise, IDE backticks, etc.)
- {style_instruction}            ← from OutputStyle (very casual no caps/periods, formal full punctuation, etc.)
- {user_style_prompt}
- Preserve the speaker's intent and meaning exactly
- Do NOT add information that wasn't spoken
- Output ONLY the cleaned text, nothing else

{existing_field_text_context}    ← "The user is continuing from: ..." (if available)

Raw transcription:
{raw_text}
```

---

## 5. Audio Capture Pipeline

```swift
class AudioCaptureManager: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    
    // Configuration
    let sampleRate: Double = 16000  // Required by Whisper/Parakeet
    let channelCount: Int = 1       // Mono
    let bufferSize: AVAudioFrameCount = 1024
    
    // Pipeline: Mic → Tap → Ring Buffer → VAD → STT
    func startCapture() async throws {
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let convertFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let converter = AVAudioConverter(from: inputFormat, to: convertFormat)!
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { 
            [weak self] buffer, time in
            // Convert to 16kHz mono Float32
            // Feed to ring buffer
            // Calculate RMS for waveform visualization
        }
        
        try audioEngine.start()
    }
}
```

### Voice Activity Detection (VAD)

For push-to-talk mode: No VAD needed — record while key held.
For hands-free mode: Use energy-based VAD + optional WebRTC VAD:
- Simple RMS threshold for silence detection
- Configurable silence duration before auto-stop (default: 1.5s)
- FluidAudio includes built-in VAD for Parakeet pipeline

---

## 5a. Audio Robustness & STT Parameter Tuning

> **Goal: Match WisprFlow's "speak naturally, get clean text" experience — but offline.**
>
> WisprFlow achieves this via cloud-based multi-layer AI processing. YapYap must match the perceived quality using a local 3-stage pipeline: **VAD pre-filtering → optimized STT decoding → LLM post-cleanup**.

### Strategy Overview: The 3-Stage Clean Speech Pipeline

```
 Stage 1: VAD Pre-Filter          Stage 2: STT with Tuned Params     Stage 3: LLM Post-Cleanup
 ─────────────────────────         ──────────────────────────────      ─────────────────────────
 Silero VAD (CoreML)               Model-specific parameters           Qwen/Llama via MLX
 • Strips silence/noise            • Suppress hallucinations           • Remove remaining fillers
 • Isolates speech segments        • Optimize for noisy audio          • Fix grammar & punctuation
 • Reduces hallucinations          • Control filler word behavior      • Apply writing style
 • <1ms per 32ms chunk             • Decoder-level robustness          • Self-correction handling
```

**Key insight from research:** Traditional audio denoising (spectral subtraction, etc.) often *hurts* STT accuracy because it distorts the spectral representation the model was trained on. Instead, the effective approach is: **VAD to remove non-speech → feed only speech to STT → LLM to clean up output.** This is what faster-whisper, WhisperX, and production pipelines all converge on.

### Stage 1: Silero VAD Pre-Filter (All Backends)

**FluidAudio ships with Silero VAD already converted to CoreML** (via `FluidInference/silero-vad-coreml`). The model is ~1.4MB total across 3 CoreML sub-models (STFT: 650KB, encoder: 254KB, RNN decoder: 527KB). It processes 32ms chunks in <1ms on Apple Silicon via ANE.

YapYap uses Silero VAD as the **universal pre-filter** before any STT engine:

```swift
struct VADConfig {
    // Speech detection sensitivity (0.0 = everything is speech, 1.0 = very selective)
    var threshold: Float = 0.35          // Default: slightly sensitive to catch quiet speech
    var minSpeechDurationMs: Int = 200   // Ignore bursts shorter than 200ms (coughs, clicks)
    var minSilenceDurationMs: Int = 300  // Need 300ms silence to split segments
    var speechPadMs: Int = 100           // Pad 100ms before/after detected speech to avoid clipping
    var maxSpeechDurationS: Float = 30   // Auto-split very long segments at silence points
}

// Noisy environment preset (user can toggle in Settings → General)
static let noisyPreset = VADConfig(
    threshold: 0.5,                 // Higher threshold = more selective, ignores background chatter
    minSpeechDurationMs: 300,       // Require longer speech to trigger (filters short noise bursts)
    minSilenceDurationMs: 200,      // Shorter silence tolerance (keep speech flowing)
    speechPadMs: 150,               // Extra padding to catch soft word beginnings
    maxSpeechDurationS: 30
)

// Quiet environment preset
static let quietPreset = VADConfig(
    threshold: 0.25,                // Lower threshold = catches quiet/whispered speech
    minSpeechDurationMs: 150,       // More sensitive to short utterances
    minSilenceDurationMs: 400,      // Longer silence needed to split (natural pauses OK)
    speechPadMs: 80,
    maxSpeechDurationS: 30
)
```

**Why Silero VAD is critical:**
- Prevents Whisper hallucinations during silence ("Thank you for watching", "Subscribe to my channel" — real artifacts Whisper generates from background noise)
- Reduces STT processing time by 40-60% for audio with significant silence/noise
- Isolates actual speech segments so STT models receive only voice data
- The Silero model was trained on 6000+ languages with various background conditions

### Stage 2: Per-Model STT Parameter Optimization

Each STT backend has different knobs. Here are the research-backed optimal parameters:

#### WhisperKit (Whisper models) — `DecodingOptions`

```swift
// YapYap optimized DecodingOptions for voice dictation in real-world environments
let whisperOptions = DecodingOptions(
    // --- Core Decoding ---
    task: .transcribe,
    temperature: 0.0,                      // Deterministic decoding (no randomness) — critical for consistency
    temperatureFallbackCount: 3,           // On failure, retry with [0.2, 0.4, 0.6] — catches hard segments
    sampleLength: 224,                     // Max tokens per segment (default)
    
    // --- Anti-Hallucination (Critical for noisy audio) ---
    compressionRatioThreshold: 2.4,        // Flag repetitive text (Whisper's "infinite loop" hallucination)
    logProbThreshold: -0.8,                // TIGHTER than default -1.0 — reject low-confidence segments
    firstTokenLogProbThreshold: -1.0,      // Reject if first token is already uncertain
    noSpeechThreshold: 0.5,               // LOWER than default 0.6 — less aggressive silence filtering
                                           // (Silero VAD already handled silence, so be lenient here)
    
    // --- Blank & Token Suppression ---
    suppressBlank: true,                   // Suppress blank tokens (reduces empty segments)
    supressTokens: [-1],                   // Default suppression list
    
    // --- Context & Conditioning ---
    usePrefillPrompt: true,                // Use task+language prefill for consistent output
    usePrefillCache: true,                 // Cache KV for prefill (faster)
    withoutTimestamps: true,               // We don't need timestamps for dictation — saves decode time
    wordTimestamps: false,                 // No word-level timing needed
    
    // --- Language ---
    language: nil,                         // Auto-detect (or set from user preference)
    detectLanguage: true                   // Auto language detection
)
```

**Parameter rationale for noisy environments:**
- `noSpeechThreshold: 0.5` (lower than default 0.6): Since Silero VAD already filters silence, we don't need Whisper's internal silence detection to be aggressive. A lower threshold means fewer valid speech segments get incorrectly dropped.
- `logProbThreshold: -0.8` (tighter than default -1.0): In noisy audio, Whisper can produce low-confidence hallucinated text. Tightening this rejects uncertain segments rather than outputting garbage.
- `compressionRatioThreshold: 2.4`: Catches the classic Whisper failure where it repeats phrases indefinitely. Essential for real-world audio.
- `temperature: 0.0` with fallback: Greedy decoding is most reliable for dictation. Temperature fallback catches edge cases where greedy fails.
- `withoutTimestamps: true`: Skips timestamp prediction overhead — 10-15% faster for pure dictation.

#### FluidAudio (Parakeet TDT) — Minimal Configuration Needed

Parakeet's TDT architecture is **inherently more robust** than Whisper for noisy audio:
- TDT (Token Duration Transducer) predicts both tokens AND durations, which naturally filters noise
- Trained on 120,000+ hours including diverse noise conditions (YouTube, telephony, varied SNR)
- Auto punctuation & capitalization built-in (no LLM needed for basic formatting)
- No hallucination problem — CTC/Transducer models don't generate text from silence like attention-based Whisper

```swift
// FluidAudio Parakeet configuration
let parakeetConfig = ASRConfig(
    sampleRate: 16000,                    // Required: 16kHz mono
    language: .auto,                      // Auto-detect from 25 European languages
    enableTimestamps: false,              // Skip timestamps for dictation speed
    enableVAD: true,                      // Use FluidAudio's built-in Silero VAD
    vadConfig: VADConfig(                 // FluidAudio accepts our VAD config
        threshold: 0.35,
        chunkSize: 512                    // 512 samples = optimal for Silero CoreML batch
    )
)
```

**Why Parakeet needs less tuning:**
- No compression ratio / log probability thresholds — these are Whisper-specific heuristics
- No temperature or beam search — Parakeet uses TDT greedy decoding which is faster and more stable
- Noise robustness is baked into the architecture (FastConformer encoder + attention masking)
- NVIDIA reports "robust performance under varied noise conditions" with "only modest degradation at lower SNRs"

#### whisper.cpp (Voxtral / GGML models) — CLI-Style Parameters

```swift
// whisper.cpp parameter struct mapping
struct WhisperCppParams {
    var language: String = "auto"
    var translate: Bool = false
    
    // --- Decoding ---
    var beamSize: Int = 5                  // Beam search for better accuracy (vs greedy)
    var bestOf: Int = 5                    // Number of candidates from sampling
    var temperature: Float = 0.0           // Greedy decoding
    var temperatureInc: Float = 0.2        // Fallback temperature increment
    
    // --- Anti-Hallucination ---
    var entropyThreshold: Float = 2.4      // = compression ratio threshold
    var logprobThreshold: Float = -0.8     // Tightened for noisy audio
    var noSpeechThreshold: Float = 0.5     // Lowered since VAD pre-filters
    
    // --- VAD (whisper.cpp has built-in Silero VAD support since 2025) ---
    var vadEnabled: Bool = true            // Enable built-in Silero VAD
    var vadThreshold: Float = 0.35         // Speech detection probability threshold
    var vadMinSpeechDurationMs: Int = 200  // Minimum speech segment length
    var vadMinSilenceDurationMs: Int = 300 // Minimum silence to split segments
    var vadMaxSpeechDurationS: Float = 30  // Maximum segment before auto-split
    
    // --- Speed ---
    var noTimestamps: Bool = true          // Skip timestamps for dictation
    var suppressBlank: Bool = true
}
```

### Stage 3: Filler Word Removal Strategy

**Research finding:** Whisper models natively suppress most "um" and "uh" filler words — this is a training artifact, not a bug. The model was trained on cleaned transcriptions, so it learned to skip fillers. However, in longer recordings or noisy conditions, fillers can leak through (especially "like", "you know", "I mean", "sort of").

Parakeet also auto-formats with punctuation/capitalization but preserves some disfluencies since it aims for verbatim transcription.

**YapYap's multi-layer filler removal approach:**

```
Layer 1 (STT-level):  Whisper's natural filler suppression (built-in, free)
                       Parakeet: verbatim output, fillers preserved
                       
Layer 2 (LLM Cleanup): System prompt instructs filler removal
                        "Remove filler words (um, uh, like, you know, I mean, sort of,
                         basically, actually, literally, kind of, so yeah)."
                        Also handles self-corrections: "meet Tuesday, no wait, Wednesday"
                        → outputs only the corrected version

Layer 3 (Regex guard):  Post-LLM safety net for any remaining isolated fillers
                        Pattern: /\b(um+|uh+|ah+|er+|hmm+)\b[,.]?\s?/gi
                        Only applied when "Remove Fillers" is enabled in Settings
```

**CleanupPromptBuilder additions for filler/noise handling:**

```swift
extension CleanupPromptBuilder {
    static func buildFillerRemovalInstruction(level: CleanupLevel) -> String {
        switch level {
        case .minimal:
            // Only remove hesitation sounds
            return """
            Remove hesitation sounds (um, uh, ah, er, hmm) from the text.
            Keep everything else exactly as spoken.
            """
        case .standard:
            // Remove fillers + self-corrections
            return """
            Clean up the transcription:
            - Remove filler words: um, uh, ah, er, hmm, like (when used as filler), 
              you know, I mean, sort of, kind of, basically, actually, literally, so yeah.
            - Handle self-corrections: if the speaker corrects themselves mid-sentence 
              (e.g., "meet Tuesday, no Wednesday"), output only the corrected version ("meet Wednesday").
            - Remove false starts and repeated words (e.g., "I I I think" → "I think").
            - Preserve the speaker's intended meaning and tone.
            """
        case .aggressive:
            // Full rewrite for clarity
            return """
            Rewrite the transcription as clean, clear prose:
            - Remove ALL filler words and verbal tics.
            - Resolve self-corrections to final intent only.
            - Fix run-on sentences and add proper paragraph breaks.
            - Maintain the speaker's voice and personality but make it read like polished writing.
            """
        }
    }
}
```

### Noise Environment Handling Summary

| Scenario | VAD Preset | STT Recommendation | LLM Cleanup Level |
|----------|-----------|-------------------|-------------------|
| **Quiet home/office** | `quietPreset` (threshold: 0.25) | Parakeet or Whisper Large — max accuracy | `minimal` — speech already clean |
| **Open office / café** | `noisyPreset` (threshold: 0.5) | Parakeet (inherently noise-robust) | `standard` — catch noise artifacts |
| **Street / commute** | `noisyPreset` (threshold: 0.5) | Parakeet strongly recommended | `standard` or `aggressive` |
| **Video call (speaker audio)** | Default (threshold: 0.35) | Whisper Large — best for mixed audio | `standard` |

### Settings UI: "Audio Quality" Section (in General tab)

Expose these as a single, user-friendly toggle in Settings → General:

```
Environment Mode: [Auto] [Quiet] [Noisy]
   Auto: Monitors ambient RMS level and switches VAD presets dynamically
   Quiet: Optimized for low-noise environments (lower VAD threshold)
   Noisy: Aggressive noise filtering (higher VAD threshold)

Remove Filler Words: [ON/OFF]  (default: ON)
   When ON: LLM prompt includes filler removal instructions
   When OFF: LLM preserves fillers (useful for verbatim transcription needs)

Cleanup Level: [Minimal] [Standard] [Aggressive]  (default: Standard)
   Minimal: Fix hesitations only
   Standard: Remove fillers + self-corrections (matches WisprFlow behavior)
   Aggressive: Full rewrite for polished prose
```

### Key Architectural Notes

1. **Silero VAD runs BEFORE STT on all backends** — not just in hands-free mode. Even for push-to-talk, we strip leading/trailing silence and any mid-speech background noise segments. This eliminates the #1 cause of Whisper hallucinations.

2. **Parakeet is recommended for noisy environments** because TDT architecture handles noise at the model level. Whisper requires more parameter tuning and still hallucinates on extended background noise.

3. **Filler removal is handled by the LLM, not the STT.** Trying to suppress fillers at the STT level (via `suppress_tokens` or `initial_prompt`) is unreliable — the same token that represents "um" also appears in words like "umbrella" and "umber". The LLM has semantic context to distinguish fillers from words.

4. **No audio denoising preprocessing.** Research consistently shows spectral denoising hurts STT models trained on diverse audio. Whisper and Parakeet handle noise internally. The only preprocessing is VAD-based segment filtering.

5. **Self-correction is a key WisprFlow feature we must match.** When a user says "send it to John, actually no, send it to Sarah", WisprFlow outputs "send it to Sarah". Our LLM cleanup prompt handles this at the `standard` level.

---

## 5b. Context-Aware App Detection & Adaptive Formatting

> **Goal: Automatically detect the active app, classify it, and adjust LLM output formatting.**
>
> WisprFlow's killer feature is context intelligence — it formats text differently in Gmail (formal, paragraphs) vs Slack (casual, no trailing periods) vs Cursor (code-aware, backtick variables, @file tags). YapYap clones this via local app detection + LLM prompt injection.

### How WisprFlow Does It (Research Findings)

WisprFlow uses 4 app categories with user-configurable style per category:

1. **Personal Messaging** (iMessage, WhatsApp, Telegram) → Styles: Very Casual, Casual, Excited, Formal
2. **Work Messaging** (Slack, Teams) → Styles: Casual, Excited, Formal
3. **Email** (Gmail, Outlook, Superhuman) → Styles: Casual, Excited, Formal
4. **Other Apps** (Docs, Notes, ChatGPT, etc.) → Styles: Casual, Excited, Formal

Style controls only punctuation, capitalization, and spacing — NOT word choice or grammar. Additionally:
- **IDE/Developer mode** ("Vibe Coding"): Variable recognition (wraps in backticks), file tagging (says "at main.py" → `@main.py`), syntax awareness
- **Command Mode**: Highlight text + voice command → AI rewrites (e.g., "make this bullet points", "make more professional")
- **Context awareness reads active window** via accessibility/screen reader APIs to understand surrounding text

### YapYap Implementation: AppContextDetector

```swift
// AppContextDetector.swift — Detect active app and classify it
import AppKit
import ApplicationServices

enum AppCategory: String, Codable, CaseIterable {
    case personalMessaging    // iMessage, WhatsApp, Telegram, Signal
    case workMessaging        // Slack, Teams, Discord
    case email                // Mail, Gmail (browser), Outlook, Superhuman
    case codeEditor           // Cursor, VS Code, Xcode, Windsurf, terminal
    case browser              // Safari, Chrome, Firefox, Arc
    case documents            // Pages, Google Docs, Notion, Obsidian, Notes
    case aiChat               // ChatGPT, Claude (browser), Perplexity
    case other                // Everything else
}

enum OutputStyle: String, Codable, CaseIterable {
    case veryCasual   // no caps, no trailing periods, minimal punctuation
    case casual       // sentence caps, light punctuation, conversational
    case excited      // sentence caps, exclamation points, upbeat
    case formal       // full caps, full punctuation, paragraphs, polished
}

struct AppContext {
    let bundleId: String
    let appName: String
    let category: AppCategory
    let style: OutputStyle          // User-configured per category
    let windowTitle: String?        // From accessibility API
    let focusedFieldText: String?   // Existing text in field (for context)
    let isIDEChatPanel: Bool        // Cursor/Windsurf AI chat panel detected
}

class AppContextDetector {
    // Bundle ID → Category mapping (extensible, user can override)
    private static let bundleMap: [String: AppCategory] = [
        // Personal Messaging
        "com.apple.MobileSMS": .personalMessaging,           // iMessage
        "net.whatsapp.WhatsApp": .personalMessaging,
        "org.telegram.desktop": .personalMessaging,
        "org.thoughtcrime.securesms": .personalMessaging,    // Signal
        
        // Work Messaging
        "com.tinyspeck.slackmacgap": .workMessaging,         // Slack
        "com.microsoft.teams2": .workMessaging,
        "com.hnc.Discord": .workMessaging,
        
        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.smartemail-macos": .email,              // Spark
        "com.superhuman.electron": .email,
        
        // Code Editors
        "com.todesktop.230313mzl4w4u92": .codeEditor,       // Cursor
        "com.microsoft.VSCode": .codeEditor,
        "com.apple.dt.Xcode": .codeEditor,
        "dev.zed.Zed": .codeEditor,
        "com.codeium.windsurf": .codeEditor,
        "com.googlecode.iterm2": .codeEditor,                // iTerm2
        "com.apple.Terminal": .codeEditor,
        
        // Documents
        "com.apple.iWork.Pages": .documents,
        "notion.id": .documents,
        "md.obsidian": .documents,
        "com.apple.Notes": .documents,
        
        // AI Chat (detected via browser URL or native app)
        "com.openai.chat": .aiChat,
    ]
    
    /// Detect the active app context when user starts recording
    static func detect() -> AppContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(bundleId: "", appName: "Unknown", category: .other,
                           style: .casual, windowTitle: nil, focusedFieldText: nil,
                           isIDEChatPanel: false)
        }
        
        let bundleId = frontApp.bundleIdentifier ?? ""
        let appName = frontApp.localizedName ?? "Unknown"
        
        // Classify the app
        var category = bundleMap[bundleId] ?? classifyByName(appName)
        
        // Browser special case: classify by URL/tab title
        if isBrowser(bundleId) {
            category = classifyBrowserTab(pid: frontApp.processIdentifier)
        }
        
        // Get window title via Accessibility API
        let windowTitle = getWindowTitle(pid: frontApp.processIdentifier)
        
        // Get focused text field content (if accessible)
        let focusedText = getFocusedFieldText()
        
        // Detect if we're in an IDE's AI chat panel (Cursor Composer, etc.)
        let isIDEChat = category == .codeEditor && isAIChatPanel(windowTitle: windowTitle)
        
        // Look up user's configured style for this category
        let style = UserSettings.shared.styleForCategory(category)
        
        return AppContext(
            bundleId: bundleId, appName: appName, category: category,
            style: style, windowTitle: windowTitle,
            focusedFieldText: focusedText, isIDEChatPanel: isIDEChat
        )
    }
    
    /// Classify browser tabs by checking window title for known patterns
    private static func classifyBrowserTab(pid: pid_t) -> AppCategory {
        guard let title = getWindowTitle(pid: pid)?.lowercased() else { return .browser }
        
        if title.contains("gmail") || title.contains("outlook.live") || 
           title.contains("mail.google") || title.contains("proton") { return .email }
        if title.contains("slack") || title.contains("teams.microsoft") { return .workMessaging }
        if title.contains("chatgpt") || title.contains("claude.ai") || 
           title.contains("perplexity") { return .aiChat }
        if title.contains("docs.google") || title.contains("notion.so") { return .documents }
        if title.contains("github.com") { return .codeEditor }
        
        return .browser
    }
    
    /// Get window title via Accessibility API
    private static func getWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success else { return nil }
        
        var title: AnyObject?
        AXUIElementCopyAttributeValue(value as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return title as? String
    }
    
    /// Get text from the currently focused text field (for context injection)
    private static func getFocusedFieldText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success else { return nil }
        
        var textValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &textValue)
        return textValue as? String
    }
}
```

### LLM Prompt Injection by App Category

The `CleanupContext` already has `appContext`. Now we expand it with the full `AppContext` and build category-specific prompts:

```swift
extension CleanupPromptBuilder {
    
    /// Build formatting instructions based on detected app category + user's style preference
    static func buildAppFormattingInstruction(context: AppContext) -> String {
        // Base formatting from user's style preference
        let styleInstruction = buildStyleInstruction(context.style)
        
        // Category-specific formatting rules
        let categoryInstruction: String = switch context.category {
            
        case .personalMessaging:
            """
            Format for personal messaging:
            - Short, conversational sentences. One thought per message.
            - \(context.style == .veryCasual ? "No capitalization at start of sentences. No trailing periods." : "")
            - Use natural line breaks between distinct thoughts.
            - NO bullet points or headers. Keep it conversational.
            """
            
        case .workMessaging:
            """
            Format for work messaging (Slack/Teams style):
            - Concise and direct. Get to the point fast.
            - Use line breaks between distinct topics.
            - Bullet points OK for lists of 3+ items.
            - Emojis OK if the speaker's tone suggests them.
            """
            
        case .email:
            """
            Format for email:
            - Use proper paragraph structure with line breaks between paragraphs.
            - Start with appropriate greeting if the speaker included one.
            - End with a sign-off if the speaker indicated one.
            - Full sentences, proper punctuation throughout.
            - Bullet points or numbered lists for action items or multiple points.
            """
            
        case .codeEditor where context.isIDEChatPanel:
            """
            Format for AI coding assistant chat:
            - Wrap variable names, function names, and code references in backticks: `variableName`
            - When the speaker says "at" followed by a filename, format as @filename (e.g., @main.py)
            - Preserve technical accuracy: API names, CLI commands, package names.
            - Use markdown formatting: code blocks for multi-line code, backticks for inline.
            """
            
        case .codeEditor:
            """
            Format for code editor (comments/documentation):
            - Concise, technical language.
            - Wrap code references in backticks.
            - If dictating a comment, prefix with // or # as appropriate.
            - Preserve exact technical terminology, library names, API calls.
            """
            
        case .documents:
            """
            Format for document writing:
            - Use proper paragraph structure.
            - Auto-detect structure: if the speaker dictates a list, format as bullet points.
            - If the speaker says "heading" or "title", format with markdown # heading.
            - Use line breaks between sections.
            """
            
        case .aiChat:
            """
            Format for AI chat (ChatGPT/Claude):
            - The user is writing a prompt. Preserve their intent precisely.
            - Keep natural conversational structure.
            - Don't over-format — the AI will interpret it.
            - Preserve technical terms and specific instructions exactly.
            """
            
        case .browser, .other:
            """
            Format with general-purpose style:
            - Clean sentences with proper punctuation.
            - Line breaks between paragraphs or distinct thoughts.
            - Bullet points if the speaker lists multiple items.
            """
        }
        
        return """
        \(styleInstruction)
        \(categoryInstruction)
        """
    }
    
    /// Build punctuation/capitalization rules from OutputStyle
    static func buildStyleInstruction(_ style: OutputStyle) -> String {
        switch style {
        case .veryCasual:
            return "Style: Very casual. No capitalization at sentence starts. No trailing periods. Minimal punctuation. Like texting a close friend."
        case .casual:
            return "Style: Casual. Normal sentence capitalization. Light punctuation — skip unnecessary commas. Conversational."
        case .excited:
            return "Style: Excited/enthusiastic. Sentence capitalization. Use exclamation points where the speaker's tone was enthusiastic. Upbeat."
        case .formal:
            return "Style: Formal. Full capitalization, complete punctuation. Professional paragraphs with proper structure."
        }
    }
}
```

### Auto-Formatting Rules (Smart Newlines, Bullets, Paragraphs)

These are LLM-level instructions, but we also add deterministic post-processing:

```swift
struct OutputFormatter {
    
    /// Post-process LLM output with deterministic formatting rules
    static func format(_ text: String, for context: AppContext) -> String {
        var result = text
        
        // Smart newlines: if output has multiple sentences about different topics,
        // and we're in email/docs, ensure paragraph breaks
        if context.category == .email || context.category == .documents {
            result = ensureParagraphBreaks(result)
        }
        
        // Very casual mode: strip trailing periods, lowercase first char
        if context.style == .veryCasual {
            result = applyVeryCasual(result)
        }
        
        // Code editor: ensure backtick wrapping for detected code tokens
        if context.category == .codeEditor {
            result = wrapCodeTokens(result)
        }
        
        // IDE file tagging: "at main.py" → "@main.py"  
        if context.isIDEChatPanel {
            result = applyFileTagging(result)
        }
        
        return result
    }
    
    /// Convert "at filename.ext" to "@filename.ext" for IDE chat panels
    private static func applyFileTagging(_ text: String) -> String {
        // Match "at <filename>.<ext>" patterns where ext is a known code extension
        let codeExtensions = "swift|py|ts|tsx|js|jsx|rs|go|rb|java|kt|cpp|c|h|css|html|json|yaml|yml|toml|md|sql|sh"
        let pattern = try! Regex("\\bat\\s+(\\w+\\.(?:\(codeExtensions)))\\b", .caseInsensitive)
        return text.replacing(pattern) { match in "@\(match.output.1)" }
    }
    
    /// Wrap known code-like tokens in backticks
    private static func wrapCodeTokens(_ text: String) -> String {
        // Match camelCase, snake_case, PascalCase identifiers, and CLI commands
        let codePattern = try! Regex("\\b([a-z]+[A-Z][a-zA-Z]*|[a-z]+_[a-z_]+|[A-Z][a-z]+[A-Z][a-zA-Z]*)\\b")
        return text.replacing(codePattern) { match in "`\(match.output.0)`" }
    }
    
    /// Strip trailing periods, lowercase sentence starts for very casual
    private static func applyVeryCasual(_ text: String) -> String {
        var result = text
        // Remove trailing periods (but not ! or ?)
        result = result.replacingOccurrences(of: "\\. *$", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\.\\n", with: "\n", options: .regularExpression)
        // Lowercase first character
        if let first = result.first, first.isUppercase {
            result = first.lowercased() + result.dropFirst()
        }
        return result
    }
}
```

### Command Mode (Voice-Powered Editing) — v0.2

WisprFlow's Command Mode: user highlights text → activates hotkey → speaks a command → AI rewrites. YapYap equivalent:

```swift
struct CommandMode {
    /// Detect if the user's speech is a command vs dictation
    /// Triggers: "make this...", "turn this into...", "rewrite...", "shorten...", "summarize..."
    static let commandPrefixes = [
        "make this", "turn this into", "rewrite this",
        "shorten this", "summarize this", "expand this",
        "make it", "format this as", "translate this to",
        "fix the grammar", "add bullet points",
        "make more professional", "make more casual"
    ]
    
    /// Check if transcribed text is a command
    static func isCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return commandPrefixes.contains(where: { lower.hasPrefix($0) })
    }
    
    /// Execute command: read selected text, send to LLM with command instruction
    static func execute(command: String) async throws -> String {
        // 1. Get selected text from active app via Accessibility API
        let selectedText = AppContextDetector.getSelectedText()
        guard let selected = selectedText, !selected.isEmpty else {
            return "⚠️ No text selected. Highlight text first, then give a command."
        }
        
        // 2. Build LLM prompt: command + selected text
        let prompt = """
        You are a text editor. Apply the following command to the text below.
        
        Command: \(command)
        
        Original text:
        \(selected)
        
        Edited text:
        """
        
        // 3. Run through LLM and replace selected text
        let result = try await LLMEngine.shared.generate(prompt: prompt)
        return result
    }
}
```

**Implementation approach:**
- Use a separate hotkey for Command Mode (default: `Cmd+Shift+.` or double-tap fn)
- When Command Mode is active, the floating bar shows 🎯 icon instead of 🎙
- After speaking, YapYap reads the selected text via AX API, sends both to LLM, replaces selection

### Personalized Style Settings (Settings → Style Tab)

New settings tab matching WisprFlow's Personalized Style:

```swift
struct StyleSettings: Codable {
    // Per-category style preferences
    var personalMessaging: OutputStyle = .casual
    var workMessaging: OutputStyle = .casual
    var email: OutputStyle = .formal
    var codeEditor: OutputStyle = .formal
    var documents: OutputStyle = .formal
    var aiChat: OutputStyle = .casual
    var browser: OutputStyle = .casual
    var other: OutputStyle = .casual
    
    // IDE-specific settings
    var ideVariableRecognition: Bool = true    // Wrap camelCase in backticks
    var ideFileTagging: Bool = true            // "at file.py" → "@file.py"
    
    // Custom app overrides (user can reclassify any app)
    var appCategoryOverrides: [String: AppCategory] = [:]  // bundleId → category
    
    func styleFor(_ category: AppCategory) -> OutputStyle {
        switch category {
        case .personalMessaging: return personalMessaging
        case .workMessaging: return workMessaging
        case .email: return email
        case .codeEditor: return codeEditor
        case .documents: return documents
        case .aiChat: return aiChat
        case .browser: return browser
        case .other: return other
        }
    }
}
```

### Personal Dictionary (Auto-Learning) — v0.2

WisprFlow monitors the text field after pasting and learns corrections:

```swift
class PersonalDictionary {
    // Stored in ~/Library/Application Support/YapYap/dictionary.json
    var entries: [String: String] = [:]  // spoken form → corrected form
    
    /// After pasting, monitor if user edits a word within 5 seconds
    /// If they change "anthropick" → "Anthropic", learn the correction
    func monitorCorrections(pastedText: String, afterDelay: TimeInterval = 5.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + afterDelay) {
            guard let currentText = AppContextDetector.getFocusedFieldText() else { return }
            let corrections = self.diffWords(original: pastedText, edited: currentText)
            for (original, corrected) in corrections {
                self.entries[original.lowercased()] = corrected
                self.save()
            }
        }
    }
    
    /// Apply dictionary before LLM cleanup (faster than LLM for known words)
    func applyCorrections(to text: String) -> String {
        var result = text
        for (spoken, corrected) in entries {
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: spoken))\\b",
                with: corrected, options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }
}
```

### Voice Snippets (Shortcuts) — v0.2

```swift
struct VoiceSnippet: Codable, Identifiable {
    let id: UUID
    let trigger: String       // "my email" or "disclaimer" or "standup template"
    let expansion: String     // Full text to insert
    let isTeamShared: Bool
}

class SnippetManager {
    var snippets: [VoiceSnippet] = []
    
    /// Check if transcribed text matches a snippet trigger
    func matchSnippet(from text: String) -> VoiceSnippet? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return snippets.first { lower == $0.trigger.lowercased() || lower == "insert \($0.trigger.lowercased())" }
    }
}
```

### Updated Pipeline Flow (with Context Awareness)

```
User presses hotkey → Start recording
                    ↓
              Detect AppContext (bundleId, category, window title)
                    ↓
              Record audio → VAD filter → STT transcribe
                    ↓
              Check: Is this a Command? (commandPrefixes check)
              ├── YES → Read selected text → LLM with command prompt → Replace selection
              └── NO  → Continue to cleanup
                    ↓
              Check: Is this a Snippet trigger?
              ├── YES → Insert snippet expansion directly
              └── NO  → Continue to cleanup
                    ↓
              Apply Personal Dictionary corrections
                    ↓
              LLM Cleanup with context-aware prompt:
                - App category formatting rules
                - User's style preference for this category
                - Filler removal level
                - Existing text in field (for continuation context)
                    ↓
              Post-process (OutputFormatter):
                - File tagging (@file)
                - Variable backtick wrapping
                - Very casual style adjustments
                - Smart newlines/paragraphs
                    ↓
              Paste via clipboard + Cmd+V (or AX API)
```

---

## 6. Paste & Integration Pipeline

The critical last mile — getting text into the user's active app:

```swift
class PasteManager {
    // Strategy 1: Clipboard + synthetic Cmd+V (default)
    func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Synthetic Cmd+V via CGEvent
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
        
        // Restore clipboard after delay
        if let previous = previousContent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
    
    // Strategy 2: Accessibility API (more reliable for some apps)
    func pasteViaAccessibility(_ text: String) {
        // Use AXUIElement to set focused text field value directly
        // Requires Accessibility permission
    }
}
```

---

## 7. Data Model & Persistence

### SQLite via SwiftData (macOS 14+)

```swift
@Model
class Transcription {
    var id: UUID
    var rawText: String
    var cleanedText: String
    var timestamp: Date
    var durationSeconds: Double
    var wordCount: Int
    var sttModel: String
    var llmModel: String
    var sourceApp: String?       // Frontmost app at time of transcription
    var language: String
    var cleanupLevel: String
}

@Model
class AppSettings {
    var sttModelId: String
    var llmModelId: String
    var stylePrompt: String
    var formality: String        // "casual" | "neutral" | "formal"
    var cleanupLevel: String     // "light" | "medium" | "heavy"
    var language: String
    var pushToTalkHotkey: Data   // Encoded KeyboardShortcuts.Shortcut
    var handsFreeHotkey: Data
    var launchAtLogin: Bool
    var showFloatingBar: Bool
    var autoPaste: Bool
    var copyToClipboard: Bool
    var notifyOnComplete: Bool
    var floatingBarPosition: String
    var historyLimit: Int
    var soundFeedback: Bool
    var hapticFeedback: Bool
    var microphoneId: String?
    var gpuAcceleration: Bool
    var autoDownloadModels: Bool
}

@Model
class PowerModeRule {
    var id: UUID
    var appBundleId: String?     // Match by app
    var urlPattern: String?      // Match by URL (for browsers)
    var stylePrompt: String
    var formality: String
    var cleanupLevel: String
    var sttModelId: String?      // Override STT model per-app
    var llmModelId: String?      // Override LLM model per-app
    var isEnabled: Bool
}

@Model
class CustomDictionaryEntry {
    var id: UUID
    var original: String         // What user says
    var replacement: String      // What gets transcribed
    var isEnabled: Bool
}

@Model  
class DailyStats {
    var date: Date
    var transcriptionCount: Int
    var wordCount: Int
    var totalDurationSeconds: Double
}
```

---

## 8. Swift Package Dependencies

```swift
// Package.swift dependencies
dependencies: [
    // STT Backends
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    
    // LLM Inference
    .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "0.2.0"),
    
    // HuggingFace model downloads
    .package(url: "https://github.com/huggingface/swift-transformers.git", from: "0.1.0"),
    
    // macOS Utilities
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.0.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
    .package(url: "https://github.com/tisfeng/SelectedTextKit.git", from: "0.3.0"),
    
    // Data
    // SwiftData is built into macOS 14+ SDK — no external dependency
]
```

---

## 9. Project Structure

```
YapYap/
├── YapYap.xcodeproj/
├── YapYap/
│   ├── App/
│   │   ├── YapYapApp.swift              # @main, app lifecycle
│   │   ├── AppDelegate.swift            # NSApplicationDelegate for StatusBar
│   │   └── AppState.swift               # Global observable state
│   │
│   ├── UI/
│   │   ├── MenuBar/
│   │   │   ├── StatusBarController.swift    # NSStatusItem management
│   │   │   ├── CreatureIcon.swift           # Animated SVG creature states
│   │   │   └── PopoverView.swift            # NSPopover content (Layer 2)
│   │   ├── FloatingBar/
│   │   │   ├── FloatingBarWindow.swift      # NSPanel configuration
│   │   │   ├── FloatingBarView.swift        # Creature + waveform
│   │   │   └── WaveformView.swift           # RMS-driven waveform bars
│   │   ├── Settings/
│   │   │   ├── SettingsWindow.swift         # NSWindow host
│   │   │   ├── SettingsView.swift           # Root settings with sidebar
│   │   │   ├── WritingStyleTab.swift
│   │   │   ├── ModelsTab.swift
│   │   │   ├── HotkeysTab.swift
│   │   │   ├── GeneralTab.swift
│   │   │   ├── AnalyticsTab.swift
│   │   │   └── AboutTab.swift
│   │   └── Creature/
│   │       ├── CreatureView.swift           # Shared creature SVG renderer
│   │       ├── CreatureState.swift          # sleeping/recording/processing enum
│   │       └── CreatureAnimations.swift     # Breathing, pulse, spin animations
│   │
│   ├── Core/
│   │   ├── Pipeline/
│   │   │   ├── TranscriptionPipeline.swift  # Orchestrates: Audio → STT → LLM → Paste
│   │   │   ├── AudioCaptureManager.swift    # AVAudioEngine mic capture
│   │   │   ├── PasteManager.swift           # Clipboard + CGEvent paste
│   │   │   └── HotkeyManager.swift          # Global hotkey registration
│   │   ├── STT/
│   │   │   ├── STTEngine.swift              # Protocol definition
│   │   │   ├── WhisperKitEngine.swift       # WhisperKit backend
│   │   │   ├── FluidAudioEngine.swift       # FluidAudio/Parakeet backend
│   │   │   ├── WhisperCppEngine.swift       # whisper.cpp/Voxtral backend
│   │   │   └── STTModelRegistry.swift       # Available models catalog
│   │   ├── LLM/
│   │   │   ├── LLMEngine.swift              # Protocol definition
│   │   │   ├── MLXEngine.swift              # MLX Swift inference
│   │   │   ├── CleanupPromptBuilder.swift   # System prompt construction
│   │   │   └── LLMModelRegistry.swift       # Available models catalog
│   │   └── Models/
│   │       ├── ModelDownloader.swift         # HuggingFace Hub download manager
│   │       ├── ModelStorage.swift            # ~/Library/Application Support/YapYap/Models/
│   │       └── ModelInfo.swift              # Metadata types
│   │
│   ├── Data/
│   │   ├── Models/
│   │   │   ├── Transcription.swift          # @Model
│   │   │   ├── AppSettings.swift            # @Model
│   │   │   ├── PowerModeRule.swift          # @Model
│   │   │   ├── CustomDictionaryEntry.swift  # @Model
│   │   │   └── DailyStats.swift             # @Model
│   │   ├── DataManager.swift                # SwiftData container setup
│   │   └── AnalyticsTracker.swift           # Local-only stats aggregation
│   │
│   ├── Utilities/
│   │   ├── AccessibilityHelper.swift        # AXUIElement for selected text
│   │   ├── AppDetector.swift                # Frontmost app detection
│   │   ├── SoundManager.swift               # Start/stop audio feedback
│   │   ├── HapticManager.swift              # Trackpad haptics
│   │   └── Permissions.swift                # Mic, Accessibility permission checks
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   │   ├── AppIcon.appiconset/
│   │   │   └── Creature/                    # Creature SVG assets
│   │   ├── Sounds/
│   │   │   ├── start.wav
│   │   │   └── stop.wav
│   │   └── Localizable.strings
│   │
│   └── Info.plist
│
├── YapYapTests/
│   ├── PipelineTests.swift
│   ├── STTEngineTests.swift
│   ├── LLMEngineTests.swift
│   ├── PasteManagerTests.swift
│   └── ModelRegistryTests.swift
│
├── README.md
├── BUILDING.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── LICENSE                                  # MIT
├── Makefile
├── .gitignore
└── docs/
    ├── ARCHITECTURE.md                      # This file
    ├── UI-SPEC.md                           # Complete UI specification
    ├── AGENT-TASKS.md                       # Task breakdown for agents
    └── DESIGN-TOKENS.md                     # Colors, fonts, animations
```

---

## 10. Entitlements & Permissions

```xml
<!-- YapYap.entitlements -->
<key>com.apple.security.app-sandbox</key>         <false/> <!-- Need CGEvent, AXUIElement -->
<key>com.apple.security.device.audio-input</key>  <true/>  <!-- Microphone -->
<key>com.apple.security.network.client</key>      <true/>  <!-- Model downloads -->
<key>com.apple.security.files.user-selected.read-write</key> <true/>
```

**Runtime permissions requested on first launch:**
1. Microphone Access (required)
2. Accessibility Access (required for paste, selected text)
3. Screen Recording (optional, for context awareness / Power Mode)

---

## 11. Build & Distribution

```makefile
# Makefile
.PHONY: build run test archive

build:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap -configuration Debug build

run: build
	open build/Debug/YapYap.app

test:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap -configuration Debug test

archive:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap \
		-configuration Release archive \
		-archivePath build/YapYap.xcarchive
	
	xcodebuild -exportArchive \
		-archivePath build/YapYap.xcarchive \
		-exportPath build/release \
		-exportOptionsPlist ExportOptions.plist

dmg: archive
	create-dmg build/release/YapYap.app build/YapYap.dmg

homebrew:
	# Generate formula after release
	# brew install --cask yapyap
```

**Update mechanism:** Sparkle framework for auto-updates via GitHub Releases appcast.xml

---

## 12. Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| App startup (cold) | <1.5s | No model loading on startup |
| Menu bar icon visible | <0.5s after launch | StatusBar setup is synchronous |
| Model load (first time) | <5s (Parakeet), <8s (Whisper Large) | Cached after first load |
| STT latency (5s audio) | <1.5s (Parakeet), <3s (Whisper Large) | End-to-end transcription |
| LLM cleanup latency | <1s for avg sentence | Qwen 1.5B at ~200 tok/s |
| Total pipeline (speak → paste) | <3s | Push-to-talk release → text appears |
| Idle RAM | <60MB | No models loaded |
| Active RAM (recording) | <2.5GB | Parakeet + Qwen 1.5B loaded |
| CPU usage (idle) | <0.5% | Only StatusBar breathing animation |
| CPU usage (recording) | <15% | Most work on GPU/ANE |

---

## 13. Competitive Differentiation vs WisprFlow

| Feature | WisprFlow | YapYap |
|---------|-----------|--------|
| Privacy | Cloud-based, sends audio to servers | 100% offline, data never leaves device |
| Price | $12/month subscription | Free & open source (MIT) |
| STT Models | Proprietary | User choice: Whisper / Parakeet / Voxtral |
| LLM Cleanup | Cloud AI (OpenAI + Llama 3.1) | Local: Qwen / Llama / Gemma (user choice) |
| Context Awareness | App category detection + style per category | ✅ Same — app detection via NSWorkspace + AX API |
| Personalized Style | 4 categories × 4 styles | ✅ Same — 8 categories × 4 styles |
| Filler Removal | Cloud AI removes fillers | ✅ 3-level filler removal (minimal/standard/aggressive) |
| Self-Correction | "Tuesday no Wednesday" → "Wednesday" | ✅ LLM-based self-correction at standard+ level |
| Command Mode | Highlight + voice = rewrite | ✅ Same — separate hotkey, AX API selected text |
| IDE Integration | Cursor/Windsurf file tagging, variable recognition | ✅ Same — backtick wrapping, @file tagging |
| Personal Dictionary | Auto-learns corrections | ✅ Same — monitors post-paste edits |
| Voice Snippets | Voice shortcuts for templates | ✅ Same — trigger phrases → expansion |
| Smart Formatting | Auto newlines, bullets, paragraphs | ✅ LLM + deterministic post-processing |
| Noise Handling | Cloud-based noise handling | ✅ Silero VAD + optimized STT params |
| Open Source | No | Yes — MIT licensed |
| Personality | Generic | Cozy creature companion 💜 |
| Platform | Mac, Windows, iOS | macOS only (initially) |
