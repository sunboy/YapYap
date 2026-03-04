// CleanupPromptBuilderV2.swift
// YapYap — V2 prompt builder: chat-style multi-turn messages for all backends
import Foundation

/// A single message in a chat conversation.
struct ChatMessage {
    enum Role: String {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

/// V2 prompt builder that produces an array of ChatMessages with proper user/assistant
/// few-shot turns, replacing V1's inline-example approach.
///
/// Output format:
///   [system] → V2 system prompt with app context keyword + cleanup level
///   [user]   → "Reformat: {example1_input}"
///   [assistant] → "{example1_output}"
///   [user]   → "Reformat: {example2_input}"
///   [assistant] → "{example2_output}"
///   ... (all few-shot pairs)
///   [user]   → "Reformat: {rawText}"      ← the actual transcript
struct CleanupPromptBuilderV2 {

    /// Builds the full message array for chat completion.
    /// The last message is always a user message containing the actual transcript.
    static func buildMessages(
        rawText: String,
        context: CleanupContext,
        userContext: UserPromptContext? = nil
    ) -> [ChatMessage] {
        let overrides = PromptOverrides.loadFromUserDefaults()

        var messages: [ChatMessage] = []

        // 1. System message
        let appKeyword = AppContextMapper.keyword(from: context.appContext)
        let systemText = overrides.effectiveSystemPrompt(variant: .unified)
            ?? PromptTemplatesV2.systemPrompt(appContext: appKeyword, cleanupLevel: context.cleanupLevel)
        messages.append(ChatMessage(role: .system, content: systemText))

        // 2. Few-shot examples as user/assistant pairs
        let examples: [(user: String, assistant: String)]
        if let customExamples = overrides.effectiveExamples() {
            examples = customExamples.map { (
                user: PromptTemplatesV2.formatUserInput($0.input),
                assistant: $0.output
            ) }
        } else {
            examples = PromptTemplatesV2.fewShotExamples
        }

        for example in examples {
            messages.append(ChatMessage(role: .user, content: example.user))
            messages.append(ChatMessage(role: .assistant, content: example.assistant))
        }

        // 3. User context (dictionary + edit memory) — append to system if present
        if let ctx = userContext {
            let dict = ctx.dictionaryBlock(modelSize: .medium)
            let style = ctx.editMemoryBlock(modelSize: .medium)
            let extras = [dict, style].filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !extras.isEmpty {
                // Append user context as a supplementary system message before the actual input
                messages.append(ChatMessage(role: .system, content: extras))
            }
        }

        // 4. Actual user input (the raw transcript)
        messages.append(ChatMessage(role: .user, content: PromptTemplatesV2.formatUserInput(rawText)))

        return messages
    }

    /// Returns (prefixMessages, suffixMessage) for prompt caching.
    /// - prefixMessages: system + all few-shot pairs (static per settings + app context)
    /// - suffixMessage: the final user message with actual transcript (dynamic per call)
    /// The prefix is cacheable across calls; only the suffix changes.
    static func buildMessageParts(
        rawText: String,
        context: CleanupContext,
        userContext: UserPromptContext? = nil
    ) -> (prefix: [ChatMessage], suffix: ChatMessage) {
        let all = buildMessages(rawText: rawText, context: context, userContext: userContext)
        // Split: everything except the last message is the cacheable prefix
        let prefix = Array(all.dropLast())
        let suffix = all.last ?? ChatMessage(role: .user, content: PromptTemplatesV2.formatUserInput(rawText))
        return (prefix, suffix)
    }
}
