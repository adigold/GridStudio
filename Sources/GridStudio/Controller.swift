// Controller: glues the grid, the mapping and CoreMIDI together, and drives the LEDs.
import Foundation
import Observation

struct MonitorLine: Identifiable {
    let id = UUID()
    let time = Date()
    let incoming: Bool
    let text: String
}

@Observable
@MainActor
final class Controller {
    var info = GridInfo()
    var midiOK = false
    var profile: Profile { didSet { if profile != oldValue { save(); applyHardwareSettings(); render() } } }
    var selected: Int? = nil
    var monitor: [MonitorLine] = []
    var monitorPaused = false
    /// The LED brightness of every pad (0...15), what the hardware shows.
    private(set) var leds: [UInt8] = Array(repeating: 0, count: 128)

    var cols: Int { info.cols }
    var rows: Int { info.rows }

    private let grid = GridDevice()
    private let midi = MIDIEngine()
    private var pressed = Set<Int>()
    private var toggles = Set<Int>()
    private var external: [Int: UInt8] = [:]      // LED levels set by the DAW
    private var faderValue: [Int: Int] = [:]      // column -> 0...127

    init() {
        if let d = UserDefaults.standard.data(forKey: "profile"),
           let p = try? JSONDecoder().decode(Profile.self, from: d) {
            profile = p
        } else {
            profile = Profile()
        }
        midiOK = midi.ok
        applySnapshotArguments()
        grid.onKey = { [weak self] x, y, down in MainActor.assumeIsolated { self?.hardwareKey(x, y, down) } }
        grid.onInfo = { [weak self] i in MainActor.assumeIsolated { self?.updateInfo(i) } }
        midi.onIncoming = { [weak self] m in MainActor.assumeIsolated { self?.incoming(m) } }
        grid.start()
        applyHardwareSettings()
        render()
    }

    func shutdown() { grid.shutdown() }

    // MARK: Mapping

    func pad(_ i: Int) -> Pad {
        profile.overrides[i] ?? profile.defaultPad(x: i % cols, y: i / cols, cols: cols, rows: rows)
    }
    func isOverridden(_ i: Int) -> Bool { profile.overrides[i] != nil }
    func setPad(_ i: Int, _ p: Pad) { profile.overrides[i] = p }
    func resetPad(_ i: Int) { profile.overrides[i] = nil }
    func resetAllPads() { profile.overrides.removeAll() }

    func label(_ i: Int) -> String {
        let p = pad(i)
        switch p.kind {
        case .note, .noteToggle: return noteName(p.number)
        case .cc, .ccToggle: return "CC\(p.number)"
        case .fader: return i / cols == 0 ? "CC\(p.number)" : ""
        case .off: return ""
        }
    }

    // MARK: Input

    private func hardwareKey(_ hx: Int, _ hy: Int, _ down: Bool) {
        let x = profile.rotate ? cols - 1 - hx : hx
        let y = profile.rotate ? rows - 1 - hy : hy
        guard x >= 0, y >= 0, x < cols, y < rows else { return }
        press(y * cols + x, down: down)
    }

    /// Hardware keys and mouse clicks in the window both land here.
    func press(_ i: Int, down: Bool) {
        if down { pressed.insert(i) } else { pressed.remove(i) }
        let p = pad(i)
        let ch = UInt8(max(1, min(16, p.channel)) - 1)
        let num = UInt8(max(0, min(127, p.number)))
        let val = UInt8(max(1, min(127, p.value)))
        switch p.kind {
        case .note:
            out(down ? .noteOn(ch: ch, note: num, vel: val) : .noteOff(ch: ch, note: num))
        case .cc:
            out(.cc(ch: ch, num: num, val: down ? val : 0))
        case .noteToggle, .ccToggle:
            guard down else { break }
            let on = !toggles.contains(i)
            if on { toggles.insert(i) } else { toggles.remove(i) }
            if p.kind == .noteToggle { out(on ? .noteOn(ch: ch, note: num, vel: val) : .noteOff(ch: ch, note: num)) }
            else { out(.cc(ch: ch, num: num, val: on ? val : 0)) }
        case .fader:
            guard down else { break }
            let x = i % cols, y = i / cols
            let v = rows > 1 ? Int((Double(rows - 1 - y) / Double(rows - 1) * 127).rounded()) : 127
            faderValue[x] = v
            out(.cc(ch: ch, num: num, val: UInt8(v)))
        case .off:
            break
        }
        if down { selected = i }
        render()
    }

    private func incoming(_ m: MIDIMsg) {
        log(true, m)
        func match(_ kinds: (PadKind) -> Bool, ch: UInt8, num: UInt8) -> [Int] {
            (0..<cols * rows).filter { let p = pad($0); return kinds(p.kind) && p.channel - 1 == Int(ch) && p.number == Int(num) }
        }
        switch m {
        case let .noteOn(ch, note, vel):
            for i in match({ $0.isNote }, ch: ch, num: note) { external[i] = level(vel) }
        case let .noteOff(ch, note):
            for i in match({ $0.isNote }, ch: ch, num: note) { external[i] = nil }
        case let .cc(ch, num, val):
            for i in match({ $0 == .cc || $0 == .ccToggle }, ch: ch, num: num) { external[i] = val == 0 ? nil : level(val) }
            for i in match({ $0 == .fader }, ch: ch, num: num) { faderValue[i % cols] = Int(val) }
        }
        render()
    }

    private func level(_ v: UInt8) -> UInt8 { max(1, UInt8((Int(v) * 15 + 63) / 127)) }

