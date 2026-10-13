import XCTest
@testable import Air7Menu

final class Air7FrameParserTests: XCTestCase {
    func testCompleteFrame() {
        var parser = Air7FrameParser()
        XCTAssertEqual(parser.append(frame(command: 0x0106, sequence: 3, payload: [0, 42])), [
            .init(command: 0x0106, sequence: 3, payload: [0, 42])
        ])
        XCTAssertEqual(parser.bufferedByteCount, 0)
    }

    func testFrameSplitAcrossChunks() {
        var parser = Air7FrameParser()
        let bytes = frame(command: 0x0103, sequence: 8, payload: [1, 2, 3])
        XCTAssertTrue(parser.append(bytes.prefix(4)).isEmpty)
        XCTAssertEqual(parser.append(bytes.suffix(from: 4)), [
            .init(command: 0x0103, sequence: 8, payload: [1, 2, 3])
        ])
    }

    func testMultipleFramesInOneChunk() {
        var parser = Air7FrameParser()
        let bytes = frame(command: 0x0106, sequence: 1, payload: [20])
            + frame(command: 0x0204, sequence: 2, payload: [30, 40])
        XCTAssertEqual(parser.append(bytes), [
            .init(command: 0x0106, sequence: 1, payload: [20]),
            .init(command: 0x0204, sequence: 2, payload: [30, 40])
        ])
    }

    func testIncompleteFrameIsRetainedAndThenCompleted() {
        var parser = Air7FrameParser()
        let bytes = frame(command: 0x0106, sequence: 6, payload: [99])
        XCTAssertTrue(parser.append(bytes.dropLast()).isEmpty)
        XCTAssertEqual(parser.bufferedByteCount, bytes.count - 1)
        XCTAssertEqual(parser.append(bytes.suffix(1)), [
            .init(command: 0x0106, sequence: 6, payload: [99])
        ])
    }

    func testMalformedAndOversizedFramesResynchronizeToNextMarker() {
        var parser = Air7FrameParser()
        // Body length 1 is invalid (the header needs at least 7 bytes).
        let shortFrame: [UInt8] = [0xAA, 0x01, 0x00]
        // Three continuation bytes are an invalid LEB128 length in this framing.
        let invalidLength: [UInt8] = [0xAA, 0x80, 0x80, 0x80]
        // 100,000 is representable as LEB128 but larger than the UInt16
        // payload field plus its fixed header.
        let oversizedLength: [UInt8] = [0xAA] + leb128(100_000)
        let valid = frame(command: 0x0106, sequence: 9, payload: [7])
        XCTAssertEqual(parser.append(shortFrame + invalidLength + oversizedLength + valid), [
            .init(command: 0x0106, sequence: 9, payload: [7])
        ])
        XCTAssertLessThanOrEqual(parser.bufferedByteCount, 1 + 3 + 7 + Int(UInt16.max))
    }

    func testMaximumUInt16PayloadIsAcceptedAndResetDiscardsPartialFrame() {
        var parser = Air7FrameParser()
        let payload = [UInt8](repeating: 0x5A, count: Int(UInt16.max))
        let bytes = frame(command: 0x0106, sequence: 10, payload: payload)
        XCTAssertEqual(parser.append(bytes).first?.payload.count, payload.count)

        XCTAssertTrue(parser.append(bytes.prefix(5)).isEmpty)
        parser.reset()
        XCTAssertEqual(parser.bufferedByteCount, 0)
        XCTAssertTrue(parser.append(bytes.suffix(from: 5)).isEmpty)
    }

    func testPendingRequestIsTakenOnlyOnceAndCloseFailsRemainingCallbacks() {
        let pending = Air7PendingRequests()
        var calls: [(UInt16, [UInt8])] = []
        pending.register(sequence: 1) { command, payload in calls.append((command, payload)) }
        let response = pending.take(sequence: 1)
        response?(0x0106, [25])
        pending.take(sequence: 1)?(0x0106, [26])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, 0x0106)
        XCTAssertEqual(calls[0].1, [25])

        pending.register(sequence: 2) { command, payload in calls.append((command, payload)) }
        let failures = pending.failAll()
        XCTAssertEqual(failures.count, 1)
        failures[0](0xFFFF, [])
        XCTAssertTrue(pending.failAll().isEmpty)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].0, 0xFFFF)
    }

    func testPendingRequestTimesOutAndReleasesItsCompletion() {
        let pending = Air7PendingRequests()
        let completed = expectation(description: "timed-out request fails once")
        var callCount = 0
        pending.register(sequence: 17, timeoutAfter: 0.02) { command, payload in
            callCount += 1
            XCTAssertEqual(command, 0xFFFF)
            XCTAssertTrue(payload.isEmpty)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
        XCTAssertNil(pending.take(sequence: 17))
        XCTAssertEqual(callCount, 1)
    }

    func testSequenceReuseFailsOldCallbackWithoutLettingItsTimeoutFailTheNewOne() {
        let pending = Air7PendingRequests()
        var oldCalls = 0
        var newCalls = 0
        pending.register(sequence: 22, timeoutAfter: 0.03) { _, _ in oldCalls += 1 }
        let replaced = pending.register(sequence: 22, timeoutAfter: 0.2) { _, _ in newCalls += 1 }
        replaced?(0xFFFF, [])
        Thread.sleep(forTimeInterval: 0.06)
        XCTAssertEqual(oldCalls, 1)
        XCTAssertEqual(newCalls, 0)
        pending.take(sequence: 22)?(0x0106, [1])
        XCTAssertEqual(newCalls, 1)
    }

    func testBatteryDecoderPreservesZeroAndRepresentsUnavailableAsMissing() {
        XCTAssertEqual(Air7BatteryDecoder.decode([2, 1, 0, 2, 55]), ["Left": 0, "Right": 55])
        XCTAssertEqual(Air7BatteryDecoder.decode([1, 2, 0]), ["Right": 0])
        XCTAssertEqual(Air7BatteryDecoder.decode([0]), [:])
        XCTAssertNil(Air7BatteryDecoder.decode([2, 1, 0]))
    }

    private func frame(command: UInt16, sequence: UInt8, payload: [UInt8]) -> [UInt8] {
        let bodyLength = 7 + payload.count
        var encodedLength: [UInt8] = []
        var remaining = bodyLength
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining > 0 { byte |= 0x80 }
            encodedLength.append(byte)
        } while remaining > 0
        return [0xAA] + encodedLength + [
            0, 0, UInt8(command & 0xFF), UInt8(command >> 8), sequence,
            UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)
        ] + payload
    }

    private func leb128(_ value: Int) -> [UInt8] {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining > 0
        return bytes
    }
}
