import Foundation
import AppKit
import CoreAudio
import Combine
import IOBluetooth
import AVFoundation
@preconcurrency import UserNotifications

enum Air7NoiseMode: String, CaseIterable, Identifiable {
    case noiseCancellation = "Noise Cancellation"
    case normal = "Normal mode"
    case transparency = "Transparency mode"
    var id: String { rawValue }
}

/// Charging is intentionally separate from battery level. The current Air 7
/// OPOv1 battery payload reports percentages only, so these remain unknown
/// until a verified protocol field is available.
enum Air7ChargingState: Equatable {
    case charging
    case notCharging
    case unknown

    var menuLabel: String {
        switch self {
        case .charging: "Charging"
        case .notCharging: "Not charging"
        case .unknown: "Charging status unavailable"
        }
    }
}

enum Air7ANCStrength: String, CaseIterable, Identifiable {
    case smart = "Smart"
    case max = "Max"
    case moderate = "Moderate"
    case mild = "Mild"
    var id: String { rawValue }

    // OPOv1 mode values. These are scalar values, not bit positions.
    var protocolValue: UInt8 {
        switch self {
        case .mild: 0x04
        case .max: 0x08
        case .moderate: 0x10
        case .smart: 0x20
        }
    }
}

struct Air7EQPreset: Identifiable {
    let title: String
    let id: UInt8
}

private final class BudsLink: NSObject, IOBluetoothRFCOMMChannelDelegate, IOBluetoothDeviceAsyncCallbacks {
    var onFrame: ((UInt16, [UInt8]) -> Void)?
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = Air7FrameParser()
    private var sequence: UInt8 = 1
    private let callbacks = Air7PendingRequests()
    private let stateLock = NSLock()
    private var sdpCompletion: ((String?) -> Void)?
    private var sdpTimeout: DispatchWorkItem?

