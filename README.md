# BirdAway

A macOS menu bar app that plays a sound at configurable intervals to deter birds. Audio can be routed to a specific Bluetooth output device independently of the system default.

## Requirements

- macOS 12.0 or later
- Xcode 14 or later (for building)

## Bluetooth Speaker Setup

**Pair your speaker before launching the app.**

1. Open **System Settings → Bluetooth** and pair your speaker.
2. The speaker does **not** need to be set as the system default output — BirdAway routes audio directly to it via CoreAudio.
3. If the speaker disconnects while the app is running, you'll receive a macOS notification and can configure the fallback behavior in the menu.

## Building

1. Open `BirdAway.xcodeproj` in Xcode.
2. Select the **BirdAway** scheme and your Mac as the destination.
3. Press **⌘R** to build and run, or **⌘B** to build only.
4. The app will appear in the menu bar (no Dock icon).

To build a release archive: **Product → Archive**.

## Usage

Click the bird icon in the menu bar to access all controls:

| Menu Item | Description |
|-----------|-------------|
| **Start / Stop** | Toggle the deterrent timer |
| **Interval: N min** | Change playback interval (1–120 min, default 10) |
| **Volume** | Low / Medium / High |
| **Output Device** | Select any enumerated audio output; refreshes automatically when devices change |
| **On Device Disconnect** | Choose between *Fall Back to System Default* or *Pause Playback* |
| **Load Sound File…** | Pick a custom .mp3 / .wav / .aiff / .m4a file |
| **Play Now** | Immediately test playback through the selected device |
| **Quit BirdAway** | Quit |

Settings (interval, volume, sound path, selected device, disconnect behavior) persist across launches via `UserDefaults`.

## Audio Routing Details

BirdAway uses `AVAudioEngine` and sets `kAudioOutputUnitProperty_CurrentDevice` on the engine's output `AudioUnit` to route playback to the chosen device. The macOS system default output is never modified. CoreAudio device-change notifications (`kAudioHardwarePropertyDevices`) trigger automatic re-enumeration of the device list.

On relaunch, the app attempts to reconnect to the previously selected device by matching its `kAudioDevicePropertyDeviceUID` stored in `UserDefaults`.
