# YapYap — Implementation Reference

> Copy-paste-ready Swift patterns for each subsystem.
> Agents should use these as starting points, not final implementations.

---

## 1. App Entry Point

```swift
// YapYapApp.swift
import SwiftUI
import SwiftData

@main
struct YapYapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No WindowGroup — we're a menu bar app
        Settings {
            EmptyView() // Settings handled by custom NSWindow
        }
    }
}

// AppDelegate.swift
import AppKit
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var appState = AppState()
    var pipeline: TranscriptionPipeline?
    var modelContainer: ModelContainer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Setup SwiftData
        let schema = Schema([
            Transcription.self,
            AppSettings.self,
            PowerModeRule.self,
            CustomDictionaryEntry.self,
            DailyStats.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try? ModelContainer(for: schema, configurations: [config])
        
        // Setup menu bar
        statusBarController = StatusBarController(appState: appState)
        
        // Setup pipeline
        pipeline = TranscriptionPipeline(appState: appState, container: modelContainer!)
        
        // Setup hotkeys
        HotkeyManager.shared.configure(pipeline: pipeline!, appState: appState)
    }
}
```

---

## 2. Status Bar + Popover

```swift
// StatusBarController.swift
import AppKit
import SwiftUI

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(appState: appState)
        )
        
        if let button = statusItem.button {
            // Embed SwiftUI creature in the button
            let hostingView = NSHostingView(
                rootView: CreatureView(state: appState.creatureState, size: 18)
            )
            hostingView.frame = NSRect(x: 5, y: 2, width: 18, height: 18)
            button.addSubview(hostingView)
            button.action = #selector(togglePopover)
            button.target = self
            
            // Right-click menu
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit YapYap", action: #selector(quit), keyEquivalent: "q"))
            button.menu = menu // Note: won't work for left click this way
            // Actually use sendAction for left click, NSMenu for right click
        }
    }
    
    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    @objc func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
    }
    
    @objc func quit() {
        NSApp.terminate(nil)
    }
}
```

---

## 3. Creature View (SwiftUI)

