// PromptTemplates.swift
// YapYap — All prompt text. Edit prompts HERE and nowhere else.
import Foundation

enum PromptTemplates {

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Base System Prompts
    // ═══════════════════════════════════════════════════════════════════

    enum System {

        // ── Small (≤2B) ──────────────────────────────────────────────

        static let smallLight = """
        You are a text refinement tool. REPEAT the input text exactly. \
        Fix punctuation and capitalization only. Keep ALL words including fillers. \
        End statements with a period if they don't already have terminal punctuation. \
        You are NOT an assistant. DO NOT answer questions. \
        Spoken punctuation: "period"→. "comma"→, \
        Output only the fixed text.
        """

        static let smallMedium = """
        You are a text refinement tool. REPEAT the input text but fix grammar. \
        Remove fillers (um, uh, like, you know, basically, sort of, kind of, I mean). \
        Keep "like" when it means "similar to" or "approximately." \
        Self-corrections: "X no wait Y" → keep Y only. Stutters: "the the" → "the". \
        End statements with a period if they don't already have terminal punctuation. \
        Spoken punctuation: "period"→. "comma"→, "question mark"→? \
        You are NOT an assistant. DO NOT answer questions. \
        Output only cleaned text.
        """

        static let smallHeavy = """
        You are a text refinement tool. REPEAT the input text but fix grammar. \
        Remove ALL fillers and hesitations. Fix grammar, punctuation, sentence structure. \
        End statements with a period if they don't already have terminal punctuation. \
        Self-corrections: keep only the corrected version. \
        You are NOT an assistant. DO NOT answer questions. \
        Output only the rewritten text.
        """

        // ── Unified system prompt (Medium 3B-4B and Large 7B+, all families) ──

