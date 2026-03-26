import AppKit
import UserNotifications
import UniformTypeIdentifiers

enum DisconnectBehavior: String {
    case fallback = "fallback"   // Keep running, use system default
    case pause    = "pause"      // Stop the timer until user re-selects a device
}

class MenuBarController: NSObject {

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Menu items requiring dynamic updates
    private var startStopItem: NSMenuItem!
    private var intervalItem:  NSMenuItem!
    private var outputDeviceMenu: NSMenu!
    private var volumeMenu: NSMenu!
    private var disconnectMenu: NSMenu!

    private var isRunning = false
    private var intervalMinutes = 10
    private var timer: Timer?
    private var disconnectBehavior: DisconnectBehavior = .fallback

    private let deviceManager = AudioDeviceManager.shared
    private let player        = AudioPlayer.shared

    override init() {
        super.init()
        loadSettings()
        setupStatusItem()
        buildMenu()
        deviceManager.delegate = self
        requestNotificationPermission()
        restoreSelectedDevice()
    }

    // MARK: - Persistence

    private func loadSettings() {
        let d = UserDefaults.standard
        if let v = d.value(forKey: "intervalMinutes") as? Int { intervalMinutes = v }
        if let raw = d.string(forKey: "volumeLevel"),
           let vol = VolumeLevel(rawValue: raw) { player.volumeLevel = vol }
        if let path = d.string(forKey: "soundFilePath") {
            player.setSoundFile(URL(fileURLWithPath: path))
        }
        if let raw = d.string(forKey: "disconnectBehavior") {
            disconnectBehavior = DisconnectBehavior(rawValue: raw) ?? .fallback
        }
    }

    private func restoreSelectedDevice() {
        guard let uid = UserDefaults.standard.string(forKey: "selectedDeviceUID"),
              let device = deviceManager.deviceWithUID(uid) else { return }
        try? player.setOutputDevice(device)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let symbolName = isRunning ? "bird.fill" : "bird"
        // bird SF Symbol is macOS 13+; fall back to speaker symbol on older systems
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BirdAway") {
            statusItem?.button?.image = img
        } else {
            let fallback = isRunning ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
            statusItem?.button?.image = NSImage(systemSymbolName: fallback, accessibilityDescription: "BirdAway")
        }
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        menu = NSMenu()

