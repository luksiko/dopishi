import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var l10n: LocalizationManager
    @ObservedObject private var service = ServiceStatus.shared
    @State private var copies: [URL] = []
    @State private var hasAccessibility = AccessibilityService.hasAccessibilityPermission

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(l10n.t("permissions.title"))
                    .font(.headline)

                Text(l10n.t("permissions.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GroupBox {
                    HStack {
                        Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasAccessibility ? .green : .orange)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text(l10n.t("permissions.accessibilityTitle"))
                                .font(.body)
                                .bold()
                            Text(hasAccessibility ? l10n.t("permissions.granted") : l10n.t("permissions.notGranted"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !hasAccessibility {
                            Button(l10n.t("permissions.grantAccess")) {
                                AccessibilityService.requestAccessibilityPermission()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(4)
                }

                if !hasAccessibility {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(l10n.t("permissions.howToEnable"))
                                .font(.subheadline)
                                .bold()

                            Text(l10n.t("permissions.step1"))
                            Text(l10n.t("permissions.step2"))
                            Text(l10n.t("permissions.step3"))
                            Text(l10n.t("permissions.step4"))
                        }
                        .font(.caption)
                        .padding(4)
                    }

                    Button(l10n.t("permissions.openSettings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n.t("permissions.serviceTitle")).bold()
                        Label(l10n.t(service.state.key), systemImage: service.state == .running ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(service.state == .running ? .green : .orange)
                        Text(l10n.t("permissions.serviceDetail")).font(.caption).foregroundStyle(.secondary)
                        Button(l10n.t("permissions.restartService")) { service.onRestart?() }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n.t("permissions.copiesTitle")).bold()
                        Text(l10n.t("permissions.copiesDetail")).font(.caption).foregroundStyle(.secondary)
                        ForEach(copies, id: \.path) { url in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l10n.t(url.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath() ? "permissions.currentCopy" : "permissions.otherCopy"))
                                    .font(.caption).bold()
                                Text(url.path).font(.caption).textSelection(.enabled)
                                Button(l10n.t("permissions.revealCopy")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }.font(.caption)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                Spacer()

                Button(l10n.t("permissions.refreshStatus")) {
                    refresh()
                }
                .font(.caption)
            }
            .padding()
        }
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            hasAccessibility = AccessibilityService.hasAccessibilityPermission
        }
    }

    private func refresh() {
        hasAccessibility = AccessibilityService.hasAccessibilityPermission
        let identifier = Bundle.main.bundleIdentifier ?? "com.dopishi.app"
        let registered = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).compactMap(\.bundleURL)
        copies = ServiceStatus.uniqueCopies([Bundle.main.bundleURL] + registered + running)
    }
}

@MainActor
final class ServiceStatus: ObservableObject {
    enum State: String {
        case disabled, permissionRequired, running, failed
        var key: String { "permissions.service." + rawValue }
    }

    static let shared = ServiceStatus()
    @Published var state: State = .disabled
    var onRestart: (() -> Void)?

    static func uniqueCopies(_ urls: [URL]) -> [URL] {
        Array(Set(urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
    }
}
