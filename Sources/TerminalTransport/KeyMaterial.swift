import Foundation
import Crypto
import Citadel
import NIOSSH
import NIOCore

public struct KeyMaterial: Sendable {
    public static var hardwareAvailable: Bool { SecureEnclave.isAvailable }
    public static func generateHardware(name: String) throws -> (data: Data, publicKey: String) {
        let key = try SecureEnclave.P256.Signing.PrivateKey()
        let publicKey = NIOSSHPrivateKey(secureEnclaveP256Key: key).publicKey
        return (key.dataRepresentation, String(openSSHPublicKey: publicKey) + " " + name.components(separatedBy: .newlines).joined(separator: " "))
    }
    public static func hardwareAuthentication(data: Data, user: String) throws -> SSHAuthenticationMethod {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        return .custom(HardwareAuthentication(user: user, key: NIOSSHPrivateKey(secureEnclaveP256Key: key)))
    }
    public let privateKey: String
    public let publicKey: String
    public static func generate(name: String) throws -> KeyMaterial {
        let key = Curve25519.Signing.PrivateKey()
        var blob = Data()
        func add(_ value: Data) { var count = UInt32(value.count).bigEndian; withUnsafeBytes(of: &count) { blob.append(contentsOf: $0) }; blob.append(value) }
        add(Data("ssh-ed25519".utf8)); add(key.publicKey.rawRepresentation)
        let comment = name.components(separatedBy: .newlines).joined(separator: " ")
        return KeyMaterial(privateKey: key.makeSSHRepresentation(comment: comment), publicKey: "ssh-ed25519 " + blob.base64EncodedString() + " " + comment)
    }
    public static func authentication(pem: String, passphrase: String, user: String) throws -> SSHAuthenticationMethod {
        let password = passphrase.isEmpty ? nil : Data(passphrase.utf8)
        if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: password) { return .ed25519(username: user, privateKey: key) }
        if let key = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: password) { return .rsa(username: user, privateKey: key) }
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) { return .p256(username: user, privateKey: key) }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: pem) { return .p384(username: user, privateKey: key) }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: pem) { return .p521(username: user, privateKey: key) }
        throw KeyError.invalid
    }
    static func agentKey(_ credentials: SSHCredentials) throws -> NIOSSHPrivateKey? {
        if let data = credentials.hardwareKey { return .init(secureEnclaveP256Key: try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)) }
        guard let pem = credentials.privateKey else { return nil }
        let password = credentials.passphrase.isEmpty ? nil : Data(credentials.passphrase.utf8)
        if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: password) { return .init(ed25519Key: key) }
        if let key = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: password) { return .init(custom: key) }
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) { return .init(p256Key: key) }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: pem) { return .init(p384Key: key) }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: pem) { return .init(p521Key: key) }
        throw KeyError.invalid
    }
    public static func publicKey(pem: String, passphrase: String, name: String) throws -> String {
        let password = passphrase.isEmpty ? nil : Data(passphrase.utf8)
        let key: NIOSSHPublicKey
        if let value = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: password) { key = NIOSSHPrivateKey(ed25519Key: value).publicKey }
        else if let value = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: password) { key = NIOSSHPrivateKey(custom: value).publicKey }
        else if let value = try? P256.Signing.PrivateKey(pemRepresentation: pem) { key = NIOSSHPrivateKey(p256Key: value).publicKey }
        else if let value = try? P384.Signing.PrivateKey(pemRepresentation: pem) { key = NIOSSHPrivateKey(p384Key: value).publicKey }
        else if let value = try? P521.Signing.PrivateKey(pemRepresentation: pem) { key = NIOSSHPrivateKey(p521Key: value).publicKey }
        else { throw KeyError.invalid }
        return String(openSSHPublicKey: key) + " " + name.components(separatedBy: .newlines).joined(separator: " ")
    }
    public enum KeyError: LocalizedError { case invalid; public var errorDescription: String? { "秘密鍵の形式またはパスフレーズを確認してください。Ed25519 / RSA OpenSSH と ECDSA PEM に対応しています。" } }
}

public enum HostTrust {
    public static func fingerprint(_ publicKey: String) -> String {
        let parts = publicKey.split(separator: " ")
        guard parts.count >= 2, let bytes = Data(base64Encoded: String(parts[1])) else { return "不正なホスト鍵" }
        return "SHA256:" + Data(SHA256.hash(data: bytes)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}

private final class HardwareAuthentication: NIOSSHClientUserAuthenticationDelegate {
    let user: String
    let key: NIOSSHPrivateKey
    var offered = false
    init(user: String, key: NIOSSHPrivateKey) { self.user = user; self.key = key }
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard !offered, availableMethods.contains(.publicKey) else { nextChallengePromise.succeed(nil); return }
        offered = true
        nextChallengePromise.succeed(.init(username: user, serviceName: "ssh-connection", offer: .privateKey(.init(privateKey: key))))
    }
}