```swift
// CreatureView.swift
import SwiftUI

struct CreatureView: View {
    let state: CreatureState
    let size: CGFloat
    
    @State private var breatheScale: CGFloat = 1.0
    @State private var headRotation: Double = 0
    @State private var zOpacity1: Double = 0.2
    @State private var zOpacity2: Double = 0.2
    @State private var pulseScale1: CGFloat = 1.0
    @State private var pulseOpacity1: Double = 0.5
    @State private var pulseScale2: CGFloat = 1.0
    @State private var pulseOpacity2: Double = 0.5
    @State private var spinRotation: Double = 0
    
    private var scale: CGFloat { size / 42.0 } // Normalized to 42pt base
    
    var body: some View {
        ZStack {
            // Pulse rings (recording only)
            if state == .recording {
                RoundedRectangle(cornerRadius: size * 0.43)
                    .stroke(Color.ypWarm, lineWidth: 1.5)
                    .frame(width: size + 8, height: size + 8)
                    .scaleEffect(pulseScale1)
                    .opacity(pulseOpacity1)
                
                RoundedRectangle(cornerRadius: size * 0.43)
                    .stroke(Color.ypWarm, lineWidth: 1.5)
                    .frame(width: size + 8, height: size + 8)
                    .scaleEffect(pulseScale2)
                    .opacity(pulseOpacity2)
            }
            
            // Spinner ring (processing only)
            if state == .processing {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.ypLavender, lineWidth: 1.5)
                    .frame(width: size + 6, height: size + 6)
                    .rotationEffect(.degrees(spinRotation))
            }
            
            // Creature body
            Canvas { context, canvasSize in
                drawCreature(context: &context, size: canvasSize, state: state)
            }
            .frame(width: size, height: size)
            .scaleEffect(y: state == .sleeping ? breatheScale : 1.0)
            .rotationEffect(.degrees(state == .sleeping ? headRotation : 0))
            
            // Floating z's (sleeping only)
            if state == .sleeping {
                Text("z")
                    .font(.custom("Caveat", size: size * 0.15))
                    .foregroundColor(.ypZzz)
                    .opacity(zOpacity1)
                    .offset(x: size * 0.3, y: -size * 0.3)
                
                Text("z")
                    .font(.custom("Caveat", size: size * 0.19))
                    .foregroundColor(.ypZzz)
                    .opacity(zOpacity2)
                    .offset(x: size * 0.38, y: -size * 0.45)
            }
        }
        .onAppear { startAnimations() }
        .onChange(of: state) { startAnimations() }
    }
    
    private func startAnimations() {
        switch state {
        case .sleeping:
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                breatheScale = 1.04
            }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                headRotation = 3
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                zOpacity1 = 0.75
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.6)) {
                zOpacity2 = 0.75
            }
            
        case .recording:
            breatheScale = 1.0
            headRotation = 0
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseScale1 = 1.3
                pulseOpacity1 = 0
            }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.75)) {
                pulseScale2 = 1.3
                pulseOpacity2 = 0
            }
            
        case .processing:
            breatheScale = 1.0
            headRotation = 0
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                spinRotation = 360
            }
        }
    }
    
    private func drawCreature(context: inout GraphicsContext, size: CGSize, state: CreatureState) {
        let s = min(size.width, size.height)
        let cx = size.width / 2
        
        // Body (ellipse at bottom)
        let bodyRect = CGRect(x: cx - s * 0.26, y: s * 0.55, width: s * 0.52, height: s * 0.33)
        context.fill(Ellipse().path(in: bodyRect), with: .color(.ypLavender))
        
        // Head (circle)
        let headRect = CGRect(x: cx - s * 0.22 - s * 0.05, y: s * 0.2, width: s * 0.44, height: s * 0.44)
        context.fill(Circle().path(in: headRect), with: .color(.ypLavender))
        
        // Ears
        let leftEar = CGRect(x: cx - s * 0.28, y: s * 0.12, width: s * 0.1, height: s * 0.14)
        let rightEar = CGRect(x: cx + s * 0.08, y: s * 0.12, width: s * 0.1, height: s * 0.14)
        context.fill(Ellipse().path(in: leftEar), with: .color(.ypLavender))
        context.fill(Ellipse().path(in: rightEar), with: .color(.ypLavender))
        
        let eyeColor = Color(hex: "2A2040")
        let headCx = cx - s * 0.05 // Head is slightly left of center
        let eyeY = s * 0.42
        
        if state == .sleeping {
            // Closed eyes (curved lines)
            // Draw with Path strokes
            var leftEye = Path()
            leftEye.move(to: CGPoint(x: headCx - s * 0.1, y: eyeY))
            leftEye.addQuadCurve(
                to: CGPoint(x: headCx - s * 0.02, y: eyeY),
                control: CGPoint(x: headCx - s * 0.06, y: eyeY + s * 0.04)
            )
            context.stroke(leftEye, with: .color(Color(hex: "6B5E8A")), lineWidth: s * 0.025)
            
            var rightEye = Path()
            rightEye.move(to: CGPoint(x: headCx + s * 0.03, y: eyeY))
            rightEye.addQuadCurve(
                to: CGPoint(x: headCx + s * 0.11, y: eyeY),
                control: CGPoint(x: headCx + s * 0.07, y: eyeY + s * 0.04)
            )
            context.stroke(rightEye, with: .color(Color(hex: "6B5E8A")), lineWidth: s * 0.025)
        } else {
            // Open eyes (circles with highlights)
            let leftPupil = CGRect(x: headCx - s * 0.12, y: eyeY - s * 0.05, width: s * 0.1, height: s * 0.1)
            let rightPupil = CGRect(x: headCx + s * 0.02, y: eyeY - s * 0.05, width: s * 0.1, height: s * 0.1)
            context.fill(Circle().path(in: leftPupil), with: .color(eyeColor))
            context.fill(Circle().path(in: rightPupil), with: .color(eyeColor))
            
            // Highlights
            let hlSize = s * 0.035
            let leftHL = CGRect(x: headCx - s * 0.09, y: eyeY - s * 0.03, width: hlSize, height: hlSize)
            let rightHL = CGRect(x: headCx + s * 0.05, y: eyeY - s * 0.03, width: hlSize, height: hlSize)
            context.fill(Circle().path(in: leftHL), with: .color(.white))
            context.fill(Circle().path(in: rightHL), with: .color(.white))
            
            // Blush cheeks
            if state == .recording {
                let blushSize = s * 0.1
                let leftBlush = CGRect(x: headCx - s * 0.2, y: eyeY + s * 0.06, width: blushSize, height: blushSize * 0.45)
                let rightBlush = CGRect(x: headCx + s * 0.1, y: eyeY + s * 0.06, width: blushSize, height: blushSize * 0.45)
                context.fill(Ellipse().path(in: leftBlush), with: .color(.ypBlush.opacity(0.4)))
                context.fill(Ellipse().path(in: rightBlush), with: .color(.ypBlush.opacity(0.4)))
            }
        }
    }
}
```

---

## 4. Floating Bar

```swift
// FloatingBarPanel.swift
import AppKit

class FloatingBarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 52),
            styleMask: [.nonactivatingPanel, .borderless, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
    }
    
    // Never become key window (never steal focus)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    func positionOnScreen(position: FloatingBarPosition) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let barFrame = self.frame
        
        let x: CGFloat
        let y: CGFloat
        
        switch position {
        case .bottomCenter:
            x = screenFrame.midX - barFrame.width / 2
            y = screenFrame.minY + 20
        case .bottomLeft:
            x = screenFrame.minX + 20
            y = screenFrame.minY + 20
        case .bottomRight:
            x = screenFrame.maxX - barFrame.width - 20
            y = screenFrame.minY + 20
        case .topCenter:
            x = screenFrame.midX - barFrame.width / 2
            y = screenFrame.maxY - barFrame.height - 20
        }
        
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

---

## 5. STT Engine Protocol & WhisperKit Implementation

### VAD Manager (Pre-STT Audio Filtering)

```swift
// VADManager.swift — Silero VAD pre-filter for all STT backends
import FluidAudio

