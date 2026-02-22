// CleanupPromptBuilder.swift
// YapYap — Builds model-specific, context-aware cleanup prompts for the LLM
import Foundation

struct CleanupPromptBuilder {

    /// Returns (systemMessage, userMessage) for the chat template.
    /// Prompts are model-specific: small models (<=2B) get ultra-minimal prompts,
    /// medium+ models (3B+) get detailed prompts with rules and more examples.
    static func buildMessages(rawText: String, context: CleanupContext, modelId: String? = nil) -> (system: String, user: String) {
        let (family, size) = resolveModel(modelId: modelId)
        let system = buildSystemPrompt(context: context, family: family, size: size)
        let user = buildUserMessage(rawText: rawText, context: context, family: family, size: size)
        return (system: system, user: user)
    }

    // MARK: - Model Resolution

    private static func resolveModel(modelId: String?) -> (LLMModelFamily, LLMModelSize) {
        guard let id = modelId, let info = LLMModelRegistry.model(for: id) else {
            return (.qwen, .small) // Default to Qwen small-style prompting
        }
        return (info.family, info.size)
    }

    // MARK: - System Prompt

    private static func buildSystemPrompt(context: CleanupContext, family: LLMModelFamily, size: LLMModelSize) -> String {
        // Small models (<=2B): ultra-minimal system prompt.
        // Testing showed 100% success with 8-word system prompt on 1B models,
        // vs 33% success with detailed prompts.
        if size == .small {
            return buildSmallModelSystemPrompt(context: context, family: family)
        }

        // Medium+ models (3B+): detailed system prompt with full rules
        switch family {
        case .llama:
            return buildLlamaDetailedSystemPrompt(context: context)
        case .qwen:
            return buildQwenDetailedSystemPrompt(context: context)
        case .gemma:
            return "You clean up speech-to-text transcripts. Output only the cleaned text."
        }
    }

    /// Concise system prompt for small models (<=2B params).
    /// Llama 3.2 1B has IFEval 59.5 — can follow short, focused instructions.
    /// Includes concise app context hints and list detection.
    private static func buildSmallModelSystemPrompt(context: CleanupContext, family: LLMModelFamily) -> String {
        var prompt: String
        switch context.cleanupLevel {
        case .light:
            prompt = "Fix dictation errors. Output only fixed text."
        case .medium:
            prompt = "Fix dictation errors. Remove filler words. Output only fixed text."
        case .heavy:
            prompt = "Fix dictation errors. Remove fillers. Improve clarity. Output only fixed text."
        }

        // List detection — concise instruction for small models
        prompt += " Lists → numbered, one per line."

        // Add concise app context hint
        if let appContext = context.appContext {
            switch appContext.category {
            case .workMessaging:
                prompt += " Keep @mentions and #channels."
            case .email:
                prompt += " Use proper sentences."
            case .codeEditor:
                if appContext.isIDEChatPanel {
                    prompt += " Prefix filenames with @."
                } else {
                    prompt += " Keep code terms exact."
                }
            case .personalMessaging:
                prompt += " Keep it casual."
            case .aiChat:
                prompt += " Keep technical terms exact."
            default:
                break
            }
        }

        return prompt
    }

