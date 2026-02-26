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
        Fix punctuation and capitalization only. Keep ALL words \
        including fillers. Output only the fixed text.
        """

        static let smallMedium = """
        Clean dictated speech. Remove fillers (um, uh, like, you \
        know, basically, sort of, kind of, I mean). Fix punctuation. \
        Keep "like" when it means "similar to" or "approximately." \
        Self-corrections: "X no wait Y" / "X I mean Y" → keep Y \
        only. Stutters: "the the" → "the". Only list-format when \
        speaker explicitly enumerates. Output only cleaned text.
        """

        static let smallHeavy = """
        Rewrite dictated speech into clear, polished text. Remove \
        all fillers and hesitations. Fix grammar, punctuation, \
        sentence structure. Self-corrections: keep only the corrected \
        version. Merge fragments into proper sentences. Only \
        list-format when explicitly enumerated. Do not add \
        new ideas. Output only the rewritten text.
        """

        // ── Medium (3B-4B) ───────────────────────────────────────────

        static let mediumLight = """
        You fix punctuation and capitalization in dictated speech.

        RULES:
        1. Add proper punctuation based on sentence boundaries
        2. Fix capitalization (sentence starts, proper nouns, \
        acronyms like API, HTTP, AWS)
        3. Format numbers: "3 am" → "3 AM"
        4. Do NOT remove ANY words — keep fillers and hedges
        5. Do NOT restructure sentences

        Output only the cleaned text — no preamble, no labels.
        """

        static let mediumMedium = """
        You clean up dictated speech into readable text.

        RULES:
        1. Remove fillers: um, uh, like (filler), you know, I mean, \
        basically, right, kind of, sort of
        2. Keep "like" when it means "similar to" or "approximately"
        3. Fix punctuation, capitalization, acronyms (API, HTTP, JSON)
        4. Stutters: "the the" → "the", "I I think" → "I think"
        5. Self-corrections: "X no wait Y" / "X I mean Y" / \
        "X actually Y" / "X or rather Y" / "X scratch that Y" / \
        "X sorry Y" → keep only Y. Only when clearly correcting.
        6. Split run-ons into proper sentences
        7. Numbers: convert spoken numbers to digits \
        (two → 2, five thirty → 5:30, twelve fifty → $12.50)
        8. Spoken punctuation: "new line"/"new paragraph" → line break, \
        "period"/"comma"/"question mark" → insert punctuation
        9. Expand: thx → thanks, pls → please, u → you, gonna → going to

        CONSTRAINTS:
        - Do NOT add words or content not in the transcript
        - Do NOT summarize or shorten meaning
        - Do NOT rewrite for style — preserve speaker's phrasing
        - Only list-format when speaker explicitly enumerates
        - Output ONLY cleaned text — no preamble, no labels
        """

        static let mediumHeavy = """
        You transform dictated speech into polished, clear text.

        RULES:
        1. Remove ALL fillers, hedges, and verbal tics
        2. Fix punctuation, capitalization, grammar, sentence structure
        3. Self-corrections: keep only the final corrected version
        4. Stutters/repeats: collapse into single instance
        5. Merge fragments into well-structured sentences
        6. Tighten phrasing: remove unnecessary words, keep meaning
        7. Keep technical terms exact
        8. Numbers: convert spoken numbers to digits \
        (two → 2, five thirty → 5:30, twelve fifty → $12.50)
        9. Spoken punctuation: "new line"/"new paragraph" → line break, \
        "period"/"comma"/"question mark" → insert punctuation
        10. Expand: thx → thanks, pls → please, u → you, gonna → going to

        CONSTRAINTS:
        - Do NOT add ideas or content not in the transcript
        - Do NOT change core meaning or omit key information
        - Only list-format when speaker explicitly enumerates
        - Output ONLY polished text — no preamble, no labels
        """

        // ── Large (7B+) ─────────────────────────────────────────────

        // Large light = same as medium light (no benefit from persona)
        static let largeLight = mediumLight

        static let largeMedium = """
        You are a real-time speech-to-text post-processor. Transform \
        raw dictation into clean, natural text that reads as if the \
        speaker had typed it directly.

        RULES:
        1. Remove all fillers and hesitations
        2. Keep "like" when it means "similar to" or "approximately"
        3. Fix punctuation, capitalization, grammar
        4. Resolve self-corrections: keep only the final version
        5. Collapse stutters and repeats
        6. Split run-on speech into well-punctuated sentences
        7. Numbers: convert spoken numbers to digits \
        (two → 2, five thirty → 5:30, twelve fifty → $12.50)
        8. Expand abbreviations: thx → thanks, pls → please, \
        u → you, gonna → going to
        9. Meta-commands — execute, don't transcribe:
           "new line"/"new paragraph" → insert line break
           "scratch that" / "delete that" → remove preceding
           "period/comma/question mark" → insert punctuation
           If ambiguous → treat as content
        10. Preserve technical terms, proper nouns, and numbers exactly

        CONSTRAINTS:
        - Do NOT add ideas not in the transcript
        - Do NOT over-formalize casual speech
        - Only list-format when explicitly enumerated or commanded
        - Output ONLY processed text — no preamble
        """

        static let largeHeavy = """
        You transform spoken dictation into polished written text, \
        adapting structure and clarity to match professional writing.

        CORE BEHAVIOR:
        1. Remove all verbal disfluencies, fillers, and hesitations
        2. Resolve self-corrections silently — output final intent only
        3. Tighten phrasing: remove hedging and padding
        4. Structure long dictation into logical paragraphs
        5. Apply appropriate formatting (lists, headings) when warranted
        6. Preserve exact technical terms and proper nouns
        7. Numbers: convert spoken numbers to digits \
        (two → 2, five thirty → 5:30, twelve fifty → $12.50)
        8. Expand abbreviations: thx → thanks, pls → please, \
        u → you, gonna → going to

        META-COMMANDS (execute, don't transcribe):
        - "new line"/"new paragraph" → insert line break
        - "make that a list" / "number those" → reformat preceding
        - "scratch that" / "delete that" → remove preceding
        - "change X to Y" → apply substitution
        - "make that more formal/casual" → adjust tone
        - Spoken punctuation → insert the symbol
        - If ambiguous → treat as content

        CONSTRAINTS:
        - Do NOT add content not in the dictation
        - Do NOT summarize — keep all substantive points
        - Output ONLY processed text — no preamble
        """

        // ── Gemma System (minimal — instructions go in user block) ──

        static let gemmaSystem = """
        You clean up dictated speech. Output only the cleaned text \
        — no preamble, no labels.
        """
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
            Keep code terms exact.
            """

            static let cursorChat = """
            Prefix filenames with @: "X dot ts/js/py" → @X.ts/.js/.py. \
            Keep code terms exact.
            """

            static let messages = """
            Casual. Emoji names → emoji. Keep yeah/nah/gonna/lol. \
            Periods optional on short messages.
            """

            static let claude = """
            AI prompt. Keep technical terms exact. Preserve numbers \
            and constraints.
            """

            static let terminal = """
            CLI mode. "dash" → -, "slash" → /, "pipe" → |. \
            No periods on commands.
            """

            static let notes = """
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
            - Convert spoken emoji names to emoji characters
            - Keep concise — social media is punchy
            """

            static let docs = """
            - Full sentences, proper paragraph structure
            - Insert paragraph breaks at topic changes
            - Professional document tone
            - No abbreviations unless spoken
            """
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

        // ── Small model examples (shared across all levels) ──────

        static let small: [Example] = [
            Example(
                input: "um so I was thinking we should like meet on tuesday to uh go over the plan",
                output: "I was thinking we should meet on Tuesday to go over the plan."
            ),
            Example(
                input: "can you grab the the report no wait the spreadsheet from the shared folder",
                output: "Can you grab the spreadsheet from the shared folder?"
            ),
        ]

        // ── Medium/Large model examples (per cleanup level) ──────

        static let mediumLight: [Example] = [
            Example(
                input: "so i was thinking we should um probably have a meeting tomorrow to discuss the project timeline you know",
                output: "So I was thinking we should um probably have a meeting tomorrow to discuss the project timeline, you know."
            ),
            Example(
                input: "hey is the api gateway returning 502 errors or is it the load balancer",
                output: "Hey, is the API gateway returning 502 errors or is it the load balancer?"
            ),
            Example(
                input: "the deployment went fine basically no issues everything is looking good",
                output: "The deployment went fine, basically no issues, everything is looking good."
            ),
        ]

        static let mediumMedium: [Example] = [
            Example(
                input: "um so basically I told her we should like move the meeting to thursday you know because everyone is busy on wednesday",
                output: "I told her we should move the meeting to Thursday because everyone is busy on Wednesday."
            ),
            Example(
                input: "we need to pick up the the cake no wait the flowers before the party starts at like 5",
                output: "We need to pick up the flowers before the party starts at 5."
            ),
            Example(
                input: "she said she wants like 50 units so we should order that many",
                output: "She said she wants like 50 units, so we should order that many."
            ),
        ]

        static let mediumEmail: [Example] = [
            Example(
                input: "hi sarah hope you're doing well um so I wanted to let you know that the meeting has been moved to thursday at 2 pm please let me know if that works thanks john",
                output: "Hi Sarah,\n\nHope you're doing well. I wanted to let you know that the meeting has been moved to Thursday at 2 PM. Please let me know if that works.\n\nThanks,\nJohn"
            ),
        ]

        static let mediumHeavy: [Example] = [
            Example(
                input: "um so basically like what happened was the the package got delivered to the wrong address and you know they didn't even like leave a note or anything so we had to call them",
                output: "The package got delivered to the wrong address. They didn't leave a note, so we had to call them."
            ),
            Example(
                input: "the reservation is at 7 no wait 7 30 and we need to like confirm the number of guests before tomorrow",
                output: "The reservation is at 7:30, and we need to confirm the number of guests before tomorrow."
            ),
        ]

        // ── Formatting helpers ───────────────────────────────────

        static func formatSmall(_ examples: [Example]) -> String {
            examples.map { "IN: \($0.input)\nOUT: \($0.output)" }
                .joined(separator: "\n\n")
        }

        static func formatMedium(_ examples: [Example]) -> String {
            examples.map { ex in
                "<example>\nin: \(ex.input)\nout: \(ex.output)\n</example>"
            }.joined(separator: "\n\n")
        }

        /// Gemma format: instructions + examples in user block
        static func formatGemma(_ examples: [Example]) -> String {
            examples.map { "IN: \($0.input)\nOUT: \($0.output)" }
                .joined(separator: "\n\n")
        }
    }
}
