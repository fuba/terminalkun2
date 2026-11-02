// MIT License
import Foundation
import Darwin

public struct TailscalePeer: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let hostname: String
    public let addresses: [String]
    public let connectedToControl: Bool?
    public let authorized: Bool?
    public let lastSeen: String?
    public let os: String?
    public var online: Bool? { connectedToControl }
    public var displayName: String { hostname.isEmpty ? name : hostname }
    public var sshHost: String { addresses.first(where: { $0.contains(".") }) ?? addresses.first ?? name.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
}

public enum TailscaleClient {
    static func oauthRequest(clientID: String, secret: String) throws -> URLRequest {
        guard (1...256).contains(clientID.utf8.count), (1...4096).contains(secret.utf8.count),
              (clientID + secret).utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { throw AppError.message("OAuth クライアント ID とシークレットを確認してください。") }
        func form(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }
        var request = URLRequest(url: URL(string: "https://api.tailscale.com/api/v2/oauth/token")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("client_id=\(form(clientID))&client_secret=\(form(secret))&grant_type=client_credentials&scope=devices%3Acore%3Aread".utf8)
        return request
    }
    public static func accessToken(clientID: String, secret: String) async throws -> String {
        let data = try await perform(oauthRequest(clientID: clientID, secret: secret), limit: 16384)
        struct Response: Decodable { let access_token: String; let token_type: String }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.token_type.lowercased() == "bearer", !response.access_token.isEmpty else { throw AppError.message("OAuth トークンの形式を確認できませんでした。") }
        return response.access_token
    }
    public static func request(tailnet: String, token: String) throws -> URLRequest {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-@_")
        guard (1...253).contains(tailnet.utf8.count), tailnet != ".", tailnet != "..", tailnet.unicodeScalars.allSatisfy(allowed.contains),
              (1...4096).contains(token.utf8.count), token.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
            throw AppError.message("Tailnet 名と API アクセストークンを確認してください。")
        }
        var request = URLRequest(url: URL(string: "https://api.tailscale.com/api/v2/tailnet/\(tailnet)/devices")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public static func decode(_ data: Data) throws -> [TailscalePeer] {
        guard data.count <= 4 * 1024 * 1024 else { throw AppError.message("Tailscale の応答が大きすぎます。") }
        struct Response: Decodable { let devices: [TailscalePeer] }
        let peers = try JSONDecoder().decode(Response.self, from: data).devices
        guard peers.count <= 10000, Set(peers.map(\.id)).count == peers.count else { throw AppError.message("Tailscale の端末一覧を確認してください。") }
        for peer in peers {
            guard peer.id.utf8.count <= 256, !peer.id.isEmpty, peer.name.utf8.count <= 253, peer.hostname.utf8.count <= 253,
                  !peer.name.hasPrefix("-"), !peer.name.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
                  peer.addresses.count <= 32, peer.addresses.allSatisfy(validIP), !peer.sshHost.isEmpty else {
                throw AppError.message("Tailscale の端末アドレスが不正です。")
            }
        }
        return peers.sorted {
            if ($0.online == true) != ($1.online == true) { return $0.online == true }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
    static func validIP(_ value: String) -> Bool {
        guard value.utf8.count <= 45 else { return false }
        var v4 = in_addr(); var v6 = in6_addr()
        return value.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }

    public static func devices(tailnet: String, token: String) async throws -> [TailscalePeer] {
        try decode(await perform(request(tailnet: tailnet, token: token), limit: 4 * 1024 * 1024))
    }
    private static func perform(_ request: URLRequest, limit: Int) async throws -> Data {
        let delegate = NoRedirect()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("Tailscale の応答を確認できませんでした。") }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw AppError.message("Tailscale の認証に失敗しました。期限と devices:core:read 権限を確認してください。")
        case 429: throw AppError.message("Tailscale の取得回数制限です。しばらく待って再読み込みしてください。")
        default: throw AppError.message("Tailscale API エラー (\(http.statusCode))。時間をおいて再読み込みしてください。")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw AppError.message("Tailscale の応答が大きすぎます。") }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
