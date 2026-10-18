import Foundation

/// Parses the framing emitted by `BudsLink.request`: AA, LEB128 body length,
/// then a 7-byte header whose final two bytes declare the payload length.
/// The payload length is encoded as UInt16, so this is a protocol-derived
/// maximum rather than a guess about current firmware response sizes.
struct Air7FrameParser {
    struct Frame: Equatable {
        let command: UInt16
        let sequence: UInt8
        let payload: [UInt8]
    }

    private static let headerLength = 7
    private static let maximumPayloadLength = Int(UInt16.max)
    private static let maximumBodyLength = headerLength + maximumPayloadLength
    private static let maximumEncodedLength = 1 + 3 + maximumBodyLength
    private var buffer: [UInt8] = []

    var bufferedByteCount: Int { buffer.count }

    mutating func append<S: Sequence>(_ bytes: S) -> [Frame] where S.Element == UInt8 {
        var frames: [Frame] = []
        for byte in bytes {
            buffer.append(byte)
            frames.append(contentsOf: drainAvailableFrames())

            // A frame with a UInt16 payload and 7-byte header fits within this
            // bound. If malformed input still leaves a full maximum-sized
            // frame incomplete, discard its marker and rescan for the next one.
            if buffer.count >= Self.maximumEncodedLength {
                buffer.removeFirst()
                frames.append(contentsOf: drainAvailableFrames())
            }
        }
        return frames
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }

    private mutating func drainAvailableFrames() -> [Frame] {
        var frames: [Frame] = []
        while let marker = buffer.firstIndex(of: 0xAA) {
            if marker > 0 { buffer.removeFirst(marker) }
            guard let length = Self.readLength(in: buffer) else { break }
            guard length.bodyLength >= Self.headerLength,
                  length.bodyLength <= Self.maximumBodyLength else {
                buffer.removeFirst()
                continue
            }

            let frameEnd = 1 + length.prefixLength + length.bodyLength
            guard buffer.count >= frameEnd else { break }

            let bodyStart = 1 + length.prefixLength
            let payloadLength = Int(buffer[bodyStart + 5]) | Int(buffer[bodyStart + 6]) << 8
            guard payloadLength <= length.bodyLength - Self.headerLength else {
                buffer.removeFirst()
                continue
            }

            let command = UInt16(buffer[bodyStart + 2]) | UInt16(buffer[bodyStart + 3]) << 8
            let sequence = buffer[bodyStart + 4]
            let payloadStart = bodyStart + Self.headerLength
            let payload = Array(buffer[payloadStart..<(payloadStart + payloadLength)])
            frames.append(Frame(command: command, sequence: sequence, payload: payload))
            buffer.removeFirst(frameEnd)
        }

        // No marker means all bytes were noise and can be dropped immediately.
        if !buffer.contains(0xAA) { buffer.removeAll(keepingCapacity: true) }
        return frames
    }

    private static func readLength(in bytes: [UInt8]) -> (bodyLength: Int, prefixLength: Int)? {
        var value = 0
        for index in 0..<3 {
            let byteIndex = 1 + index
            guard bytes.count > byteIndex else { return nil }
            let byte = bytes[byteIndex]
            value |= Int(byte & 0x7F) << (index * 7)
            if byte & 0x80 == 0 { return (value, index + 1) }
        }
        // Three continuation bytes exceed the supported 21-bit encoding.
        return (Int.max, 3)
    }
}

/// Thread-safe, one-shot storage for RFCOMM requests awaiting a response.
/// The owning link supplies its local transport-failure sentinel on close.
final class Air7PendingRequests {
    typealias Completion = (UInt16, [UInt8]) -> Void
    private struct Entry {
        let id: UUID
        let completion: Completion
        let timeout: DispatchWorkItem
    }
    private let lock = NSLock()
    private var pending: [UInt8: Entry] = [:]

    @discardableResult
    func register(sequence: UInt8, timeoutAfter seconds: TimeInterval = 15, completion: @escaping Completion) -> Completion? {
        let id = UUID()
        let timeout = DispatchWorkItem { [weak self] in self?.expire(sequence: sequence, id: id) }
        lock.lock()
        let replaced = pending.removeValue(forKey: sequence)
        replaced?.timeout.cancel()
        pending[sequence] = Entry(id: id, completion: completion, timeout: timeout)
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: timeout)
        return replaced?.completion
    }

    func take(sequence: UInt8) -> Completion? {
        lock.lock()
        let entry = pending.removeValue(forKey: sequence)
        entry?.timeout.cancel()
        lock.unlock()
        return entry?.completion
    }

    func failAll() -> [Completion] {
        lock.lock()
        let entries = Array(pending.values)
        entries.forEach { $0.timeout.cancel() }
        pending.removeAll(keepingCapacity: false)
        lock.unlock()
        return entries.map(\.completion)
    }

    private func expire(sequence: UInt8, id: UUID) {
        lock.lock()
        guard let entry = pending[sequence], entry.id == id else {
            lock.unlock()
            return
        }
        pending.removeValue(forKey: sequence)
        lock.unlock()
        NSLog("Air7Menu RFCOMM request timed out (sequence=%d)", sequence)
        entry.completion(0xFFFF, [])
    }
}

struct Air7BatterySnapshot: Equatable {
    let levels: [String: Int]
    let chargingStates: [String: Air7ChargingState]
}

enum Air7BatteryDecoder {
    /// The current Air 7 reports battery percentages for each entry. Keep the
    /// legacy case charging display, but do not treat the earbuds' high bit as
    /// a verified charging signal. Missing IDs remain absent; zero is a reading.
    static func decodeSnapshot(_ payload: [UInt8]) -> Air7BatterySnapshot? {
        let offset: Int
        if payload.count >= 1, Int(payload[0]) * 2 + 1 == payload.count { offset = 0 }
        else if payload.count >= 2, Int(payload[1]) * 2 + 2 == payload.count { offset = 1 }
        else { return nil }

        let count = Int(payload[offset])
        guard payload.count >= offset + 1 + count * 2 else { return nil }
        var values: [String: Int] = [:]
        var chargingStates: [String: Air7ChargingState] = [:]
        for index in 0..<count {
            let id = payload[offset + 1 + index * 2]
            let raw = payload[offset + 2 + index * 2]
            let key = [1: "Left", 2: "Right", 3: "Case"][Int(id)]
            if let key {
                values[key] = min(Int(raw & 0x7F), 100)
                if key == "Case" {
                    chargingStates[key] = raw & 0x80 == 0 ? .notCharging : .charging
                } else {
                    chargingStates[key] = .unknown
                }
            }
        }
        return Air7BatterySnapshot(levels: values, chargingStates: chargingStates)
    }

    /// Compatibility helper for existing battery-level consumers.
    static func decode(_ payload: [UInt8]) -> [String: Int]? {
        decodeSnapshot(payload)?.levels
    }
}