struct VADConfig {
    var threshold: Float = 0.35
    var minSpeechDurationMs: Int = 200
    var minSilenceDurationMs: Int = 300
    var speechPadMs: Int = 100
    var maxSpeechDurationS: Float = 30
    
    static let noisyPreset = VADConfig(
        threshold: 0.5, minSpeechDurationMs: 300,
        minSilenceDurationMs: 200, speechPadMs: 150
    )
    static let quietPreset = VADConfig(
        threshold: 0.25, minSpeechDurationMs: 150,
        minSilenceDurationMs: 400, speechPadMs: 80
    )
}

struct AudioSegment {
    let startSample: Int
    let endSample: Int
    let buffer: AVAudioPCMBuffer
}

class VADManager {
    private let vadModel: VADModel  // FluidAudio Silero VAD CoreML
    private var config: VADConfig
    
    init(config: VADConfig = VADConfig()) {
        self.config = config
        self.vadModel = VADModel()  // ~1.4MB CoreML model, loads in <100ms
    }
    
    func updateConfig(_ newConfig: VADConfig) {
        self.config = newConfig
    }
    
    /// Filter audio buffer to extract only speech segments
    /// Called BEFORE passing audio to any STT engine
    func filterSpeechSegments(from buffer: AVAudioPCMBuffer) async throws -> [AudioSegment] {
        let floatArray = bufferToFloatArray(buffer)
        let sampleRate = Int(buffer.format.sampleRate)
        let chunkSize = 512  // Optimal for Silero CoreML
        
        // Process chunks and get speech probabilities
        var speechProbs: [(index: Int, probability: Float)] = []
        for i in stride(from: 0, to: floatArray.count, by: chunkSize) {
            let end = min(i + chunkSize, floatArray.count)
            let chunk = Array(floatArray[i..<end])
            let prob = try await vadModel.processChunk(chunk)
            speechProbs.append((i, prob.probability))
        }
        
        // Apply threshold + duration filters to get speech timestamps
        let segments = extractSpeechSegments(
            probabilities: speechProbs,
            sampleRate: sampleRate,
            chunkSize: chunkSize
        )
        
        // Extract audio segments with padding
        return segments.compactMap { segment in
            let padSamples = Int(Float(config.speechPadMs) / 1000.0 * Float(sampleRate))
            let start = max(0, segment.startSample - padSamples)
            let end = min(Int(buffer.frameLength), segment.endSample + padSamples)
            return extractSubBuffer(from: buffer, start: start, end: end)
        }
    }
}
```

### Filler Removal (Post-LLM Regex Safety Net)

```swift
// FillerFilter.swift — Post-LLM regex guard for remaining filler words
struct FillerFilter {
    // Regex pattern for isolated hesitation sounds
    // Only catches standalone fillers, NOT parts of words (um in "umbrella" is safe)
    static let hesitationPattern = /\b(u[hm]+|a[hm]+|e[hr]+|hmm+)\b[,.]?\s?/
    
    // Extended fillers (used when Remove Fillers is ON)
    static let extendedFillers = [
        "you know", "I mean", "sort of", "kind of",
        "basically", "literally", "actually", "right",
        "so yeah", "yeah so", "like I said"
    ]
    
