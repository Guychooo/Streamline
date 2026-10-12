import Foundation

/// Turns ISO 639-1 / 639-2 codes into readable names.
public enum LanguageNames {
    /// ISO 639-2/B codes that differ from the 639-2/T form Foundation understands.
    private static let bibliographicToTerminology: [String: String] = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho", "cze": "ces",
        "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu", "gre": "ell", "ice": "isl",
        "mac": "mkd", "mao": "mri", "may": "msa", "per": "fas", "rum": "ron", "slo": "slk",
        "tib": "bod", "wel": "cym"
    ]

    public static func displayName(for code: String, locale: Locale = .current) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "und" else { return "Unknown" }
        let lower = trimmed.lowercased()
        let normalized = bibliographicToTerminology[lower] ?? lower
        if let name = locale.localizedString(forLanguageCode: normalized), name.lowercased() != normalized {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        // Not a recognised code: the protocol says to show the raw value.
        return trimmed
    }
}
