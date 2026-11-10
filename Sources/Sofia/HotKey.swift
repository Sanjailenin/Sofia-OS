import AppKit
import Carbon.HIToolbox

final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1
    private var ref: EventHotKeyRef?
    private var id: UInt32 = 0

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.install()
        id = Self.nextID; Self.nextID += 1
        Self.handlers[id] = handler
        let hid = EventHotKeyID(signature: OSType(0x534F4649), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hid, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { Self.handlers[id] = nil; return nil }
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        Self.handlers[id] = nil
    }
    deinit { unregister() }

    private static func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hid = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hid)
            DispatchQueue.main.async { HotKey.handlers[hid.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