    static func removeFillers(from text: String, aggressive: Bool = false) -> String {
        var cleaned = text
        
        // Always remove hesitation sounds
        cleaned = cleaned.replacing(hesitationPattern, with: "")
        
        if aggressive {
            for filler in extendedFillers {
                // Case-insensitive, with optional surrounding punctuation
                let pattern = try! Regex("\\b\(filler)\\b[,.]?\\s?", .caseInsensitive)
                cleaned = cleaned.replacing(pattern, with: "")
            }
        }
        
        // Clean up double spaces and leading/trailing whitespace
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

### STT Engine Protocol

```swift
// STTEngine.swift
import AVFoundation

struct TranscriptionResult {
    let text: String
    let language: String?
    let segments: [TranscriptionSegment]
    let processingTime: TimeInterval
}

struct TranscriptionSegment {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct STTModelInfo {
    let id: String
    let name: String
    let backend: STTBackend
    let sizeBytes: Int64
    let languages: [String]
    let description: String
}

enum STTBackend {
    case whisperKit, fluidAudio, whisperCpp
}

protocol STTEngine: AnyObject {
    var modelInfo: STTModelInfo { get }
    var isLoaded: Bool { get }
    func loadModel(progressHandler: @escaping (Double) -> Void) async throws
    func unloadModel()
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult
}

// WhisperKitEngine.swift
import WhisperKit

class WhisperKitEngine: STTEngine {
    let modelInfo: STTModelInfo
    private var pipe: WhisperKit?
    
    var isLoaded: Bool { pipe != nil }
    
    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }
    
    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        let modelPath = ModelStorage.shared.path(for: modelInfo)
        let config = WhisperKitConfig(
            model: modelInfo.id,
            modelFolder: modelPath
        )
        pipe = try await WhisperKit(config)
    }
    
    func unloadModel() {
        pipe = nil
    }
    
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard let pipe = pipe else {
            throw YapYapError.modelNotLoaded
        }
        
        let startTime = Date()
        
        // Convert AVAudioPCMBuffer to [Float]
        let floatArray = bufferToFloatArray(audioBuffer)
        
        // YapYap-optimized decoding options for robust dictation
        let options = DecodingOptions(
            task: .transcribe,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -0.8,           // Tighter: reject low-confidence noise artifacts
            firstTokenLogProbThreshold: -1.0,
            noSpeechThreshold: 0.5,           // Lower: Silero VAD already stripped silence
            suppressBlank: true,
            withoutTimestamps: true,           // Skip timestamps for ~15% speed boost
            wordTimestamps: false,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: true
        )
        
        let result = try await pipe.transcribe(audioArray: floatArray, decodeOptions: options)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return TranscriptionResult(
            text: result.map { $0.text }.joined(separator: " "),
            language: result.first?.language,
            segments: result.flatMap { segment in
                segment.tokens.map { token in
                    TranscriptionSegment(
                        text: token.text,
                        start: token.start,
                        end: token.end
                    )
                }
            },
            processingTime: processingTime
        )
    }
    
    private func bufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        let channelData = buffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
}
```

---

## 6. LLM Engine & Cleanup Prompt

```swift
// LLMEngine.swift
protocol LLMEngine: AnyObject {
    var isLoaded: Bool { get }
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws
    func unloadModel()
    func cleanup(rawText: String, context: CleanupContext) async throws -> String
}

struct CleanupContext {
    let stylePrompt: String
    let formality: Formality
    let language: String
    let appContext: String?
    let cleanupLevel: CleanupLevel
    let removeFillers: Bool          // User toggle from Settings → General
    
    enum Formality: String, Codable {
        case casual, neutral, formal
    }
    
    enum CleanupLevel: String, Codable {
        case light, medium, heavy     // maps to minimal/standard/aggressive
    }
}

// CleanupPromptBuilder.swift
struct CleanupPromptBuilder {
    static func buildPrompt(rawText: String, context: CleanupContext) -> String {
        let formalityInstruction: String = switch context.formality {
        case .casual: "Write casually, like texting a friend. Use contractions, simple words."
        case .neutral: "Write in everyday professional tone. Clear and direct."
        case .formal: "Write formally. Precise language, no contractions, polished."
        }
        
        let cleanupInstruction: String = switch context.cleanupLevel {
        case .light: "Only fix grammar and punctuation. Keep the speaker's exact words as much as possible."
        case .medium: "Fix grammar, restructure sentences for clarity. Maintain the speaker's voice."
        case .heavy: "Fully rewrite for maximum clarity and polish. Match the speaker's intent, not their exact words."
        }
        
        // Filler removal instructions scale with cleanup level
        let fillerInstruction: String
        if context.removeFillers {
            fillerInstruction = switch context.cleanupLevel {
            case .light:
                "Remove hesitation sounds (um, uh, ah, er, hmm). Keep everything else as spoken."
            case .medium:
                """
                Remove filler words: um, uh, ah, er, hmm, like (as filler), you know, I mean, sort of, kind of, basically, actually, literally, so yeah.
                Handle self-corrections: if the speaker says "meet Tuesday, no Wednesday", output only "meet Wednesday".
                Remove false starts and word repetitions (e.g., "I I I think" → "I think").
                """
            case .heavy:
                """
                Remove ALL filler words, verbal tics, and hesitations.
                Resolve all self-corrections to final intent only.
                Fix run-on sentences and add paragraph breaks where appropriate.
                """
            }
        } else {
            fillerInstruction = "Preserve filler words and disfluencies as spoken (verbatim mode)."
        }
        
        let appNote = context.appContext.map { "The user is writing in \($0)." } ?? ""
        
        return """
        You are a writing assistant that cleans up voice transcriptions.
        
        Rules:
        - \(fillerInstruction)
        - Fix grammar and punctuation
        - \(formalityInstruction)
        - \(cleanupInstruction)
        - \(context.stylePrompt.isEmpty ? "" : context.stylePrompt)
        - Preserve the speaker's intent and meaning exactly
        - Do NOT add information that wasn't spoken
        - Do NOT include any preamble, explanation, or notes
        - Output ONLY the cleaned text
        \(appNote)
        
        Raw transcription:
        \(rawText)
        
        Cleaned text:
        """
    }
}

// MLXEngine.swift
import MLX
import MLXLM

class MLXEngine: LLMEngine {
    private var model: LLMModel?
    private var tokenizer: Tokenizer?
    private var modelId: String?
    
    var isLoaded: Bool { model != nil }
    
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {
        let config = ModelConfiguration(id: id)
        let (loadedModel, loadedTokenizer) = try await MLXLM.load(configuration: config) { progress in
            progressHandler(progress.fractionCompleted)
        }
        self.model = loadedModel
        self.tokenizer = loadedTokenizer
        self.modelId = id
    }
    
    func unloadModel() {
        model = nil
        tokenizer = nil
        modelId = nil
    }
    
    func cleanup(rawText: String, context: CleanupContext) async throws -> String {
        guard let model = model, let tokenizer = tokenizer else {
            throw YapYapError.modelNotLoaded
        }
        
        let prompt = CleanupPromptBuilder.buildPrompt(rawText: rawText, context: context)
        
        let result = try await MLXLM.generate(
            model: model,
            tokenizer: tokenizer,
            prompt: prompt,
            parameters: .init(temperature: 0.3, topP: 0.9, maxTokens: 512)
        )
        
        // Strip any preamble the model might add
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

---

## 7. Transcription Pipeline

```swift
// TranscriptionPipeline.swift
import SwiftData

@Observable
class TranscriptionPipeline {
    let appState: AppState
    let audioCapture: AudioCaptureManager
    let pasteManager: PasteManager
    
    private var sttEngine: (any STTEngine)?
    private var llmEngine: (any LLMEngine)?
    private let container: ModelContainer
    
    init(appState: AppState, container: ModelContainer) {
        self.appState = appState
        self.container = container
        self.audioCapture = AudioCaptureManager()
        self.pasteManager = PasteManager()
    }
    
    func ensureModelsLoaded() async throws {
        // Load STT if not loaded
        if sttEngine == nil || !sttEngine!.isLoaded {
            let settings = try fetchSettings()
            sttEngine = STTEngineFactory.create(modelId: settings.sttModelId)
            try await sttEngine!.loadModel { progress in
                // Update UI progress
            }
        }
        
        // Load LLM if not loaded  
        if llmEngine == nil || !llmEngine!.isLoaded {
            let settings = try fetchSettings()
            llmEngine = MLXEngine()
            try await llmEngine!.loadModel(id: settings.llmModelId) { progress in
                // Update UI progress
            }
        }
    }
    
    func startRecording() async throws {
        try await ensureModelsLoaded()
        
        appState.creatureState = .recording
        appState.isRecording = true
        
        SoundManager.shared.playStart()
        HapticManager.shared.tap()
        
        try await audioCapture.startCapture { [weak self] rms in
            DispatchQueue.main.async {
                self?.appState.currentRMS = rms
            }
        }
    }
    
    func stopRecordingAndProcess() async throws -> String {
        // Stop recording
        let audioBuffer = audioCapture.stopCapture()
        appState.isRecording = false
        appState.creatureState = .processing
        
        SoundManager.shared.playStop()
        HapticManager.shared.tap()
        
        do {
            // STT
            let transcription = try await sttEngine!.transcribe(audioBuffer: audioBuffer)
            let rawText = transcription.text
            
            // LLM Cleanup
            let settings = try fetchSettings()
            let context = CleanupContext(
                stylePrompt: settings.stylePrompt,
                formality: CleanupContext.Formality(rawValue: settings.formality) ?? .neutral,
                language: settings.language,
                appContext: AppDetector.frontmostAppName(),
                cleanupLevel: CleanupContext.CleanupLevel(rawValue: settings.cleanupLevel) ?? .medium
            )
            
            let cleanedText = try await llmEngine!.cleanup(rawText: rawText, context: context)
            
            // Paste
            if settings.autoPaste {
                pasteManager.paste(cleanedText)
            }
            if settings.copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cleanedText, forType: .string)
            }
            
            // Save to history
            try saveTranscription(raw: rawText, cleaned: cleanedText, duration: transcription.processingTime)
            
            // Update state
            appState.creatureState = .sleeping
            appState.lastTranscription = cleanedText
            
            return cleanedText
            
        } catch {
            appState.creatureState = .sleeping
            throw error
        }
    }
    
