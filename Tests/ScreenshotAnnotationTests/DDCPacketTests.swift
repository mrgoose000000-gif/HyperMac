import Testing
import Foundation
import CoreGraphics
@testable import HyperMac

@Suite struct DDCPacketTests {
    @Test func setVCPPacketHasValidChecksum() {
        let packet = DDCPacket.setVCP(code: 0x10, value: 50)
        #expect(packet.count == 6)
        #expect(Array(packet[0..<5]) == [0x84, 0x03, 0x10, 0x00, 0x32])
        // XOR toàn bộ frame (kể cả địa chỉ 0x6E và sub-address 0x51) phải bằng 0.
        #expect(packet.reduce(UInt8(0x6E ^ 0x51), ^) == 0)
    }

    @Test func setVCPSplitsHighByte() {
        let packet = DDCPacket.setVCP(code: 0x10, value: 0x0123)
        #expect(packet[3] == 0x01)
        #expect(packet[4] == 0x23)
    }

    @Test func getVCPRequestHasValidChecksum() {
        let packet = DDCPacket.getVCPRequest(code: 0x10)
        #expect(Array(packet[0..<3]) == [0x82, 0x01, 0x10])
        #expect(packet.reduce(UInt8(0x6E ^ 0x51), ^) == 0)
    }

    @Test func parsesValidReply() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x2A]
        reply.append(reply.reduce(0x50, ^))
        reply.append(0)
        let parsed = DDCPacket.parseGetVCPReply(reply, code: 0x10)
        #expect(parsed?.current == 42)
        #expect(parsed?.max == 100)
    }

    @Test func rejectsErrorWrongCodeOrGarbage() {
        let unsupported: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x64, 0x00, 0x2A, 0x00, 0x00]
        #expect(DDCPacket.parseGetVCPReply(unsupported, code: 0x10) == nil)
        let wrongCode: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x2A, 0x00, 0x00]
        #expect(DDCPacket.parseGetVCPReply(wrongCode, code: 0x10) == nil)
        #expect(DDCPacket.parseGetVCPReply([UInt8](repeating: 0, count: 12), code: 0x10) == nil)
        let zeroMax: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(DDCPacket.parseGetVCPReply(zeroMax, code: 0x10) == nil)
        #expect(DDCPacket.parseGetVCPReply([0x6E, 0x88], code: 0x10) == nil)
    }

    @Test func parsesEDIDIdentity() {
        // Dell (DEL = 0x10AC), product 0xA0C1, serial 0x12345678
        let edid: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00,
                             0x10, 0xAC, 0xC1, 0xA0, 0x78, 0x56, 0x34, 0x12]
        #expect(DDCPacket.parseEDID(edid) == .init(vendor: 0x10AC, product: 0xA0C1, serial: 0x1234_5678))
        #expect(DDCPacket.parseEDID(Array(repeating: 0, count: 16)) == nil)
    }

    @Test func matchesByEDIDIncludingIdenticalMonitors() {
        let a = DDCPacket.EDIDIdentity(vendor: 1, product: 2, serial: 0)
        let b = DDCPacket.EDIDIdentity(vendor: 3, product: 4, serial: 99)
        let mapping = DDCPacket.match(
            displays: [(10, a), (11, a), (12, b)],
            services: [b, a, a]
        )
        #expect(mapping[12] == 0)
        #expect(Set([mapping[10], mapping[11]]) == Set([1, 2]))
    }

    @Test func matchesSingleUnknownServiceToSingleDisplay() {
        let a = DDCPacket.EDIDIdentity(vendor: 1, product: 2, serial: 3)
        let mapping = DDCPacket.match(displays: [(10, a)], services: [nil])
        #expect(mapping[10] == 0)
    }

    @Test func doesNotGuessWhenAmbiguous() {
        let a = DDCPacket.EDIDIdentity(vendor: 1, product: 2, serial: 3)
        let b = DDCPacket.EDIDIdentity(vendor: 5, product: 6, serial: 7)
        let mapping = DDCPacket.match(displays: [(10, a), (11, b)], services: [nil, nil])
        #expect(mapping.isEmpty)
    }

    // MARK: - DDCFailureTracker

    @Test func singleWriteFailureDoesNotFallBack() {
        var tracker = DDCFailureTracker(threshold: 3)
        #expect(tracker.record(success: false, for: 1) == false)
        #expect(tracker.record(success: false, for: 1) == false)
    }

    @Test func fallsBackAfterConsecutiveFailures() {
        var tracker = DDCFailureTracker(threshold: 3)
        _ = tracker.record(success: false, for: 1)
        _ = tracker.record(success: false, for: 1)
        #expect(tracker.record(success: false, for: 1) == true)
    }

    @Test func successResetsFailureCount() {
        var tracker = DDCFailureTracker(threshold: 3)
        _ = tracker.record(success: false, for: 1)
        _ = tracker.record(success: false, for: 1)
        _ = tracker.record(success: true, for: 1)
        #expect(tracker.record(success: false, for: 1) == false)
        #expect(tracker.record(success: false, for: 1) == false)
    }

    @Test func failuresAreCountedPerDisplay() {
        var tracker = DDCFailureTracker(threshold: 2)
        _ = tracker.record(success: false, for: 1)
        #expect(tracker.record(success: false, for: 2) == false)
        #expect(tracker.record(success: false, for: 1) == true)
    }
}
