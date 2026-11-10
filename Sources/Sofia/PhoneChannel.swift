import Combine
import Foundation
import SofiaCore

@MainActor
final class PhoneChannel {
    let bot = TelegramBot()
    private let settings: AppSettings
    private let turn: AssistantTurn
    private var bag = Set<AnyCancellable>()

    init(settings: AppSettings, turn: AssistantTurn) {
        self.settings = settings; self.turn = turn
        bot.onPaired = { [weak self] chat in MainActor.assumeIsolated { self?.settings.telegramChatID = chat } }
        bot.remoteEnabled = { [weak self] in MainActor.assumeIsolated { self?.settings.remoteAccess ?? false } }
        bot.setRemoteEnabled = { [weak self] on in MainActor.assumeIsolated { self?.settings.remoteAccess = on } }
        bot.freeform = { [weak self] text in
            guard let self else { return "" }
            do { return try await self.turn.run(text, channel: "phone", provider: self.settings.phoneProviderInstance, ownerName: self.settings.ownerName, allowComputer: self.settings.allowComputer, assistantName: self.settings.assistantName).reply }
            catch { return "I couldn't reach the model: \(error.localizedDescription)" }
        }
        settings.$telegramChatID.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.start() } }.store(in: &bag)
    }

    func start() {
        bot.start(token: settings.telegramToken.read() ?? "", chatID: settings.telegramChatID, settings: settings)
    }

    var pairingCode: String { bot.pairingCode }
}