    func cancelRecording() {
        audioCapture.cancelCapture()
        appState.isRecording = false
        appState.creatureState = .sleeping
    }
    
    private func fetchSettings() throws -> AppSettings {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        return try context.fetch(descriptor).first ?? AppSettings.defaults()
    }
    
    private func saveTranscription(raw: String, cleaned: String, duration: TimeInterval) throws {
        let context = ModelContext(container)
        let entry = Transcription(
            id: UUID(),
            rawText: raw,
            cleanedText: cleaned,
            timestamp: Date(),
            durationSeconds: duration,
            wordCount: cleaned.split(separator: " ").count,
            sttModel: sttEngine?.modelInfo.id ?? "unknown",
            llmModel: "unknown",
            sourceApp: AppDetector.frontmostAppName(),
            language: "en",
            cleanupLevel: "medium"
        )
        context.insert(entry)
        try context.save()
    }
}
```

---

## 8. Key Info.plist Settings

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hide from Dock -->
    <key>LSUIElement</key>
    <true/>
    
    <!-- Microphone usage description -->
    <key>NSMicrophoneUsageDescription</key>
    <string>YapYap needs microphone access to transcribe your voice into text.</string>
    
    <!-- Accessibility usage (for paste) -->
    <key>NSAppleEventsUsageDescription</key>
    <string>YapYap needs accessibility access to paste transcribed text into your apps.</string>
    
    <!-- Minimum macOS version -->
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    
    <!-- App category -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    
    <!-- Sparkle feed URL -->
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/yapyap-app/yapyap/main/appcast.xml</string>
</dict>
</plist>
```

