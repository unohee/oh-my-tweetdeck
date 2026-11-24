import Foundation

/// Per-service length counting for the composer.
///
/// These are close approximations of each service's own rules, chosen to err on the
/// side of over-counting so the composer never green-lights a post the service rejects.
public enum TextMetrics {
    /// Length of `text` in the counting unit of `service`.
    public static func length(of text: String, for service: Service) -> Int {
        switch service {
        case .x: return xWeightedLength(text)
        case .threads: return threadsLength(text)
        case .instagram: return text.count
        }
    }

    public static func remaining(_ text: String, for service: Service) -> Int {
        service.maxLength - length(of: text, for: service)
    }

    // MARK: X

    /// X's weighted length (twitter-text v3 config): URLs count 23, emoji count 2,
    /// code points in the light ranges below count 1, everything else (CJK, Hangul...) counts 2.
    static func xWeightedLength(_ text: String) -> Int {
        var total = 0
        for token in tokenizeURLs(text) {
            switch token {
            case .url:
                total += 23
            case .text(let chunk):
                for character in chunk {
                    if isEmoji(character) {
                        total += 2
                        continue
                    }
                    for scalar in character.unicodeScalars {
                        total += isLightWeight(scalar.value) ? 1 : 2
                    }
                }
            }
        }
        return total
    }

    private static func isLightWeight(_ v: UInt32) -> Bool {
        (0...4351).contains(v) || (8192...8205).contains(v) || (8208...8223).contains(v)
            || (8242...8247).contains(v)
    }

    // MARK: Threads

    /// Threads counts characters, but its docs state emoji count as their UTF-8 byte length.
    static func threadsLength(_ text: String) -> Int {
        text.reduce(0) { sum, character in
            sum + (isEmoji(character) ? String(character).utf8.count : 1)
        }
    }

    // MARK: Helpers

    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        // Digits and '#' have Emoji=Yes but are only emoji when followed by VS16 / keycap.
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && scalars.count > 1
    }

    enum Token: Equatable {
        case text(Substring)
        case url
    }

    static func tokenizeURLs(_ text: String) -> [Token] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [.text(Substring(text))] }
        let ns = text as NSString
        var tokens: [Token] = []
        var cursor = 0
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                let r = NSRange(location: cursor, length: match.range.location - cursor)
                tokens.append(.text(Substring(ns.substring(with: r))))
            }
            tokens.append(.url)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            tokens.append(.text(Substring(ns.substring(from: cursor))))
        }
        return tokens
    }
}
