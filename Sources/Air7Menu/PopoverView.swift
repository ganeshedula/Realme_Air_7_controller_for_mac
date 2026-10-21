import AppKit
import SwiftUI

enum Air7Design {
    static let accent = Color(red: 0.20, green: 0.82, blue: 0.57)
    static let glassEdge = Color.white.opacity(0.13)
    static let warning = Color.orange
    static let critical = Color.red
    static let separator = Color.primary.opacity(0.08)
    static let panelRadius: CGFloat = 18
    static let cardRadius: CGFloat = 14
    static let contentWidth: CGFloat = 390

    static func isGenericDeviceName(_ name: String) -> Bool {
        let compact = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return compact == "realmebudsair7"
    }
}

struct PopoverView: View {
    @ObservedObject var model: EarbudModel
    var showBatteryPopup: () -> Void = {}
    var quitApp: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var modeSelectionAnimation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.isConnected {
                batterySummary
                connectedControls
            } else {
                disconnectedMessage
            }

            footer
        }
        .padding(16)
        .frame(width: Air7Design.contentWidth)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.16, blue: 0.19).opacity(0.68), Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Ellipse()
                    .fill(Air7Design.accent.opacity(0.15))
                    .frame(width: 230, height: 120)
                    .blur(radius: 48)
                    .offset(x: -100, y: -150)
                Ellipse()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 190, height: 140)
                    .blur(radius: 50)
                    .offset(x: 150, y: 170)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Air7Design.glassEdge))
        }
        .preferredColorScheme(.dark)
        .tint(Air7Design.accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isConnected)
    }

    private var header: some View {
        VStack(spacing: 11) {
        HStack(spacing: 9) {
            Image(systemName: "airpodspro")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(model.isConnected ? Air7Design.accent : Color.secondary)
                .frame(width: 34, height: 34)
                .background(Air7Design.accent.opacity(model.isConnected ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Air7Design.accent.opacity(0.22)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("realme Buds Air 7")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isConnected ? Air7Design.accent : Color.secondary.opacity(0.55))
                        .frame(width: 6, height: 6)
                    Text(model.connectionText)
                        .font(.system(size: 12))
                        .foregroundStyle(model.isConnected ? Air7Design.accent : Color.secondary)
                    if model.isConnected, let name = model.outputName, !name.isEmpty, !Air7Design.isGenericDeviceName(name) {
                        Text("· \(name)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 8)
            Button(action: showBatteryPopup) {
                Image(systemName: "rectangle.topright.inset.filled")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 25, height: 25)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Show compact battery pop-up")
            .accessibilityLabel("Show compact battery pop-up")
            Button(action: model.retryControls) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 25, height: 25)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Refresh earbud status")
            .accessibilityLabel("Refresh earbud status")
        }
        Rectangle()
            .fill(Air7Design.glassEdge.opacity(0.75))
            .frame(height: 1)
        }
    }

    private var disconnectedMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("Connect Doraemon").font(.subheadline.weight(.medium))
                Text("Connect your earbuds in System Settings → Bluetooth. Battery and controls will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Air7Design.cardRadius, style: .continuous))
    }

    private var batterySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BATTERY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text("Live device data")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
            VStack(spacing: 6) {
                // The Air 7 protocol exposes a case percentage but no lid
                // state. A zero is the device's closed-case placeholder in
                // this flow, so only show the case while it reports charge.
                if let caseLevel = model.battery["Case"], caseLevel > 0 {
                    batteryCell("Case")
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    Divider().opacity(0.45).padding(.horizontal, 14)
                }
                HStack(spacing: 8) {
                    batteryCell("Left")
                    batteryCell("Right")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Air7Design.glassEdge.opacity(0.65)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.battery["Case"])
        }
    }

    private var connectedControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Listening controls").font(.system(size: 15, weight: .semibold))
                Spacer()
                if model.canControl {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Air7Design.accent)
                }
            }

            if !model.canControl && !model.controlStatus.isEmpty {
                Text(model.controlStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Noise Control")
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 2) {
                        ForEach(Air7NoiseMode.allCases) { mode in
                            modeButton(mode)
                        }
                    }
                    .padding(2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Air7Design.glassEdge.opacity(0.65)))
                }
                .padding(.bottom, 6)

                Divider().opacity(0.4)

                settingRow("360° Spatial Audio", icon: "dot.radiowaves.left.and.right") {
                    if model.spatialAvailable {
                        Toggle("360° Spatial Audio", isOn: Binding(
                            get: { model.spatialEnabled ?? false },
                            set: model.setSpatial
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(model.spatialEnabled == nil)
                        .accessibilityLabel("360 degree spatial audio")
                    } else {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 5)

                Divider().opacity(0.4)

                settingRow("EQ Presets", icon: "slider.horizontal.3") {
                    Menu {
                        ForEach(model.eqPresets) { preset in
                            Button {
                                model.setEQ(preset.id)
                            } label: {
                                HStack {
                                    Text(preset.title)
                                    if model.eqPreset == preset.title { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(model.eqPreset ?? "Choose preset")
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 7)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(!model.eqAvailable)
                    .accessibilityLabel("EQ preset: \(model.eqPreset ?? "Choose preset")")
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Air7Design.glassEdge.opacity(0.7)))
        }
    }

    private func modeButton(_ mode: Air7NoiseMode) -> some View {
        let selected = model.noiseMode == mode
        let icon: String = switch mode {
        case .noiseCancellation: "waveform.badge.mic"
        case .normal: "waveform"
        case .transparency: "ear"
        }
        let title: String = switch mode {
        case .noiseCancellation: "Noise Cancellation"
        case .normal: "Normal"
        case .transparency: "Transparency"
        }
        return Button {
            model.setNoiseMode(mode)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(selected ? Air7Design.accent : Color.primary.opacity(0.76))
            .frame(maxWidth: .infinity, minHeight: 43)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.13), Air7Design.accent.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Air7Design.accent.opacity(0.34)))
                        .shadow(color: Air7Design.accent.opacity(0.12), radius: 8)
                }
            }
            .matchedGeometryEffect(id: selected ? "selected-noise-mode" : "noise-mode-\(mode.id)", in: modeSelectionAnimation, isSource: selected)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.canControl || model.noiseMode == nil)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func settingRow<Control: View>(
        _ title: String,
        icon: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 27)
    }

    private func batteryCell(_ side: String) -> some View {
        BatteryBarCard(
            title: side == "Case" ? "Case" : side,
            level: model.battery[side],
            chargingState: model.chargingState[side] ?? .unknown,
            accent: Air7Design.accent
        )
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Show pop-up when earbuds connect", isOn: Binding(
                get: { model.showOnConnection },
                set: model.setShowOnConnection
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: model.setLaunchAtLogin
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(action: quitApp) {
                    Label("Quit Air 7 Menu", systemImage: "power")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .accessibilityHint("Quits the menu bar app")
                Spacer()
                Text("⇧⌘R")
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.top, 1)
        }
        .padding(.top, 1)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Air7Design.glassEdge.opacity(0.55)))
    }
}