    /// Detailed Llama system prompt for 3B+ models.
    private static func buildLlamaDetailedSystemPrompt(context: CleanupContext) -> String {
        var parts: [String] = []

        parts.append("You are a speech-to-text cleanup engine. You receive raw transcribed text and return a cleaned version.")

        switch context.cleanupLevel {
        case .light:
            parts.append("RULES:\n1. Fix punctuation and capitalization\n2. Do NOT remove any words")
        case .medium:
            parts.append("RULES:\n1. Remove filler words: um, uh, like, you know, I mean, basically, right, kind of, sort of\n2. Fix punctuation and capitalization\n3. Handle self-corrections: \"X no wait Y\" → output only Y")
        case .heavy:
            parts.append("RULES:\n1. Remove ALL filler words and hesitations\n2. Fix punctuation, capitalization, and sentence structure\n3. Handle self-corrections: \"X no wait Y\" → output only Y\n4. Improve clarity without changing meaning")
        }

        parts.append("STRICT CONSTRAINTS:\n- Do NOT add any words, ideas, or content not in the transcript\n- Do NOT summarize or shorten\n- Do NOT explain your changes\n- If the input contains a list of items (comma-separated, colon-introduced, or ordinal), format each item on its own line as a numbered list\n- Output ONLY the cleaned text, nothing else")

        if let appContext = context.appContext {
            parts.append("App: \(appContext.appName) (\(toneHint(for: appContext)))")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Detailed Qwen system prompt for 3B+ models.
    private static func buildQwenDetailedSystemPrompt(context: CleanupContext) -> String {
        var parts: [String] = []

        parts.append("You clean up speech-to-text transcripts.")

        switch context.cleanupLevel {
        case .light:
            parts.append("Rules:\n- Fix punctuation and capitalization\n- Do NOT remove any words")
        case .medium:
            parts.append("Rules:\n- Remove: um, uh, like, you know, I mean, basically, right, kind of, sort of\n- Fix punctuation and capitalization\n- \"X no wait Y\" → keep only Y")
        case .heavy:
            parts.append("Rules:\n- Remove ALL filler words and hesitations\n- Fix punctuation, capitalization, and sentence structure\n- \"X no wait Y\" → keep only Y\n- Improve clarity without changing meaning")
        }

        switch context.formality {
        case .casual:
            parts.append("Tone: casual")
        case .neutral:
            break
        case .formal:
            parts.append("Tone: formal, no contractions")
        }

        if let appContext = context.appContext {
            parts.append("App: \(appContext.appName) (\(toneHint(for: appContext)))")
        }

        if !context.stylePrompt.isEmpty {
            parts.append("Style: \(context.stylePrompt)")
        }

        parts.append("If the input contains a list of items (comma-separated, colon-introduced, or ordinal), format each item on its own line as a numbered list.\nDo NOT add new words. Do NOT summarize. Output only cleaned text.")

        return parts.joined(separator: "\n")
    }

    // MARK: - User Message

    private static func buildUserMessage(rawText: String, context: CleanupContext, family: LLMModelFamily, size: LLMModelSize) -> String {
        // Small models: compact 2-example format for all families
        if size == .small {
            return buildSmallModelUserMessage(rawText: rawText, context: context)
        }

        // Medium+ models: family-specific with 3 detailed examples
        switch family {
        case .llama:
            return buildLlamaDetailedUserMessage(rawText: rawText, context: context)
        case .qwen:
            return buildQwenDetailedUserMessage(rawText: rawText, context: context)
        case .gemma:
            return buildGemmaUserMessage(rawText: rawText, context: context)
        }
    }

    /// Compact user message for small models (<=2B).
    /// Uses 2 short examples with IN:/OUT: format.
    /// Testing showed this achieves 100% success on Llama 1B.
    private static func buildSmallModelUserMessage(rawText: String, context: CleanupContext) -> String {
        var parts: [String] = []

        parts.append("""
        Examples:
        IN: um so like i need to uh finish the report by friday
        OUT: I need to finish the report by Friday.

        IN: hey so basically the thing is the api is broken and uh nobody noticed
        OUT: Hey, the API is broken and nobody noticed.

        IN: things to do today check email review the PR and update the docs
        OUT:
        1. Check email
        2. Review the PR
        3. Update the docs
        """)

        parts.append("Fix this:\n\(rawText)")
        return parts.joined(separator: "\n\n")
    }

    /// Detailed Llama user message for 3B+ models with 3 examples.
    private static func buildLlamaDetailedUserMessage(rawText: String, context: CleanupContext) -> String {
        var parts: [String] = []

        parts.append("Clean up this transcript. Follow the examples exactly.")

        switch context.cleanupLevel {
        case .light:
            parts.append("""
            EXAMPLE 1:
            Input: so i was thinking we should probably have a meeting tomorrow to discuss the project timeline
            Output: So I was thinking we should probably have a meeting tomorrow to discuss the project timeline.

            EXAMPLE 2:
            Input: the server is basically down and nobody is responding to the alerts we need to fix this right away
            Output: The server is basically down and nobody is responding to the alerts. We need to fix this right away.
            """)
        case .medium:
            parts.append("""
            EXAMPLE 1:
            Input: um so i was thinking we should uh have a meeting tomorrow to discuss the project timeline you know
            Output: I was thinking we should have a meeting tomorrow to discuss the project timeline.

            EXAMPLE 2:
            Input: basically what happened was the server went down at like 3 am and you know nobody was monitoring it so it was actually down for like two hours before anyone noticed
            Output: What happened was the server went down at 3 AM and nobody was monitoring it, so it was down for two hours before anyone noticed.

            EXAMPLE 3:
            Input: hey can you uh look at the app the app is crashing when users try to log in i think it's a null pointer issue
            Output: Hey, can you look at the app? It's crashing when users try to log in. I think it's a null pointer issue.
            """)
        case .heavy:
            parts.append("""
            EXAMPLE 1:
            Input: um so basically like i was thinking about it and uh we should probably you know have a meeting tomorrow to uh discuss the project timeline
            Output: We should have a meeting tomorrow to discuss the project timeline.

            EXAMPLE 2:
            Input: so like basically what happened was the server went down at like 3 am and you know nobody was monitoring it so it was actually down for like two hours before anyone noticed i mean that's not great right
            Output: The server went down at 3 AM. Nobody was monitoring it, so it was down for two hours before anyone noticed.
            """)
        }

        parts.append("NOW CLEAN THIS TRANSCRIPT:\n\(rawText)")
        return parts.joined(separator: "\n\n")
    }

    /// Detailed Qwen user message for 3B+ models.
    private static func buildQwenDetailedUserMessage(rawText: String, context: CleanupContext) -> String {
        var parts: [String] = []

        parts.append("""
        Clean up this transcript. Follow the examples exactly.

        EXAMPLE 1:
        Input: um so i was thinking we should uh have a meeting tomorrow to discuss the project timeline you know
        Output: I was thinking we should have a meeting tomorrow to discuss the project timeline.

        EXAMPLE 2:
        Input: basically what happened was the server went down at like 3 am and you know nobody was monitoring it so it was actually down for like two hours before anyone noticed
        Output: What happened was the server went down at 3 AM and nobody was monitoring it, so it was down for two hours before anyone noticed.

        EXAMPLE 3:
        Input: hey can you uh look at the app the app is crashing when users try to log in i think it's a null pointer issue
        Output: Hey, can you look at the app? It's crashing when users try to log in. I think it's a null pointer issue.
        """)

        parts.append("NOW CLEAN THIS TRANSCRIPT:\n\(rawText)")
        return parts.joined(separator: "\n\n")
    }

    /// Gemma user message with all instructions + examples (no system role support).
    private static func buildGemmaUserMessage(rawText: String, context: CleanupContext) -> String {
        var parts: [String] = []

        var instructions = "INSTRUCTIONS: Clean up the transcript at the end.\n"
        switch context.cleanupLevel {
        case .light:
            instructions += "FIX: punctuation, capitalization\n"
        case .medium:
            instructions += "REMOVE: filler words (um, uh, like, you know, I mean, basically)\nFIX: punctuation, capitalization\nSELF-CORRECTIONS: \"X no wait Y\" → keep only Y\n"
        case .heavy:
            instructions += "REMOVE: ALL filler words and hesitations\nFIX: punctuation, capitalization, sentence structure\nSELF-CORRECTIONS: \"X no wait Y\" → keep only Y\n"
        }
        instructions += "If the input contains a list of items (comma-separated, colon-introduced, or ordinal), format each item on its own line as a numbered list.\n"
        instructions += "Do NOT add new words. Do NOT summarize. Output ONLY the cleaned text."
        parts.append(instructions)

        if let appContext = context.appContext {
            parts.append("App: \(appContext.appName) (\(toneHint(for: appContext)))")
        }

        parts.append("""
        EXAMPLES:
        IN: um so i was thinking about like refactoring the auth module you know
        OUT: I was thinking about refactoring the auth module.

        IN: hey just wanted to let you know the deploy went fine no issues everything's looking good
        OUT: Hey, just wanted to let you know the deploy went fine. No issues, everything's looking good.
        """)

        parts.append("TRANSCRIPT TO CLEAN:\n\(rawText)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - App Context Helpers

    /// Brief tone hint from app category, kept compact for small model context windows.
    /// IDE chat panels get a special hint to prefix filenames with @.
    private static func toneHint(for appContext: AppContext) -> String {
        if appContext.isIDEChatPanel {
            return "IDE chat panel, prefix filenames with @, keep technical terms exact"
        }
        switch appContext.category {
        case .personalMessaging:
            return "casual messaging"
        case .workMessaging:
            return "work messaging (Slack/Teams), keep @mentions and #channels intact"
        case .email:
            return "email, use proper sentences and paragraph structure"
        case .codeEditor:
            return "code editor, keep technical terms exact"
        case .browser:
            return "browser"
        case .documents:
            return "document, clean prose"
        case .aiChat:
            return "AI chat, keep technical terms and code references exact"
        case .other:
            return "general"
        }
    }
}
