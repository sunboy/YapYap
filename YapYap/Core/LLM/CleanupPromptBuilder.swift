// CleanupPromptBuilder.swift
// YapYap — Builds context-aware cleanup prompts for the LLM
import Foundation

struct CleanupPromptBuilder {

    static func buildPrompt(rawText: String, context: CleanupContext) -> String {
        let formalityInstruction = buildFormalityInstruction(context.formality)
        let cleanupInstruction = buildCleanupInstruction(context.cleanupLevel)
        let fillerInstruction = buildFillerRemovalInstruction(context)
        let appFormatting = context.appContext.map { buildAppFormattingInstruction($0) } ?? ""
        let styleInstruction = context.appContext.map { buildStyleInstruction($0.style) } ?? ""

        let userStyle = context.stylePrompt.isEmpty ? "" : "- \(context.stylePrompt)"

        return """
        You are a writing assistant that cleans up voice transcriptions.

        Rules:
        - \(fillerInstruction)
        - Fix grammar and punctuation
        - \(formalityInstruction)
        - \(cleanupInstruction)
        \(styleInstruction.isEmpty ? "" : "- \(styleInstruction)")
        \(appFormatting.isEmpty ? "" : "- \(appFormatting)")
        \(userStyle)
        - Preserve the speaker's intent and meaning exactly
        - Do NOT add information that wasn't spoken
        - Do NOT include any preamble, explanation, or notes
        - Output ONLY the cleaned text

        Raw transcription:
        \(rawText)

        Cleaned text:
        """
    }

    // MARK: - Formality

    static func buildFormalityInstruction(_ formality: CleanupContext.Formality) -> String {
        switch formality {
        case .casual:
            return "Write casually, like texting a friend. Use contractions, simple words."
        case .neutral:
            return "Write in everyday professional tone. Clear and direct."
        case .formal:
            return "Write formally. Precise language, no contractions, polished."
        }
    }

    // MARK: - Cleanup Level

    static func buildCleanupInstruction(_ level: CleanupContext.CleanupLevel) -> String {
        switch level {
        case .light:
            return "Only fix grammar and punctuation. Keep the speaker's exact words as much as possible."
        case .medium:
            return "Fix grammar, restructure sentences for clarity. Maintain the speaker's voice."
        case .heavy:
            return "Fully rewrite for maximum clarity and polish. Match the speaker's intent, not their exact words."
        }
    }

    // MARK: - Filler Removal

    static func buildFillerRemovalInstruction(_ context: CleanupContext) -> String {
        guard context.removeFillers else {
            return "Preserve filler words and disfluencies as spoken (verbatim mode)."
        }

        switch context.cleanupLevel {
        case .light:
            return "Remove hesitation sounds (um, uh, ah, er, hmm). Keep everything else as spoken."
        case .medium:
            return """
            Remove filler words: um, uh, ah, er, hmm, like (as filler), you know, I mean, sort of, kind of, basically, actually, literally, so yeah.
            Handle self-corrections: if the speaker says "meet Tuesday, no Wednesday", output only "meet Wednesday".
            Remove false starts and word repetitions (e.g., "I I I think" → "I think").
            """
        case .heavy:
            return """
            Remove ALL filler words and verbal tics.
            Resolve all self-corrections to final intent only.
            Fix run-on sentences and add paragraph breaks where appropriate.
            """
        }
    }

    // MARK: - App Formatting

    static func buildAppFormattingInstruction(_ appContext: AppContext) -> String {
        switch appContext.category {
        case .personalMessaging:
            return "Format for personal messaging: short, conversational sentences. \(appContext.style == .veryCasual ? "No capitalization. No trailing periods." : "")"
        case .workMessaging:
            return "Format for work messaging: concise and direct. Bullet points OK for lists."
        case .email:
            return "Format for email: proper paragraphs, greeting if included, sign-off if indicated."
        case .codeEditor where appContext.isIDEChatPanel:
            return "Format for AI coding chat: wrap code references in backticks, use @filename for file references, preserve technical terms."
        case .codeEditor:
            return "Format for code editor: concise, technical language. Wrap code references in backticks."
        case .documents:
            return "Format for document: proper paragraph structure. Auto-detect lists and format as bullet points."
        case .aiChat:
            return "Format for AI chat prompt: preserve intent precisely. Keep natural structure."
        case .browser, .other:
            return "Format with general-purpose style: clean sentences, proper punctuation."
        }
    }

    // MARK: - Style

    static func buildStyleInstruction(_ style: OutputStyle) -> String {
        switch style {
        case .veryCasual:
            return "Style: Very casual. No capitalization at sentence starts. No trailing periods. Minimal punctuation."
        case .casual:
            return "Style: Casual. Normal sentence capitalization. Light punctuation. Conversational."
        case .excited:
            return "Style: Excited. Sentence capitalization. Use exclamation points where tone suggests enthusiasm."
        case .formal:
            return "Style: Formal. Full capitalization, complete punctuation. Professional paragraphs."
        }
    }
}
