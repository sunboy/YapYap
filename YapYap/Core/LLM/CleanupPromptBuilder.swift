// CleanupPromptBuilder.swift
// YapYap — Builds model-specific, context-aware cleanup prompts for the LLM
import Foundation

struct CleanupPromptBuilder {

    /// Returns (systemMessage, userMessage) for the chat template.
    /// Prompts are model-specific: small models (<=2B) get ultra-minimal prompts,
    /// medium+ models (3B+) get detailed prompts with rules and more examples.
    /// For Gemma family: system is empty, all content moves to user block.
    static func buildMessages(rawText: String, context: CleanupContext, modelId: String? = nil, userContext: UserPromptContext? = nil) -> (system: String, user: String) {
        let parts = buildMessageParts(rawText: rawText, context: context, modelId: modelId, userContext: userContext)
        return (system: parts.system, user: parts.userPrefix + parts.userSuffix)
    }

    /// Returns (system, userPrefix, userSuffix) for prompt caching.
    /// - system: full system prompt (static for given settings + app context)
    /// - userPrefix: examples + instructions (static, no rawText)
    /// - userSuffix: the rawText portion (dynamic per inference)
    /// The split point is chosen at a natural token boundary (newline) so prefix
    /// and suffix can be encoded independently without BPE boundary issues.
    static func buildMessageParts(rawText: String, context: CleanupContext, modelId: String? = nil, userContext: UserPromptContext? = nil) -> (system: String, userPrefix: String, userSuffix: String) {
        let (family, resolvedSize) = resolveModel(modelId: modelId)
        let is1BModel = modelId == "llama-3.2-1b" || modelId == "gemma-3-1b"
        let size = (context.experimentalPrompts && resolvedSize == .small && !is1BModel) ? .medium : resolvedSize

        let systemContent = buildSystemPrompt(context: context, family: family, size: size)
        let (userPrefix, userSuffix) = buildUserMessageParts(rawText: rawText, context: context, family: family, size: size, userContext: userContext)

        // Gemma: merge system content into user block (system role unreliable for Gemma)
        if family == .gemma && size != .small {
            return (system: "", userPrefix: systemContent + "\n\n" + userPrefix, userSuffix: userSuffix)
        }

        return (system: systemContent, userPrefix: userPrefix, userSuffix: userSuffix)
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
        if size == .small {
            return buildSmallModelSystemPrompt(context: context, family: family)
        }

        // Medium+ models (3B+): unified benchmark-proven prompt for ALL families
        return buildUnifiedSystemPrompt(context: context)
    }

    /// Concise system prompt for small models (<=2B params).
    /// Adopts the "text refinement tool" framing with minimal rules.
    private static func buildSmallModelSystemPrompt(context: CleanupContext, family: LLMModelFamily) -> String {
        var prompt: String
        switch context.cleanupLevel {
        case .light:
            prompt = PromptTemplates.System.smallLight
        case .medium:
            prompt = PromptTemplates.System.smallMedium
        case .heavy:
            prompt = PromptTemplates.System.smallHeavy
        }

        // Add concise formality hint
        switch context.formality {
        case .casual:
            prompt += " " + PromptTemplates.Formality.casualSmall
        case .neutral:
            break
        case .formal:
            prompt += " " + PromptTemplates.Formality.formalSmall
        }

        // List instruction for small models: require explicit enumeration signal
        prompt += " Only list-format when speaker explicitly enumerates (first/second/third or items after a colon)."

        // Add concise app context hint
        if let appContext = context.appContext {
            let appRule = smallAppRule(for: appContext)
            if !appRule.isEmpty {
                prompt += " " + appRule
            }
        }

        // Inject user's custom style instruction
        if !context.stylePrompt.isEmpty {
            prompt += " " + context.stylePrompt
        }

        return prompt
    }

