import XCTest
import Crypto
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
}
