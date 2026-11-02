import XCTest
@testable import TerminalCore

final class TailscaleTests: XCTestCase {
    func testActualAPIFieldNamesAndOnlineState() throws {
        let data = Data(#"{"devices":[{"id":"1","name":"owned-test.example.ts.net","hostname":"owned-test","addresses":["100.64.0.1","fd7a:115c:a1e0::1"],"connectedToControl":true,"authorized":true,"os":"linux"},{"id":"2","name":"offline.example.ts.net","hostname":"offline","addresses":[],"connectedToControl":false,"lastSeen":"2026-10-01T00:00:00Z","authorized":true}]}"#.utf8)
        let peers = try TailscaleClient.decode(data)
        XCTAssertEqual(peers.count, 2)
        XCTAssertEqual(peers[0].online, true)
        XCTAssertEqual(peers[0].sshHost, "100.64.0.1")
        XCTAssertEqual(peers[1].online, false)
        XCTAssertEqual(peers[1].sshHost, "offline.example.ts.net")
    }
    func testRequestRestrictsCredentialsToOfficialHTTPSHost() throws {
        let oauth = try TailscaleClient.oauthRequest(clientID: "test-client", secret: "test+secret&value")
        XCTAssertEqual(oauth.httpMethod, "POST")
        XCTAssertNil(oauth.url?.query)
        XCTAssertTrue(String(decoding: oauth.httpBody!, as: UTF8.self).contains("client_secret=test%2Bsecret%26value"))
        XCTAssertTrue(String(decoding: oauth.httpBody!, as: UTF8.self).contains("scope=devices%3Acore%3Aread"))
        let request = try TailscaleClient.request(tailnet: "-", token: "test-only-token")
        XCTAssertEqual(request.url?.absoluteString, "https://api.tailscale.com/api/v2/tailnet/-/devices")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-token")
        XCTAssertThrowsError(try TailscaleClient.request(tailnet: "../other", token: "test-only-token"))
        XCTAssertThrowsError(try TailscaleClient.request(tailnet: "-", token: "bad\r\nheader"))
        XCTAssertThrowsError(try TailscaleClient.decode(Data(#"{"devices":[{"id":"1","name":"-bad","addresses":["; command"],"hostname":"bad"}]}"#.utf8)))
    }
}
