// CleanupPromptBuilder.swift
// YapYap — Assembles prompts from templates + runtime context
import Foundation

struct CleanupPromptBuilder {

    /// Main entry point. Returns (system, user) for the chat template.
    /// The loaded model doesn't change at runtime — family and size
    /// are fixed for the session. App context changes every dictation.
    static func buildMessages(
        rawText: String,
        context: CleanupContext,
        modelId: String? = nil,
        userContext: UserPromptContext? = nil
    ) -> (system: String, user: String) {

        let (family, size) = resolveModel(modelId: modelId, context: context)

        // ── 1. System prompt ────────────────────────────────────
        let system: String
        if family == .gemma {
            // Gemma: minimal system prompt (instructions go in user)
            system = PromptTemplates.System.gemmaSystem
        } else {
            system = assembleSystemPrompt(
                level: context.cleanupLevel,
                size: size,
                app: context.appContext,
                formality: context.formality
            )
        }

        // ── 2. User prompt ──────────────────────────────────────
        let user = assembleUserPrompt(
            rawText: rawText,
            level: context.cleanupLevel,
            size: size,
            family: family,
            app: context.appContext,
            formality: context.formality,
            userContext: userContext
        )

        return (system: system, user: user)
    }

    // MARK: - System Prompt Assembly

    /// system = base(size, level) + appRules(size, app) + formality
    private static func assembleSystemPrompt(
        level: CleanupContext.CleanupLevel,
        size: LLMModelSize,
        app: AppContext?,
        formality: CleanupContext.Formality
    ) -> String {
        var parts: [String] = []

        // 1. Base prompt for this size × level
        parts.append(baseSystemPrompt(size: size, level: level))

        // 2. App-specific rules
        if let app = app {
            let rules = appRules(size: size, app: app)
            if !rules.isEmpty { parts.append(rules) }
        }

        // 3. Formality modifier
        let formalityBlock = formalityModifier(
            formality: formality, size: size
        )
        if !formalityBlock.isEmpty { parts.append(formalityBlock) }

        return parts.joined(separator: "\n\n")
    }

    private static func baseSystemPrompt(
        size: LLMModelSize,
        level: CleanupContext.CleanupLevel
    ) -> String {
        switch (size, level) {
        case (.small, .light):   return PromptTemplates.System.smallLight
        case (.small, .medium):  return PromptTemplates.System.smallMedium
        case (.small, .heavy):   return PromptTemplates.System.smallHeavy
        case (.medium, .light):  return PromptTemplates.System.mediumLight
        case (.medium, .medium): return PromptTemplates.System.mediumMedium
        case (.medium, .heavy):  return PromptTemplates.System.mediumHeavy
        case (.large, .light):   return PromptTemplates.System.largeLight
        case (.large, .medium):  return PromptTemplates.System.largeMedium
        case (.large, .heavy):   return PromptTemplates.System.largeHeavy
        }
    }

    private static func appRules(
        size: LLMModelSize,
        app: AppContext
    ) -> String {
        let key = app.isIDEChatPanel ? "cursorChat" : appKey(app.category)
        switch size {
        case .small:
            return smallAppRules(key)
        case .medium, .large:
            return mediumAppRules(key)
        }
    }

    private static func smallAppRules(_ key: String) -> String {
        switch key {
        case "slack":      return PromptTemplates.AppRules.Small.slack
        case "mail":       return PromptTemplates.AppRules.Small.mail
        case "cursor":     return PromptTemplates.AppRules.Small.cursor
        case "cursorChat": return PromptTemplates.AppRules.Small.cursorChat
        case "messages":   return PromptTemplates.AppRules.Small.messages
        case "claude":     return PromptTemplates.AppRules.Small.claude
        case "terminal":   return PromptTemplates.AppRules.Small.terminal
        case "notes":      return PromptTemplates.AppRules.Small.notes
        case "social":     return PromptTemplates.AppRules.Small.social
        case "docs":       return PromptTemplates.AppRules.Small.docs
        default:           return PromptTemplates.AppRules.Small.generic
        }
    }

