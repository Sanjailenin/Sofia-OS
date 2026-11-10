import AVFoundation

enum CleanMic {
    static func enable(_ engine: AVAudioEngine) -> Bool {
        let input = engine.inputNode
        if !input.isVoiceProcessingEnabled {
            do { try input.setVoiceProcessingEnabled(true) } catch { return false }
        }
        if #available(macOS 14.0, *) {
            input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        }
        _ = engine.mainMixerNode
        return true
    }

    static func disable(_ engine: AVAudioEngine) {
        let input = engine.inputNode
        if input.isVoiceProcessingEnabled { try? input.setVoiceProcessingEnabled(false) }
    }
}

final class MonoResampler {
    let mono: AVAudioFormat
    let out: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from input: AVAudioFormat, to rate: Double = 16000) {
        guard input.sampleRate > 0, input.commonFormat == .pcmFormatFloat32,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: input.sampleRate, channels: 1, interleaved: false),
              let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: mono, to: out) else { return nil }
        self.mono = mono; self.out = out; self.converter = converter
    }

    func firstChannel(_ buf: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buf.frameLength > 0, let src = buf.floatChannelData?[0], let m = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buf.frameLength), let dst = m.floatChannelData?[0] else { return nil }
        dst.update(from: src, count: Int(buf.frameLength))
        m.frameLength = buf.frameLength
        return m
    }

    func resample(_ m: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let o = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: AVAudioFrameCount(Double(m.frameLength) * out.sampleRate / mono.sampleRate) + 16) else { return nil }
        var supplied = false
        converter.convert(to: o, error: nil) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return m
        }
        return o.frameLength > 0 ? o : nil
    }
}
