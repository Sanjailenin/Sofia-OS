import Foundation

public enum FilePolicy {
    public static let defaultRoots = ["Desktop", "Documents", "Downloads", "Movies", "Pictures", "Music"]
    public static let maxBytes = 100 * 1024 * 1024
    static let secretNames = try! NSRegularExpression(pattern: #"(^\.|\.(pem|key|p12|pfx|keychain(-db)?|kdbx|wallet|gpg|asc|ovpn|credentials)$|^id_(rsa|ed25519|ecdsa)|\.env(\.|$)|secret|password|token|private)"#, options: .caseInsensitive)
    static let forbiddenDirs: Set<String> = ["Library", ".ssh", ".gnupg", ".aws", ".config", ".kube", "node_modules"]

    public static func roots(from setting: String, home: String) -> [String] {
        let names = setting.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let list = names.isEmpty ? defaultRoots : names
        return list.compactMap { n in
            let p = n.hasPrefix("/") ? n : (n.hasPrefix("~") ? home + n.dropFirst() : home + "/" + n)
            let clean = (p as NSString).standardizingPath
            guard clean.hasPrefix(home + "/"), !clean.contains("/..") else { return nil }
            let parts = clean.dropFirst(home.count + 1).split(separator: "/").map(String.init)
            return parts.contains(where: { $0.hasPrefix(".") || forbiddenDirs.contains($0) }) ? nil : clean
        }
    }

    public static func refusal(forResolved path: String, roots: [String], size: Int) -> String? {
        let std = (path as NSString).standardizingPath
        guard roots.contains(where: { std == $0 || std.hasPrefix($0 + "/") }) else { return "that file isn't in a folder I'm allowed to send from" }
        let parts = std.split(separator: "/").map(String.init)
        if parts.contains(where: { forbiddenDirs.contains($0) }) { return "that folder is off limits" }
        if parts.contains(where: { $0.hasPrefix(".") }) { return "hidden files stay on the Mac" }
        let name = parts.last ?? ""
        if secretNames.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil { return "that looks like a key or a secret; it stays on the Mac" }
        if size <= 0 { return "the file is empty" }
        if size > maxBytes { return "the file is over 100 MB" }
        return nil
    }

    public static func looksSecret(_ head: Data) -> Bool {
        let s = String(decoding: head.prefix(400), as: UTF8.self)
        return s.contains("PRIVATE KEY-----") || s.range(of: #"(?m)^(AWS_SECRET|ANTHROPIC_API_KEY|OPENAI_API_KEY|[A-Z_]*TOKEN|[A-Z_]*SECRET)\s*="#, options: .regularExpression) != nil
    }

    public static func sizeText(_ bytes: Int) -> String {
        bytes >= 1_048_576 ? String(format: "%.1f MB", Double(bytes) / 1_048_576) : bytes >= 1024 ? "\(bytes / 1024) KB" : "\(bytes) B"
    }
}
