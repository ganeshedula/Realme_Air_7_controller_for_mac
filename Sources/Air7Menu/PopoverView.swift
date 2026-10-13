import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: EarbudModel
    var showBatteryPopup: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let realmeGreen = Color(red: 0.12, green: 0.82, blue: 0.48)
    @Namespace private var modeSelectionAnimation

    private var deviceName: String {
        guard let output = model.outputName, !output.isEmpty else { return "realme Buds Air 7" }
        let normalized = output.lowercased()
        if normalized.contains("realme") || normalized.contains("air 7") || normalized.contains("air7") {
            return output
        }
        return "realme Buds Air 7"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 12)

            if model.isConnected {
                batterySummary
                Divider().padding(.vertical, 12)
                connectedControls
            } else {
                Label(
                    "Connect the earbuds in System Settings → Bluetooth. Controls follow the Mac’s current audio output.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            }

            Divider().padding(.vertical, 10)
            footer
        }
        .padding(16)
        .frame(width: 380)
        .tint(realmeGreen)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "airpodspro")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(model.isConnected ? realmeGreen : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(deviceName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    if model.isConnected {
                        Circle().fill(realmeGreen).frame(width: 6, height: 6)
                    }
                    Text(model.connectionText)
                        .font(.subheadline)
                        .foregroundStyle(model.isConnected ? realmeGreen : Color.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: showBatteryPopup) {
                Image(systemName: "rectangle.topright.inset.filled")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Show compact battery pop-up")
            .accessibilityLabel("Show compact battery pop-up")
            Button(action: model.retryControls) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Refresh earbud status")
            .accessibilityLabel("Refresh earbud status")
        }
    }

    private var batterySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battery")
                .font(.headline)
            VStack(spacing: 12) {
                if let caseLevel = model.battery["Case"], caseLevel > 0 {
                    batteryCell("Case")
                        .padding(.top, 3)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 18)
                }
                HStack(spacing: 8) {
                    batteryCell("Left")
                    batteryCell("Right")
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.battery["Case"])
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.24), .white.opacity(0.06), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .padding(.top, 2)
    }

    private var connectedControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Earbud controls")
                .font(.headline)

            if !model.controlStatus.isEmpty && model.controlStatus != "Air 7 control link connected." {
                Text(model.controlStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Noise control")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 5) {
                        ForEach(Air7NoiseMode.allCases) { mode in
                            modeButton(mode)
                        }
                    }
                }
                .padding(.bottom, 9)

                Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)

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
                .padding(.vertical, 8)

                Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)

                settingRow("EQ Presets", icon: "slider.horizontal.3") {
                    Menu {
                        ForEach(model.eqPresets) { preset in
                            Button(preset.title) { model.setEQ(preset.id) }
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
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(!model.eqAvailable)
                    .accessibilityLabel("EQ preset: \(model.eqPreset ?? "Choose preset")")
                }
                .padding(.top, 8)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                    .allowsHitTesting(false)
            }
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
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                model.setNoiseMode(mode)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .scaleEffect(selected ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
                    .frame(width: 34, height: 34)
                    .background(selected ? realmeGreen.opacity(0.18) : Color.primary.opacity(0.06), in: Circle())
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? realmeGreen : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 55)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(realmeGreen.opacity(0.11))
                        .matchedGeometryEffect(id: "selected-noise-mode", in: modeSelectionAnimation)
                }
            }
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
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title).font(.body)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 28)
    }

    private func batteryCell(_ side: String) -> some View {
        let level = model.battery[side]
        let tint: Color = (level ?? 100) <= 20 ? .orange : realmeGreen
        let isCase = side == "Case"
        return VStack(spacing: 7) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 4)
                if let level {
                    Circle()
                        .trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: level)
                }
                VStack(spacing: 1) {
                    Image(systemName: isCase ? "battery.100percent" : "earbuds")
                        .font(.system(size: isCase ? 14 : 15, weight: .medium))
                        .rotationEffect(.degrees(side == "Left" ? -18 : (side == "Right" ? 18 : 0)))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(level.map { "\($0)%" } ?? "—")
                        .font(.system(size: isCase ? 12 : 11, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(level == nil ? .secondary : .primary)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: isCase ? 68 : 60, height: isCase ? 68 : 60)
            .accessibilityHidden(true)
            Text(isCase ? "Charging Case" : side)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.map { "\(isCase ? "Charging case" : side) battery \($0) percent" } ?? "\(isCase ? "Charging case" : side) battery unavailable")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show pop-up when earbuds connect", isOn: Binding(
                get: { model.showOnConnection },
                set: model.setShowOnConnection
            ))
            .toggleStyle(.checkbox)
            .font(.subheadline)

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: model.setLaunchAtLogin
            ))
            .toggleStyle(.checkbox)
            .font(.subheadline)

            HStack {
                Text("Quit App")
                Spacer()
                Text("⇧⌘R")
                    .font(.system(.caption, design: .rounded).weight(.medium).monospaced())
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.leading, 26)
            .padding(.trailing, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Quit App, Shift Command R")
        }
    }
}

private struct LowBatteryFloatingAlert: View {
    let levels: [String: Int]
    private let warning = Color(red: 1.0, green: 0.68, blue: 0.32)

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
                Text("Low Battery")
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
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.27), .white.opacity(0.07), warning.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Low battery. \(sideDescription). \(batteryDescription)")
    }
}

private struct BatteryPopupView: View {
    @ObservedObject var model: EarbudModel
    private let accent = Color(red: 0.12, green: 0.82, blue: 0.48)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.outputName ?? "Air 7").font(.headline).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 6, height: 6)
                        Text("Connected").font(.caption).foregroundStyle(accent)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                batteryCell("Left")
                batteryCell("Right")
            }
        }
        .padding(18)
        .frame(width: 480)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
            }
        }
        .tint(accent)
    }

    private func batteryCell(_ side: String) -> some View {
        let level = model.battery[side]
        return HStack(spacing: 9) {
            Image(systemName: "earbuds")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent)
                .rotationEffect(.degrees(side == "Left" ? -18 : 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(side).font(.caption).foregroundStyle(.secondary)
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.map { "\(side) battery \($0) percent" } ?? "\(side) battery unavailable")
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
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 148),
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
        batteryPanel.setContentSize(NSSize(width: 480, height: 148))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let top = screen.safeAreaInsets.top > 0
                ? screen.frame.maxY - screen.safeAreaInsets.top
                : screen.visibleFrame.maxY
            batteryPanel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - batteryPanel.frame.width / 2,
                y: top - batteryPanel.frame.height - 8
            ))
        }
        batteryPanel.orderFrontRegardless()
        NSLog("Air7Menu battery pop-up ordered front; visible=%d", batteryPanel.isVisible)
        dismissalTimer?.invalidate()
        dismissalTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak batteryPanel] _ in
            batteryPanel?.orderOut(nil)
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