    /// Unified benchmark-proven system prompt for medium+ models (all families).
    private static func buildUnifiedSystemPrompt(context: CleanupContext) -> String {
        let contextLine = buildContextLine(for: context.appContext)
        let richRules = buildRichAppRules(for: context.appContext)
        let levelKey: String
        switch context.cleanupLevel {
        case .light: levelKey = "light"
        case .medium: levelKey = "medium"
        case .heavy: levelKey = "heavy"
        }
        // Number conversion only for medium and heavy
        let numberRule = context.cleanupLevel != .light

        var system = PromptTemplates.System.unified(
            cleanupLevel: levelKey,
            contextLine: contextLine,
            richRules: richRules,
            numberRule: numberRule
        )

        // Append formality modifier
        switch context.formality {
        case .casual:
            system += "\n\nTONE:\n" + PromptTemplates.Formality.casualMedium
        case .neutral:
            break
        case .formal:
            system += "\n\nTONE:\n" + PromptTemplates.Formality.formalMedium
        }

        // Inject user's custom style instruction
        if !context.stylePrompt.isEmpty {
            system += "\n\nCUSTOM STYLE:\n" + context.stylePrompt
        }

        return system
    }

    // MARK: - Context Line (natural language, for unified prompt)

    /// Returns a "CONTEXT: You are typing in {description}." line.
    private static func buildContextLine(for appContext: AppContext?) -> String {
        guard let ctx = appContext else { return "" }
        let description = naturalLanguageContext(for: ctx)
        return "CONTEXT: You are typing in \(description)."
    }

    private static func naturalLanguageContext(for appContext: AppContext) -> String {
        if appContext.isIDEChatPanel {
            return "an IDE chat panel (\(appContext.appName))"
        }
        switch appContext.category {
        case .personalMessaging:
            return "a casual messaging app (\(appContext.appName))"
        case .workMessaging:
            return "a work messaging app (\(appContext.appName))"
        case .email:
            return "an email client (\(appContext.appName))"
        case .codeEditor:
            return "a code editor (\(appContext.appName))"
        case .browser:
            return "a web browser (\(appContext.appName))"
        case .documents:
            return "a document editor (\(appContext.appName))"
        case .aiChat:
            return "an AI chat interface (\(appContext.appName))"
        case .terminal:
            return "a terminal (\(appContext.appName))"
        case .notes:
            return "a notes app (\(appContext.appName))"
        case .social:
            return "a social media app (\(appContext.appName))"
        case .other:
            return appContext.appName
        }
    }

    // MARK: - Rich App Rules (Medium/Large)

    private static func buildRichAppRules(for appContext: AppContext?) -> String {
        guard let ctx = appContext else { return "" }

        // Check for user-defined override first
        let overrides = PromptOverrides.loadFromUserDefaults()
        if let customRules = overrides.effectiveRules(for: ctx.category), !ctx.isIDEChatPanel {
            return customRules
        }

        if ctx.isIDEChatPanel {
            return PromptTemplates.AppRules.Medium.cursorChat
        }
        switch ctx.category {
        case .workMessaging:
            return PromptTemplates.AppRules.Medium.slack
        case .email:
            return PromptTemplates.AppRules.Medium.mail
        case .codeEditor:
            return PromptTemplates.AppRules.Medium.cursor
        case .personalMessaging:
            return PromptTemplates.AppRules.Medium.messages
        case .aiChat:
            return PromptTemplates.AppRules.Medium.claude
        case .terminal:
            return PromptTemplates.AppRules.Medium.terminal
        case .notes:
            return PromptTemplates.AppRules.Medium.notes
        case .social:
            return PromptTemplates.AppRules.Medium.social
        case .documents:
            return PromptTemplates.AppRules.Medium.docs
        case .browser, .other:
            return PromptTemplates.AppRules.Medium.generic
        }
    }

    // MARK: - Small Model App Rule (compact, 1-line)

    private static func smallAppRule(for appContext: AppContext) -> String {
        // Check for user-defined override first
        let overrides = PromptOverrides.loadFromUserDefaults()
        if let customRules = overrides.effectiveRules(for: appContext.category), !appContext.isIDEChatPanel {
            return customRules
        }

        if appContext.isIDEChatPanel {
            return PromptTemplates.AppRules.Small.cursorChat
        }
        switch appContext.category {
        case .workMessaging:
            return PromptTemplates.AppRules.Small.slack
        case .email:
            return PromptTemplates.AppRules.Small.mail
        case .codeEditor:
            return PromptTemplates.AppRules.Small.cursor
        case .personalMessaging:
            return PromptTemplates.AppRules.Small.messages
        case .aiChat:
            return PromptTemplates.AppRules.Small.claude
        case .terminal:
            return PromptTemplates.AppRules.Small.terminal
        case .notes:
            return PromptTemplates.AppRules.Small.notes
        case .social:
            return PromptTemplates.AppRules.Small.social
        case .documents:
            return PromptTemplates.AppRules.Small.docs
        case .browser, .other:
            return ""
        }
    }

