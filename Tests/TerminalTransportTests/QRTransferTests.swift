import XCTest
import Crypto
@testable import TerminalTransport

final class QRTransferTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let phrase = "ABCDEFGHIJKLMNOPQRSTUVWX"

    func testSharedIndependentCryptoKitVector() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tkqr1-v1", withExtension: "json", subdirectory: "Fixtures"))
        let vector = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let frame = try XCTUnwrap((vector["frames"] as? [String])?.first)
        var collector = QRTransferCollector()
        let packet = try XCTUnwrap(collector.append(frame, now: now))
        let payload = try packet.open(passphrase: phrase, now: now)
        XCTAssertEqual(String(decoding: payload.key, as: UTF8.self), "test-only-not-a-private-key")
        XCTAssertThrowsError(try KeyMaterial.publicKey(pem: String(decoding: payload.key, as: UTF8.self), passphrase: "", name: payload.name))
        let plaintext = try XCTUnwrap(vector["plaintextUTF8"] as? String)
        XCTAssertEqual(try QRKeyPayload.decode(Data(plaintext.utf8)).name, payload.name)
    }

    func testRealKeyRoundtripWithReorderedDuplicateFrames() throws {
        let material = try KeyMaterial.generate(name: "日本語の鍵")
        let payload = try QRKeyPayload(name: "日本語の鍵", format: "openssh", key: Data(material.privateKey.utf8))
        let frames = try QRTransfer.seal(payload, passphrase: phrase, now: now)
        var collector = QRTransferCollector()
        var packet: QRTransfer?
        for frame in frames.reversed() {
            packet = try collector.append(frame, now: now, uptime: 1) ?? packet
            _ = try collector.append(frame, now: now, uptime: 2)
        }
        let decoded = try XCTUnwrap(packet).open(passphrase: phrase, now: now)
        XCTAssertEqual(decoded.key, payload.key)
        XCTAssertEqual(decoded.name, payload.name)
        XCTAssertEqual(try KeyMaterial.publicKey(pem: String(decoding: decoded.key, as: UTF8.self), passphrase: "", name: decoded.name), material.publicKey)
        XCTAssertThrowsError(try packet?.open(passphrase: "ZYXWVUTSRQPONMLKJIHGFEDC", now: now))
        XCTAssertThrowsError(try packet?.open(passphrase: phrase, now: now.addingTimeInterval(361)))
    }

    func testBoundedCollectionRejectsMixingAndExpires() throws {
        let payload = try QRKeyPayload(name: "test", format: "pem", key: Data(repeating: 65, count: 3000))
        let a = try QRTransfer.seal(payload, passphrase: phrase, now: now)
        let b = try QRTransfer.seal(payload, passphrase: phrase, now: now)
        XCTAssertGreaterThan(a.count, 1)
        var collector = QRTransferCollector()
        XCTAssertNil(try collector.append(a[0], now: now, uptime: 10))
        XCTAssertThrowsError(try collector.append(b[1], now: now, uptime: 11))
        XCTAssertThrowsError(try collector.append(a[1], now: now, uptime: 311))
        XCTAssertThrowsError(try QRTransferCollector.Frame(String(repeating: "A", count: 769)))
        XCTAssertThrowsError(try QRTransferCollector.Frame(a[0].replacingOccurrences(of: "/1/", with: "/01/")))
    }

    func testPayloadRejectsDuplicateKeysAndInvalidMetadata() throws {
        XCTAssertThrowsError(try QRKeyPayload.decode(Data(#"{"kind":"ssh-private-key","kind":"ssh-private-key","name":"test","format":"pem","key":"QQ"}"#.utf8)))
        XCTAssertThrowsError(try QRKeyPayload(name: "bad\nname", format: "pem", key: Data([1])))
        XCTAssertThrowsError(try QRKeyPayload(name: "test", format: "pem", key: Data(repeating: 0, count: 16385)))
        XCTAssertThrowsError(try QRTransfer.decodeBase64URL("QR"))
    }

    func testTamperAndConflictingFrameAreRejected() throws {
        let payload = try QRKeyPayload(name: "test", format: "pem", key: Data(repeating: 65, count: 2000))
        let frames = try QRTransfer.seal(payload, passphrase: phrase, now: now)
        var collector = QRTransferCollector()
        _ = try collector.append(frames[0], now: now)
        var parts = frames[0].components(separatedBy: "/")
        parts[5] = "B" + parts[5].dropFirst()
        XCTAssertThrowsError(try collector.append(parts.joined(separator: "/"), now: now))
        var raw = try QRTransfer.decodeBase64URL(frames.map { $0.components(separatedBy: "/")[5] }.joined())
        raw[raw.count - 1] ^= 1
        let packet = try QRTransfer(raw, now: now)
        XCTAssertThrowsError(try packet.open(passphrase: phrase, now: now))
    }
}