    func connect(preferredName: String?, audioUID: String?, completion: @escaping (String?) -> Void) {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let audioAddress = Self.bluetoothAddress(in: audioUID ?? "")
        let knownAddress = UserDefaults.standard.string(forKey: "air7.bluetoothAddress")
        let byKnownAddress = knownAddress.flatMap { address in devices.first(where: { ($0.addressString ?? "").caseInsensitiveCompare(address) == .orderedSame && $0.isConnected() }) }
        let byAudioRoute = audioAddress.flatMap { address in devices.first(where: { ($0.addressString ?? "").lowercased() == address.lowercased() && $0.isConnected() }) }
        let preferred = Self.normalizedDeviceName(preferredName ?? "")
        let named = devices.first(where: { d in
            let name = Self.normalizedDeviceName(d.name ?? "")
            return d.isConnected() && Self.isAir7Name(name, preferredName: preferred)
        })
        let connected = devices.filter { $0.isConnected() }
        NSLog("Air7Menu Bluetooth lookup: paired=%d connected=%d routeAddress=%d namedMatch=%d", devices.count, connected.count, audioAddress == nil ? 0 : 1, named == nil ? 0 : 1)
        guard let candidate = byKnownAddress ?? byAudioRoute ?? named else {
            completion("Could not match the active audio route to a paired Bluetooth device. Keep the Air 7 connected and try Refresh."); return
        }
        guard !(candidate.addressString ?? "").isEmpty else {
            completion("macOS reports Doraemon as an audio output, but IOBluetooth has no device address for it. Remove and re-pair it in System Settings → Bluetooth, then retry."); return
        }
        UserDefaults.standard.set(candidate.addressString, forKey: "air7.bluetoothAddress")
        device = candidate
        NSLog("Air7Menu Bluetooth target: namePresent=%d addressPresent=%d", (candidate.name ?? "").isEmpty ? 0 : 1, (candidate.addressString ?? "").isEmpty ? 0 : 1)
        stateLock.lock()
        sdpTimeout?.cancel()
        sdpCompletion = completion
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishSDP("Bluetooth service discovery timed out. Reconnect the earbuds and retry.")
        }
        sdpTimeout = timeout
        stateLock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        // Ask for the complete SDP database. Some Realme firmware does not
        // answer filtered service searches, even though its full SDP database
        // advertises the control service.
        let result = candidate.performSDPQuery(self)
        NSLog("Air7Menu SDP query start result=%d", result)
        guard result == kIOReturnSuccess else {
            finishSDP("Bluetooth service discovery failed (\(result)). Check that Doraemon is still connected.")
            return
        }
    }

    private static let controlServiceUUIDs = [
        IOBluetoothSDPUUID(data: Data([0x00,0x00,0x07,0x9A,0xD1,0x02,0x11,0xE1,0x9B,0x23,0x00,0x02,0x5B,0x00,0xA5,0xA5])),
        IOBluetoothSDPUUID(data: Data([0x00,0x00,0x11,0x07,0xD1,0x02,0x11,0xE1,0x9B,0x23,0x00,0x02,0x5B,0x00,0xA5,0xA5]))
    ]

    private static func bluetoothAddress(in value: String) -> String? {
        let pattern = #"(?i)([0-9a-f]{2})[:-]([0-9a-f]{2})[:-]([0-9a-f]{2})[:-]([0-9a-f]{2})[:-]([0-9a-f]{2})[:-]([0-9a-f]{2})"#
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        return value[range].replacingOccurrences(of: "-", with: ":")
    }

    private static func normalizedDeviceName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isAir7Name(_ name: String, preferredName: String) -> Bool {
        name == "doraemon"
            || name.contains("realme buds air 7")
            || name.contains("realme buds air7")
            || name.contains("air 7")
            || name.contains("air7")
            || (!preferredName.isEmpty && name == preferredName)
    }
    @objc(sdpQueryComplete:status:)
    func sdpQueryComplete(_ queried: IOBluetoothDevice!, status: IOReturn) {
        NSLog("Air7Menu SDP callback status=%d", status)
        guard status == kIOReturnSuccess, let queried else {
            NSLog("Air7Menu SDP did not return a device (status=%d)", status)
            finishSDP("The earbuds do not expose the companion control service to this Mac.")
            return
        }
        let records = Self.controlServiceUUIDs.compactMap { queried.getServiceRecord(for: $0) }
        NSLog("Air7Menu control service records=%d", records.count)
        guard let record = records.first else {
            finishSDP("The earbuds responded to Bluetooth discovery, but did not advertise the Air 7 companion control service. macOS audio output works; device controls require that service.")
            return
        }
        var rfcommID = BluetoothRFCOMMChannelID(0)
        let channelResult = record.getRFCOMMChannelID(&rfcommID)
        NSLog("Air7Menu RFCOMM channel lookup result=%d channel=%d", channelResult, rfcommID)
        guard channelResult == kIOReturnSuccess else {
            finishSDP("Could not find the earbuds’ control channel.")
            return
        }
        var opened: IOBluetoothRFCOMMChannel?
        let result = queried.openRFCOMMChannelSync(&opened, withChannelID: rfcommID, delegate: self)
        NSLog("Air7Menu RFCOMM open result=%d channelOpened=%d", result, opened == nil ? 0 : 1)
        guard result == kIOReturnSuccess, let opened else {
            finishSDP("Could not open the earbuds’ control channel (Bluetooth permission or connection may be needed).")
            return
        }
        stateLock.lock()
        channel = opened
        stateLock.unlock()
        finishSDP(nil)
    }

    private func finishSDP(_ error: String?) {
        stateLock.lock()
        let completion = sdpCompletion
        sdpCompletion = nil
        sdpTimeout?.cancel()
        sdpTimeout = nil
        stateLock.unlock()
        completion?(error)
    }

    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}

    func request(_ command: UInt16, payload: [UInt8] = [], completion: ((UInt16, [UInt8]) -> Void)? = nil) {
        // RFCOMM writeSync accepts the complete frame size as UInt16. Include
        // the start byte, up to three LEB128 length bytes, and fixed header.
        guard payload.count <= Int(UInt16.max) - 11 else {
            NSLog("Air7Menu rejected an RFCOMM request too large for writeSync")
            completion?(0xFFFF, [])
            return
        }
        stateLock.lock()
        guard let channel else {
            stateLock.unlock()
            completion?(0xFFFF, [])
            return
        }
        let seq = sequence; sequence = sequence == 0xFE ? 1 : sequence &+ 1
        let replacedCallback: ((UInt16, [UInt8]) -> Void)?
        if let completion {
            replacedCallback = callbacks.register(sequence: seq, completion: completion)
        } else {
            replacedCallback = nil
        }
        stateLock.unlock()
        replacedCallback?(0xFFFF, [])

        var frame: [UInt8] = [0xAA]
        frame += Self.leb128(7 + payload.count)
        frame += [0, 0, UInt8(command & 0xFF), UInt8(command >> 8), seq,
                  UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + payload
        let writeResult = frame.withUnsafeMutableBufferPointer { p -> IOReturn in
            guard let base = p.baseAddress else { return kIOReturnError }
            return channel.writeSync(base, length: UInt16(p.count))
        }
        if writeResult != kIOReturnSuccess {
            let pending = callbacks.take(sequence: seq)
            pending?(0xFFFF, [])
            NSLog("Air7Menu RFCOMM write failed for command=0x%04X status=%d", command, writeResult)
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard length > 0, let pointer else { return }
        let bytes = Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: length))
        stateLock.lock()
        let frames = parser.append(bytes)
        var completions: [((UInt16, [UInt8]) -> Void, Air7FrameParser.Frame)] = []
        var pushFrames: [Air7FrameParser.Frame] = []
        for frame in frames {
            if let callback = callbacks.take(sequence: frame.sequence) {
                completions.append((callback, frame))
            } else {
                pushFrames.append(frame)
            }
        }
        let pushHandler = onFrame
        stateLock.unlock()

        completions.forEach { callback, frame in callback(frame.command, frame.payload) }
        pushFrames.forEach { pushHandler?($0.command, $0.payload) }
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        stateLock.lock()
        channel = nil
        parser.reset()
        let pending = callbacks.failAll()
        stateLock.unlock()
        // 0xFFFF with an empty payload is the local transport-failure sentinel.
        // Removing callbacks under the lock before invoking them ensures a
        // racing response or second close cannot complete one twice.
        pending.forEach { $0(0xFFFF, []) }
    }
    private static func leb128(_ value: Int) -> [UInt8] {
        var n = value, bytes = [UInt8]()
        repeat { var b = UInt8(n & 0x7F); n >>= 7; if n > 0 { b |= 0x80 }; bytes.append(b) } while n > 0
        return bytes
    }
}

