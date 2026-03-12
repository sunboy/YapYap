// CleanupPromptBuilderV3.swift
// YapYap — V3 prompt builder: model-family-specific prompts with static prefix for KV caching
//
// Key architectural difference from V2:
// - System prompt is CONSTANT per model family (no app context baked in)
// - Few-shots are CONSTANT per model family
// - App context goes in the user message: "[Context: Slack] Reformat: ..."
// - This means system + few-shots form a static prefix → KV-cached once at startup
// - Switching apps (Slack → Email) only changes the ~20-token user message, not the prefix
import Foundation

/// V3 prompt builder that produces chat messages with a static, cacheable prefix.
///
/// Output format:
///   [system]    → family-specific system prompt (CONSTANT)
///   [user]      → few-shot input 1 (CONSTANT)
///   [assistant] → few-shot output 1 (CONSTANT)
///   ... (all few-shot pairs, CONSTANT)
///   ──── KV cache prefix ends here ────
///   [user]      → "[Context: Slack] Reformat: hey check the logs"  ← ONLY THIS CHANGES
struct CleanupPromptBuilderV3 {

    /// Builds the full message array for chat completion.
    /// The last message is always a user message with app context embedded.
    static func buildMessages(
        rawText: String,
        context: CleanupContext,
        modelId: String? = nil,
        userContext: UserPromptContext? = nil
    ) -> [ChatMessage] {
        let (family, size) = resolveModelInfo(modelId: modelId)
        let overrides = PromptOverrides.loadFromUserDefaults()

        var messages: [ChatMessage] = []

        // 1. System message — static per model family (no app context!)
        let vocabularyBlock = buildVocabularyBlock(userContext: userContext, modelSize: size)
        let systemText = overrides.effectiveSystemPrompt(variant: .unified)
            ?? PromptTemplatesV3.systemPrompt(family: family, size: size, vocabularyBlock: vocabularyBlock)
        messages.append(ChatMessage(role: .system, content: systemText))

        // 2. Few-shot examples as user/assistant pairs — static per model family
        let examples: [(user: String, assistant: String)]
        if let customExamples = overrides.effectiveExamples() {
            examples = customExamples.map { (
                user: PromptTemplatesV3.formatUserInput($0.input, appContext: "IDE"),
                assistant: $0.output
            ) }
        } else {
            examples = PromptTemplatesV3.fewShots(family: family, size: size)
        }

        for example in examples {
            messages.append(ChatMessage(role: .user, content: example.user))
            messages.append(ChatMessage(role: .assistant, content: example.assistant))
        }

        // 3. Actual user input with app context embedded in the message
        let appKeyword = AppContextMapper.keyword(from: context.appContext)
        let userContent = PromptTemplatesV3.formatUserInput(rawText, appContext: appKeyword)
        messages.append(ChatMessage(role: .user, content: userContent))

        return messages
    }

    /// Returns (prefixMessages, suffixMessage) for prompt caching.
    /// - prefixMessages: system + all few-shot pairs — CONSTANT across app switches
    /// - suffixMessage: "[Context: X] Reformat: ..." — changes per call
    ///
    /// The prefix is cacheable across ALL calls regardless of which app is active.
    /// Only the suffix (~20 tokens) needs fresh prefill each time.
    static func buildMessageParts(
        rawText: String,
        context: CleanupContext,
        modelId: String? = nil,
        userContext: UserPromptContext? = nil
    ) -> (prefix: [ChatMessage], suffix: ChatMessage) {
        let all = buildMessages(rawText: rawText, context: context, modelId: modelId, userContext: userContext)
        let prefix = Array(all.dropLast())
        let suffix = all.last!
        return (prefix, suffix)
    }

    /// Returns just the static prefix messages (system + few-shots) for pre-caching at startup.
    /// This is used by MLXEngine to compute and cache the KV state once at model load time,
    /// before any user request arrives.
    ///
    /// Delegates to `buildMessages` with a dummy input and drops the final user message,
    /// guaranteeing the prefix is always identical to what `buildMessageParts` returns.
    static func buildPrefixMessages(
        modelId: String? = nil,
        userContext: UserPromptContext? = nil
    ) -> [ChatMessage] {
        // Use a dummy context — only the prefix (system + few-shots) is kept,
        // so the app context and raw text don't matter.
        let dummyContext = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false,
            promptVersion: .v3
        )
        let all = buildMessages(rawText: "", context: dummyContext, modelId: modelId, userContext: userContext)
        return Array(all.dropLast())
    }

    // MARK: - Private

    private static func resolveModelInfo(modelId: String?) -> (LLMModelFamily, LLMModelSize) {
        guard let id = modelId, let info = LLMModelRegistry.model(for: id) else {
            return (.qwen, .medium)
        }
        return (info.family, info.size)
    }

    private static func buildVocabularyBlock(userContext: UserPromptContext?, modelSize: LLMModelSize) -> String {
        guard let ctx = userContext else { return "" }
        let dict = ctx.dictionaryBlock(modelSize: modelSize)
        let style = ctx.editMemoryBlock(modelSize: modelSize)
        return [dict, style].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
