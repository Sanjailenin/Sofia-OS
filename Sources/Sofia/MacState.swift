import AppKit
import CoreAudio
import CoreGraphics

enum MacState {
    static let ignoredAudio: Set<String> = ["com.apple.CoreSpeech", "com.apple.corespeechd", "com.apple.siri", "com.apple.assistantd",
                                            "com.apple.SpeechRecognitionCore", "com.apple.accessibility.heard"]
    static func audioSources() -> [String] {
        guard #available(macOS 14.2, *) else { return outputDeviceRunning() ? ["output device"] : [] }
        let me = getpid(), own = Bundle.main.bundleIdentifier ?? ""
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var found: [String] = []
        for id in ids {
            var running: UInt32 = 0, rsize = UInt32(MemoryLayout<UInt32>.size)
            var raddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &raddr, 0, nil, &rsize, &running) == noErr, running != 0 else { continue }
            var pid: pid_t = 0, psize = UInt32(MemoryLayout<pid_t>.size)
            var paddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyData(id, &paddr, 0, nil, &psize, &pid)
            if pid == me { continue }
            var cf: Unmanaged<CFString>?, bsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var baddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let bundle = AudioObjectGetPropertyData(id, &baddr, 0, nil, &bsize, &cf) == noErr ? (cf?.takeRetainedValue() as String? ?? "") : ""
            if bundle == own || ignoredAudio.contains(bundle) { continue }
            found.append(bundle.isEmpty ? "pid \(pid)" : bundle)
        }
        return found
    }
    static func audioPlaying() -> Bool { !audioSources().isEmpty }

    private static func outputDeviceRunning() -> Bool {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr, device != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    static func screenLocked() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if (d["CGSSessionScreenIsLocked"] as? Bool) == true { return true }
        if let onConsole = d[kCGSessionOnConsoleKey as String] as? Bool, !onConsole { return true }
        return false
    }

    static func secondsSinceKey() -> Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) }
    static func secondsSinceClick() -> Double {
        min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown))
    }
}
