import Foundation
import SofiaCore

enum EngineLibrary {
    private static let loaded: (handle: UnsafeMutableRawPointer?, error: String) = load()

    static func open() -> (handle: UnsafeMutableRawPointer?, error: String) { loaded }

    private static func load() -> (UnsafeMutableRawPointer?, String) {
        let source = Kokoro.folder.appendingPathComponent("lib")
        var files: [String: Data] = [:]
        for name in [EnginePins.main, EnginePins.runtime] {
            files[name] = try? Data(contentsOf: source.appendingPathComponent(name), options: .uncached)
        }
        if let why = EnginePins.check(files) {
            WakeLog.write("engine refused: \(why)")
            return (nil, why)
        }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("sofia-engine-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for (name, data) in files {
                let dest = dir.appendingPathComponent(name)
                guard fm.createFile(atPath: dest.path, contents: data, attributes: [.posixPermissions: 0o500]) else { throw CocoaError(.fileWriteUnknown) }
            }
        } catch {
            try? fm.removeItem(at: dir)
            return (nil, "couldn't prepare the voice engine: \(error.localizedDescription)")
        }
        let handle = dlopen(dir.appendingPathComponent(EnginePins.main).path, RTLD_NOW | RTLD_LOCAL)
        let why = handle == nil ? String(cString: dlerror()) : ""
        try? fm.removeItem(at: dir)
        return (handle, why)
    }
}
