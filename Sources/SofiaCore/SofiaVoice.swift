import Foundation

public struct SofiaVoice: Sendable, Equatable, Identifiable {
    public enum Gender: String, Sendable { case woman, man }

    public let id: String
    public let name: String
    public let gender: Gender
    public let speaker: Int32
    public let speed: Float
    public let appleFallback: [String]

    public static let all: [SofiaVoice] = [
        SofiaVoice(id: "af_heart", name: "Heart", gender: .woman, speaker: 3, speed: 0.8, appleFallback: womenOnMac),
        SofiaVoice(id: "af_kore", name: "Kore", gender: .woman, speaker: 5, speed: 0.8, appleFallback: womenOnMac),
        SofiaVoice(id: "af_sarah", name: "Sarah", gender: .woman, speaker: 9, speed: 0.8, appleFallback: womenOnMac),
        SofiaVoice(id: "af_aoede", name: "Aoede", gender: .woman, speaker: 1, speed: 0.825, appleFallback: womenOnMac),
        SofiaVoice(id: "am_puck", name: "Puck", gender: .man, speaker: 18, speed: 0.75, appleFallback: menOnMac),
        SofiaVoice(id: "am_fenrir", name: "Fenrir", gender: .man, speaker: 14, speed: 0.8, appleFallback: menOnMac),
    ]
    public static let standard = all[0]

    static let womenOnMac = ["Samantha", "Karen", "Moira", "Tessa"]
    static let menOnMac = ["Daniel", "Rishi", "Fred"]

    public static func resolve(_ stored: String) -> SofiaVoice {
        let key = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.id == key || $0.name.lowercased() == key } ?? standard
    }

    public var label: String { "\(name) · \(gender == .woman ? "woman" : "man")" }
}

public enum WaveFile {
    public static func pcm16(_ samples: [Float], sampleRate: Int) -> Data {
        var d = Data(capacity: 44 + samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
        return d
    }
}