---

## 9. Error Types

```swift
// YapYapError.swift
enum YapYapError: LocalizedError {
    case modelNotLoaded
    case modelDownloadFailed(String)
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case audioCaptureFailed(Error)
    case transcriptionFailed(Error)
    case cleanupFailed(Error)
    case pasteFailed(Error)
    case noAudioRecorded
    case recordingTimeout
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "AI model is not loaded. Go to Settings → Models to download one."
        case .modelDownloadFailed(let msg):
            return "Failed to download model: \(msg)"
        case .microphonePermissionDenied:
            return "Microphone access is required. Open System Settings → Privacy & Security → Microphone."
        case .accessibilityPermissionDenied:
            return "Accessibility access is required for auto-paste. Open System Settings → Privacy & Security → Accessibility."
        case .audioCaptureFailed(let err):
            return "Audio capture failed: \(err.localizedDescription)"
        case .transcriptionFailed(let err):
            return "Transcription failed: \(err.localizedDescription)"
        case .cleanupFailed(let err):
            return "Text cleanup failed: \(err.localizedDescription)"
        case .pasteFailed(let err):
            return "Paste failed: \(err.localizedDescription)"
        case .noAudioRecorded:
            return "No speech was detected. Try speaking louder or closer to the mic."
        case .recordingTimeout:
            return "Recording exceeded the maximum duration (5 minutes)."
        }
    }
}
```

---

## 10. App Context Detection & Adaptive Formatting

