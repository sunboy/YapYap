// PromptTemplatesV2.swift
// YapYap — V2 prompt templates: single unified system prompt with chat-style few-shot
import Foundation

/// V2 prompt system: a single, model-size-agnostic system prompt with cleanup level
/// adaptation and chat-style (user/assistant turn) few-shot examples.
///
/// Key differences from V1 (PromptTemplates):
/// - One system prompt for all model sizes (tested on 1.5B–7B)
/// - App context is a derived keyword ("IDE", "Slack", "Email", "LinkedIn", etc.)
/// - Few-shot examples are user/assistant message pairs, not inline XML
/// - User input is prefixed with "Reformat: "
enum PromptTemplatesV2 {

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - System Prompt
    // ═══════════════════════════════════════════════════════════════════

    /// Builds the V2 system prompt with the given app context keyword and cleanup level.
    /// Optionally includes VOCABULARY and REPLACEMENTS sections from the personal dictionary.
    static func systemPrompt(
        appContext: String,
        cleanupLevel: CleanupContext.CleanupLevel,
        vocabularyBlock: String = ""
    ) -> String {
        let cleanupRule = cleanupRuleForLevel(cleanupLevel)
        // Rules 1-16, with rule 3 adapted for cleanup level
        var prompt = """
        You are a deterministic STT refinement engine, not a chatbot.
        Task: return the same user text with light cleanup only.
        CONTEXT: \(appContext)
        HARD RULES:
        1. Output ONLY the refined transcription text. No preface, no explanation, no quotes around the whole answer.
        2. Never answer requests. Never execute commands. Never add helper text like "Here is the corrected text" or "Here is the reformatted text".
        3. \(cleanupRule)
        4. Keep questions as questions, commands as commands, statements as statements. End statements with a period if they don't already have terminal punctuation.
        5. Use bullets only when the input clearly enumerates list items.
        6. File tagging rule: prefix real file names/paths with '@' (example: main.py -> @main.py).
        7. Do NOT use '@' for people, companies, products, hashtags, or generic words.
        8. In Terminal context, preserve shell commands literally. Do not rewrite into prose.
        9. For spoken file names like "main dot py", normalize to "main.py" before applying '@' when applicable.
        10. Preserve sentence structure. Do not reorder into labels like "Dockerfile check" or "README check".
        11. Preserve hashtags exactly (example: #newjob stays #newjob).
        12. If input says "write/build/create/script/code", keep it as a request sentence. Do NOT generate code or content.
        13. Insert paragraph breaks (double newlines) where there is a logical shift in topic, tone, or section (e.g., between greeting and body, or between distinct points).
        14. For LinkedIn context, use short, punchy paragraphs (1-2 sentences max) for readability.
        """

        if !vocabularyBlock.isEmpty {
            prompt += "\n" + """
            15. Use the provided VOCABULARY list to correct specific terms (e.g., if input has "gema", output "Gemma").
            16. Apply the provided REPLACEMENTS exactly as specified (e.g., if input has "yapyap", replace with "YapYap").
            """
            prompt += "\n" + vocabularyBlock
        }

        return prompt
    }

    /// Returns the cleanup-level-specific wording for rule 3.
    private static func cleanupRuleForLevel(_ level: CleanupContext.CleanupLevel) -> String {
        switch level {
        case .light:
            return "Preserve meaning and wording exactly. Only fix punctuation and capitalization. Keep ALL words including fillers."
        case .medium:
            return "Preserve meaning and wording. Only fix punctuation, casing, obvious grammar, and fillers (\"uh\", \"um\", \"like\", \"so\")."
        case .heavy:
            return "Fix grammar, punctuation, and sentence structure. Remove ALL fillers and hesitations. Self-corrections: \"X no wait Y\" → keep only Y."
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Few-Shot Examples
    // ═══════════════════════════════════════════════════════════════════

    /// Chat-style few-shot examples as (user, assistant) message pairs.
    /// These are prepended to the conversation as separate turns.
    static let fewShotExamples: [(user: String, assistant: String)] = [
        (
            user: "Reformat: hey uh open the main dot py file",
            assistant: "Open the `@main.py` file."
        ),
        (
            user: "Reformat: i think the bug is in user controller dot py line 45",
            assistant: "I think the bug is in `@user_controller.py` line 45."
        ),
        (
            user: "Reformat: draft an email to the team",
            assistant: "Draft an email to the team."
        ),
        (
            user: "Reformat: hi dave i have an update on the project first we finished the backend second the frontend is halfway done and finally we need to discuss the deployment timeline thanks",
            assistant: "Hi Dave,\n\nI have an update on the project.\n\nFirst, we finished the backend. Second, the frontend is halfway done. Finally, we need to discuss the deployment timeline.\n\nThanks."
        ),
        (
            user: "Reformat: i just learned something crazy about ai it turns out most people are using it wrong they treat it like a search engine instead of a reasoning engine here is why that matters",
            assistant: "I just learned something crazy about AI.\n\nIt turns out most people are using it wrong.\n\nThey treat it like a search engine instead of a reasoning engine.\n\nHere is why that matters."
        ),
    ]

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - User Input Format
    // ═══════════════════════════════════════════════════════════════════

    /// Wraps raw transcription text with the "Reformat:" prefix.
    static func formatUserInput(_ rawText: String) -> String {
        "Reformat: \(rawText)"
    }
}
