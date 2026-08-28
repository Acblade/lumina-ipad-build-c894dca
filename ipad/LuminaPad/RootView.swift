import SwiftUI
import UIKit

enum SidebarDestination: String, CaseIterable, Identifiable {
    case lights
    case modes
    case settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lights: "灯光"
        case .modes: "模式"
        case .settings: "设置"
        }
    }
    var icon: String {
        switch self {
        case .lights: "lightbulb.fill"
        case .modes: "sparkles"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var selection: SidebarDestination = .lights

    var body: some View {
        Group {
            switch selection {
            case .lights: DashboardView()
            case .modes: ModesView()
            case .settings: SettingsView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LuminaNavigationBar(selection: $selection)
        }
        .alert("Lumina", isPresented: errorBinding) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .overlay(alignment: .top) {
            if let message = model.confirmationMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LuminaTheme.midnight)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThickMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.2))
                        if model.confirmationMessage == message { model.confirmationMessage = nil }
                    }
            }
        }
        .animation(.snappy, value: model.confirmationMessage)
        .sheet(item: $model.pendingPairing) { pairing in
            VStack(alignment: .leading, spacing: 22) {
                Label("连接 Lumina Hub", systemImage: "qrcode.viewfinder")
                    .font(.title2.bold())
                Text("确认连接到以下 Hub。Token 不会显示，也不会发送到其他服务。")
                    .foregroundStyle(.secondary)
                Text(pairing.connection.effectiveLocalBaseURL.isEmpty
                    ? pairing.connection.relayBaseURL
                    : pairing.connection.effectiveLocalBaseURL)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                if let errorMessage = model.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Button("打开系统设置") {
                            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(settingsURL)
                        }
                    }
                }
                HStack {
                    Button("取消", role: .cancel) { model.cancelPendingPairing() }
                    Spacer()
                    Button("连接并验证") {
                        Task { await model.confirmPendingPairing() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LuminaTheme.indigo)
                    .disabled(model.isLoading)
                }
            }
            .padding(28)
            .presentationDetents([.medium])
            .interactiveDismissDisabled(model.isLoading)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && model.pendingPairing == nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct LuminaNavigationBar: View {
    @Binding var selection: SidebarDestination

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(SidebarDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        Label(destination.title, systemImage: destination.icon)
                            .font(.headline)
                            .labelStyle(LuminaNavigationLabelStyle(selected: selection == destination))
                            .foregroundStyle(selection == destination ? LuminaTheme.midnight : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .background(selection == destination ? LuminaTheme.selectedNavigation : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
            .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(LuminaTheme.navigation)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
}

private struct LuminaNavigationLabelStyle: LabelStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon.font(.title3)
            configuration.title.font(.caption.weight(selected ? .bold : .medium))
        }
    }
}
