import AppKit
import UserNotifications

enum DisconnectBehavior: String {
    case fallback = "fallback"   // Keep running, use system default
    case pause    = "pause"      // Stop the timer until user re-selects a device
}

class MenuBarController: NSObject, ManageSoundsDelegate {

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Menu items requiring dynamic updates
    private var startStopItem: NSMenuItem!
    private var intervalMenu:  NSMenu!
    private var outputDeviceMenu: NSMenu!
    private var volumeMenu: NSMenu!
    private var disconnectMenu: NSMenu!
    private var rotationItem: NSMenuItem!

    private static let intervalPresets = [1, 5, 10, 15, 30, 45, 60, 90, 120]

    private var isRunning = false
    private var intervalMinutes = 10
    private var timer: Timer?
    private var disconnectBehavior: DisconnectBehavior = .fallback
    private var isRotationEnabled = false
    private var soundFilePaths: [String] = []
    private var currentSoundIndex = 0

    private var manageSoundsWindowController: ManageSoundsWindowController?

    private let deviceManager = AudioDeviceManager.shared
    private let player        = AudioPlayer.shared

    override init() {
        super.init()
        loadSettings()
        buildMenu()
        setupStatusItem()
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
        if let raw = d.string(forKey: "disconnectBehavior") {
            disconnectBehavior = DisconnectBehavior(rawValue: raw) ?? .fallback
        }

        isRotationEnabled = d.bool(forKey: "isRotationEnabled")
        soundFilePaths = d.stringArray(forKey: "soundFilePaths") ?? []
        currentSoundIndex = d.integer(forKey: "currentSoundIndex")

        updatePlayerSound()
    }

    private func updatePlayerSound() {
        if soundFilePaths.isEmpty {
            player.setSoundFile(nil)
        } else {
            if currentSoundIndex >= soundFilePaths.count {
                currentSoundIndex = 0
            }
            player.setSoundFile(URL(fileURLWithPath: soundFilePaths[currentSoundIndex]))
        }
    }

    func soundListDidChange() {
        soundFilePaths = UserDefaults.standard.stringArray(forKey: "soundFilePaths") ?? []
        currentSoundIndex = 0
        UserDefaults.standard.set(0, forKey: "currentSoundIndex")
        updatePlayerSound()
    }

    private func restoreSelectedDevice() {
        guard let uid = UserDefaults.standard.string(forKey: "selectedDeviceUID"),
              let device = deviceManager.deviceWithUID(uid) else { return }
        try? player.setOutputDevice(device)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
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

        // Interval submenu
        let intervalParent = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        intervalMenu = buildIntervalMenu()
        intervalParent.submenu = intervalMenu
        menu.addItem(intervalParent)

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

        // Manage Sounds
        let manageItem = NSMenuItem(title: "Manage Sounds…", action: #selector(manageSounds), keyEquivalent: "")
        manageItem.target = self
        menu.addItem(manageItem)

        // Rotation Toggle
        rotationItem = NSMenuItem(title: "Rotation: \(isRotationEnabled ? "On" : "Off")", action: #selector(toggleRotation), keyEquivalent: "")
        rotationItem.target = self
        menu.addItem(rotationItem)

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
    }

    private func buildIntervalMenu() -> NSMenu {
        let m = NSMenu()
        for minutes in MenuBarController.intervalPresets {
            let label = minutes == 1 ? "1 min" : "\(minutes) min"
            let item = NSMenuItem(title: label, action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.state = (minutes == intervalMinutes) ? .on : .off
            m.addItem(item)
        }
        return m
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

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        intervalMinutes = minutes
        UserDefaults.standard.set(intervalMinutes, forKey: "intervalMinutes")
        intervalMenu.items.forEach { $0.state = ($0.representedObject as? Int == minutes) ? .on : .off }
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
        player.resetToSystemDefault()
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

    @objc private func manageSounds() {
        NSApp.activate(ignoringOtherApps: true)
        if manageSoundsWindowController == nil {
            manageSoundsWindowController = ManageSoundsWindowController()
            manageSoundsWindowController?.delegate = self
        }
        manageSoundsWindowController?.showWindow(nil)
    }

    @objc private func toggleRotation() {
        isRotationEnabled.toggle()
        UserDefaults.standard.set(isRotationEnabled, forKey: "isRotationEnabled")
        rotationItem.title = "Rotation: \(isRotationEnabled ? "On" : "Off")"
    }

    @objc private func playNow() {
        updatePlayerSound()
        do {
            try player.play()
        } catch {
            showErrorAlert(message: "Playback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        scheduleNextPlayback()
    }

    private func scheduleNextPlayback() {
        let baseSeconds = Double(intervalMinutes * 60)
        let randomFactor = Double.random(in: 0.7...1.3)
        let jitteredSeconds = baseSeconds * randomFactor

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: jitteredSeconds, repeats: false) { [weak self] _ in
            self?.playNextSound()
            self?.scheduleNextPlayback()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func playNextSound() {
        updatePlayerSound()
        try? player.play()

        if isRotationEnabled && !soundFilePaths.isEmpty {
            currentSoundIndex = (currentSoundIndex + 1) % soundFilePaths.count
            UserDefaults.standard.set(currentSoundIndex, forKey: "currentSoundIndex")
        }
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
            player.resetToSystemDefault()
        }

        refreshOutputDeviceMenu()
    }
}
