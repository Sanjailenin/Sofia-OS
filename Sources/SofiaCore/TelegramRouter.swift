import Foundation

public struct TelegramState: Equatable {
    public var pairedChat: Int
    public var pairingCode: String
    public var remoteEnabled: Bool
    public var wrongCodes: Int
    public var lockedUntil: Date?
    public init(pairedChat: Int = 0, pairingCode: String = "", remoteEnabled: Bool = true, wrongCodes: Int = 0, lockedUntil: Date? = nil) {
        self.pairedChat = pairedChat; self.pairingCode = pairingCode; self.remoteEnabled = remoteEnabled; self.wrongCodes = wrongCodes; self.lockedUntil = lockedUntil
    }
}

public enum TelegramDecision: Equatable {
    case ignore
    case reply(String)
    case paired(Int, String)
    case command(RemoteCommand)
    case setRemote(Bool, String)
    case freeform(String)
}

public enum TelegramRouter {
    public static let maxWrongCodes = 5
    public static let lockout: TimeInterval = 3600

    public static func route(_ u: TelegramUpdate, state: inout TelegramState, now: Date = Date()) -> TelegramDecision {
        guard !u.text.isEmpty else { return .ignore }
        guard u.chatType == "private" else { return state.pairedChat == 0 ? .reply("I only pair with a private chat. Message me directly, not from a group.") : .ignore }
        if state.pairedChat == 0 {
            if let until = state.lockedUntil, now < until { return .ignore }
            state.lockedUntil = nil
            if Pairing.isCode(u.text, state.pairingCode) {
                state.pairedChat = u.chatID; state.pairingCode = ""; state.wrongCodes = 0
                return .paired(u.chatID, "Paired. This chat can now reach the Mac. Send “help” to see what I can do.")
            }
            state.wrongCodes += 1
            if state.wrongCodes >= maxWrongCodes { state.lockedUntil = now.addingTimeInterval(lockout); state.wrongCodes = 0; return .reply("Too many wrong codes. Pairing is paused for an hour.") }
            return .reply("Not paired. Open \(WakeWord.current.name)'s Settings on the Mac and send me the six-digit code shown there.")
        }
        guard u.chatID == state.pairedChat else { return .ignore }
        if let command = RemoteCommand.parse(u.text) {
            switch command {
            case .stopRemote: state.remoteEnabled = false; return .setRemote(false, "Remote access is off until you send “start remote”.")
            case .startRemote: state.remoteEnabled = true; return .setRemote(true, "Remote access is on.")
            default: break
            }
            guard state.remoteEnabled else { return .reply("Remote access is off. Send “start remote” to turn it on.") }
            return .command(command)
        }
        guard state.remoteEnabled else { return .reply("Remote access is off. Send “start remote” to turn it on.") }
        return .freeform(u.text)
    }

    public static func backoff(failures: Int, jitter: Double) -> TimeInterval {
        let base = min(60, 5 * Double(max(1, failures)))
        return base + base * 0.3 * max(0, min(1, jitter))
    }
}