```swift
// AppContextDetector.swift — Full implementation reference
import AppKit
import ApplicationServices

enum AppCategory: String, Codable, CaseIterable {
    case personalMessaging, workMessaging, email, codeEditor
    case browser, documents, aiChat, other
    
    var displayName: String {
        switch self {
        case .personalMessaging: return "Personal Messaging"
        case .workMessaging: return "Work Messaging"
        case .email: return "Email"
        case .codeEditor: return "Code Editor"
        case .browser: return "Browser"
        case .documents: return "Documents"
        case .aiChat: return "AI Chat"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .personalMessaging: return "💬"
        case .workMessaging: return "💼"
        case .email: return "✉️"
        case .codeEditor: return "🖥️"
        case .browser: return "🌐"
        case .documents: return "📄"
        case .aiChat: return "🤖"
        case .other: return "⚙️"
        }
    }
    
    var exampleApps: String {
        switch self {
        case .personalMessaging: return "iMessage, WhatsApp, Telegram, Signal"
        case .workMessaging: return "Slack, Teams, Discord"
        case .email: return "Mail, Gmail, Outlook, Superhuman"
        case .codeEditor: return "Cursor, VS Code, Xcode, Windsurf"
        case .browser: return "Safari, Chrome, Firefox, Arc"
        case .documents: return "Pages, Notion, Obsidian, Notes"
        case .aiChat: return "ChatGPT, Claude, Perplexity"
        case .other: return "Other applications"
        }
    }
    
    /// Which OutputStyles are available for this category
    var availableStyles: [OutputStyle] {
        switch self {
        case .personalMessaging: return [.veryCasual, .casual, .excited, .formal]
        case .workMessaging: return [.casual, .excited, .formal]
        case .email: return [.casual, .excited, .formal]
        case .codeEditor: return [.casual, .formal]
        case .documents: return [.casual, .formal]
        case .aiChat: return [.casual, .formal]
        case .browser: return [.casual, .excited, .formal]
        case .other: return [.casual, .formal]
        }
    }
}

enum OutputStyle: String, Codable, CaseIterable {
    case veryCasual, casual, excited, formal
    
    var displayName: String {
        switch self {
        case .veryCasual: return "Very Casual"
        case .casual: return "Casual"
        case .excited: return "Excited"
        case .formal: return "Formal"
        }
    }
    
    var previewText: String {
        switch self {
        case .veryCasual: return "hey yeah that sounds good to me"
        case .casual: return "Hey, yeah that sounds good to me"
        case .excited: return "Hey, yeah that sounds good to me!"
        case .formal: return "Hey, that sounds good to me."
        }
    }
}

struct AppContext {
    let bundleId: String
    let appName: String
    let category: AppCategory
    let style: OutputStyle
    let windowTitle: String?
    let focusedFieldText: String?
    let isIDEChatPanel: Bool
}

class AppContextDetector {
    
    // MARK: - Bundle ID Mapping
    
    private static let bundleMap: [String: AppCategory] = [
        // Personal Messaging
        "com.apple.MobileSMS": .personalMessaging,
        "net.whatsapp.WhatsApp": .personalMessaging,
        "org.telegram.desktop": .personalMessaging,
        "org.thoughtcrime.securesms": .personalMessaging,
        "com.facebook.archon": .personalMessaging,        // Messenger
        
        // Work Messaging
        "com.tinyspeck.slackmacgap": .workMessaging,
        "com.microsoft.teams2": .workMessaging,
        "com.hnc.Discord": .workMessaging,
        "us.zoom.xos": .workMessaging,
        
        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.smartemail-macos": .email,
        "com.superhuman.electron": .email,
        
        // Code Editors
        "com.todesktop.230313mzl4w4u92": .codeEditor,    // Cursor
        "com.microsoft.VSCode": .codeEditor,
        "com.apple.dt.Xcode": .codeEditor,
        "dev.zed.Zed": .codeEditor,
        "com.codeium.windsurf": .codeEditor,
        "com.googlecode.iterm2": .codeEditor,
        "com.apple.Terminal": .codeEditor,
        
        // Documents
        "com.apple.iWork.Pages": .documents,
        "notion.id": .documents,
        "md.obsidian": .documents,
        "com.apple.Notes": .documents,
        
        // AI Chat (native apps)
        "com.openai.chat": .aiChat,
        
        // Browsers
        "com.apple.Safari": .browser,
        "com.google.Chrome": .browser,
        "org.mozilla.firefox": .browser,
        "company.thebrowser.Browser": .browser,            // Arc
        "com.brave.Browser": .browser,
    ]
    
    private static let browserBundleIds: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
        "company.thebrowser.Browser", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera"
    ]
    
    // MARK: - Detection
    
    static func detect(settings: StyleSettings) -> AppContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(bundleId: "", appName: "Unknown", category: .other,
                           style: settings.styleFor(.other), windowTitle: nil,
                           focusedFieldText: nil, isIDEChatPanel: false)
        }
        
        let bundleId = frontApp.bundleIdentifier ?? ""
        let appName = frontApp.localizedName ?? "Unknown"
        let pid = frontApp.processIdentifier
        
        // Check user overrides first
        var category: AppCategory
        if let override = settings.appCategoryOverrides[bundleId] {
            category = override
        } else if let mapped = bundleMap[bundleId] {
            category = mapped
        } else if browserBundleIds.contains(bundleId) {
            category = classifyBrowserTab(pid: pid)
        } else {
            category = .other
        }
        
        let windowTitle = getWindowTitle(pid: pid)
        let focusedText = getFocusedFieldText()
        let isIDEChat = category == .codeEditor && isAIChatPanel(windowTitle: windowTitle)
        let style = settings.styleFor(category)
        
        return AppContext(bundleId: bundleId, appName: appName, category: category,
                        style: style, windowTitle: windowTitle,
                        focusedFieldText: focusedText, isIDEChatPanel: isIDEChat)
    }
    
    // MARK: - Browser Tab Classification
    
    private static func classifyBrowserTab(pid: pid_t) -> AppCategory {
        guard let title = getWindowTitle(pid: pid)?.lowercased() else { return .browser }
        
        let patterns: [(String, AppCategory)] = [
            ("gmail", .email), ("outlook.live", .email), ("mail.google", .email),
            ("proton", .email), ("yahoo.com/mail", .email),
            ("slack.com", .workMessaging), ("teams.microsoft", .workMessaging),
            ("chatgpt", .aiChat), ("claude.ai", .aiChat), ("perplexity", .aiChat),
            ("docs.google", .documents), ("notion.so", .documents),
            ("github.com", .codeEditor), ("gitlab.com", .codeEditor),
        ]
        
        for (pattern, category) in patterns {
            if title.contains(pattern) { return category }
        }
        return .browser
    }
    
    // MARK: - IDE Chat Panel Detection
    
    private static func isAIChatPanel(windowTitle: String?) -> Bool {
        guard let title = windowTitle?.lowercased() else { return false }
        return title.contains("composer") || title.contains("chat") ||
               title.contains("copilot") || title.contains("ai assistant")
    }
    
    // MARK: - Accessibility API Helpers
    
    static func getWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else { return nil }
        
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(windowValue as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        return titleValue as? String
    }
    
    static func getFocusedFieldText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success else { return nil }
        
        var textValue: AnyObject?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &textValue) == .success else { return nil }
        
        // Return last 500 chars max (for context, not the whole document)
        if let text = textValue as? String {
            return String(text.suffix(500))
        }
        return nil
    }
    
    /// Get selected text from active app (for Command Mode)
    static func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success else { return nil }
        
        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success else { return nil }
        return selectedText as? String
    }
}
```