    private static func mediumAppRules(_ key: String) -> String {
        switch key {
        case "slack":      return PromptTemplates.AppRules.Medium.slack
        case "mail":       return PromptTemplates.AppRules.Medium.mail
        case "cursor":     return PromptTemplates.AppRules.Medium.cursor
        case "cursorChat": return PromptTemplates.AppRules.Medium.cursorChat
        case "messages":   return PromptTemplates.AppRules.Medium.messages
        case "claude":     return PromptTemplates.AppRules.Medium.claude
        case "terminal":   return PromptTemplates.AppRules.Medium.terminal
        case "notes":      return PromptTemplates.AppRules.Medium.notes
        case "social":     return PromptTemplates.AppRules.Medium.social
        case "docs":       return PromptTemplates.AppRules.Medium.docs
        default:           return PromptTemplates.AppRules.Medium.generic
        }
    }

    private static func appKey(_ category: AppCategory) -> String {
        switch category {
        case .workMessaging:     return "slack"
        case .email:             return "mail"
        case .codeEditor:        return "cursor"
        case .personalMessaging: return "messages"
        case .aiChat:            return "claude"
        case .terminal:          return "terminal"
        case .notes:             return "notes"
        case .social:            return "social"
        case .documents:         return "docs"
        default:                 return "generic"
        }
    }

    private static func formalityModifier(
        formality: CleanupContext.Formality,
        size: LLMModelSize
    ) -> String {
        switch (formality, size) {
        case (.casual, .small):
            return PromptTemplates.Formality.casualSmall
        case (.casual, _):
            return PromptTemplates.Formality.casualMedium
        case (.formal, .small):
            return PromptTemplates.Formality.formalSmall
        case (.formal, _):
            return PromptTemplates.Formality.formalMedium
        case (.neutral, _):
            return ""
        }
    }

    // MARK: - User Prompt Assembly

    /// user = [gemmaInstructions] + dictionary + editMemory + examples
    ///        + outputInstruction + transcript
    private static func assembleUserPrompt(
        rawText: String,
        level: CleanupContext.CleanupLevel,
        size: LLMModelSize,
        family: LLMModelFamily,
        app: AppContext?,
        formality: CleanupContext.Formality,
        userContext: UserPromptContext?
    ) -> String {
        var parts: [String] = []

        // 0. Gemma: system instructions go here (no system role)
        if family == .gemma && size != .small {
            let sysBlock = assembleSystemPrompt(
                level: level, size: size, app: app, formality: formality
            )
            parts.append("INSTRUCTIONS:\n\(sysBlock)")
        }

        // 1. Dictionary
        if let ctx = userContext {
            let dict = ctx.dictionaryBlock(modelSize: size)
            if !dict.isEmpty { parts.append(dict) }

            // 2. Edit memory
            let style = ctx.editMemoryBlock(modelSize: size)
            if !style.isEmpty { parts.append(style) }
        }

        // 3. Few-shot examples
        let examples = selectExamples(level: level, size: size)
        let formatted: String
        switch (size, family) {
        case (.small, _):
            formatted = PromptTemplates.Examples.formatSmall(examples)
        case (_, .gemma):
            formatted = PromptTemplates.Examples.formatGemma(examples)
        default:
            formatted = PromptTemplates.Examples.formatMedium(examples)
        }
        parts.append(formatted)

        // 4. Output instruction + transcript
        let instruction = size == .small
            ? "Output only the cleaned text.\n\n\(rawText)"
            : "Reply with only the cleaned text (no preamble, no labels).\n\nTranscript:\n\(rawText)"
        parts.append(instruction)

        return parts.joined(separator: "\n\n")
    }

    private static func selectExamples(
        level: CleanupContext.CleanupLevel,
        size: LLMModelSize
    ) -> [PromptTemplates.Example] {
        if size == .small {
            return Array(PromptTemplates.Examples.small.prefix(3))
        }
        switch level {
        case .light:  return PromptTemplates.Examples.mediumLight
        case .medium: return PromptTemplates.Examples.mediumMedium
        case .heavy:  return PromptTemplates.Examples.mediumHeavy
        }
    }

