import AppKit
import SwiftUI

struct DiagnosticsSettingsView: View {
    @State private var monitor = DiagnosticsMonitor(nowPlaying: AppServices.shared.nowPlaying)
    @State private var isCopied = false
    private let settingsWindow = SettingsWindowController.shared
    private let menuBar = AppServices.shared.menuBar

    var body: some View {
        Form {
            Section {
                LabeledContent("CPU") {
                    cpuText(monitor.app?.cpu)
                }
                LabeledContent("Memory") {
                    memoryText(monitor.app?.memory)
                }
                LabeledContent("Peak memory") {
                    memoryText(monitor.app?.peakMemory)
                }
                if let helper = monitor.helper {
                    LabeledContent("Media helper") {
                        HStack(spacing: 12) {
                            cpuText(helper.cpu)
                            memoryText(helper.memory)
                        }
                    }
                }
            } header: {
                Text("Usage")
            } footer: {
                Text("Measured only while this tab is open. 100 % is one processor core.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Services") {
                ForEach(DiagnosticsReport.services()) { service in
                    LabeledContent {
                        ServiceDetail(service: service)
                    } label: {
                        Text(service.title)
                    }
                }
            }
            Section {
                LabeledContent("Report") {
                    Button(isCopied ? "Copied" : "Copy report") {
                        copyReport()
                    }
                    .disabled(isCopied)
                }
            } footer: {
                Text("The report lists your Mac model, macOS version, displays, \(AppInfo.name)'s settings and the state of its services. It contains no track, file path or location. Nothing is sent: it is only copied to the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { menuBar.refreshAccess() }
        .task(id: settingsWindow.isWindowVisible) {
            // The window can be closed, minimized or covered while this tab stays selected.
            guard settingsWindow.isWindowVisible else { return }
            await monitor.run()
        }
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }

    @ViewBuilder
    private func cpuText(_ cpu: Double?) -> some View {
        if let cpu {
            Text(cpu, format: .percent.precision(.fractionLength(1)))
                .monospacedDigit()
        } else {
            Text("Measuring…")
        }
    }

    @ViewBuilder
    private func memoryText(_ memory: UInt64?) -> some View {
        if let memory {
            Text(Int64(memory), format: .byteCount(style: .memory))
                .monospacedDigit()
        } else {
            Text("Measuring…")
        }
    }

    private func copyReport() {
        let report = DiagnosticsReport.text(app: monitor.app, helper: monitor.helper)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        isCopied = true
    }
}

private struct ServiceDetail: View {
    let service: ServiceStatus

    var body: some View {
        switch service.level {
        case .neutral:
            Text(service.detail)
        case .ok:
            Label { Text(service.detail) } icon: { Image(systemName: "checkmark.circle.fill") }
                .foregroundStyle(.green)
        case .warning:
            Label { Text(service.detail) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .foregroundStyle(.orange)
        case .failure:
            Label { Text(service.detail) } icon: { Image(systemName: "xmark.octagon.fill") }
                .foregroundStyle(.red)
        }
    }
}
