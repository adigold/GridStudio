// GridDevice: the monome grid driver.
// Talks to the grid directly over USB serial with the monome "mext" protocol
// (https://monome.org/docs/serialosc/serial.txt). serialosc is not needed.
// Finds the grid by itself and reconnects when it is plugged back in.
import Foundation

struct GridInfo: Equatable {
    var connected = false
    var path = ""
    var id = ""
    var firmware = ""
    var cols = 16
    var rows = 8
}

final class GridDevice {
    /// Called on the main queue.
    var onKey: ((Int, Int, Bool) -> Void)?
    var onInfo: ((GridInfo) -> Void)?

    private let q = DispatchQueue(label: "grid.serial", qos: .userInteractive)
    private var fd: Int32 = -1
    private var reader: DispatchSourceRead?
    private var flushTimer: DispatchSourceTimer?
    private var scanTimer: DispatchSourceTimer?
    private var rx = [UInt8]()
    private var levels = [UInt8](repeating: 0, count: 256) // 16x16 so any size fits
    private var dirty = true
    private var globalIntensity: UInt8 = 15
    private var info = GridInfo()

    // Length of every message the grid can send.
    private static let inLen: [UInt8: Int] = [
        0x00: 3, 0x01: 33, 0x02: 3, 0x03: 3, 0x0F: 9,
        0x20: 3, 0x21: 3, 0x50: 3, 0x80: 8,
    ]

    func start() {
        q.async { [self] in
            let scan = DispatchSource.makeTimerSource(queue: q)
            scan.schedule(deadline: .now(), repeating: 1.5)
            scan.setEventHandler { [weak self] in self?.tryConnect() }
            scan.resume()
            scanTimer = scan

            let flush = DispatchSource.makeTimerSource(queue: q)
            flush.schedule(deadline: .now(), repeating: 1.0 / 60.0)
            flush.setEventHandler { [weak self] in self?.flush() }
            flush.resume()
            flushTimer = flush
        }
    }

    /// Turns every LED off and closes the port (used when the app quits).
    func shutdown() {
        q.sync {
            scanTimer?.cancel()
            flushTimer?.cancel()
            if fd >= 0 { write([0x12]); usleep(20_000) }
            closePort(notify: false)
        }
    }

    // MARK: LEDs (safe from any thread)

    func setLevels(_ frame: [UInt8], cols: Int, rows: Int) {
        q.async { [self] in
            for y in 0..<min(rows, 16) {
                for x in 0..<min(cols, 16) {
                    let v = min(frame[y * cols + x], 15)
                    if levels[y * 16 + x] != v { levels[y * 16 + x] = v; dirty = true }
                }
            }
        }
    }

    func setIntensity(_ i: Int) {
        q.async { [self] in
            globalIntensity = UInt8(max(0, min(15, i)))
            write([0x17, globalIntensity])
        }
    }

    // MARK: Discovery

    static func findPort() -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        // monome grids show up as cu.usbmodemm<serial> (2020+) or cu.usbserial-m<serial> (older).
        let hit = names.sorted().first { $0.hasPrefix("cu.usbmodemm") || $0.hasPrefix("cu.usbserial-m") }
        return hit.map { "/dev/" + $0 }
    }

    private func tryConnect() {
        guard fd < 0, let path = Self.findPort() else { return }
        let f = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else { return }
        if ioctl(f, TIOCEXCL) == -1 { Darwin.close(f); return } // busy (serialosc running?)

        var t = termios()
        tcgetattr(f, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(B115200))
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tcsetattr(f, TCSANOW, &t)
        tcflush(f, TCIOFLUSH)

        fd = f
        rx.removeAll()
        info = GridInfo(connected: true, path: path)
        let r = DispatchSource.makeReadSource(fileDescriptor: f, queue: q)
        r.setEventHandler { [weak self] in self?.readAvailable() }
        r.resume()
        reader = r

        write([0x00]); write([0x01]); write([0x05]); write([0x0F])
        write([0x17, globalIntensity])
        dirty = true
        publishInfo()
    }

    private func closePort(notify: Bool = true) {
        reader?.cancel(); reader = nil
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        if notify { info.connected = false; publishInfo() }
    }

    // MARK: Serial IO

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 512)
        let n = read(fd, &buf, buf.count)
        if n <= 0 {
            if n == 0 || (errno != EAGAIN && errno != EINTR) { closePort() } // unplugged
            return
        }
        rx.append(contentsOf: buf[0..<n])
        while let first = rx.first {
            guard let len = Self.inLen[first] else { rx.removeFirst(); continue }
            if rx.count < len { break }
            let m = Array(rx[0..<len])
            rx.removeFirst(len)
            handle(m)
        }
    }

    private func handle(_ m: [UInt8]) {
        switch m[0] {
        case 0x01:
            info.id = String(decoding: m[1...].prefix { $0 != 0 }, as: UTF8.self)
            publishInfo()
        case 0x03:
            info.cols = Int(m[1] == 0 ? 16 : m[1])
            info.rows = Int(m[2] == 0 ? 8 : m[2])
            dirty = true
            publishInfo()
        case 0x0F:
            info.firmware = String(decoding: m[1...].prefix { $0 != 0 }, as: UTF8.self)
            publishInfo()
        case 0x20, 0x21:
            let x = Int(m[1]), y = Int(m[2]), down = m[0] == 0x21
            DispatchQueue.main.async { self.onKey?(x, y, down) }
        default:
            break
        }
    }

    private func publishInfo() {
        let i = info
        DispatchQueue.main.async { self.onInfo?(i) }
    }

    /// Sends changed LEDs as 8x8 quads (0x1A level map, 4 bits per LED).
    private func flush() {
        guard dirty, fd >= 0 else { return }
        dirty = false
        var qy = 0
        while qy < info.rows {
            var qx = 0
            while qx < info.cols {
                var msg: [UInt8] = [0x1A, UInt8(qx), UInt8(qy)]
                for y in 0..<8 {
                    for x in stride(from: 0, to: 8, by: 2) {
                        let i = (qy + y) * 16 + qx + x
                        let a = i < 256 ? levels[i] : 0
                        let b = i + 1 < 256 ? levels[i + 1] : 0
                        msg.append((a << 4) | b)
                    }
                }
                write(msg)
                qx += 8
            }
            qy += 8
        }
    }

    private func write(_ bytes: [UInt8]) {
        guard fd >= 0 else { return }
        bytes.withUnsafeBufferPointer { p in
            var off = 0
            var tries = 0
            while off < p.count && tries < 50 {
                let n = Darwin.write(fd, p.baseAddress! + off, p.count - off)
                if n > 0 { off += n } else if errno == EAGAIN { tries += 1; usleep(200) } else { break }
            }
        }
    }
}
