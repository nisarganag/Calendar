import AppKit
import Carbon.HIToolbox

// MARK: - System-wide hotkey
//
// Carbon's RegisterEventHotKey rather than NSEvent.addGlobalMonitorForEvents,
// because the global monitor needs Accessibility permission to see key events
// and this does not. For an ad-hoc-signed menu bar app, staying prompt-free is
// worth more than using the newer API.

final class HotKey {

    /// ⌃⌥C — Control-Option is a sparse namespace on macOS, so collisions are
    /// unlikely. Deliberately fixed: changing it means editing these two
    /// constants, which is the trade we made for dropping a recorder UI.
    static let defaultKeyCode = UInt32(kVK_ANSI_C)
    static let defaultModifiers = UInt32(controlKey | optionKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// Four-char code identifying our hot key, so the handler ignores anyone
    /// else's.
    private static let signature: OSType = 0x43_42_48_4B  // 'CBHK'

    /// Registers the hotkey. Returns false if the combination is already taken
    /// by another application, in which case CalBar carries on without it
    /// rather than failing to launch.
    @discardableResult
    func register(
        keyCode: UInt32 = HotKey.defaultKeyCode,
        modifiers: UInt32 = HotKey.defaultModifiers,
        action: @escaping () -> Void
    ) -> Bool {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                guard status == noErr, id.signature == HotKey.signature else { return noErr }
                Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action?()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else {
            self.action = nil
            return false
        }

        let registered = RegisterEventHotKey(
            keyCode, modifiers,
            EventHotKeyID(signature: HotKey.signature, id: 1),
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registered == noErr else {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        action = nil
    }

    deinit { unregister() }
}
