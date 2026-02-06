public enum TextRhythm {
    // Counts consecutive '-' characters immediately after the current index.
    // This intentionally does not wrap to the beginning of the script.
    public static func holdRunLength(
        after index: Int,
        in characters: [Character],
        holdCharacters: Set<Character> = ["-"]
    ) -> Int {
        guard !characters.isEmpty else { return 0 }
        guard index >= 0 && index < characters.count else { return 0 }
        guard !holdCharacters.isEmpty else { return 0 }

        var count = 0
        var cursor = index + 1
        while cursor < characters.count, holdCharacters.contains(characters[cursor]) {
            count += 1
            cursor += 1
        }
        return count
    }
}
