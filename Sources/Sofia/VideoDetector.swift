import AppKit

@MainActor
enum VideoDetector {
    static let players: Set<String> = ["com.apple.TV", "com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.colliderli.iina", "io.mpv", "com.firecore.infuse",
                                       "com.eltima.elmedia6", "com.plexapp.plex", "com.netflix.Netflix", "tv.plex.player.desktop", "com.apple.Music"]
    static func isVideoInFront() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return players.contains(id)
    }
}
