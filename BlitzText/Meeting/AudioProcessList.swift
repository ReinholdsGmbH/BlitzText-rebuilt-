import CoreAudio
import Foundation

/// Ein Prozess, den Core Audio gerade kennt, weil er Audio-IO hat oder hatte.
struct AudioProcessInfo: Equatable {
    let pid: pid_t
    let bundleIdentifier: String
    /// Der Prozess liest gerade von einem Eingabegerät, also meist vom Mikrofon.
    let isRunningInput: Bool
}

protocol AudioProcessListing {
    func processes() -> [AudioProcessInfo]
}

/// Liest `kAudioHardwarePropertyProcessObjectList` (macOS 14.2+).
///
/// Zwei Gründe, warum BlitzText das braucht:
/// 1. Browser und Teams geben Ton über Hilfsprozesse aus („Google Chrome Helper",
///    `com.microsoft.teams2.modulehost`). Ein Tap auf die PID der Haupt-App bleibt dann
///    stumm. Die Prozessliste liefert die tatsächlichen Audio-PIDs samt Bundle-ID.
/// 2. `kAudioProcessPropertyIsRunningInput` sagt, ob eine App gerade das Mikrofon
///    benutzt. „Teams läuft" ist kein Meeting, „Teams hört zu" schon.
struct CoreAudioProcessList: AudioProcessListing {

    func processes() -> [AudioProcessInfo] {
        objectIDs().compactMap { objectID in
            guard let pid: pid_t = read(objectID, kAudioProcessPropertyPID),
                  let bundleID = readString(objectID, kAudioProcessPropertyBundleID),
                  !bundleID.isEmpty
            else { return nil }
            let input: UInt32 = read(objectID, kAudioProcessPropertyIsRunningInput) ?? 0
            return AudioProcessInfo(pid: pid, bundleIdentifier: bundleID, isRunningInput: input != 0)
        }
    }

    private func objectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private func read<T>(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, value) == noErr else {
            return nil
        }
        return value.pointee
    }

    private func readString(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue()
        else { return nil }
        return string as String
    }
}

/// Ordnet Meeting-Quellen ihren Audio-Prozessen zu. Reine Logik, damit testbar.
enum MeetingAudioMatcher {

    /// App-Familien, die Audio auf Prozesse mit abweichender Bundle-ID verteilen.
    /// Alle anderen Apps zählen nur mit exakter ID oder Unter-ID (`<id>.helper`) —
    /// ein loses Präfix würde `com.google.Chrome` auch `com.google.Chromecast` zuordnen.
    private static let families: [[String]] = [
        ["us.zoom."],
        ["com.microsoft.teams"],
        ["com.cisco.webex", "com.webex."]
    ]

    static func belongs(_ process: AudioProcessInfo, to source: MeetingSource) -> Bool {
        let id = process.bundleIdentifier
        let own = source.bundleIdentifier
        if id == own || id.hasPrefix(own + ".") { return true }
        guard let family = families.first(where: { $0.contains { own.hasPrefix($0) } }) else { return false }
        return family.contains { id.hasPrefix($0) }
    }

    /// PIDs, die der Tap aufnehmen soll: die Quellen selbst plus ihre Audio-Hilfsprozesse.
    static func tapPIDs(for sources: [MeetingSource], in processes: [AudioProcessInfo]) -> [pid_t] {
        var pids = Set(sources.map(\.pid))
        for process in processes where sources.contains(where: { belongs(process, to: $0) }) {
            pids.insert(process.pid)
        }
        return pids.sorted()
    }

    /// Quellen, deren App-Familie gerade das Mikrofon benutzt. Browser-Quellen zählen
    /// immer, denn sie werden nur über den Mikrofon-/Kamera-Zusatz im Titel erkannt.
    static func activeSources(_ sources: [MeetingSource], in processes: [AudioProcessInfo]) -> [MeetingSource] {
        sources.filter { source in
            if source.kind == .browserTab { return true }
            return processes.contains { $0.isRunningInput && belongs($0, to: source) }
        }
    }
}
