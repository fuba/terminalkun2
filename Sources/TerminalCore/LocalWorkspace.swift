import Foundation

/// A real, app-owned command environment; iOS does not permit spawning system shells.
public final class LocalWorkspace: @unchecked Sendable {
    public let root: URL
    public private(set) var directory: URL
    public init(root: URL) { self.root = root.resolvingSymlinksInPath(); directory = self.root }
    public func resolve(_ path: String) throws -> URL {
        let base = path == "~" ? root : (path.hasPrefix("~/") ? root.appendingPathComponent(String(path.dropFirst(2))) :
            (path.hasPrefix("/") ? root.appendingPathComponent(String(path.dropFirst())) : directory.appendingPathComponent(path)))
        let url = base.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw AppError.message("アプリの作業フォルダの外にはアクセスできません。") }
        return url
    }
    public func execute(_ line: String) async throws -> String {
        let words = try Self.lex(line)
        var output = "", pipeline: [String] = [], input = ""
        var index = 0
        while index <= words.count {
            let lexeme = index == words.count ? Token(value: ";", isOperator: true) : words[index]
            let token = lexeme.value
            if lexeme.isOperator && (token == "|" || token == ";") {
                if !pipeline.isEmpty { input = try await run(pipeline, input: input); pipeline = [] }
                if token == ";" { output += input; input = "" }
            } else if lexeme.isOperator && (token == ">" || token == ">>") {
                guard index + 1 < words.count else { throw AppError.message("保存先が必要です。") }
                if !pipeline.isEmpty { input = try await run(pipeline, input: input); pipeline = [] }
                let target = try resolve(words[index + 1].value); index += 1
                var data = token == ">>" ? ((try? Data(contentsOf: target)) ?? Data()) : Data()
                data.append(Data(input.utf8)); try data.write(to: target, options: [.atomic]); input = ""
            } else { pipeline.append(token) }
            index += 1
        }
        return output
    }
    private func run(_ words: [String], input: String) async throws -> String {
        guard let command = words.first else { return input }
        let args = Array(words.dropFirst()), fm = FileManager.default
        func source() throws -> String {
            let files = args.filter { !$0.hasPrefix("-") }
            if files.isEmpty { return input }
            return try files.map { try String(contentsOf: resolve($0), encoding: .utf8) }.joined()
        }
        switch command {
        case "help": return "pwd cd ls cat echo printf mkdir touch cp mv rm head tail grep wc sort uniq base64 date uname whoami hostname env curl clear\nパイプ | と > / >> に対応。ファイルはこのアプリの Documents 内で操作します。\n任意のシェル・開発ツールは SSH 接続先で実行できます。\n"
        case "pwd": return "/" + directory.path.dropFirst(root.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "\n"
        case "cd":
            let url = try resolve(args.first ?? "~")
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw AppError.message("ディレクトリがありません。") }
            directory = url; return ""
        case "ls":
            let folder = try resolve(args.first(where: { !$0.hasPrefix("-") }) ?? ".")
            let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]).sorted { $0.lastPathComponent < $1.lastPathComponent }
            return try files.filter { args.contains(where: { $0.contains("a") && $0.hasPrefix("-") }) || !$0.lastPathComponent.hasPrefix(".") }.map { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                return (args.contains(where: { $0.contains("l") && $0.hasPrefix("-") }) ? String(format: "%8d  ", values.fileSize ?? 0) : "") + url.lastPathComponent + (values.isDirectory == true ? "/" : "")
            }.joined(separator: "\n") + (files.isEmpty ? "" : "\n")
        case "cat": return try source()
        case "echo": return args.joined(separator: " ") + "\n"
        case "printf":
            var format = args.first ?? ""
            for value in args.dropFirst() { if let range = format.range(of: "%s") { format.replaceSubrange(range, with: value) } }
            return format.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t").replacingOccurrences(of: "\\e", with: "\u{1b}")
        case "mkdir":
            for path in args where !path.hasPrefix("-") { try fm.createDirectory(at: resolve(path), withIntermediateDirectories: args.contains("-p")) }; return ""
        case "touch":
            for path in args { let url = try resolve(path); if !fm.fileExists(atPath: url.path) { try Data().write(to: url) } else { try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path) } }; return ""
        case "cp", "mv":
            guard args.count == 2 else { throw AppError.message("コピー元とコピー先が必要です。") }
            let source = try resolve(args[0]), target = try resolve(args[1])
            if command == "cp" { try fm.copyItem(at: source, to: target) } else { try fm.moveItem(at: source, to: target) }; return ""
        case "rm":
            for path in args where !path.hasPrefix("-") {
                let url = try resolve(path)
                guard url.path != root.path, url.path != directory.path else { throw AppError.message("作業中のディレクトリは削除できません。") }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory != true || args.contains("-r") || args.contains("-rf") else { throw AppError.message("ディレクトリには -r を指定してください。") }
                try fm.removeItem(at: url)
            }; return ""
        case "head", "tail":
            var count = 10, paths = args
            if paths.first == "-n", paths.count >= 2 { count = max(0, min(100000, Int(paths[1]) ?? 10)); paths.removeFirst(2) }
            let text = paths.isEmpty ? input : try paths.map { try String(contentsOf: resolve($0), encoding: .utf8) }.joined()
            var lines = text.components(separatedBy: "\n"); if lines.last == "" { lines.removeLast() }
            return (command == "head" ? Array(lines.prefix(count)) : Array(lines.suffix(count))).joined(separator: "\n") + "\n"
        case "grep":
            let flags = args.filter { $0.hasPrefix("-") }.joined(), plain = args.filter { !$0.hasPrefix("-") }
            guard let pattern = plain.first else { throw AppError.message("検索文字列が必要です。") }
            let regex = try NSRegularExpression(pattern: pattern, options: flags.contains("i") ? [.caseInsensitive] : [])
            let text = plain.count > 1 ? try plain.dropFirst().map { try String(contentsOf: resolve($0), encoding: .utf8) }.joined() : input
            return text.components(separatedBy: "\n").filter { line in
                let matched = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                return flags.contains("v") ? !matched : matched
            }.joined(separator: "\n") + "\n"
        case "wc": let text = try source(); return "\(text.filter { $0 == "\n" }.count) \(text.split(whereSeparator: { $0.isWhitespace }).count) \(text.utf8.count)\n"
        case "sort", "uniq":
            var lines = try source().components(separatedBy: "\n"); if lines.last == "" { lines.removeLast() }
            if command == "sort" { lines.sort() } else { lines = lines.enumerated().filter { $0.offset == 0 || lines[$0.offset - 1] != $0.element }.map(\.element) }
            return lines.joined(separator: "\n") + "\n"
        case "base64":
            if args.contains("-d") { guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw AppError.message("不正な Base64 です。") }; return String(decoding: data, as: UTF8.self) }
            return Data(try source().utf8).base64EncodedString() + "\n"
        case "date": return Date().formatted(.iso8601) + "\n"
        case "uname": return "Darwin \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        case "whoami": return "mobile\n"
        case "hostname": return ProcessInfo.processInfo.hostName + "\n"
        case "env": return "HOME=/\nTERM=xterm-256color\nLANG=ja_JP.UTF-8\n"
        case "clear": return "\u{1b}[2J\u{1b}[H"
        case "curl":
            guard let text = args.last, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw AppError.message("HTTP(S) URL を指定してください。") }
            var request = URLRequest(url: url); request.timeoutInterval = 30
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var data = Data()
            for try await byte in bytes {
                guard data.count < 16 * 1024 * 1024 else { throw AppError.message("応答が 16 MiB を超えています。") }
                data.append(byte)
            }
            return String(decoding: data, as: UTF8.self)
        default: throw AppError.message("\(command): この端末内では利用できません。help でコマンドを確認するか、SSH 接続先で実行してください。")
        }
    }
    private struct Token { var value: String; var isOperator = false }
    private static func lex(_ source: String) throws -> [Token] {
        var tokens: [Token] = [], word = "", quote: Character?, escaped = false, started = false
        for char in source {
            if escaped { word.append(char); escaped = false; started = true; continue }
            if char == "\\", quote != "'" { escaped = true; continue }
            if let q = quote { if q == char { quote = nil } else { word.append(char) }; started = true; continue }
            if char == "'" || char == "\"" { quote = char; started = true }
            else if char == "`" || char == "$" { throw AppError.message("コマンド置換・変数展開は利用できません。") }
            else if char.isWhitespace || "|;>".contains(char) {
                if started { tokens.append(Token(value: word)); word = ""; started = false }
                if !char.isWhitespace {
                    if char == ">", tokens.last?.isOperator == true, tokens.last?.value == ">" { tokens[tokens.count - 1].value = ">>" } else { tokens.append(Token(value: String(char), isOperator: true)) }
                }
            } else { word.append(char); started = true }
        }
        guard quote == nil, !escaped else { throw AppError.message("引用符を閉じてください。") }
        if started { tokens.append(Token(value: word)) }; return tokens
    }
}
