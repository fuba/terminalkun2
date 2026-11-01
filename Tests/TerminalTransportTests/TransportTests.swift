import XCTest
import Crypto
import NIO
import NIOSSH
@testable import TerminalTransport

final class TransportTests: XCTestCase {
    func testGeneratedKeyRoundtripAndSignature() throws {
        let material = try KeyMaterial.generate(name: "iPhone 日本語")
        XCTAssertTrue(material.publicKey.hasPrefix("ssh-ed25519 "))
        let key = try KeyMaterial.authentication(pem: material.privateKey, passphrase: "", user: "test")
        XCTAssertNotNil(key)
        XCTAssertFalse(material.publicKey.contains("PRIVATE"))
    }
    func testFingerprintMatchesOpenSSHFormat() {
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtdDJ9EJ1+hl8K+tMG4yWrT55IcLvuAJTjZmvqk04lF test"
        XCTAssertTrue(HostTrust.fingerprint(key).hasPrefix("SHA256:"))
        XCTAssertFalse(HostTrust.fingerprint(key).hasSuffix("="))
    }
    func testAgentSignsSelectedKeyAndRejectsMutationAndLockedUse() throws {
        let key = Curve25519.Signing.PrivateKey()
        let agent = AgentIdentity(key: .init(ed25519Key: key), comment: "test")
        var identities = agent.respond(to: ByteBuffer(bytes: [11]))
        XCTAssertEqual(identities.readInteger(as: UInt8.self), 12)
        XCTAssertEqual(identities.readInteger(as: UInt32.self), 1)
        let keySize = try XCTUnwrap(identities.readInteger(as: UInt32.self))
        let blob = try XCTUnwrap(identities.readBytes(length: Int(keySize)))
        let message = Data("real-agent-signature".utf8)
        var request = ByteBuffer(); request.writeInteger(UInt8(13)); request.writeInteger(UInt32(blob.count)); request.writeBytes(blob)
        request.writeInteger(UInt32(message.count)); request.writeBytes(message); request.writeInteger(UInt32(0))
        var response = agent.respond(to: request)
        XCTAssertEqual(response.readInteger(as: UInt8.self), 14)
        _ = response.readInteger(as: UInt32.self)
        let algorithmSize = try XCTUnwrap(response.readInteger(as: UInt32.self))
        XCTAssertEqual(response.readString(length: Int(algorithmSize)), "ssh-ed25519")
        let signatureSize = try XCTUnwrap(response.readInteger(as: UInt32.self))
        let signature = try XCTUnwrap(response.readBytes(length: Int(signatureSize)))
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: message))
        XCTAssertEqual(agent.respond(to: ByteBuffer(bytes: [17])).readableBytesView.first, 5)
        agent.setAvailable(false)
        XCTAssertEqual(agent.respond(to: request).readableBytesView.first, 5)
    }
}