/// Horizontal battery card matching the Stitch companion bar. Empty readings
/// stay empty instead of suggesting a level the device has not reported.
private struct BatteryBarCard: View {
    let title: String
    let level: Int?
    let chargingState: Air7ChargingState
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCharging: Bool { chargingState == .charging }
    private var tint: Color {
        guard let level else { return Color.white.opacity(0.38) }
        if level <= 10 { return Air7Design.critical }
        if level <= 20 { return Air7Design.warning }
        return accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: title == "Case" ? "battery.100percent" : "earbuds")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 0)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            HStack(spacing: 12) {
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(level == nil ? Color.white.opacity(0.56) : .white)
                    .contentTransition(.numericText())
                    .frame(minWidth: 54, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        if let level {
                            Capsule()
                                .fill(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geometry.size.width * CGFloat(min(max(level, 0), 100)) / 100)
                                .shadow(color: tint.opacity(0.2), radius: 5)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: level)
                        }
                    }
                }
                .frame(height: 8)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(level.map { "\($0) percent" } ?? "Unavailable")
    }

    private var accessibilityDescription: String {
        let name = title == "Case" ? "Charging case" : "\(title) earbud"
        let battery = level.map { "battery \($0) percent" } ?? "battery unavailable"
        return switch chargingState {
        case .charging: "\(name) \(battery), charging"
        case .notCharging: "\(name) \(battery), not charging"
        case .unknown: "\(name) \(battery)"
        }
    }

}

private struct LowBatteryFloatingAlert: View {
    let levels: [String: Int]
    private var isCritical: Bool { levels.values.contains { $0 <= 10 } }
    private var warning: Color { isCritical ? Air7Design.critical : Air7Design.warning }

