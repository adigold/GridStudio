// What each pad sends. A layout gives every pad a default; any pad can be overridden.
import Foundation

enum PadKind: String, Codable, CaseIterable, Identifiable {
    case note, noteToggle, cc, ccToggle, fader, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .note: "Note"
        case .noteToggle: "Note toggle"
        case .cc: "CC"
        case .ccToggle: "CC toggle"
        case .fader: "Fader (column)"
        case .off: "Off"
        }
    }
    var detail: String {
        switch self {
        case .note: "Note on while held, note off on release"
        case .noteToggle: "Press once for note on, again for note off"
        case .cc: "Sends the value while held, 0 on release"
        case .ccToggle: "Press to switch between the value and 0"
        case .fader: "The column is a fader, the row sets the value"
        case .off: "Sends nothing"
        }
    }
    var isNote: Bool { self == .note || self == .noteToggle }
    var isToggle: Bool { self == .noteToggle || self == .ccToggle }
}

struct Pad: Codable, Equatable {
    var kind: PadKind = .note
    var channel: Int = 1      // 1...16
    var number: Int = 60      // note or CC number 0...127
    var value: Int = 100      // velocity or CC value 1...127
}

enum Layout: String, Codable, CaseIterable, Identifiable {
    case chromatic, isomorphic, drums, toggles, faders
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chromatic: "128 notes"
        case .isomorphic: "Keyboard"
        case .drums: "Drum pads"
        case .toggles: "Toggles"
        case .faders: "Faders"
        }
    }
    var detail: String {
        switch self {
        case .chromatic: "All 128 MIDI notes, one per pad, from top left, row by row"
        case .isomorphic: "Rows a fourth apart (like Push), low notes at the bottom"
        case .drums: "4x4 blocks of 16 pads like Ableton Drum Rack, from the lowest note, bottom half first"
        case .toggles: "Every pad is an on/off CC switch, for mutes and clip launch"
        case .faders: "Every column is a fader sending its own CC"
        }
    }
    var symbol: String {
        switch self {
        case .chromatic: "square.grid.4x3.fill"
        case .isomorphic: "pianokeys"
        case .drums: "square.grid.2x2"
        case .toggles: "switch.2"
        case .faders: "slider.vertical.3"
        }
    }
}

enum LEDMode: String, Codable, CaseIterable, Identifiable {
    case local, daw, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: "Local"
        case .daw: "From DAW"
        case .both: "Both"
        }
    }
}

struct Profile: Codable, Equatable {
    var layout: Layout = .isomorphic
    var baseNote: Int = 36
    var rowOffset: Int = 5
    var channel: Int = 1
    var velocity: Int = 100
    var ccBase: Int = 20
    var ledMode: LEDMode = .both
    var idleGlow: Int = 2          // brightness of mapped pads at rest
    var brightness: Int = 15       // global grid intensity
    var rotate: Bool = false       // cable on the left
    var overrides: [Int: Pad] = [:]

    /// Switching layout also picks a sensible lowest note for it.
    mutating func choose(_ l: Layout) {
        if l == .chromatic { baseNote = 0 } else if layout == .chromatic && baseNote == 0 { baseNote = 36 }
        layout = l
    }

    func defaultPad(x: Int, y: Int, cols: Int, rows: Int) -> Pad {
        var p = rawPad(x: x, y: y, cols: cols, rows: rows)
        if p.kind.isNote && !(0...127).contains(p.number) { p.kind = .off } // past the MIDI note range
        return p
    }

    private func rawPad(x: Int, y: Int, cols: Int, rows: Int) -> Pad {
        let ch = channel
        switch layout {
        case .chromatic:
            return Pad(kind: .note, channel: ch, number: baseNote + y * cols + x, value: velocity)
        case .isomorphic:
            return Pad(kind: .note, channel: ch, number: baseNote + (rows - 1 - y) * rowOffset + x, value: velocity)
        case .drums:
            let block = x / 4, bx = x % 4, by = (rows - 1 - y) % 4, bank = (rows - 1 - y) / 4
            let n = baseNote + (block + bank * (cols / 4)) * 16 + by * 4 + bx
            return Pad(kind: .note, channel: ch, number: n, value: velocity)
        case .toggles:
            return Pad(kind: .ccToggle, channel: ch, number: clamp(y * cols + x), value: 127)
        case .faders:
            return Pad(kind: .fader, channel: ch, number: clamp(ccBase + x), value: 127)
        }
    }

    private func clamp(_ n: Int) -> Int { max(0, min(127, n)) }
}

private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
func noteName(_ n: Int) -> String { "\(noteNames[((n % 12) + 12) % 12])\(n / 12 - 2)" }