    // MARK: - Model Resolution

    private static func resolveModel(
        modelId: String?,
        context: CleanupContext
    ) -> (LLMModelFamily, LLMModelSize) {
        guard let id = modelId,
              let info = LLMModelRegistry.model(for: id) else {
            return (.qwen, .small)
        }
        var size = info.size
        // Experimental: upgrade 1.5B+ small models to medium prompts
        if context.experimentalPrompts && size == .small
            && info.sizeBytes >= 800_000_000 {
            size = .medium
        }
        return (info.family, size)
    }

    // MARK: - Self-Correction Patterns

    /// All self-correction patterns that occur in natural speech.
    /// Used across all prompt paths (small and medium+).
    private static let selfCorrectionRule = """
        Self-corrections (speaker backtracks and corrects themselves): \
        "X no wait Y" → keep only Y; \
        "X or not X, Y" → keep only Y; \
        "X I mean Y" → keep only Y; \
        "X actually Y" → keep only Y (when used as a correction, not a new fact); \
        "X or rather Y" → keep only Y; \
        "X scratch that Y" → keep only Y; \
        "X strike that Y" → keep only Y; \
        "X sorry Y" → keep only Y; \
        "X correction Y" → keep only Y. \
        Only apply when the speaker is clearly replacing X with Y—not when "actually" or "no" add new information.
        """

    /// Compact version for small model prompts where token budget is tight.
    /// Covers the most common patterns; omits rare ones to stay under word budget.
    private static let selfCorrectionRuleCompact = "Speaker corrections ('X no wait Y', 'X I mean Y', 'X or not X Y') → keep only Y."

