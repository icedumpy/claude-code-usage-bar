import SwiftUI
import UsageCore

/// Preferences form, shown in a standalone window from the dropdown's Settings…
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Refresh every", selection: $store.refreshInterval) {
                    Text("15 seconds").tag(TimeInterval(15))
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("60 seconds").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                }
                Toggle("Show reset countdown", isOn: $store.showCountdown)
                Picker("Show", selection: $store.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.label).tag($0) }
                }
                Picker("Driven by", selection: $store.heroChoice) {
                    ForEach(HeroLimitChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section("Dropdown") {
                Picker("Usage display", selection: $store.vizStyle) {
                    ForEach(VisualizationStyle.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Pinned panel") {
                HStack {
                    Text("Opacity")
                    Slider(value: $store.pinOpacity, in: 0.1...1.0)
                    Text("\(Int(store.pinOpacity * 100))%")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Toggle("Show weekly limits", isOn: $store.pinShowWeekly)
                Toggle("Show per-model breakdown", isOn: $store.pinShowModels)
            }

            Section("Alerts") {
                Toggle("Notify on high usage", isOn: $store.alertsEnabled)
                Stepper("Warn at \(store.warnThreshold)%",
                        value: $store.warnThreshold, in: 50...95, step: 5)
                    .disabled(!store.alertsEnabled)
                Stepper("Critical at \(store.critThreshold)%",
                        value: $store.critThreshold, in: 80...99, step: 1)
                    .disabled(!store.alertsEnabled)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.set(newValue)
                        let actual = LaunchAtLogin.isEnabled
                        if actual != newValue { launchAtLogin = actual }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 590)
    }
}
