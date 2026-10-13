import AppKit
import Foundation
import IOBluetooth

// UserDefaults key written by Air7Menu when the user explicitly quits.
// Air7Monitor reads this flag before deciding to relaunch the main app.
// The flag is cleared by Air7Monitor when earbuds disconnect, so a fresh
// connection in a new session can trigger an automatic launch again.
private let userDidExplicitlyQuitKey = "air7.userDidExplicitlyQuit"
private let showPopupOnConnectionKey = "air7.showPopupOnConnection"

private final class Air7BluetoothMonitor: NSObject {
    private let knownAddressKey = "air7.bluetoothAddress"
    private let connectionEventTimestampKey = "air7.connectionEventTimestamp"
    private let connectionEventNameKey = "air7.connectionEventName"
    private let connectionNotification = Notification.Name("com.local.air7menu.earbudsConnected")
    private let defaults = UserDefaults.standard
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:))
        )

        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        for device in paired where device.isConnected() && isAir7(device) {
            watchDisconnect(for: device)
            // Earbuds are already connected at monitor start. Record the event
            // and clear any stale explicit-quit flag — the disconnect that
            // normally clears it never fired if the device was connected at
            // boot / monitor restart, leaving the app unable to relaunch.
            if userExplicitlyQuit() {
                defaults.removeObject(forKey: userDidExplicitlyQuitKey)
                defaults.synchronize()
                NSLog("Air7Monitor: earbuds already connected at startup — cleared stale explicit-quit flag")
            }
            recordConnectionEvent(for: device)
        }
        // Do NOT call launchMainApp() here. The main app is launched at login
        // by the launchd KeepAlive mechanism or the user's own action. The
        // monitor's only job is to fire when earbuds *connect* while the main
        // app is not running and the user has not explicitly quit it.
    }

    @objc(deviceDidConnect:device:)
    private func deviceDidConnect(_ notification: IOBluetoothUserNotification!, device: IOBluetoothDevice!) {
        guard let device, isAir7(device) else { return }
        watchDisconnect(for: device)
        recordConnectionEvent(for: device)
        // Only relaunch the main app if the user has NOT explicitly quit it
        // and the "show pop-up on connection" preference is enabled.
        guard !userExplicitlyQuit() else {
            NSLog("Air7Monitor: user explicitly quit — not relaunching the main app")
            return
        }
        guard showOnConnection() else {
            NSLog("Air7Monitor: show-on-connection disabled — not relaunching the main app")
            return
        }
        launchMainApp()
    }

    @objc(deviceDidDisconnect:device:)
    private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification!, device: IOBluetoothDevice!) {
        guard let device, isAir7(device) else { return }
        disconnectNotifications.removeValue(forKey: device.addressString ?? "")
        // When the earbuds disconnect, clear the explicit-quit flag so that
        // the NEXT fresh connection can trigger a normal automatic launch again.
        if userExplicitlyQuit() {
            defaults.removeObject(forKey: userDidExplicitlyQuitKey)
            defaults.synchronize()
            NSLog("Air7Monitor: earbuds disconnected — cleared explicit-quit flag for next session")
        }
    }

    private func userExplicitlyQuit() -> Bool {
        defaults.synchronize()
        return defaults.bool(forKey: userDidExplicitlyQuitKey)
    }

    private func showOnConnection() -> Bool {
        defaults.synchronize()
        // Default to true if the preference has never been set.
        if defaults.object(forKey: showPopupOnConnectionKey) == nil { return true }
        return defaults.bool(forKey: showPopupOnConnectionKey)
    }

    private func watchDisconnect(for device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        defaults.set(address, forKey: knownAddressKey)
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDidDisconnect(_:device:))
        )
    }

    private func isAir7(_ device: IOBluetoothDevice) -> Bool {
        if let address = device.addressString,
           let known = defaults.string(forKey: knownAddressKey),
           address.caseInsensitiveCompare(known) == .orderedSame {
            return true
        }
        let name = (device.name ?? "").lowercased()
        return name.contains("realme buds air 7") || name.contains("realme buds air7") || name == "doraemon"
    }

    private func recordConnectionEvent(for device: IOBluetoothDevice) {
        defaults.set(Date().timeIntervalSince1970, forKey: connectionEventTimestampKey)
        if let name = device.name, !name.isEmpty {
            defaults.set(name, forKey: connectionEventNameKey)
        }
        defaults.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            connectionNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        NSLog("Air7Monitor recorded a connection event for %@", device.name ?? "the earbuds")
    }

    private func launchMainApp() {
        DispatchQueue.main.async {
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.local.air7menu").first != nil {
                NSLog("Air7Monitor: main app is already running — skipping launch")
                return
            }
            let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let bundledAppURL = executableURL
                .deletingLastPathComponent() // MacOS
                .deletingLastPathComponent() // Contents
                .deletingLastPathComponent() // Air7Menu.app
            let bundledMainExecutable = bundledAppURL
                .appendingPathComponent("Contents/MacOS/Air7Menu")
            let appURL: URL
            if bundledAppURL.pathExtension == "app",
               FileManager.default.isExecutableFile(atPath: bundledMainExecutable.path) {
                appURL = bundledAppURL
            } else if let registeredApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.local.air7menu") {
                appURL = registeredApp
            } else {
                NSLog("Air7Monitor cannot find its containing Air 7 Menu.app bundle.")
                return
            }
            NSLog("Air7Monitor launching app at %@", appURL.path)
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error { NSLog("Air7Monitor could not launch Air 7 Menu: %@", error.localizedDescription) }
            }
        }
    }
}

private let monitor = Air7BluetoothMonitor()
monitor.start()
RunLoop.current.run()
