import Foundation
import SofiaCore

final class MemoryStore: MemoryStoring, @unchecked Sendable {
    static let shared = MemoryStore()
    private let url: URL
    private let lock = NSLock()
    private var list: [String]

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sofia")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("memory.json")
        list = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
    }

    var facts: [String] { lock.lock(); defer { lock.unlock() }; return list }

    func remember(_ fact: String) {
        let f = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); defer { lock.unlock() }
        guard !f.isEmpty, !list.contains(where: { $0.lowercased() == f.lowercased() }) else { return }
        list.append(String(f.prefix(300)))
        if list.count > 200 { list.removeFirst(list.count - 200) }
        save()
    }

    func forget(matching words: String) -> Int {
        let needles = words.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !needles.isEmpty else { return 0 }
        lock.lock(); defer { lock.unlock() }
        let before = list.count
        list.removeAll { f in needles.allSatisfy { f.lowercased().contains($0) } }
        if list.count != before { save() }
        return before - list.count
    }

    private func save() { try? JSONEncoder().encode(list).write(to: url, options: .atomic) }
}