    private var affectedSides: [String] { ["Left", "Right"].filter { levels[$0] != nil } }
    private var sideDescription: String { affectedSides.count == 2 ? "Both" : (affectedSides.first ?? "Earbud") }
    private var batteryDescription: String {
        affectedSides.compactMap { side in levels[side].map { "\(side) \($0)%" } }.joined(separator: "   ·   ")
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "airpodspro")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(warning)
                .frame(width: 38, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(isCritical ? "Critical Battery" : "Low Battery")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                HStack(spacing: 7) {
                    Text(sideDescription)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(warning)
                    Text(batteryDescription)
                        .font(.system(.subheadline, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 340, height: 72)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Air7Design.glassEdge))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isCritical ? "Critical" : "Low") battery. \(sideDescription). \(batteryDescription)")
    }
}

private struct BatteryPopupView: View {
    @ObservedObject var model: EarbudModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Air7Design.accent)
                    .frame(width: 34, height: 34)
                    .background(Air7Design.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("realme Buds Air 7").font(.headline).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(Air7Design.accent).frame(width: 6, height: 6)
                        Text("Connected").font(.caption).foregroundStyle(Air7Design.accent)
                        if let name = model.outputName, !name.isEmpty, !Air7Design.isGenericDeviceName(name) {
                            Text("· \(name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: 9) {
                batteryCell("Left")
                batteryCell("Right")
            }
        }
        .padding(15)
        .frame(width: 366)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.19).opacity(0.76), Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Air7Design.glassEdge))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
        .preferredColorScheme(.dark)
        .tint(Air7Design.accent)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func batteryCell(_ side: String) -> some View {
        BatteryBarCard(
            title: side,
            level: model.battery[side],
            chargingState: model.chargingState[side] ?? .unknown,
            accent: Air7Design.accent
        )
        .frame(maxWidth: .infinity)
    }
}

@MainActor
final class BatteryPopupController {
    static let shared = BatteryPopupController()
    private var panel: NSPanel?
    private var dismissalTimer: Timer?

    func dismiss() {
        dismissalTimer?.invalidate()
        dismissalTimer = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    func show(model: EarbudModel) {
        guard model.isConnected, model.outputName?.isEmpty == false else {
            NSLog("Air7Menu did not show the battery pop-up because no connected earbud state was available.")
            dismiss()
            return
        }
        NSLog("Air7Menu presenting the battery pop-up for %@", model.outputName ?? "Air 7")
        model.refreshControls()

        let batteryPanel: NSPanel
        if let panel {
            batteryPanel = panel
        } else {
            let created = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 366, height: 150),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = false
            created.hidesOnDeactivate = false
            created.isMovableByWindowBackground = false
            self.panel = created
            batteryPanel = created
        }

        batteryPanel.contentView = NSHostingView(rootView: BatteryPopupView(model: model))
        batteryPanel.setContentSize(NSSize(width: 366, height: 150))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let top = screen.safeAreaInsets.top > 0
                ? screen.frame.maxY - screen.safeAreaInsets.top
                : screen.visibleFrame.maxY
            batteryPanel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - batteryPanel.frame.width / 2,
                y: top - batteryPanel.frame.height - 8
            ))
        }
        batteryPanel.alphaValue = 0
        batteryPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            batteryPanel.animator().alphaValue = 1
        }
        NSLog("Air7Menu battery pop-up ordered front; visible=%d", batteryPanel.isVisible)
        dismissalTimer?.invalidate()
        dismissalTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak batteryPanel] _ in
            guard let batteryPanel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                batteryPanel.animator().alphaValue = 0
            }, completionHandler: {
                batteryPanel.orderOut(nil)
                batteryPanel.alphaValue = 1
            })
        }
    }
}

@MainActor
final class LowBatteryAlertController {
    static let shared = LowBatteryAlertController()
    private var panel: NSPanel?
    private var dismissalTimer: Timer?

    func show(levels: [String: Int]) {
        guard !levels.isEmpty else { return }
        let alertPanel: NSPanel
        if let panel {
            alertPanel = panel
        } else {
            let created = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 72),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = false
            created.hidesOnDeactivate = false
            created.isMovableByWindowBackground = false
            self.panel = created
            alertPanel = created
        }
        alertPanel.contentView = NSHostingView(rootView: LowBatteryFloatingAlert(levels: levels))
        alertPanel.setContentSize(NSSize(width: 340, height: 72))
        if let screen = NSScreen.main?.visibleFrame {
            alertPanel.setFrameOrigin(NSPoint(
                x: screen.midX - alertPanel.frame.width / 2,
                y: screen.maxY - alertPanel.frame.height - 28
            ))
        }
        alertPanel.orderFrontRegardless()
        dismissalTimer?.invalidate()
        dismissalTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak alertPanel] _ in
            alertPanel?.orderOut(nil)
        }
    }
}