@MainActor
final class EarbudModel: ObservableObject {
    var onConnectionDetected: (() -> Void)?
    var onTargetEarbudDisconnected: (() -> Void)?
    @Published private(set) var outputName: String?
    @Published private(set) var outputUID: String?
    @Published private(set) var connected = false
    @Published private(set) var bluetoothOutput = false
    @Published var launchAtLogin = true
    @Published var showOnConnection = true
    @Published private(set) var controlStatus = "Connect the Air 7 to enable controls."
    @Published private(set) var noiseMode: Air7NoiseMode?
    @Published private(set) var ancStrength: Air7ANCStrength?
    @Published private(set) var spatialAvailable = false
    @Published private(set) var spatialEnabled: Bool?
    @Published private(set) var eqPreset: String?
    @Published private(set) var eqAvailable = false
    @Published private(set) var battery: [String: Int] = [:]
    /// The Air 7 battery payload does not provide a verified charging state.
    @Published private(set) var chargingState: [String: Air7ChargingState] = [
        "Case": .unknown, "Left": .unknown, "Right": .unknown
    ]
    private let buds = BudsLink()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var controlReady = false
    private var connectingControls = false
    private var productReplyPending = false
    private var syncing = false
    private var settingMaximumANC = false
    /// Highest alert stage already reached by each earbud: 30 means above 20%,
    /// 20 means the low-battery alert was reached, and 10 means critical.
    private var batteryAlertStage: [String: Int] = [:]
    private var connectionPopupPending = false
    private var connectionNotificationPending = false
    private var earbudBluetoothConnected = false
    private var disconnectTask: Task<Void, Never>?
    private var bluetoothPowerNotificationObservers: [NSObjectProtocol] = []
    private var bluetoothConnectNotification: IOBluetoothUserNotification?
    private var bluetoothDisconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private let bluetoothAddressKey = "air7.bluetoothAddress"
    private let connectionEventTimestampKey = "air7.connectionEventTimestamp"
    private let connectionEventNameKey = "air7.connectionEventName"
    private let connectionNotification = Notification.Name("com.local.air7menu.earbudsConnected")
    private var monitorConnectionObserver: NSObjectProtocol?

