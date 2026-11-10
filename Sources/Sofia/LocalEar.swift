import Foundation
import Speech

enum LocalEar {
    static let timeout: TimeInterval = 4

    static var available: Bool { recognizer() != nil && SFSpeechRecognizer.authorizationStatus() == .authorized }

    private static func recognizer() -> SFSpeechRecognizer? {
        for id in ["en-GB", "en-US", "en-AU", "en-IE"] {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable, r.supportsOnDeviceRecognition { return r }
        }
        return nil
    }

    static func transcribe(wav: Data, hints: [String], timeout: Double = LocalEar.timeout) async -> String? {
        guard available, let recognizer = recognizer() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sofia-clip-\(UUID().uuidString).wav")
        guard (try? wav.write(to: url, options: .atomic)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = false
        req.taskHint = .dictation
        req.contextualStrings = Array(hints.prefix(100))
        if #available(macOS 13.0, *) { req.addsPunctuation = true }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { await run(recognizer, req) }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func run(_ recognizer: SFSpeechRecognizer, _ req: SFSpeechURLRecognitionRequest) async -> String? {
        final class Box: @unchecked Sendable { var task: SFSpeechRecognitionTask?; var done = false; let lock = NSLock() }
        let box = Box()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
                box.task = recognizer.recognitionTask(with: req) { result, error in
                    box.lock.lock(); defer { box.lock.unlock() }
                    guard !box.done else { return }
                    if let result, result.isFinal { box.done = true; c.resume(returning: result.bestTranscription.formattedString) }
                    else if error != nil { box.done = true; c.resume(returning: nil) }
                }
            }
        } onCancel: { box.task?.cancel() }
    }
}
