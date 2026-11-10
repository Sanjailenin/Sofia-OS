import AVFoundation
import AppKit
import SofiaCore

@MainActor
final class Entrance: NSObject, AVAudioPlayerDelegate {
    static let cooldown: TimeInterval = 20
    private var player: AVAudioPlayer?
    private var lastPlayed = Date.distantPast
    private var spotifyTask: Task<Void, Never>?

    var inCooldown: Bool { Date().timeIntervalSince(lastPlayed) < Self.cooldown }

    func play(_ settings: AppSettings, allowSpotify: Bool = true) {
        stop()
        lastPlayed = Date()
        if allowSpotify, let uri = SpotifyTrack.uri(from: settings.entranceSpotify) {
            playSpotify(uri, start: max(0, settings.entranceSpotifyStart), stopAfter: max(0, settings.entranceSpotifyStop), fallback: settings.entranceFile)
            return
        }
        playFile(settings.entranceFile)
    }

    private func playSpotify(_ uri: String, start: Double, stopAfter: Double, fallback: String) {
        spotifyTask = Task.detached(priority: .userInitiated) { [weak self] in
            let wasRunning = !NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.spotify.client" }.isEmpty
            let ok = (try? MacRunner.script("tell application \"Spotify\"\nactivate\nplay track \"\(uri)\"\nend tell")) != nil
            guard ok else {
                WakeLog.write("entrance: Spotify didn't play")
                await MainActor.run { [weak self] in self?.playFile(fallback) }
                return
            }
            if start > 0 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                try? MacRunner.script("tell application \"Spotify\" to set player position to \(Int(start))")
            }
            var wait = stopAfter
            if wait <= 0 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if let info = try? MacRunner.script("tell application \"Spotify\" to return ((duration of current track) as string) & \",\" & ((round (player position)) as string)") {
                    let parts = info.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if parts.count == 2, parts[0] > 0 { wait = max(1, parts[0] / 1000 - parts[1] + 0.3) }
                }
                if wait <= 0 { wait = 240 }
            }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            try? MacRunner.script("tell application \"Spotify\" to pause")
            if !wasRunning {
                try? await Task.sleep(nanoseconds: 500_000_000)
                try? MacRunner.script("tell application \"Spotify\" to quit")
            }
        }
    }

    private func playFile(_ file: String) {
        let path = (file as NSString).expandingTildeInPath
        if !path.isEmpty, FileManager.default.fileExists(atPath: path), let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
            p.delegate = self; p.volume = 0.9; player = p; p.play()
        } else {
            NSSound(named: "Hero")?.play()
        }
    }

    func stop() {
        player?.delegate = nil; player?.stop(); player = nil
        spotifyTask?.cancel(); spotifyTask = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.player = nil } }
    }
}
