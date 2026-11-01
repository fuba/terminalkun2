import Foundation
import NIO
import NIOSSH

/// The forwarded agent exposes one selected identity and never accepts key imports or exports.
final class AgentIdentity: @unchecked Sendable {
    private let key: NIOSSHPrivateKey
    private let blob: Data
    private let comment: String
    private let rsa: Bool
    private let lock = NSLock()
    private var available = true
    private var interval = Date.timeIntervalSinceReferenceDate
    private var signatures = 0
    init(key: NIOSSHPrivateKey, comment: String) {
        self.key = key; self.comment = comment
        let text = String(openSSHPublicKey: key.publicKey).split(separator: " ")
        blob = Data(base64Encoded: String(text[1]))!
        rsa = text[0] == "ssh-rsa"
    }
    func setAvailable(_ available: Bool) { lock.lock(); self.available = available; lock.unlock() }
    func respond(to request: ByteBuffer) -> ByteBuffer {
        lock.lock(); defer { lock.unlock() }
        var input = request
        guard available, let type: UInt8 = input.readInteger() else { return ByteBuffer(bytes: [5]) }
        if type == 11, input.readableBytes == 0 {
            var reply = ByteBuffer(); reply.writeInteger(UInt8(12)); reply.writeInteger(UInt32(1))
            Self.string(blob, to: &reply); Self.string(Data(comment.utf8), to: &reply); return reply
        }
        guard type == 13, let keyBlob = Self.string(from: &input), keyBlob == blob,
              let message = Self.string(from: &input), let flags: UInt32 = input.readInteger(), input.readableBytes == 0,
              !rsa || flags == 2 || flags == 4 else { return ByteBuffer(bytes: [5]) }
        let now = Date.timeIntervalSinceReferenceDate
        if now - interval > 1 { interval = now; signatures = 0 }
        guard signatures < 30 else { return ByteBuffer(bytes: [5]) }; signatures += 1
        do {
            let signature = try key.signAgentPayload(ByteBuffer(bytes: message), flags: flags)
            var reply = ByteBuffer(); reply.writeInteger(UInt8(14)); Self.string(Data(signature.readableBytesView), to: &reply); return reply
        } catch { return ByteBuffer(bytes: [5]) }
    }
    private static func string(_ data: Data, to buffer: inout ByteBuffer) { buffer.writeInteger(UInt32(data.count)); buffer.writeBytes(data) }
    private static func string(from buffer: inout ByteBuffer) -> Data? {
        guard let size: UInt32 = buffer.readInteger(), size <= 256 * 1024, let bytes = buffer.readBytes(length: Int(size)) else { return nil }
        return Data(bytes)
    }
}

final class AgentChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    private var buffer = ByteBuffer()
    private let identity: AgentIdentity
    init(identity: AgentIdentity) { self.identity = identity }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .byteBuffer(var bytes) = unwrapInboundIn(data).data, buffer.readableBytes + bytes.readableBytes <= 512 * 1024 else { context.close(promise: nil); return }
        buffer.writeBuffer(&bytes)
        while let size: UInt32 = buffer.getInteger(at: buffer.readerIndex) {
            guard size > 0, size <= 256 * 1024 else { context.close(promise: nil); return }
            guard buffer.readableBytes >= Int(size) + 4 else { return }
            buffer.moveReaderIndex(forwardBy: 4)
            guard let request = buffer.readSlice(length: Int(size)) else { return }
            let response = identity.respond(to: request)
            var framed = ByteBuffer(); framed.writeInteger(UInt32(response.readableBytes)); framed.writeImmutableBuffer(response)
            context.writeAndFlush(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(framed))), promise: nil)
            buffer.discardReadBytes()
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}
