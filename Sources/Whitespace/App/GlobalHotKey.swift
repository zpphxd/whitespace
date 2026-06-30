import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon `RegisterEventHotKey` — work regardless of the
/// frontmost app and need no Accessibility permission.
///
/// IMPORTANT: there is exactly ONE installed Carbon event handler, shared across
/// all hotkeys, which dispatches by hotkey id. Installing one handler per hotkey
/// is a trap: Carbon invokes handlers last-installed-first, and a handler that
/// returns `noErr` consumes the event, so the most recently registered hotkey
/// swallows every keypress and the others never fire.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Register (or replace) a global hotkey. `id` must be unique per hotkey.
    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32,
                  action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        actions[id] = action

        if let existing = hotKeyRefs[id] {
            UnregisterEventHotKey(existing)
            hotKeyRefs[id] = nil
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x57535041), id: id) // 'WSPA'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs[id] = ref
            Log.write("HotKey id=\(id) keyCode=\(keyCode) registered OK")
            return true
        }
        Log.write("HotKey id=\(id) keyCode=\(keyCode) FAILED status=\(status)")
        return false
    }

    fileprivate func fire(id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return noErr }
                var firedID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &firedID)
                let idValue = firedID.id
                // Carbon hotkey handlers fire on the main thread.
                MainActor.assumeIsolated { HotKeyCenter.shared.fire(id: idValue) }
                return noErr
            },
            1, &eventType, nil, &handlerRef
        )
    }
}