    // MARK: - System Prompt (Feature/Validation)

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
            return "You clean up speech-to-text transcripts. Reply with only the cleaned text. No preamble, no labels, no repeating instructions—start with the first word of the cleaned text."
        }
    }

    /// Concise system prompt for small models (<=2B params).
    /// Llama 3.2 1B has IFEval 59.5 — can follow short, focused instructions.
    /// Includes concise app context hints and list detection.
    private static func buildSmallModelSystemPrompt(context: CleanupContext, family: LLMModelFamily) -> String {
        var prompt: String
        switch context.cleanupLevel {
        case .light:
            prompt = "Fix dictation errors. Reply with only the fixed text—no preamble or labels."
        case .medium:
            prompt = "Fix dictation errors. Remove filler words. \(selfCorrectionRuleCompact) Reply with only the fixed text—no preamble or labels."
        case .heavy:
            prompt = "Fix dictation errors. Remove fillers. \(selfCorrectionRuleCompact) Improve clarity. Reply with only the fixed text—no preamble or labels."
        }

        // List detection — only trigger on explicit enumerations, not multi-clause sentences
        prompt += " Only format as a list if the speaker explicitly says 'first/second/third' or lists items after a colon. Do not list-format multi-clause sentences."

        // Add concise app context hint
        if let appContext = context.appContext {
            switch appContext.category {
            case .workMessaging:
                prompt += " Keep @mentions and #channels."
            case .email:
                prompt += " Format as email with proper sentences and paragraphs."
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
            parts.append("RULES:\n1. Remove filler words: um, uh, like, you know, I mean, basically, right, kind of, sort of\n2. Fix punctuation and capitalization\n3. \(selfCorrectionRule)")
        case .heavy:
            parts.append("RULES:\n1. Remove ALL filler words and hesitations\n2. Fix punctuation, capitalization, and sentence structure\n3. \(selfCorrectionRule)\n4. Improve clarity without changing meaning")
        }

        parts.append("STRICT CONSTRAINTS:\n- Do NOT add any words, ideas, or content not in the transcript\n- Do NOT summarize or shorten\n- Do NOT explain your changes\n- Do NOT repeat these instructions, add a preamble, or label your reply (e.g. no \"Here is the cleaned transcript:\" or similar). Start your reply with the first word of the cleaned text.\n- Only format as a list if the speaker explicitly enumerates items (e.g. 'first... second... third' or lists items after a colon). Do NOT convert multi-clause sentences into lists.\n- Output ONLY the cleaned text, nothing else")

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
            parts.append("Rules:\n- Remove: um, uh, like, you know, I mean, basically, right, kind of, sort of\n- Fix punctuation and capitalization\n- \(selfCorrectionRule)")
        case .heavy:
            parts.append("Rules:\n- Remove ALL filler words and hesitations\n- Fix punctuation, capitalization, and sentence structure\n- \(selfCorrectionRule)\n- Improve clarity without changing meaning")
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

        parts.append("Only format as a list if the speaker explicitly enumerates items (e.g. 'first... second... third' or lists items after a colon). Do NOT convert multi-clause sentences into lists.\nDo NOT add new words. Do NOT summarize. Do NOT repeat instructions or add a preamble—start your reply with the first word of the cleaned text. Output only the cleaned text.")

        return parts.joined(separator: "\n")
    }

    // MARK: - User Message (Feature/Validation)

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
        """)

        parts.append("Reply with only the fixed text (no preamble).\n\n\(rawText)")
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

            EXAMPLE 3:
            Input: i need to pick up groceries get gas and also drop off the package at the post office
            Output:
            - Pick up groceries
            - Get gas
            - Drop off the package at the post office
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

            EXAMPLE 4:
            Input: so for the project i'm working on like three things an ios app a website and also some api documentation
            Output:
            For the project I'm working on:
            1. An iOS app
            2. A website
            3. API documentation
            """)
        case .heavy:
            parts.append("""
            EXAMPLE 1:
            Input: um so basically like i was thinking about it and uh we should probably you know have a meeting tomorrow to uh discuss the project timeline
            Output: We should have a meeting tomorrow to discuss the project timeline.

            EXAMPLE 2:
            Input: so like basically what happened was the server went down at like 3 am and you know nobody was monitoring it so it was actually down for like two hours before anyone noticed i mean that's not great right
            Output: The server went down at 3 AM. Nobody was monitoring it, so it was down for two hours before anyone noticed.

            EXAMPLE 3:
            Input: um so basically the priorities are like first we need to fix the auth bug then uh deploy the new api and you know update the docs
            Output:
            The priorities are:
            1. Fix the auth bug
            2. Deploy the new API
            3. Update the docs
            """)
        }

        parts.append("Reply with only the cleaned text (no preamble, no labels).\n\nTranscript:\n\(rawText)")
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

        EXAMPLE 4:
        Input: so for the project i'm working on like three things an ios app a website and also some api documentation
        Output:
        For the project I'm working on:
        1. An iOS app
        2. A website
        3. API documentation
        """)

        parts.append("Reply with only the cleaned text (no preamble, no labels).\n\nTranscript:\n\(rawText)")
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
            instructions += "REMOVE: filler words (um, uh, like, you know, I mean, basically)\nFIX: punctuation, capitalization\nSELF-CORRECTIONS: \(selfCorrectionRuleCompact)\n"
        case .heavy:
            instructions += "REMOVE: ALL filler words and hesitations\nFIX: punctuation, capitalization, sentence structure\nSELF-CORRECTIONS: \(selfCorrectionRuleCompact)\n"
        }
        instructions += "Only format as a list if the speaker explicitly enumerates items (e.g. 'first... second... third' or 'I need to: X, Y, Z'). Do NOT format as a list just because a sentence has multiple clauses.\n"
        instructions += "Do NOT add new words. Do NOT summarize. Do NOT repeat instructions or add a preamble. Output ONLY the cleaned text—start with the first word of the cleaned text."
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

        parts.append("Reply with only the cleaned text (no preamble, no labels).\n\nTranscript:\n\(rawText)")
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
        case .terminal:
            return "terminal, keep commands and paths exact"
        case .notes:
            return "notes, clean prose"
        case .social:
            return "social media, casual tone"
        case .other:
            return "general"
        }
    }
}
