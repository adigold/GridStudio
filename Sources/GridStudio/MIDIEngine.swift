// MIDIEngine: publishes the grid as a CoreMIDI device.
// "Grid Studio" appears as a MIDI input in every app on the Mac (Ableton, Logic, Bitwig...).
// A second endpoint, "Grid Studio LEDs", lets those apps send notes/CCs back to light the pads.
import CoreMIDI
import Foundation

enum MIDIMsg {
    case noteOn(ch: UInt8, note: UInt8, vel: UInt8)
    case noteOff(ch: UInt8, note: UInt8)
    case cc(ch: UInt8, num: UInt8, val: UInt8)
}

final class MIDIEngine {
    /// Called on the main queue for every note/CC arriving at "Grid Studio LEDs".
    var onIncoming: ((MIDIMsg) -> Void)?
    private(set) var ok = false

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var dest = MIDIEndpointRef()

    init(name: String = "Grid Studio") {
        guard MIDIClientCreateWithBlock(name as CFString, &client, nil) == noErr else { return }
        guard MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source) == noErr else { return }
        setStableID(source, key: "midi.sourceID", fallback: 0x4D47_5301)

        let status = MIDIDestinationCreateWithProtocol(client, "\(name) LEDs" as CFString, ._1_0, &dest) { [weak self] list, _ in
            self?.receive(list)
        }
        if status == noErr { setStableID(dest, key: "midi.destID", fallback: 0x4D47_5302) }
        for ep in [source, dest] {
            MIDIObjectSetStringProperty(ep, kMIDIPropertyManufacturer, "monome / Grid Studio" as CFString)
            MIDIObjectSetStringProperty(ep, kMIDIPropertyModel, "grid" as CFString)
        }
        ok = true
    }

    /// Keeps the same MIDI ID across launches so DAWs remember the device.
    private func setStableID(_ ep: MIDIEndpointRef, key: String, fallback: Int32) {
        let saved = UserDefaults.standard.integer(forKey: key)
        let id = saved != 0 ? Int32(truncatingIfNeeded: saved) : fallback
        if MIDIObjectSetIntegerProperty(ep, kMIDIPropertyUniqueID, id) == noErr {
            UserDefaults.standard.set(Int(id), forKey: key)
        }
    }

    func send(_ m: MIDIMsg) {
        guard ok else { return }
        let word: UInt32
        switch m {
        case let .noteOn(ch, note, vel): word = Self.ump(0x90 | (ch & 15), note, vel)
        case let .noteOff(ch, note):     word = Self.ump(0x80 | (ch & 15), note, 0)
        case let .cc(ch, num, val):      word = Self.ump(0xB0 | (ch & 15), num, val)
        }
        var list = MIDIEventList()
        var w = word
        let pkt = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, pkt, 0, 1, &w)
        MIDIReceivedEventList(source, &list)
    }

    /// MIDI 1.0 channel voice message packed as a Universal MIDI Packet (type 2, group 0).
    private static func ump(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) -> UInt32 {
        (0x2 << 28) | (UInt32(status) << 16) | (UInt32(d1 & 0x7F) << 8) | UInt32(d2 & 0x7F)
    }

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        var out = [MIDIMsg]()
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                for i in 0..<min(count, words.count) {
                    let w = words[i]
                    guard w >> 28 == 0x2 else { continue }
                    let status = UInt8((w >> 16) & 0xFF), d1 = UInt8((w >> 8) & 0x7F), d2 = UInt8(w & 0x7F)
                    let ch = status & 0x0F
                    switch status & 0xF0 {
                    case 0x90: out.append(d2 == 0 ? .noteOff(ch: ch, note: d1) : .noteOn(ch: ch, note: d1, vel: d2))
                    case 0x80: out.append(.noteOff(ch: ch, note: d1))
                    case 0xB0: out.append(.cc(ch: ch, num: d1, val: d2))
                    default: break
                    }
                }
            }
        }
        guard !out.isEmpty else { return }
        DispatchQueue.main.async { out.forEach { self.onIncoming?($0) } }
    }
}
