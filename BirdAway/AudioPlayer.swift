import AVFoundation
import CoreAudio
import AppKit

enum VolumeLevel: String, CaseIterable {
    case low    = "Low"
    case medium = "Medium"
    case high   = "High"

    var floatValue: Float {
        switch self {
        case .low:    return 0.25
        case .medium: return 0.60
        case .high:   return 1.00
        }
    }
}

class AudioPlayer {
    static let shared = AudioPlayer()

    private var engine     = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()

    // FIX: isPlaying is always reset in stop(); no longer gets permanently stuck.
    private var isPlaying = false

    private(set) var soundFileURL: URL?
    private(set) var selectedDeviceUID: String?

    var volumeLevel: VolumeLevel = .medium {
        didSet { playerNode.volume = volumeLevel.floatValue }
    }

    init() {
        setupEngine()
    }

    // MARK: - Setup

    private func setupEngine() {
        engine     = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        playerNode.volume = volumeLevel.floatValue
        // prepare() allocates the AudioUnit so outputNode.audioUnit is accessible
        // before the engine is started for the first time.
        engine.prepare()
    }

    // MARK: - Device Routing

    /// Routes this engine's output to the given device without touching the system default.
    func setOutputDevice(_ device: AudioDevice) throws {
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw BirdAwayError.audioUnitUnavailable
        }

        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }

        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            // FIX: restart the engine so it's not left stopped on failure
            if wasRunning { try? engine.start() }
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to route audio to \(device.name) (err \(status))"]
            )
        }

        selectedDeviceUID = device.uid

        // FIX: call prepare() again after stopping so the AudioUnit is ready
        engine.prepare()

        if wasRunning {
            try engine.start()
        }
    }

    func resetToSystemDefault() {
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        isPlaying = false
        selectedDeviceUID = nil
        setupEngine()
        if wasRunning {
            try? engine.start()
        }
    }

    // MARK: - Playback

    func setSoundFile(_ url: URL) {
        soundFileURL = url
    }

    /// Plays the current sound file (or system Ping if none loaded).
    /// Throws if the file is missing or unreadable.
    func play() throws {
        guard !isPlaying else { return }

        // FIX: validate file existence before attempting to open it
        let url: URL
        if let customURL = soundFileURL {
            guard FileManager.default.fileExists(atPath: customURL.path) else {
                throw BirdAwayError.soundFileNotFound(customURL)
            }
            url = customURL
        } else {
            url = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
        }

        let audioFile = try AVAudioFile(forReading: url)

        if !engine.isRunning {
            try engine.start()
        }

        isPlaying = true
        playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
            DispatchQueue.main.async { self?.isPlaying = false }
        }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        // FIX: always reset isPlaying regardless of playerNode.isPlaying state
        isPlaying = false
    }
}

// MARK: - Errors

enum BirdAwayError: LocalizedError {
    case audioUnitUnavailable
    case soundFileNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .audioUnitUnavailable:
            return "The audio engine's output unit is not yet available. Try again after starting playback once."
        case .soundFileNotFound(let url):
            return "Sound file not found at \"\(url.lastPathComponent)\". Please load a new file."
        }
    }
}