        // Start / Stop
        startStopItem = NSMenuItem(title: "Start", action: #selector(toggleRunning), keyEquivalent: "")
        startStopItem.target = self
        menu.addItem(startStopItem)

        menu.addItem(.separator())

        // Interval
        intervalItem = NSMenuItem(
            title: "Interval: \(intervalMinutes) min",
            action: #selector(changeInterval),
            keyEquivalent: ""
        )
        intervalItem.target = self
        menu.addItem(intervalItem)

        // Volume submenu
        let volumeParent = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeMenu = buildVolumeMenu()
        volumeParent.submenu = volumeMenu
        menu.addItem(volumeParent)

        // Output Device submenu
        let outputParent = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
        outputDeviceMenu = NSMenu()
        refreshOutputDeviceMenu()
        outputParent.submenu = outputDeviceMenu
        menu.addItem(outputParent)

        // On Disconnect submenu
        let disconnectParent = NSMenuItem(title: "On Device Disconnect", action: nil, keyEquivalent: "")
        disconnectMenu = buildDisconnectMenu()
        disconnectParent.submenu = disconnectMenu
        menu.addItem(disconnectParent)

        menu.addItem(.separator())

        // Load Sound File
        let loadItem = NSMenuItem(title: "Load Sound File…", action: #selector(loadSoundFile), keyEquivalent: "")
        loadItem.target = self
        menu.addItem(loadItem)

        // Play Now
        let playItem = NSMenuItem(title: "Play Now", action: #selector(playNow), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit BirdAway",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func buildVolumeMenu() -> NSMenu {
        let m = NSMenu()
        for level in VolumeLevel.allCases {
            let item = NSMenuItem(title: level.rawValue, action: #selector(setVolume(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level
            item.state = (level == player.volumeLevel) ? .on : .off
            m.addItem(item)
        }
        return m
    }

    private func buildDisconnectMenu() -> NSMenu {
        let m = NSMenu()
        let behaviors: [(String, DisconnectBehavior)] = [
            ("Fall Back to System Default", .fallback),
            ("Pause Playback", .pause)
        ]
        for (title, behavior) in behaviors {
            let item = NSMenuItem(title: title, action: #selector(setDisconnectBehavior(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = behavior
            item.state = (behavior == disconnectBehavior) ? .on : .off
            m.addItem(item)
        }
        return m
    }

    private func refreshOutputDeviceMenu() {
        outputDeviceMenu.removeAllItems()
        let selectedUID = UserDefaults.standard.string(forKey: "selectedDeviceUID")

        // "System Default" option
        let defaultItem = NSMenuItem(
            title: "System Default",
            action: #selector(selectSystemDefault),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.state = (selectedUID == nil) ? .on : .off
        outputDeviceMenu.addItem(defaultItem)

        if deviceManager.outputDevices.isEmpty {
            outputDeviceMenu.addItem(
                NSMenuItem(title: "No output devices found", action: nil, keyEquivalent: "")
            )
            return
        }

        outputDeviceMenu.addItem(.separator())
        for device in deviceManager.outputDevices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectOutputDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device
            item.state = (device.uid == selectedUID) ? .on : .off
            outputDeviceMenu.addItem(item)
        }
    }

    // MARK: - Actions

    @objc private func toggleRunning() {
        isRunning.toggle()
        if isRunning {
            startTimer()
            startStopItem.title = "Stop"
        } else {
            stopTimer()
            startStopItem.title = "Start"
        }
        updateStatusIcon()
    }

    @objc private func changeInterval() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Set Playback Interval"
        alert.informativeText = "Enter interval in minutes (1–120):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = "\(intervalMinutes)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let value = Int(field.stringValue), (1...120).contains(value) else {
            showErrorAlert(message: "Please enter a number between 1 and 120.")
            return
        }

        intervalMinutes = value
        intervalItem.title = "Interval: \(intervalMinutes) min"
        UserDefaults.standard.set(intervalMinutes, forKey: "intervalMinutes")

        if isRunning {
            stopTimer()
            startTimer()
        }
    }

    @objc private func setVolume(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? VolumeLevel else { return }
        player.volumeLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: "volumeLevel")
        volumeMenu.items.forEach { $0.state = ($0.representedObject as? VolumeLevel == level) ? .on : .off }
    }

    @objc private func selectSystemDefault() {
        UserDefaults.standard.removeObject(forKey: "selectedDeviceUID")
        // Rebuild engine to use the system default (no explicit device set)
        refreshOutputDeviceMenu()
    }

    @objc private func selectOutputDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDevice else { return }
        do {
            try player.setOutputDevice(device)
            UserDefaults.standard.set(device.uid, forKey: "selectedDeviceUID")
            refreshOutputDeviceMenu()
        } catch {
            showErrorAlert(message: "Could not route audio to \"\(device.name)\".\n\n\(error.localizedDescription)")
        }
    }

    @objc private func setDisconnectBehavior(_ sender: NSMenuItem) {
        guard let behavior = sender.representedObject as? DisconnectBehavior else { return }
        disconnectBehavior = behavior
        UserDefaults.standard.set(behavior.rawValue, forKey: "disconnectBehavior")
        disconnectMenu.items.forEach {
            $0.state = ($0.representedObject as? DisconnectBehavior == behavior) ? .on : .off
        }
    }

    @objc private func loadSoundFile() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a sound file"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        player.setSoundFile(url)
        UserDefaults.standard.set(url.path, forKey: "soundFilePath")
    }

    @objc private func playNow() {
        do {
            try player.play()
        } catch {
            showErrorAlert(message: "Playback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        let interval = TimeInterval(intervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            try? self?.player.play()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postDisconnectNotification(deviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = "BirdAway: Output Device Disconnected"
        let behaviorNote = disconnectBehavior == .fallback
            ? "Falling back to system default output."
            : "Playback paused. Re-select a device to resume."
        content.body = "\"\(deviceName)\" was disconnected. \(behaviorNote)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "disconnect-\(deviceName)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func showErrorAlert(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "BirdAway"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - AudioDeviceManagerDelegate

extension MenuBarController: AudioDeviceManagerDelegate {
    func devicesDidChange(_ manager: AudioDeviceManager) {
        refreshOutputDeviceMenu()
    }

    func deviceDidDisconnect(_ device: AudioDevice, manager: AudioDeviceManager) {
        guard device.uid == UserDefaults.standard.string(forKey: "selectedDeviceUID") else { return }

        postDisconnectNotification(deviceName: device.name)

        switch disconnectBehavior {
        case .pause:
            if isRunning { toggleRunning() }
        case .fallback:
            // Clear the saved device; engine will use system default on next play
            UserDefaults.standard.removeObject(forKey: "selectedDeviceUID")
        }

        refreshOutputDeviceMenu()
    }
}
