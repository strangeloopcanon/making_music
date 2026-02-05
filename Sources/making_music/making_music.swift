import AppKit
import UniformTypeIdentifiers

@main
struct MakingMusicApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var contentView: KeyCaptureView?
    private var controller: KeystrokeMusicController?
    private var textPerformer: TextMusicPerformer?
    private var inputRouter: InputRouter?
    private var globalListener: GlobalKeyListener?
    private var globalListeningIsEnabled = false

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var armMenuItem: NSMenuItem?
    private var globalListeningMenuItem: NSMenuItem?
    private var modeMenuItem: NSMenuItem?
    private var powerChordsMenuItem: NSMenuItem?
    private var soundMenuItem: NSMenuItem?
    private var instrumentMenuItems: [NSMenuItem] = []
    private var scaleMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        let output: NoteOutput
        do {
            output = try SamplerAudioOutput()
        } catch {
            NSAlert(error: error).runModal()
            output = ConsoleNoteOutput()
        }

        let controller = KeystrokeMusicController(output: output)
        self.controller = controller
        AppRuntime.controller = controller
        self.globalListener = GlobalKeyListener()

        let textPerformer = TextMusicPerformer(controller: controller)
        self.textPerformer = textPerformer

        let contentView = KeyCaptureView(controller: controller, textPerformer: textPerformer)
        self.contentView = contentView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidChange(_:)),
            name: .makingMusicStateDidChange,
            object: controller
        )

        let window = KeyRoutingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Making Music — Keystrokes → \(controller.instrument.rawValue)"
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)

        let inputRouter = InputRouter(controller: controller, keyCaptureView: contentView)
        window.inputRouter = inputRouter
        self.inputRouter = inputRouter

        setupStatusBar()
        syncStatusUI()

        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        AppRuntime.controller = nil
        globalListener?.stop()
    }

    @objc private func controllerDidChange(_ notification: Notification) {
        _ = notification
        syncStatusUI()
    }

    @objc private func showWindowAction(_ sender: Any?) {
        _ = sender
        showWindow()
    }

    @objc private func toggleArmedAction(_ sender: Any?) {
        _ = sender
        controller?.toggleArmed()
    }

    @objc private func toggleGlobalListeningAction(_ sender: Any?) {
        _ = sender
        globalListeningIsEnabled.toggle()
        if globalListeningIsEnabled {
            globalListener?.start()
        } else {
            globalListener?.stop()
        }
        syncStatusUI()

        if globalListeningIsEnabled {
            let alert = NSAlert()
            alert.messageText = "Global listening enabled"
            alert.informativeText = "If you don’t hear notes while typing in other apps, enable Input Monitoring for this app (or your terminal) in System Settings → Privacy & Security → Input Monitoring."
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    @objc private func toggleModeAction(_ sender: Any?) {
        _ = sender
        controller?.toggleMappingMode()
    }

    @objc private func togglePowerChordsAction(_ sender: Any?) {
        _ = sender
        controller?.togglePowerChordMode()
    }

    @objc private func chooseSoundFontAction(_ sender: Any?) {
        _ = sender
        showWindow()

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["sf2", "dls"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a SoundFont (.sf2) or DLS sound bank to improve realism."

        guard let window else {
            if panel.runModal() == .OK, let url = panel.url {
                let ok = controller?.setSoundFont(url: url) ?? false
                if !ok {
                    presentSoundFontLoadFailedAlert()
                }
            }
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { return }
            let ok = self.controller?.setSoundFont(url: url) ?? false
            if !ok {
                self.presentSoundFontLoadFailedAlert()
            }
        }
    }

    @objc private func useBuiltInSoundsAction(_ sender: Any?) {
        _ = sender
        let ok = controller?.useBuiltInSounds() ?? false
        if !ok {
            presentSoundFontNotSupportedAlert()
        }
    }

    @objc private func selectScaleAction(_ sender: NSMenuItem) {
        guard let controller else { return }
        let index = sender.tag
        guard index >= 0, index < controller.availableScales.count else { return }
        controller.setScale(controller.availableScales[index])
    }

    @objc private func selectInstrumentAction(_ sender: NSMenuItem) {
        guard let controller else { return }
        let index = sender.tag
        guard index >= 0, index < Instrument.allCases.count else { return }
        controller.setInstrument(Instrument.allCases[index])
    }

    @objc private func panicAction(_ sender: Any?) {
        _ = sender
        controller?.panicNow()
    }

    @objc private func quitAction(_ sender: Any?) {
        _ = sender
        NSApplication.shared.terminate(nil)
    }

    private func showWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "MM"
        item.menu = statusMenu
        statusItem = item

        let showWindowItem = NSMenuItem(title: "Show Window", action: #selector(showWindowAction(_:)), keyEquivalent: "")
        showWindowItem.target = self
        statusMenu.addItem(showWindowItem)

        statusMenu.addItem(.separator())

        let armItem = NSMenuItem(title: "Arm (Ctrl+Opt+Cmd+M)", action: #selector(toggleArmedAction(_:)), keyEquivalent: "")
        armItem.target = self
        statusMenu.addItem(armItem)
        armMenuItem = armItem

        let globalItem = NSMenuItem(title: "Enable Global Listening", action: #selector(toggleGlobalListeningAction(_:)), keyEquivalent: "")
        globalItem.target = self
        statusMenu.addItem(globalItem)
        globalListeningMenuItem = globalItem

        statusMenu.addItem(.separator())

        let modeItem = NSMenuItem(title: "Toggle Scale Lock / All Notes", action: #selector(toggleModeAction(_:)), keyEquivalent: "")
        modeItem.target = self
        statusMenu.addItem(modeItem)
        modeMenuItem = modeItem

        let chordsItem = NSMenuItem(title: "Power Chords", action: #selector(togglePowerChordsAction(_:)), keyEquivalent: "")
        chordsItem.target = self
        statusMenu.addItem(chordsItem)
        powerChordsMenuItem = chordsItem

        let instrumentMenu = NSMenu()
        instrumentMenuItems = []
        for (index, instrument) in Instrument.allCases.enumerated() {
            let item = NSMenuItem(title: instrument.rawValue, action: #selector(selectInstrumentAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            instrumentMenu.addItem(item)
            instrumentMenuItems.append(item)
        }

        let instrumentItem = NSMenuItem(title: "Instrument", action: nil, keyEquivalent: "")
        instrumentItem.submenu = instrumentMenu
        statusMenu.addItem(instrumentItem)

        let scaleMenu = NSMenu()
        scaleMenuItems = []
        for (index, scale) in (controller?.availableScales ?? []).enumerated() {
            let scaleItem = NSMenuItem(title: scale.name, action: #selector(selectScaleAction(_:)), keyEquivalent: "")
            scaleItem.target = self
            scaleItem.tag = index
            scaleMenu.addItem(scaleItem)
            scaleMenuItems.append(scaleItem)
        }

        let scaleItem = NSMenuItem(title: "Scale", action: nil, keyEquivalent: "")
        scaleItem.submenu = scaleMenu
        statusMenu.addItem(scaleItem)

        let soundMenu = NSMenu()
        let chooseSoundFontItem = NSMenuItem(title: "Choose SoundFont…", action: #selector(chooseSoundFontAction(_:)), keyEquivalent: "")
        chooseSoundFontItem.target = self
        soundMenu.addItem(chooseSoundFontItem)

        let builtInSoundsItem = NSMenuItem(title: "Use Built-in Sounds", action: #selector(useBuiltInSoundsAction(_:)), keyEquivalent: "")
        builtInSoundsItem.target = self
        soundMenu.addItem(builtInSoundsItem)

        let soundItem = NSMenuItem(title: "Sound: Built-in", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        statusMenu.addItem(soundItem)
        soundMenuItem = soundItem

        statusMenu.addItem(.separator())

        let panicItem = NSMenuItem(title: "Panic (all notes off)", action: #selector(panicAction(_:)), keyEquivalent: "")
        panicItem.target = self
        statusMenu.addItem(panicItem)

        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction(_:)), keyEquivalent: "")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    private func syncStatusUI() {
        guard let controller else { return }

        statusItem?.button?.title = controller.isArmed ? "MM*" : "MM"
        window?.title = "Making Music — Keystrokes → \(controller.instrument.rawValue)"

        armMenuItem?.title = controller.isArmed ? "Disarm (Ctrl+Opt+Cmd+M)" : "Arm (Ctrl+Opt+Cmd+M)"

        globalListeningMenuItem?.state = globalListeningIsEnabled ? .on : .off
        globalListeningMenuItem?.title = globalListeningIsEnabled ? "Disable Global Listening" : "Enable Global Listening"

        modeMenuItem?.title = controller.mappingMode == .musical ? "Mode: Scale Lock (toggle)" : "Mode: All Notes (toggle)"

        powerChordsMenuItem?.state = controller.powerChordModeIsOn ? .on : .off

        for (index, item) in instrumentMenuItems.enumerated() {
            let selected = index < Instrument.allCases.count && Instrument.allCases[index] == controller.instrument
            item.state = selected ? .on : .off
        }

        for (index, item) in scaleMenuItems.enumerated() {
            let selected = index < controller.availableScales.count && controller.availableScales[index] == controller.currentScale
            item.state = selected ? .on : .off
        }

        soundMenuItem?.title = "Sound: \(controller.soundSourceDisplayName)"
    }

    private func presentSoundFontNotSupportedAlert() {
        let alert = NSAlert()
        alert.messageText = "SoundFonts not supported"
        alert.informativeText = "SoundFont loading is only available when the built-in sampler output is active."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentSoundFontLoadFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Couldn’t load SoundFont"
        alert.informativeText = "Try a different .sf2 (General MIDI soundfonts usually work best). You can also switch back to built-in sounds."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
