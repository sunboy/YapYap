// CleanupPromptBuilder.swift
// YapYap — Builds model-specific, context-aware cleanup prompts for the LLM
import Foundation

struct CleanupPromptBuilder {

    /// Returns (systemMessage, userMessage) for the chat template.
    /// Prompts are model-specific: small models (<=2B) get ultra-minimal prompts,
    /// medium+ models (3B+) get detailed prompts with rules and more examples.
    /// For Gemma family: system is empty, all content moves to user block.
    static func buildMessages(rawText: String, context: CleanupContext, modelId: String? = nil, userContext: UserPromptContext? = nil) -> (system: String, user: String) {
        let (family, resolvedSize) = resolveModel(modelId: modelId)
        // Experimental mode: treat small models as medium so they get detailed prompts
        // Exception: 1B models (Llama 1B, Gemma 1B) can't follow detailed prompts — stay on small
        let is1BModel = modelId == "llama-3.2-1b" || modelId == "gemma-3-1b"
        let size = (context.experimentalPrompts && resolvedSize == .small && !is1BModel) ? .medium : resolvedSize

        let systemContent = buildSystemPrompt(context: context, family: family, size: size)
        let userContent = buildUserMessage(rawText: rawText, context: context, family: family, size: size, userContext: userContext)

        // Gemma: merge system content into user block (system role unreliable for Gemma)
        if family == .gemma && size != .small {
            return (system: "", user: systemContent + "\n\n" + userContent)
        }

        return (system: systemContent, user: userContent)
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
        // Small models: compact XML examples for all families
        if size == .small {
            return buildSmallModelUserMessage(rawText: rawText, context: context, userContext: userContext)
        }

        // Medium+ models: 10 benchmark examples + transcript repetition
        return buildUnifiedUserMessage(rawText: rawText, context: context, userContext: userContext, modelSize: size)
    }

    /// Compact user message for small models (<=2B).
    /// Uses bare <input>/<output> XML pairs (no <example> wrapper) to prevent echo contamination.
    /// Uses safe example indices (no list example which caused Gemma 1B echo contamination).
    private static func buildSmallModelUserMessage(rawText: String, context: CleanupContext, userContext: UserPromptContext? = nil) -> String {
        // Format examples as bare input/output pairs (no <example> wrapper for small models)
        let examples = PromptTemplates.Examples.small
        let examplesText = examples.map { "<input>\($0.input)</input>\n<output>\($0.output)</output>" }
            .joined(separator: "\n\n")

        var parts: [String] = [examplesText]

        // Inject user dictionary if present
        if let ctx = userContext {
            let dict = ctx.dictionaryBlock(modelSize: .small)
            if !dict.isEmpty { parts.append(dict) }
            let style = ctx.editMemoryBlock(modelSize: .small)
            if !style.isEmpty { parts.append(style) }
        }

        parts.append("Only remove filler words and fix punctuation. Keep every other word exactly as spoken — do NOT substitute synonyms or rephrase. Do NOT drop any sentences. Do NOT answer questions.")
        parts.append("<input>\(rawText)</input>\n<output>")

        return parts.joined(separator: "\n\n")
    }

    /// Unified user message for medium+ models (all families).
    /// Uses all 10 benchmark examples + transcript repetition technique.
    /// Specialized context examples injected for code editor and social.
    private static func buildUnifiedUserMessage(rawText: String, context: CleanupContext, userContext: UserPromptContext? = nil, modelSize: LLMModelSize = .medium) -> String {
        var parts: [String] = []

        // Choose examples: specialized for code editor and social, benchmark otherwise
        var examples = PromptTemplates.Examples.benchmark
        if let appContext = context.appContext {
            if appContext.isIDEChatPanel || appContext.category == .codeEditor {
                // Inject 2 code editor examples into benchmark set at position 1
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

        parts.append(PromptTemplates.Examples.formatMedium(examples))

        // Inject user dictionary and style memory if present
        if let ctx = userContext {
            let dict = ctx.dictionaryBlock(modelSize: modelSize)
            if !dict.isEmpty { parts.append(dict) }
            let style = ctx.editMemoryBlock(modelSize: modelSize)
            if !style.isEmpty { parts.append(style) }
        }

        // Transcript repetition technique (arxiv 2512.14982) — repeat transcript twice
        // for better instruction following in medium/large models
        parts.append("Transcript: \(rawText)\n\nTranscript: \(rawText)")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Legacy toneHint (kept for backward compatibility)

    /// Brief tone hint from app category.
    /// Prefer naturalLanguageContext() for new code.
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
            return "terminal, no sentence-ending periods on commands"
        case .notes:
            return "notes, support markdown formatting"
        case .social:
            return "social media, keep concise"
        case .other:
            return "general"
        }
    }
}
