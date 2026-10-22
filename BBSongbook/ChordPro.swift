import Foundation

/// Lyrics in ChordPro style: "[C]คำร้อง [G]ต่อ" and "{ท่อน 1}" section headings.
enum ChordPro {
    struct Segment: Hashable {
        var chord: String
        var text: String
    }

    enum Line: Hashable {
        case section(String)
        case lyric([Segment])
        case blank
    }

    static func parse(_ lyrics: String) -> [Line] {
        lyrics.components(separatedBy: .newlines).map { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return .blank }
            if line.hasPrefix("{"), line.hasSuffix("}") {
                return .section(String(line.dropFirst().dropLast()))
            }
            return .lyric(segments(line))
        }
    }

    private static func segments(_ line: String) -> [Segment] {
        var result: [Segment] = []
        var chord = ""
        var text = ""
        var inChord = false
        for ch in line {
            switch ch {
            case "[" where !inChord:
                if !chord.isEmpty || !text.isEmpty { result.append(Segment(chord: chord, text: text)) }
                chord = ""
                text = ""
                inChord = true
            case "]" where inChord:
                inChord = false
            default:
                if inChord { chord.append(ch) } else { text.append(ch) }
            }
        }
        if !chord.isEmpty || !text.isEmpty { result.append(Segment(chord: chord, text: text)) }
        return result
    }

    /// Shift every chord by `steps` semitones (for changing key on stage).
    static func transpose(_ lyrics: String, by steps: Int) -> String {
        guard steps % 12 != 0 else { return lyrics }
        var out = ""
        var chord = ""
        var inChord = false
        for ch in lyrics {
            if ch == "[" && !inChord {
                inChord = true
                chord = ""
            } else if ch == "]" && inChord {
                inChord = false
                out += "[" + transposeChord(chord, by: steps) + "]"
            } else if inChord {
                chord.append(ch)
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flats = ["Db": 1, "Eb": 3, "Gb": 6, "Ab": 8, "Bb": 10]

    static func transposeChord(_ chord: String, by steps: Int) -> String {
        // Handles slash chords like "C/G".
        chord.split(separator: "/", omittingEmptySubsequences: false)
            .map { part -> String in
                let s = String(part)
                for length in [2, 1] where s.count >= length {
                    let root = String(s.prefix(length))
                    if let i = sharps.firstIndex(of: root) ?? flats[root] {
                        return sharps[((i + steps) % 12 + 12) % 12] + s.dropFirst(length)
                    }
                }
                return s
            }
            .joined(separator: "/")
    }
}
