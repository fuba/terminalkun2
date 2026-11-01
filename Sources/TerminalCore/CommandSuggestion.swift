import Foundation

public enum CommandSuggestion {
    public static func offline(_ text: String) -> String? {
        let value = text.precomposedStringWithCompatibilityMapping.lowercased().filter { !$0.isWhitespace && !"。、,.!?！？".contains($0) }
        let options = [
            (["現在のディレクトリ", "今いるディレクトリ", "カレントディレクトリ"], "pwd"),
            (["ファイル一覧", "ファイルを一覧", "ディレクトリの中身", "一覧を表示"], "ls -la"),
            (["gitの状態", "gitステータス", "ギットステータス"], "git status"),
            (["ディスク使用量", "ディスクの空き容量"], "df -h"),
            (["メモリ使用量", "メモリの空き容量"], "free -h"),
            (["プロセス一覧"], "ps aux"), (["ipアドレス"], "ip addr"),
            (["現在時刻", "今日の日付"], "date"), (["ユーザー名"], "whoami"),
            (["ホスト名", "コンピューター名"], "hostname"), (["親ディレクトリに移動", "一つ上のディレクトリ"], "cd ..")
        ]
        return options.first(where: { words, _ in words.contains { value.contains($0) } })?.1
    }
    public static func generate(request text: String, endpoint: String, model: String) async throws -> String {
        guard var components = URLComponents(string: endpoint), let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, !model.isEmpty else { throw AppError.message("設定で Ollama の URL とモデル名を指定してください。") }
        if scheme == "http", host != "localhost", host != "127.0.0.1", host != "::1", !host.hasSuffix(".local"), !host.hasSuffix(".home.fuba.dev") {
            throw AppError.message("このサーバーには HTTPS URL を指定してください。")
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "/api/chat" : components.path
        guard let url = components.url else { throw AppError.message("不正な URL です。") }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false, "format": "json",
            "messages": [
                ["role": "system", "content": "Convert the user's request into one POSIX shell command. Return only JSON {\"command\":\"...\"}. Do not execute anything. Do not add newlines, terminal escape codes, markdown, or explanations. Prefer read-only commands and do not invent hostnames or paths."],
                ["role": "user", "content": text]
            ]
        ])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw AppError.message("コマンド生成サーバーがエラーを返しました。") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1024 * 1024 else { throw AppError.message("応答が大きすぎます。") }; data.append(byte)
        }
        struct Envelope: Decodable { struct Message: Decodable { var content: String }; var message: Message }
        struct Command: Decodable { var command: String }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let generated = try JSONDecoder().decode(Command.self, from: Data(envelope.message.content.utf8)).command
        guard !generated.isEmpty, generated.utf8.count <= 16384,
              !generated.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 }) else {
            throw AppError.message("単一行のコマンドとして受け取れませんでした。")
        }
        return generated
    }
}
