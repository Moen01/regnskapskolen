import Foundation

/// The invented species name a creature carries on its nameplate: 5–9 capital letters built from
/// syllables that sit well in Norwegian, always the same for the same puzzle id. The puzzle's
/// title is too long for a nameplate, so it is read out in the dialog instead.
public enum SpeciesName {
    static let onsets = ["", "B", "D", "F", "G", "H", "K", "L", "M", "N", "P", "R", "S", "T", "V", "BR", "KR", "TR", "SK", "ST"]
    static let vowels = ["A", "E", "I", "O", "U", "Y", "Æ", "Ø", "Å"]
    static let codas = ["", "", "N", "R", "S", "L", "KS", "NT", "RK"]
    static let minLength = 5
    static let maxLength = 9

    public static func name(for id: String) -> String {
        var generator = SplitMix64(seed: fnv1a(id))
        var name = ""
        let wanted = 2 + Int(generator.next() % 2)
        var syllables = 0
        while syllables < wanted || name.count < minLength {
            let syllable = pick(onsets, &generator) + pick(vowels, &generator) + pick(codas, &generator)
            if name.count + syllable.count > maxLength {
                // Out of room: a bare vowel still fits, else the name is long enough already.
                if name.count < minLength { name += pick(vowels, &generator) }
                break
            }
            name += syllable
            syllables += 1
        }
        return String(name.prefix(maxLength))
    }

    private static func pick(_ table: [String], _ generator: inout SplitMix64) -> String {
        table[Int(generator.next() % UInt64(table.count))]
    }

    /// FNV-1a over UTF-8: a stable hash, unlike `hashValue`, which changes per process.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