    // MARK: - User Message

    private static func buildUserMessage(rawText: String, context: CleanupContext, family: LLMModelFamily, size: LLMModelSize, userContext: UserPromptContext? = nil) -> String {
        let (prefix, suffix) = buildUserMessageParts(rawText: rawText, context: context, family: family, size: size, userContext: userContext)
        return prefix + suffix
    }

    /// Returns (userPrefix, userSuffix) where the split is at the rawText boundary.
    /// The prefix contains examples + instructions (cacheable), the suffix contains
    /// the raw transcript (dynamic per call). Split at newline for clean BPE boundaries.
    private static func buildUserMessageParts(rawText: String, context: CleanupContext, family: LLMModelFamily, size: LLMModelSize, userContext: UserPromptContext? = nil) -> (prefix: String, suffix: String) {
        if size == .small {
            return buildSmallModelUserMessageParts(rawText: rawText, context: context, userContext: userContext)
        }
        return buildUnifiedUserMessageParts(rawText: rawText, context: context, userContext: userContext, modelSize: size)
    }

    /// Small model user message split into (prefix, suffix).
    /// Prefix: examples + instruction. Suffix: <input>{rawText}</input>\n<output>
    private static func buildSmallModelUserMessageParts(rawText: String, context: CleanupContext, userContext: UserPromptContext? = nil) -> (prefix: String, suffix: String) {
        let examples = PromptTemplates.Examples.small
        let examplesText = examples.map { "<input>\($0.input)</input>\n<output>\($0.output)</output>" }
            .joined(separator: "\n\n")

        var prefixParts: [String] = [examplesText]

        if let ctx = userContext {
            let dict = ctx.dictionaryBlock(modelSize: .small)
            if !dict.isEmpty { prefixParts.append(dict) }
            let style = ctx.editMemoryBlock(modelSize: .small)
            if !style.isEmpty { prefixParts.append(style) }
        }

        prefixParts.append("Only remove filler words and fix punctuation. Keep every other word exactly as spoken — do NOT substitute synonyms or rephrase. Do NOT drop any sentences. Do NOT answer questions.")

        // Split: prefix ends with newline, suffix starts with <input> tag
        let prefix = prefixParts.joined(separator: "\n\n") + "\n\n"
        let suffix = "<input>\(rawText)</input>\n<output>"

        return (prefix, suffix)
    }

    /// Medium/large model user message split into (prefix, suffix).
    /// Prefix: examples + user dict/style. Suffix: Transcript repetition with rawText.
    private static func buildUnifiedUserMessageParts(rawText: String, context: CleanupContext, userContext: UserPromptContext? = nil, modelSize: LLMModelSize = .medium) -> (prefix: String, suffix: String) {
        var prefixParts: [String] = []

        var examples = PromptTemplates.Examples.benchmark
        if let appContext = context.appContext {
            if appContext.isIDEChatPanel || appContext.category == .codeEditor {
                var codeExamples = PromptTemplates.Examples.benchmark
                codeExamples.insert(contentsOf: PromptTemplates.Examples.mediumCodeEditor, at: 1)
                examples = codeExamples
            } else if appContext.category == .social {
                var socialExamples = PromptTemplates.Examples.benchmark
                socialExamples.insert(contentsOf: PromptTemplates.Examples.mediumSocial, at: 1)
                examples = socialExamples
            } else if appContext.category == .email {
                var emailExamples = PromptTemplates.Examples.benchmark
                emailExamples.insert(contentsOf: PromptTemplates.Examples.mediumEmail, at: 1)
                examples = emailExamples
            }
        }

        prefixParts.append(PromptTemplates.Examples.formatMedium(examples))

        if let ctx = userContext {
            let dict = ctx.dictionaryBlock(modelSize: modelSize)
            if !dict.isEmpty { prefixParts.append(dict) }
            let style = ctx.editMemoryBlock(modelSize: modelSize)
            if !style.isEmpty { prefixParts.append(style) }
        }

        // Split: prefix ends with double newline, suffix is the transcript repetition
        let prefix = prefixParts.joined(separator: "\n\n") + "\n\n"
        let suffix = "Transcript: \(rawText)\n\nTranscript: \(rawText)"

        return (prefix, suffix)
    }

}