    private func out(_ m: MIDIMsg) {
        midi.send(m)
        log(false, m)
    }

    private func log(_ incoming: Bool, _ m: MIDIMsg) {
        guard !monitorPaused else { return }
        let t: String
        switch m {
        case let .noteOn(ch, n, v): t = "Note On   ch \(ch + 1)  \(noteName(Int(n))) (\(n))  vel \(v)"
        case let .noteOff(ch, n):   t = "Note Off  ch \(ch + 1)  \(noteName(Int(n))) (\(n))"
        case let .cc(ch, n, v):     t = "CC        ch \(ch + 1)  #\(n)  = \(v)"
        }
        monitor.insert(MonitorLine(incoming: incoming, text: t), at: 0)
        if monitor.count > 300 { monitor.removeLast(monitor.count - 300) }
    }

    // MARK: Output to the LEDs

    private func updateInfo(_ i: GridInfo) {
        let sizeChanged = i.cols != info.cols || i.rows != info.rows
        info = i
        if !i.connected { pressed.removeAll() }
        if sizeChanged { selected = nil; external.removeAll(); toggles.removeAll() }
        if i.connected { applyHardwareSettings() }
        render()
    }

    private func applyHardwareSettings() { grid.setIntensity(profile.brightness) }

    func render() {
        let n = cols * rows
        var l = [UInt8](repeating: 0, count: n)
        let local = profile.ledMode != .daw
        let daw = profile.ledMode != .local
        let idle = UInt8(max(0, min(15, profile.idleGlow)))
        for i in 0..<n {
            let p = pad(i)
            var v: UInt8 = p.kind == .off ? 0 : idle
            if p.kind.isNote, profile.layout == .isomorphic || profile.layout == .chromatic,
               profile.overrides[i] == nil, p.number % 12 == profile.baseNote % 12, idle > 0 {
                v = min(15, idle + 4) // root notes glow a little brighter
            }
            if p.kind == .fader {
                let x = i % cols, y = i / cols
                let lit = Int((Double(faderValue[x] ?? 0) / 127 * Double(rows)).rounded())
                v = (rows - y) <= lit ? ((rows - y) == lit ? 15 : 8) : idle
            }
            if local, toggles.contains(i) { v = 15 }
            if local, pressed.contains(i), p.kind != .fader { v = 15 }
            if daw, let e = external[i] { v = max(v, e) }
            l[i] = v
        }
        leds = l
        // The hardware gets the same picture, flipped when the grid is rotated.
        var hw = [UInt8](repeating: 0, count: n)
        for i in 0..<n {
            let x = i % cols, y = i / cols
            let hx = profile.rotate ? cols - 1 - x : x, hy = profile.rotate ? rows - 1 - y : y
            hw[hy * cols + hx] = l[i]
        }
        grid.setLevels(hw, cols: cols, rows: rows)
    }

    func isPressed(_ i: Int) -> Bool { pressed.contains(i) }

    func panic() {
        for ch in 0..<16 { midi.send(.cc(ch: UInt8(ch), num: 123, val: 0)) }
        toggles.removeAll(); external.removeAll()
        monitor.insert(MonitorLine(incoming: false, text: "All notes off, every channel"), at: 0)
        render()
    }

    // MARK: Persistence

    private var snapshotMode: Bool { CommandLine.arguments.contains("--snapshot") }

    /// Only used to stage README screenshots. Never saved.
    private func applySnapshotArguments() {
        let a = CommandLine.arguments
        guard snapshotMode else { return }
        func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
        var p = Profile()
        if let l = arg("--layout").flatMap(Layout.init(rawValue:)) { p.choose(l) }
        if let m = arg("--leds").flatMap(LEDMode.init(rawValue:)) { p.ledMode = m }
        profile = p
        if let s = arg("--select").flatMap(Int.init) { selected = s }
        if let s = arg("--override").flatMap(Int.init) {
            profile.overrides[s] = Pad(kind: .ccToggle, channel: 2, number: 64, value: 127)
        }
        if a.contains("--demo") {
            switch profile.layout {
            case .faders:
                for (x, v) in [100, 64, 30, 127, 90, 45, 70, 110, 20, 80, 127, 55, 35, 95, 60, 10].enumerated() { faderValue[x] = v }
            case .toggles:
                toggles = [1, 2, 5, 18, 21, 22, 36, 39, 40, 41, 55, 66, 72, 75, 88, 91, 99, 104, 106, 117, 120, 125]
            default:
                for (i, v) in [(97, UInt8(15)), (101, 12), (104, 15), (76, 9), (83, 13), (60, 7), (39, 11), (19, 6)] where pad(i).kind != .off { external[i] = v }
                pressed = [97, 104]
            }
            monitor = [
                MonitorLine(incoming: true, text: "Note On   ch 1  E2 (52)  vel 96"),
                MonitorLine(incoming: false, text: "Note Off  ch 1  C2 (48)"),
                MonitorLine(incoming: false, text: "Note On   ch 1  C2 (48)  vel 100"),
                MonitorLine(incoming: false, text: "CC        ch 1  #21  = 64"),
                MonitorLine(incoming: true, text: "CC        ch 1  #20  = 127"),
            ]
        }
        render()
    }

    private func save() {
        guard !snapshotMode else { return }
        if let d = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(d, forKey: "profile") }
    }

    func exportProfile(to url: URL) throws {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(profile).write(to: url)
    }

    func importProfile(from url: URL) throws {
        profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
        toggles.removeAll(); external.removeAll(); faderValue.removeAll()
        render()
    }
}
