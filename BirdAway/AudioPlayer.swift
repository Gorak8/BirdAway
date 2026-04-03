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

    private var engine       = AVAudioEngine()
    private var playerNode   = AVAudioPlayerNode()
    private var isPlaying    = false

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
        engine    = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        playerNode.volume = volumeLevel.floatValue
        // Prepare allocates the AudioUnit so outputNode.audioUnit is accessible
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
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to route audio to \(device.name) (err \(status))"]
            )
        }

        selectedDeviceUID = device.uid

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

    func setSoundFile(_ url: URL?) {
        soundFileURL = url
    }

    private func validateAudioFilePath(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    func play() throws {
        guard !isPlaying else { return }

        var urlToPlay: URL? = nil
        if let customURL = soundFileURL, validateAudioFilePath(customURL) {
            urlToPlay = customURL
        } else {
            // No custom sound or invalid file path — fall back to a system beep so "Play Now" is always audible
            if let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .systemDomainMask).first {
                let pingURL = libraryURL.appendingPathComponent("Sounds/Ping.aiff")
                if validateAudioFilePath(pingURL) {
                    urlToPlay = pingURL
                }
            }
        }

        guard let finalURL = urlToPlay else {
            throw BirdAwayError.fileNotFound
        }

        let audioFile = try AVAudioFile(forReading: finalURL)

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
        if playerNode.isPlaying { playerNode.stop() }
        if engine.isRunning     { engine.stop() }
        isPlaying = false
    }
}

// MARK: - Errors

enum BirdAwayError: LocalizedError {
    case audioUnitUnavailable
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .audioUnitUnavailable:
            return "The audio engine's output unit is not yet available. Try again after starting playback once."
        case .fileNotFound:
            return "The requested audio file could not be found or is invalid."
        }
    }
}