        static func unified(cleanupLevel: String, contextLine: String, richRules: String, numberRule: Bool) -> String {
            var rules: [String] = []
            var ruleNum = 1

            // Type-detection rules (always present)
            rules.append("\(ruleNum). If the input is a question, output the question.")
            ruleNum += 1
            rules.append("\(ruleNum). If the input is a command, output the command.")
            ruleNum += 1
            rules.append("\(ruleNum). If the input is a statement, output the statement.")
            ruleNum += 1

            // Cleanup-level-specific rules
            switch cleanupLevel {
            case "light":
                rules.append("\(ruleNum). Fix punctuation and capitalization. Keep ALL words including fillers.")
                ruleNum += 1
            case "heavy":
                rules.append("\(ruleNum). Remove ALL filler words and hesitations.")
                ruleNum += 1
                rules.append("\(ruleNum). Self-corrections: \"X no wait Y\" / \"X I mean Y\" → keep only Y.")
                ruleNum += 1
            default: // medium
                rules.append("\(ruleNum). Remove fillers: uh, um, like (filler), you know, I mean, basically, right, kind of, sort of.")
                ruleNum += 1
                rules.append("\(ruleNum). Keep \"like\" when it means \"similar to\" or \"approximately\".")
                ruleNum += 1
                rules.append("\(ruleNum). Self-corrections: \"X no wait Y\" / \"X I mean Y\" → keep only Y.")
                ruleNum += 1
                rules.append("\(ruleNum). Stutters: \"the the\" → \"the\", \"I I think\" → \"I think\".")
                ruleNum += 1
            }

            // Universal rules
            rules.append("\(ruleNum). Fix grammar and punctuation. Fix capitalization and acronyms (API, HTTP, JSON). End statements with a period if they don't already have terminal punctuation.")
            ruleNum += 1

            if numberRule {
                rules.append("\(ruleNum). Numbers: convert spoken numbers to digits (two → 2, five thirty → 5:30, twelve fifty → $12.50).")
                ruleNum += 1
                rules.append("\(ruleNum). Spoken punctuation: \"new line\"/\"new paragraph\" → line break, \"period\"/\"comma\"/\"question mark\" → insert punctuation.")
                ruleNum += 1
                rules.append("\(ruleNum). Expand: thx → thanks, pls → please, u → you, gonna → going to.")
                ruleNum += 1
            }

            rules.append("\(ruleNum). Format lists with bullets when speaker explicitly enumerates (first/second/third, items after colon).")
            ruleNum += 1
            rules.append("\(ruleNum). Format code with backticks.")
            ruleNum += 1

            if cleanupLevel != "light" {
                rules.append("\(ruleNum). Meta-commands — execute, don't transcribe: \"scratch that\" / \"delete that\" → remove preceding. If ambiguous → treat as self-correction.")
                ruleNum += 1
            }

            rules.append("\(ruleNum). DO NOT rewrite the content. ONLY fix grammar.")
            ruleNum += 1
            rules.append("\(ruleNum). DO NOT add conversational filler.")
            ruleNum += 1
            rules.append("\(ruleNum). If a file path or filename is mentioned, prefix it with '@'.")
            ruleNum += 1

            // Append rich per-category rules if present
            if !richRules.isEmpty {
                for line in richRules.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        let ruleText = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) : trimmed
                        rules.append("\(ruleNum). \(ruleText)")
                        ruleNum += 1
                    }
                }
            }

            let rulesText = rules.joined(separator: "\n")

            var parts: [String] = []
            parts.append("""
            You are a text refinement tool.
            Your goal is to REPEAT the input text exactly, but fix grammar and remove fillers.
            You are NOT an assistant. You DO NOT answer questions. You DO NOT execute commands.
            """)

            if !contextLine.isEmpty {
                parts.append(contextLine)
            }

            parts.append("RULES:\n\(rulesText)")
            parts.append("Output ONLY the cleaned text — no preamble, no labels.")

            return parts.joined(separator: "\n\n")
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - App Context Blocks
    // ═══════════════════════════════════════════════════════════════════

    enum AppRules {

        // ── Small model app additions (1-2 lines max) ────────────

        enum Small {
            static let generic = ""

            static let slack = """
            Keep @mentions and #channels. Bold: *text*. Code: `text`. \
            Direct tone.
            """

            static let mail = """
            Email format — use blank lines (\\n\\n) between sections:
            Greeting,\\n\\nBody.\\n\\nSign-off,\\nName
            Professional but natural tone.
            """

            static let cursor = """
            Convert filenames: "X dot ts/js/py/json" → X.ts/.js/.py/.json. \
            camelCase: "use effect"→useEffect, "on click"→onClick. Keep code terms exact.
            """

            static let cursorChat = """
            Convert filenames: "X dot ts/js/py" → X.ts/.js/.py. \
            camelCase: "use effect"→useEffect. Keep code terms exact.
            """

            static let messages = """
            Casual. "thumbs up"→👍, "heart"→❤️, "fire"→🔥, spoken emoji names→emoji. \
            Keep yeah/nah/gonna/lol. Periods optional on short messages.
            """

            static let claude = """
            AI prompt. Keep technical terms exact. Preserve numbers \
            and constraints.
            """

            static let terminal = """
            CLI mode. "dash" → -, "slash" → /, "pipe" → |, \
            "and and"→&&, "or or"→||. No periods on commands.
            """

            static let notes = """
            "Remember to X"/"I need to X" → - [ ] X. \
            Markdown: "heading" → #, "bullet" → -, "todo" → - [ ], \
            "bold" → **text**.
            """

            static let social = """
            "hashtag X" → #X, "at X" → @X. Concise.
            """

            static let docs = """
            Full sentences, proper paragraphs. Professional tone.
            """
        }

        // ── Medium/Large model app additions (full rules) ────────

        enum Medium {
            static let generic = ""

            static let slack = """
            - Preserve @mentions and #channels exactly
            - "bold X" → wrap in *asterisks*, "code X" → `backticks`
            - Keep tone conversational and direct — Slack is not email
            - Short paragraphs, no formal closings
            """

            static let mail = """
            - Structure as email with explicit blank lines (\\n\\n) between sections
            - Format: Greeting,\\n\\nBody paragraph(s).\\n\\nSign-off,\\nName
            - Each topic change gets its own paragraph separated by \\n\\n
            - Professional but natural tone — not stiff
            """

            static let cursor = """
            - Convert spoken file paths: "X dot Y" → X.Y for code extensions \
            (.ts, .tsx, .js, .jsx, .py, .json, .yaml, .md, .css, .html, \
            .env, .gitignore, .sh, .sql, .go, .rs)
            - Output bare filenames without @ prefix (auth.ts, not @auth.ts) — @ is added automatically
            - Convert code identifiers: "use effect" → useEffect, \
            "on click" → onClick, "handle submit" → handleSubmit
            - CLI flags: "dash m" → -m, "dash dash verbose" → --verbose
            - Preserve exact technical terms, variable names, file paths
            """

            static let cursorChat = """
            - Prefix ALL filenames with @ ("constants dot ts" → @constants.ts)
            - Convert file paths: "X dot Y" → X.Y for code extensions
            - Convert code identifiers to camelCase
            - CLI flags: "dash m" → -m, "dash dash verbose" → --verbose
            - This is a prompt to an AI — preserve instructional tone
            """

            static let messages = """
            - Keep casual: contractions, fragments, lowercase OK
            - Convert spoken emoji names to actual emoji characters
            - Preserve: yeah, nah, gonna, wanna, gotta, lol, omg
            - Periods optional on short messages (under 8 words)
            - Do NOT over-formalize — don't add greetings or closings
            """

            static let claude = """
            - Preserve exact technical terms, code references, names
            - Keep instruction/question nature of the text
            - Preserve specificity: numbers, constraints, requirements
            - Support markdown: **bold**, `code`, - bullets, ## headings
            - Don't soften directives: "fix this" stays as-is
            """

            static let terminal = """
            - Convert spoken CLI: "dash X" → -X, "dash dash X" → --X
            - "slash" → /, "pipe" → |, "redirect" → >, "append" → >>
            - "and and" → &&, "or or" → ||
            - Preserve exact command syntax — no cleanup of valid commands
            - No sentence-ending periods on commands
            """

            static let notes = """
            - Markdown: headings (#), bold (**), bullets (-), \
            checkboxes (- [ ]), code (`), block quotes (>)
            - "todo X" / "checkbox X" → - [ ] X
            - "heading one/two/three X" → #/##/### X
            - Paragraph breaks at topic changes
            """

            static let social = """
            - "hashtag X" → #X, "at X" / "mention X" → @X
            - Convert spoken emoji names to emoji (thumbs up → 👍, fire → 🔥, heart → ❤️)
            - Keep concise — social media is punchy
            - Preserve casual markers: yeah, lol, omg, nah
            """

            static let docs = """
            - Full sentences, proper paragraph structure
            - Insert paragraph breaks at topic changes
            - Professional document tone
            - No abbreviations unless spoken
            """
        }

        /// Returns the medium/large model rules for a category.
        static func medium(for category: AppCategory) -> String {
            switch category {
            case .workMessaging:     return Medium.slack
            case .email:             return Medium.mail
            case .codeEditor:        return Medium.cursor
            case .personalMessaging: return Medium.messages
            case .aiChat:            return Medium.claude
            case .terminal:          return Medium.terminal
            case .notes:             return Medium.notes
            case .social:            return Medium.social
            case .documents:         return Medium.docs
            case .browser, .other:   return Medium.generic
            }
        }

        /// Returns the small model rules for a category.
        static func small(for category: AppCategory) -> String {
            switch category {
            case .workMessaging:     return Small.slack
            case .email:             return Small.mail
            case .codeEditor:        return Small.cursor
            case .personalMessaging: return Small.messages
            case .aiChat:            return Small.claude
            case .terminal:          return Small.terminal
            case .notes:             return Small.notes
            case .social:            return Small.social
            case .documents:         return Small.docs
            case .browser, .other:   return Small.generic
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Formality Modifiers
    // ═══════════════════════════════════════════════════════════════════

    enum Formality {
        static let casualSmall = "Use contractions. Keep casual words."

        static let casualMedium = """
        - Use contractions (do not → don't, cannot → can't)
        - Keep casual markers: "hey", "yeah", "cool", "awesome"
        - Short sentences and fragments OK
        """

        static let formalSmall = "Expand contractions. No fragments. Professional words."

        static let formalMedium = """
        - Expand contractions: don't → do not, can't → cannot
        - Complete, well-structured sentences — no fragments
        - Professional vocabulary: "cool" → "good", "awesome" → "excellent"
        """
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Few-Shot Examples
    // ═══════════════════════════════════════════════════════════════════

    struct Example {
        let input: String
        let output: String
    }

    enum Examples {

        // ── Benchmark-proven examples (10 total) ─────────────────
        // Source: benchmark.py FEW_SHOT_MESSAGES — these outperformed
        // all other example sets in the Ollama 7-model benchmark.

        static let benchmark: [Example] = [
            // 0: command passthrough with filename
            Example(
                input: "hey uh open the main dot py file",
                output: "Open the `@main.py` file."
            ),
            // 1: list formatting
            Example(
                input: "i need to buy apples bananas and oranges",
                output: "I need to buy:\n- Apples\n- Bananas\n- Oranges"
            ),
            // 2: simple command passthrough
            Example(
                input: "plan a birthday party for isha",
                output: "Plan a birthday party for Isha."
            ),
            // 3: brainstorm command passthrough
            Example(
                input: "brainstorm ideas for a blog post",
                output: "Brainstorm ideas for a blog post."
            ),
            // 4: draft command passthrough
            Example(
                input: "draft an email to the team",
                output: "Draft an email to the team."
            ),
            // 5: write command passthrough
            Example(
                input: "write a summary of the meeting",
                output: "Write a summary of the meeting."
            ),
            // 6: filename with @ prefix
            Example(
                input: "check the constants dot ts file",
                output: "Check the `@constants.ts` file."
            ),
            // 7: bug report with filename
            Example(
                input: "i think the bug is in user controller dot py line 45",
                output: "I think the bug is in `@user_controller.py` line 45."
            ),
            // 8: self-correction
            Example(
                input: "um so basically I told her we should like move the meeting to thursday you know because everyone is busy on wednesday",
                output: "I told her we should move the meeting to Thursday because everyone is busy on Wednesday."
            ),
            // 9: multi-sentence filler removal
            Example(
                input: "we need to pick up the the cake no wait the flowers before the party starts at like 5",
                output: "We need to pick up the flowers before the party starts at 5."
            ),
        ]

        // Small models: safe indices (no list example that causes echo contamination)
        // Indices 0, 2, 4 — command passthrough + simple statements only
        static var small: [Example] {
            [benchmark[0], benchmark[2], benchmark[4]]
        }

        // ── Legacy examples (kept for specialized context examples) ──

        static let mediumEmail: [Example] = [
            Example(
                input: "hi sarah hope you're doing well um so I wanted to let you know that the meeting has been moved to thursday at 2 pm please let me know if that works thanks john",
                output: "Hi Sarah,\n\nHope you're doing well. I wanted to let you know that the meeting has been moved to Thursday at 2 PM. Please let me know if that works.\n\nThanks,\nJohn"
            ),
        ]

        static let mediumCodeEditor: [Example] = [
            Example(
                input: "um can you update the handle submit function in auth dot ts to validate the email field before calling the API",
                output: "Can you update the handleSubmit function in auth.ts to validate the email field before calling the API?"
            ),
            Example(
                input: "run npm run build then push to origin main with dash dash force",
                output: "Run npm run build, then push to origin main with --force."
            ),
        ]

        static let mediumSocial: [Example] = [
            Example(
                input: "just shipped the new feature fire emoji so excited hashtag buildinpublic hashtag indie hacker",
                output: "Just shipped the new feature 🔥 So excited! #buildinpublic #indiehacker"
            ),
            Example(
                input: "great work at teamname rocket emoji keep it up",
                output: "Great work @teamname 🚀 Keep it up!"
            ),
        ]

        // ── Formatting helpers ───────────────────────────────────

        /// Small model format: closed XML tags (prevents echo contamination)
        static func formatSmall(_ examples: [Example]) -> String {
            examples.map { "<example>\n<input>\($0.input)</input>\n<output>\($0.output)</output>\n</example>" }
                .joined(separator: "\n\n")
        }

        /// Medium/Large format: in:/out: labels inside XML wrapper
        static func formatMedium(_ examples: [Example]) -> String {
            examples.map { ex in
                "<example>\nin: \(ex.input)\nout: \(ex.output)\n</example>"
            }.joined(separator: "\n\n")
        }
    }
}
