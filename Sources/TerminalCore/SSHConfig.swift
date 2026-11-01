import Foundation

public enum SSHConfig {
    public struct Result { public var profiles: [ConnectionProfile]; public var warnings: [String] }
    private struct Block { var patterns: [String]; var options: [(String, String)] }
    public static func parse(_ source: String) throws -> Result {
        var blocks = [Block(patterns: ["*"], options: [])]
        var names: [String] = []
        var warnings: [String] = []
        for (number, line) in source.components(separatedBy: .newlines).enumerated() {
            let tokens = try tokenize(line)
            guard let first = tokens.first else { continue }
            let key = first.lowercased()
            let values = Array(tokens.dropFirst())
            if key == "host" {
                blocks.append(Block(patterns: values, options: []))
                for value in values where !value.contains(where: { "*?!".contains($0) }) {
                    if !names.contains(value) { names.append(value) }
                }
            } else if key == "include" || key == "match" {
                warnings.append("\(number + 1)行: \(first) は個別にインポートしてください。")
                if key == "match" { blocks.append(Block(patterns: [], options: [])) }
            } else if let value = values.first {
                blocks[blocks.count - 1].options.append((key, values.joined(separator: " ")))
                if key == "proxycommand" || key == "localcommand" || key == "remotecommand" {
                    warnings.append("\(number + 1)行: \(first) は自動実行しません。")
                }
                _ = value
            }
        }
        let profiles = names.map { name in
            var options: [String: String] = [:]
            for block in blocks where matches(block.patterns, name) {
                for (key, value) in block.options where options[key] == nil { options[key] = value }
            }
            let unsupported = ["proxycommand", "localcommand", "remotecommand"].filter { options[$0] != nil }
            let host = (options["hostname"] ?? name).replacingOccurrences(of: "%h", with: name)
            return ConnectionProfile(name: name, host: host, user: options["user"] ?? "", port: Int(options["port"] ?? "22") ?? 0,
                                     jumpHost: options["proxyjump"] == "none" ? nil : options["proxyjump"], unsupportedOptions: unsupported)
        }
        return Result(profiles: profiles, warnings: warnings)
    }
    private static func matches(_ patterns: [String], _ value: String) -> Bool {
        var included = false
        for pattern in patterns {
            let negative = pattern.hasPrefix("!")
            let glob = negative ? String(pattern.dropFirst()) : pattern
            let regex = "^" + NSRegularExpression.escapedPattern(for: glob).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
            if value.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil {
                if negative { return false }; included = true
            }
        }
        return included
    }
    public static func tokenize(_ line: String) throws -> [String] {
        var result: [String] = [], token = "", quote: Character?, escaped = false, started = false
        for character in line {
            if escaped { token.append(character); escaped = false; started = true; continue }
            if character == "\\", quote != "'" { escaped = true; continue }
            if let current = quote {
                if current == character { quote = nil } else { token.append(character) }; started = true; continue
            }
            if character == "\"" || character == "'" { quote = character; started = true }
            else if character == "#" { break }
            else if character.isWhitespace || (character == "=" && result.isEmpty) {
                if started { result.append(token); token = ""; started = false }
            } else { token.append(character); started = true }
        }
        guard quote == nil, !escaped else { throw AppError.message("引用符またはエスケープが閉じていません。") }
        if started { result.append(token) }
        return result
    }
}
