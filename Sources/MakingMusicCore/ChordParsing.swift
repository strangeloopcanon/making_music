import Foundation

public enum ChordParsing {
    public static func parseRootAndBass(_ token: String) -> (root: PitchClass, bass: PitchClass?, raw: String)? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let main = String(parts.first ?? "")
        let bassToken = parts.count == 2 ? String(parts[1]) : nil

        guard let root = parsePitchClassPrefix(main) else { return nil }
        let bass = bassToken.flatMap { parsePitchClassPrefix($0) }
        return (root: root, bass: bass, raw: trimmed)
    }

    public static func parsePitchClassPrefix(_ token: String) -> PitchClass? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }

        let base: Int
        switch String(first).uppercased() {
        case "C": base = 0
        case "D": base = 2
        case "E": base = 4
        case "F": base = 5
        case "G": base = 7
        case "A": base = 9
        case "B": base = 11
        default: return nil
        }

        var value = base
        let chars = Array(trimmed)
        if chars.count >= 2 {
            if chars[1] == "#" {
                value = (value + 1) % 12
            } else if chars[1] == "b" {
                value = (value + 11) % 12
            }
        }
        return PitchClass(rawValue: value)
    }

    public static func pitchClassPrefixLength(_ token: String) -> Int {
        let chars = Array(token)
        guard !chars.isEmpty else { return 0 }
        if chars.count >= 2, chars[1] == "#" || chars[1] == "b" {
            return 2
        }
        return 1
    }
}
