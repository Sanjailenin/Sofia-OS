import Foundation
import AVFoundation
import SoundAnalysis

enum SoundClassifier {
    private final class Collector: NSObject, SNResultsObserving {
        var best: [String: Double] = [:]
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            for c in r.classifications { best[c.identifier] = max(best[c.identifier] ?? 0, c.confidence) }
        }
    }

    static let window = 0.75

    static func classify(_ samples: [Int16]) -> [String: Double]? {
        guard samples.count >= Int(16000 * window), let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let out = buffer.floatChannelData?[0],
              let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        for (i, s) in samples.enumerated() { out[i] = Float(s) / 32768 }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        request.windowDuration = CMTime(seconds: window, preferredTimescale: 16000)
        request.overlapFactor = 0.75
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let collector = Collector()
        do { try analyzer.add(request, withObserver: collector) } catch { return nil }
        analyzer.analyze(buffer, atAudioFramePosition: 0)
        analyzer.completeAnalysis()
        return collector.best
    }
}