    var isConnected: Bool { earbudBluetoothConnected }
    var canControl: Bool { controlReady }
    var connectionText: String {
        isConnected ? "Connected" : "Disconnected"
    }
    let eqPresets = [
        Air7EQPreset(title: "Serenade", id: 0),
        Air7EQPreset(title: "Original Sound", id: 1),
        Air7EQPreset(title: "Pure Bass", id: 2),
        Air7EQPreset(title: "Deep Bass", id: 3)
    ]

    init() {
        let defaults = UserDefaults.standard
        showOnConnection = defaults.object(forKey: "air7.showPopupOnConnection") as? Bool
            ?? defaults.object(forKey: "air7.autoLaunchMonitor") as? Bool
            ?? true
        defaults.set(showOnConnection, forKey: "air7.showPopupOnConnection")
        configureBluetoothMonitor()
        buds.onFrame = { [weak self] cmd, payload in Task { @MainActor in self?.handlePush(cmd, payload) } }
        refreshOutput()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in Task { @MainActor in self?.refreshOutput() } }
        monitorConnectionObserver = DistributedNotificationCenter.default().addObserver(
            forName: connectionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMonitorConnectionEvent() }
        }
        observeBluetoothPowerChanges()
        startBluetoothMonitoring()
    }

    private func observeBluetoothPowerChanges() {
        let center = NotificationCenter.default
        let poweredOff = Notification.Name.IOBluetoothHostControllerPoweredOff
        let poweredOn = Notification.Name.IOBluetoothHostControllerPoweredOn

        bluetoothPowerNotificationObservers.append(center.addObserver(
            forName: poweredOff,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.disconnectTask?.cancel()
                self.disconnectTask = nil
                NSLog("Air7Menu detected Bluetooth power off; quitting the app")
                self.onTargetEarbudDisconnected?()
                NSApplication.shared.terminate(nil)
            }
        })

        bluetoothPowerNotificationObservers.append(center.addObserver(
            forName: poweredOn,
            object: nil,
            queue: .main
        ) { _ in
            NSLog("Air7Menu detected Bluetooth power on")
        })
    }

    private func startBluetoothMonitoring() {
        bluetoothConnectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(earbudDidConnect(_:device:))
        )
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        for device in paired where isTargetEarbud(device) {
            watchDisconnect(for: device)
            if device.isConnected() { updateEarbudConnection(true, name: device.name) }
        }
    }

    private func isTargetEarbud(_ device: IOBluetoothDevice) -> Bool {
        let address = device.addressString ?? ""
        if let known = UserDefaults.standard.string(forKey: bluetoothAddressKey),
           !address.isEmpty, address.caseInsensitiveCompare(known) == .orderedSame { return true }
        let name = (device.name ?? "").lowercased()
        return name == "doraemon" || name.contains("realme buds air 7") || name.contains("realme buds air7")
    }

    private func watchDisconnect(for device: IOBluetoothDevice) {
        guard let address = device.addressString, bluetoothDisconnectNotifications[address] == nil else { return }
        UserDefaults.standard.set(address, forKey: bluetoothAddressKey)
        bluetoothDisconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(earbudDidDisconnect(_:device:))
        )
    }

    @objc private func earbudDidConnect(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device, isTargetEarbud(device) else { return }
        watchDisconnect(for: device)
        Task { @MainActor in self.updateEarbudConnection(true, name: device.name) }
    }

    @objc private func earbudDidDisconnect(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device, isTargetEarbud(device) else { return }
        if let address = device.addressString { bluetoothDisconnectNotifications.removeValue(forKey: address) }
        Task { @MainActor in self.updateEarbudConnection(false, name: device.name) }
    }

    private func updateEarbudConnection(_ isConnected: Bool, name: String?) {
        let wasConnected = self.isConnected
        connected = isConnected
        earbudBluetoothConnected = isConnected
        if let name, !name.isEmpty { outputName = name }
        if isConnected != wasConnected {
            resetChargingStatesToUnknown()
            batteryAlertStage.removeAll()
        }
        if isConnected && !wasConnected {
            disconnectTask?.cancel()
            disconnectTask = nil
            NSLog("Air7Menu paired Air 7 Bluetooth connection detected")
            connectionPopupPending = showOnConnection
            presentPendingConnectionPopup()
        }
        if !isConnected {
            connectionNotificationPending = false
            controlReady = false
            connectingControls = false
            if wasConnected { closeAfterTargetDisconnectIfBluetoothIsOn() }
        } else if !controlReady && !connectingControls {
            connectControls()
        }
    }

    private func closeAfterTargetDisconnectIfBluetoothIsOn() {
        disconnectTask?.cancel()
        disconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, !self.isConnected else { return }
            NSLog("Air7Menu quitting after Doraemon disconnected")
            self.onTargetEarbudDisconnected?()
            self.disconnectTask = nil
        }
    }

    func setShowOnConnection(_ enabled: Bool) {
        showOnConnection = enabled
        if !enabled { connectionPopupPending = false }
        UserDefaults.standard.set(enabled, forKey: "air7.showPopupOnConnection")
    }

    func presentPendingConnectionPopup() {
        guard connectionPopupPending, showOnConnection,
              let onConnectionDetected,
              isConnected, outputName?.isEmpty == false else { return }
        connectionPopupPending = false
        onConnectionDetected()
    }

    /// Consumes the notification written by the background monitor immediately
    /// before it launches this app. Events expire so an old connection cannot
    /// cause a pop-up after a later manual launch.
    func consumeMonitorConnectionEvent() -> Bool {
        let defaults = UserDefaults.standard
        defaults.synchronize()
        guard defaults.object(forKey: connectionEventTimestampKey) != nil else { return false }
        let timestamp = defaults.double(forKey: connectionEventTimestampKey)
        defaults.removeObject(forKey: connectionEventTimestampKey)
        guard Date().timeIntervalSince1970 - timestamp < 30 else { return false }

        connected = true
        earbudBluetoothConnected = true
        connectionPopupPending = showOnConnection
        if let name = defaults.string(forKey: connectionEventNameKey), !name.isEmpty {
            outputName = name
        }
        presentPendingConnectionPopup()
        if !controlReady && !connectingControls { connectControls() }
        NSLog("Air7Menu received a Bluetooth connection event from Air7Monitor")
        return true
    }

    private func handleMonitorConnectionEvent() {
        _ = consumeMonitorConnectionEvent()
    }

    private func configureBluetoothMonitor() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "air7.autoLaunchMonitor") as? Bool ?? true
        launchAtLogin = saved

        guard saved else { return }

        let label = "com.local.air7menu.monitor"
        let agentURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
        let expectedMonitor = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/Air7Monitor").path
        let savedArguments = (try? Data(contentsOf: agentURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            .flatMap { $0["ProgramArguments"] as? [String] }
        let plistIsCurrent = savedArguments?.first == expectedMonitor
            && FileManager.default.isExecutableFile(atPath: expectedMonitor)
        let job = runLaunchctl(["print", "gui/\(getuid())/\(label)"])
        let jobIsCurrent = job.success && job.output.contains(expectedMonitor)

        // Install the watcher on first run, or repair it after the app bundle
        // moves. A correctly loaded job is left alone so manual plist edits
        // are preserved across ordinary launches.
        if !plistIsCurrent || !jobIsCurrent {
            NSLog("Air7Menu Bluetooth monitor is missing or points to an old app path; installing it")
            setLaunchAtLogin(true)
        }
    }

    func refreshOutput() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0); var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else {
            return
        }
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var unmanagedName: Unmanaged<CFString>?; size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &size, &unmanagedName) == noErr, let name = unmanagedName?.takeUnretainedValue() else { return }
        if outputName == nil { outputName = name as String }
        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var unmanagedUID: Unmanaged<CFString>?; size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size, &unmanagedUID) == noErr {
            outputUID = unmanagedUID?.takeUnretainedValue() as String?
        }
        var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(kAudioDeviceTransportTypeUnknown); size = 4
        bluetoothOutput = AudioObjectGetPropertyData(device, &ta, 0, nil, &size, &transport) == noErr && transport == kAudioDeviceTransportTypeBluetooth
        // CoreAudio describes the selected output route, not earbud Bluetooth
        // connection state. IOBluetooth callbacks above own that state.
        if isConnected && !controlReady && !connectingControls { connectControls() }
    }

    func connectControls() {
        guard !connectingControls else { return }
        connectingControls = true
        controlStatus = "Discovering the Air 7 control service…"
        buds.connect(preferredName: outputName, audioUID: outputUID) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.connectingControls = false; self.controlStatus = error; return }
                self.productReplyPending = true
                self.buds.request(0x0103) { _, p in
                    NSLog("Air7Menu identity callback payloadBytes=%d", p.count)
                    Task { @MainActor in
                        self.productReplyPending = false
                        self.connectingControls = false
                        guard p.count >= 4 else { self.controlStatus = "Air 7 identity could not be read."; return }
                        let productID = Int(p[1]) | Int(p[2]) << 8 | Int(p[3]) << 16
                        NSLog("Air7Menu product identity response=%@ productID=0x%06X", p.map { String(format: "%02X", $0) }.joined(separator: " "), productID)
                        guard productID == 0x064812 else { self.controlReady = false; self.controlStatus = "Connected device is not identified as realme Buds Air 7 (ID \(String(productID, radix: 16))). No controls sent."; return }
                        self.controlReady = true; self.controlStatus = "Air 7 control link connected."; self.refreshControls()
                    }
                }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard let self, self.productReplyPending else { return }
                    self.productReplyPending = false
                    self.connectingControls = false
                    self.controlStatus = "The control channel opened, but the earbuds did not answer the Air 7 identity query. Reconnect them and retry."
                }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, self.connectingControls else { return }
            self.connectingControls = false
            self.controlStatus = "Bluetooth service discovery timed out. Reconnect Doraemon in System Settings → Bluetooth, then tap Refresh."
        }
    }
    func retryControls() {
        refreshOutput()
        guard isConnected else { return }
        controlReady = false
        connectingControls = false
        connectControls()
    }
    func refreshControls() {
        guard controlReady else { return }; syncing = true; eqAvailable = true
        buds.request(0x010C, payload: [1,1]) { [weak self] _, p in Task { @MainActor in self?.parseANC(p) } }
        buds.request(0x0106) { [weak self] _, p in Task { @MainActor in self?.parseBattery(p) } }
        buds.request(0x010D, payload: [1, 0x1B]) { [weak self] _, p in Task { @MainActor in
            guard let self else { return }; self.spatialAvailable = p.count >= 4 && p[2] == 0x1B
            if self.spatialAvailable { self.spatialEnabled = p[3] == 1 }
            self.syncing = false
        } }
    }

    func setNoiseMode(_ mode: Air7NoiseMode) {
        switch mode {
        case .noiseCancellation:
            setANCStrength(.max)
        case .normal:
            sendNoiseMode(0x01, mode: .normal, strength: nil)
        case .transparency:
            sendNoiseMode(0x02, mode: .transparency, strength: nil)
        }
    }

    func setANCStrength(_ strength: Air7ANCStrength) {
        sendNoiseMode(strength.protocolValue, mode: .noiseCancellation, strength: strength)
    }

    private func sendNoiseMode(_ value: UInt8, mode: Air7NoiseMode, strength: Air7ANCStrength?) {
        guard controlReady else { return }
        buds.request(0x0404, payload: [1, 1, value]) { [weak self] _, response in Task { @MainActor in
            guard let self else { return }
            if response.first == 0 {
                self.noiseMode = mode
                self.ancStrength = strength
            }
            self.refreshControls()
        } }
    }
    func setSpatial(_ enabled: Bool) {
        guard controlReady, spatialAvailable else { return }
        let utterance = AVSpeechUtterance(string: enabled ? "Spatial audio on" : "Spatial audio off")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN") ?? AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(utterance)
        buds.request(0x0403, payload: [0x1B, enabled ? 1 : 0]) { [weak self] _, _ in Task { @MainActor in self?.refreshControls() } }
    }
    func setEQ(_ id: UInt8) {
        guard controlReady, eqAvailable else { return }
        buds.request(0x0406, payload: [id]) { [weak self] _, payload in Task { @MainActor in
            guard let self else { return }
            if payload.first == 0, let preset = self.eqPresets.first(where: { $0.id == id }) {
                self.eqPreset = preset.title
                self.controlStatus = "EQ set to \(preset.title)."
            } else {
                self.controlStatus = "The earbuds rejected that EQ preset."
            }
            self.refreshControls()
        } }
    }
    private func parseANC(_ p: [UInt8]) {
        guard let value = p.last else { return }
        // GET_NOISE_REDUCTION_INFO returns a compact state (0=normal,
        // 8=noise cancellation, 16=transparency). Push events carry the
        // selected ANC preset directly (1/2/4/8/16/32).
        if p.count == 4, p[0] == 0, p[1] == 1, p[2] == 1 {
            switch value {
            case 0:
                noiseMode = .normal; ancStrength = nil
            case 8:
                noiseMode = .noiseCancellation; ancStrength = ancStrength ?? .smart
                enforceMaximumANC()
            case 16:
                noiseMode = .transparency; ancStrength = nil
            default:
                applyNoisePreset(value)
            }
            return
        }
        applyNoisePreset(value)
    }

    private func applyNoisePreset(_ value: UInt8) {
        switch value {
        case 0x01:
            noiseMode = .normal; ancStrength = nil
        case 0x02:
            noiseMode = .transparency; ancStrength = nil
        case 0x04:
            noiseMode = .noiseCancellation; ancStrength = .mild
        case 0x08:
            noiseMode = .noiseCancellation; ancStrength = .max
        case 0x10:
            noiseMode = .noiseCancellation; ancStrength = .moderate
        case 0x20:
            noiseMode = .noiseCancellation; ancStrength = .smart
        default:
            break
        }
        if noiseMode == .noiseCancellation, ancStrength != .max {
            enforceMaximumANC()
        }
    }

    private func enforceMaximumANC() {
        guard controlReady, !settingMaximumANC else { return }
        settingMaximumANC = true
        buds.request(0x0404, payload: [1, 1, Air7ANCStrength.max.protocolValue]) { [weak self] _, response in
            Task { @MainActor in
                guard let self else { return }
                self.settingMaximumANC = false
                if response.first == 0 {
                    self.noiseMode = .noiseCancellation
                    self.ancStrength = .max
                } else {
                    self.controlStatus = "Could not set Noise Cancellation to Max."
                }
            }
        }
    }
    private func parseBattery(_ p: [UInt8]) {
        guard let snapshot = Air7BatteryDecoder.decodeSnapshot(p) else { return }
        let values = snapshot.levels
        var nextChargingStates: [String: Air7ChargingState] = [
            "Case": .unknown, "Left": .unknown, "Right": .unknown
        ]
        snapshot.chargingStates.forEach { nextChargingStates[$0.key] = $0.value }
        // Avoid invalidating every battery-dependent SwiftUI view when the
        // earbuds repeat the same status frame.
        if battery != values { battery = values }
        if chargingState != nextChargingStates { chargingState = nextChargingStates }
        handleLowBatteryTransitions(in: values)
    }

    private func resetChargingStatesToUnknown() {
        let unknown: [String: Air7ChargingState] = [
            "Case": .unknown, "Left": .unknown, "Right": .unknown
        ]
        if chargingState != unknown { chargingState = unknown }
    }

    private func postConnectionNotification(battery: [String: Int]?) {
        connectionNotificationPending = false
        let levels = ["Left", "Right"].compactMap { side in
            battery?[side].map { "\(side): \($0)%" }
        }
        let content = UNMutableNotificationContent()
        content.title = "realme Buds Air 7 connected"
        content.body = levels.isEmpty ? "Your earbuds are connected." : levels.joined(separator: "  ·  ")
        let request = UNNotificationRequest(
            identifier: "air7-connected-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let add: () -> Void = {
                center.add(request) { error in
                    if let error { NSLog("Air7Menu connection notification failed: %@", error.localizedDescription) }
                }
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                add()
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, error in
                    if granted { add() }
                    else if let error { NSLog("Air7Menu notification permission request failed: %@", error.localizedDescription) }
                }
            case .denied:
                NSLog("Air7Menu connection notification skipped: notifications are disabled")
            @unknown default:
                break
            }
        }
    }

    private func handleLowBatteryTransitions(in values: [String: Int]) {
        let sides = ["Left", "Right"]
        guard sides.contains(where: { values[$0] != nil }) else { return }

        var newlyAlerted: [String: Int] = [:]
        for side in sides {
            // Missing readings are unknown; retain state instead of treating them as 0%.
            guard let level = values[side] else { continue }
            let stage = level <= 10 ? 10 : (level <= 20 ? 20 : 30)
            let previousStage = batteryAlertStage[side] ?? 30
            if stage < previousStage { newlyAlerted[side] = level }
            batteryAlertStage[side] = stage
        }

        guard !newlyAlerted.isEmpty else { return }
        NSLog("Air7Menu low-battery alert threshold reached: %@", newlyAlerted.description)
        LowBatteryAlertController.shared.show(levels: newlyAlerted)
    }
    private func handlePush(_ cmd: UInt16, _ payload: [UInt8]) {
        if cmd == 0x0204, payload.first == 1 { parseBattery(Array(payload.dropFirst())) }
        if cmd == 0x0204, payload.first == 3 { parseANC(Array(payload.dropFirst())) }
        if cmd == 0x0504, let id = payload.first,
           let preset = eqPresets.first(where: { $0.id == id }) {
            eqPreset = preset.title
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "air7.autoLaunchMonitor")
        let uid = String(getuid())
        let domain = "gui/\(uid)"
        let label = "com.local.air7menu.monitor"
        let agentURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")

        if enabled {
            // Resolve the stable .app bundle path.
            // Strategy: walk UP from the running executable to find the .app,
            // then look for Air7Monitor inside it. Falls back to NSWorkspace
            // if the app was launched from somewhere else (e.g. DerivedData).
            let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
            // executableURL is .../Air7Menu.app/Contents/MacOS/Air7Menu
            let candidateAppURL = executableURL
                .deletingLastPathComponent()  // MacOS/
                .deletingLastPathComponent()  // Contents/
                .deletingLastPathComponent()  // Air7Menu.app
            let candidateMonitor = candidateAppURL
                .appendingPathComponent("Contents/MacOS/Air7Monitor")

            let appURL: URL
            if candidateAppURL.pathExtension == "app",
               FileManager.default.isExecutableFile(atPath: candidateMonitor.path) {
                appURL = candidateAppURL
            } else if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.local.air7menu"),
                      FileManager.default.isExecutableFile(atPath:
                          registered.appendingPathComponent("Contents/MacOS/Air7Monitor").path) {
                appURL = registered
            } else {
                NSLog("Air7Menu setLaunchAtLogin: cannot find Air7Monitor binary; skipping plist write")
                launchAtLogin = false
                return
            }

            let executable = appURL.appendingPathComponent("Contents/MacOS/Air7Monitor").path
            NSLog("Air7Menu setLaunchAtLogin: monitor path = %@", executable)

            // KeepAlive is intentionally NOT set (defaults to false).
            // The monitor is a long-running RunLoop process that stays alive
            // on its own. Setting KeepAlive: true would make launchd a
            // process supervisor that restarts the monitor after every exit,
            // which in turn calls launchMainApp() and re-opens the main app
            // even after the user has explicitly quit it.
            let values: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable],
                "RunAtLoad": true
            ]
            do {
                let directory = agentURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
                try data.write(to: agentURL, options: .atomic)
                let currentJob = runLaunchctl(["print", "\(domain)/\(label)"])
                if currentJob.success && (!currentJob.output.contains(executable) || !FileManager.default.fileExists(atPath: executable)) {
                    _ = runLaunchctl(["bootout", domain, agentURL.path])
                }
                let jobAfterCleanup = runLaunchctl(["print", "\(domain)/\(label)"])
                if !jobAfterCleanup.success {
                    let result = runLaunchctl(["bootstrap", domain, agentURL.path])
                    if !result.success {
                        NSLog("Air7Menu could not start its Bluetooth monitor: %@", result.output)
                    } else {
                        NSLog("Air7Menu Bluetooth monitor is running from %@", executable)
                    }
                }
                launchAtLogin = true
            } catch {
                NSLog("Air7Menu could not install its Bluetooth monitor: %@", error.localizedDescription)
                launchAtLogin = false
            }
        } else {
            _ = runLaunchctl(["bootout", domain, agentURL.path])
            do { try FileManager.default.removeItem(at: agentURL) }
            catch where (error as NSError).code == NSFileNoSuchFileError { }
            catch { NSLog("Air7Menu could not remove its Bluetooth monitor: %@", error.localizedDescription) }
            launchAtLogin = false
        }
    }

    private func runLaunchctl(_ arguments: [String]) -> (success: Bool, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
