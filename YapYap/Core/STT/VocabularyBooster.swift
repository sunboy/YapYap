// VocabularyBooster.swift
// YapYap — Prepare personal dictionary terms for STT vocabulary boosting
import Foundation

/// Extracts and ranks terms from PersonalDictionary for STT vocabulary boosting.
/// Currently used to inject terms into WhisperKit's initial prompt.
/// Future: when FluidAudio exposes a hotword/bias API, these terms will be
/// passed directly to the Parakeet CTC decoder for first-pass accuracy.
struct VocabularyBooster {

    struct BoostTerm {
        let term: String
        let weight: Float
    }

    /// Maximum number of terms to boost (CTC decoders have practical limits)
    static let maxTerms = 256

    /// Extract enabled dictionary entries, sorted by frequency, capped at maxTerms.
    static func boostTerms(from dictionary: PersonalDictionary) -> [BoostTerm] {
        dictionary.entries.values
            .filter { $0.isEnabled }
            .sorted { $0.hitCount > $1.hitCount }
            .prefix(maxTerms)
            .map { BoostTerm(term: $0.corrected, weight: Float($0.hitCount + 1)) }
    }

    /// Format terms as a WhisperKit initial prompt string.
    /// WhisperKit uses the initial prompt to bias the decoder toward expected vocabulary.
    static func whisperPrompt(from dictionary: PersonalDictionary) -> String? {
        let terms = boostTerms(from: dictionary)
        guard !terms.isEmpty else { return nil }
        return terms.map(\.term).joined(separator: ", ")
    }
}
