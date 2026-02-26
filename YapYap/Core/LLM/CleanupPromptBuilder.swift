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
        // Medium/large: repeat transcript (arxiv 2512.14982 — repetition improves
        // instruction following on non-reasoning LLMs; no latency penalty, prefill only)
        let instruction: String
        if size == .small {
            instruction = "Output only the cleaned text.\n\n\(rawText)"
        } else {
            instruction = "Reply with only the cleaned text (no preamble, no labels).\n\nTranscript:\n\(rawText)\n\nClean this transcript:\n\(rawText)"
        }
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
}
