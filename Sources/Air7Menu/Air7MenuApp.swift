import SwiftUI
import ServiceManagement

@main
struct Air7MenuApp: App {
    @NSApplicationDelegateAdaptor(Air7AppDelegate.self) private var appDelegate
    @StateObject private var model: EarbudModel

    init() {
        let model = EarbudModel()
        _model = StateObject(wrappedValue: model)
        appDelegate.model = model
        // Show the connection pop-up as soon as the target device is confirmed;
        // battery values populate from the device as readings arrive.
        model.onConnectionDetected = { BatteryPopupController.shared.show(model: model) }
        // Exit when the target earbuds disconnect. The separate Bluetooth
        // monitor remains alive and can relaunch the app on the next connection.
        model.onTargetEarbudDisconnected = {
            NSApplication.shared.terminate(nil)
        }
        DispatchQueue.main.async {
            _ = model.consumeMonitorConnectionEvent()
            model.presentPendingConnectionPopup()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model, showBatteryPopup: {
                model.refreshOutput()
                BatteryPopupController.shared.show(model: model)
            }, quitApp: quitApp)
                .frame(width: Air7Design.contentWidth)
        } label: {
            Label("Air 7", systemImage: "airpodspro")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show Battery Pop-up") {
                    model.refreshOutput()
                    BatteryPopupController.shared.show(model: model)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
            CommandGroup(after: .appTermination) {
                Button("Quit Air 7 Menu") {
                    quitApp()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }

    /// Records that the user intentionally quit before terminating.
    /// Air7Monitor reads this flag and will not relaunch the main app
    /// while it remains set (it is cleared on the next earbud disconnect).
    private func quitApp() {
        UserDefaults.standard.set(true, forKey: "air7.userDidExplicitlyQuit")
        UserDefaults.standard.synchronize()
        NSLog("Air7Menu: user explicitly quit — flag written, terminating")
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class Air7AppDelegate: NSObject, NSApplicationDelegate {
    var model: EarbudModel?

    func applicationDidBecomeActive(_ notification: Notification) {
        // Refresh connection / audio-route state when the app becomes active.
        // Do NOT auto-show the battery pop-up here — that caused it to reappear
        // on every app-activation event (e.g. after the monitor relaunched it)
        // and bypassed the user's explicit-quit intent.
        guard let model else { return }
        model.refreshOutput()
    }
}
