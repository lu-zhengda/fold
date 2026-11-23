import Carbon

final class HotKey {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func register() -> Bool {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x464F4C44, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        return RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x464F4C44, id: 1), GetApplicationEventTarget(), 0, &registration) == noErr
    }

    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
    }
}