```swift
// OutputFormatter.swift — Deterministic post-processing after LLM cleanup
import Foundation

struct OutputFormatter {
    
    static func format(_ text: String, for context: AppContext) -> String {
        var result = text
        
        // Very casual: strip trailing periods, lowercase
        if context.style == .veryCasual {
            result = applyVeryCasual(result)
        }
        
        // IDE file tagging
        if context.isIDEChatPanel {
            result = applyFileTagging(result)
        }
        
        // IDE variable backtick wrapping
        if context.category == .codeEditor && UserSettings.shared.styleSettings.ideVariableRecognition {
            result = wrapCodeTokens(result)
        }
        
        return result
    }
    
    // MARK: - File Tagging
    
    static func applyFileTagging(_ text: String) -> String {
        let extensions = ["swift", "py", "ts", "tsx", "js", "jsx", "rs", "go", "rb",
                         "java", "kt", "cpp", "c", "h", "css", "html", "json",
                         "yaml", "yml", "toml", "md", "sql", "sh", "vue", "svelte"]
        let extPattern = extensions.joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: "\\bat\\s+(\\w+\\.(?:\(extPattern)))\\b",
            options: [.caseInsensitive]
        ) else { return text }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "@$1")
    }
    
    // MARK: - Code Token Wrapping
    
    static func wrapCodeTokens(_ text: String) -> String {
        // Match camelCase and snake_case identifiers not already in backticks
        guard let regex = try? NSRegularExpression(
            pattern: "(?<!`)\\b([a-z]+[A-Z][a-zA-Z]*|[a-z]+_[a-z_]+)\\b(?!`)",
            options: []
        ) else { return text }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "`$0`")
    }
    
    // MARK: - Very Casual Formatting
    
    static func applyVeryCasual(_ text: String) -> String {
        var result = text
        
        // Remove trailing periods (keep ! and ?)
        result = result.replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\.\\n", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\. ", with: " ", options: .regularExpression)
        
        // Lowercase first character of each line
        let lines = result.components(separatedBy: "\n")
        result = lines.map { line in
            guard let first = line.first, first.isUppercase else { return line }
            return first.lowercased() + line.dropFirst()
        }.joined(separator: "\n")
        
        return result
    }
}
```

```swift
// CommandMode.swift — Voice-powered text editing
import Foundation

struct CommandMode {
    
    static let commandPrefixes = [
        "make this", "turn this into", "turn into", "rewrite this", "rewrite",
        "shorten this", "shorten", "summarize this", "summarize",
        "expand this", "expand", "make it", "format this as", "format as",
        "translate this to", "translate to", "fix the grammar", "fix grammar",
        "add bullet points", "make more professional", "make more casual",
        "make this more", "make it more", "simplify this", "simplify",
    ]
    
    static func isCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return commandPrefixes.contains(where: { lower.hasPrefix($0) })
    }
    
    static func buildPrompt(command: String, selectedText: String) -> String {
        """
        You are a text editor assistant. Apply the user's command to transform the given text.
        
        RULES:
        - Apply ONLY the requested transformation
        - Preserve the original meaning and intent
        - Output ONLY the transformed text, nothing else
        - No explanations, no preamble
        
        USER COMMAND: \(command)
        
        ORIGINAL TEXT:
        \(selectedText)
        
        TRANSFORMED TEXT:
        """
    }
}
```

```swift
// StyleSettings.swift — User's per-category style preferences
import Foundation

struct StyleSettings: Codable {
    var personalMessaging: OutputStyle = .casual
    var workMessaging: OutputStyle = .casual
    var email: OutputStyle = .formal
    var codeEditor: OutputStyle = .formal
    var documents: OutputStyle = .formal
    var aiChat: OutputStyle = .casual
    var browser: OutputStyle = .casual
    var other: OutputStyle = .casual
    
    var ideVariableRecognition: Bool = true
    var ideFileTagging: Bool = true
    
    var appCategoryOverrides: [String: AppCategory] = [:]
    
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

```swift
// PersonalDictionary.swift — Auto-learning word corrections
import Foundation

class PersonalDictionary: ObservableObject {
    @Published var entries: [String: String] = [:]
    
    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("YapYap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }()
    
    init() { load() }
    
    func applyCorrections(to text: String) -> String {
        var result = text
        for (spoken, corrected) in entries {
            let escaped = NSRegularExpression.escapedPattern(for: spoken)
            if let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: corrected)
            }
        }
        return result
    }
    
    func learnCorrection(spoken: String, corrected: String) {
        entries[spoken.lowercased()] = corrected
        save()
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        entries = decoded
    }
}
```
