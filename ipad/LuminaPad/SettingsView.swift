import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var baseURL = ""
    @State private var token = ""
    @State private var cloudflareID = ""
    @State private var cloudflareSecret = ""
    @State private var revealSecrets = false
    @State private var showingAdvanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    LuminaPageHeader("设置", subtitle: "场景、小组件与本地网关")

                    SceneManagementView()

                    LuminaSectionHeader("本地网关", subtitle: "Hub 负责场景存储、日程与运行")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 410), spacing: 18)], spacing: 18) {
                        connectionCard
                        statusCard
                    }

                    securityCard
                }
                .frame(maxWidth: 1320)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 128)
                .frame(maxWidth: .infinity)
            }
            .luminaPageBackground()
            .navigationBarHidden(true)
            .task { load() }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("连接信息", systemImage: "router.fill")
                .font(.title3.bold())
                .foregroundStyle(LuminaTheme.midnight)

            LuminaField(title: "网关地址", icon: "network") {
                TextField("http://192.168.x.x:17890", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            LuminaField(title: "配对 Token", icon: "key.fill") {
                secretField("配对 Token", text: $token)
            }

            DisclosureGroup("Cloudflare Access（可选）", isExpanded: $showingAdvanced) {
                VStack(spacing: 14) {
                    LuminaField(title: "Client ID", icon: "person.badge.key") {
                        TextField("CF-Access-Client-Id", text: $cloudflareID)
                            .textInputAutocapitalization(.never)
                    }
                    LuminaField(title: "Client Secret", icon: "lock.fill") {
                        secretField("CF-Access-Client-Secret", text: $cloudflareSecret)
                    }
                    Toggle("显示敏感字段", isOn: $revealSecrets)
                }
                .padding(.top, 14)
            }
            .tint(LuminaTheme.indigo)

            Button {
                Task {
                    _ = await model.saveConnection(.init(
                        baseURL: baseURL,
                        bearerToken: token,
                        cloudflareClientID: cloudflareID,
                        cloudflareClientSecret: cloudflareSecret
                    ))
                }
            } label: {
                Label(model.isLoading ? "正在测试…" : "保存并测试", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(LuminaTheme.indigo)
            .disabled(baseURL.isEmpty || token.isEmpty || model.isLoading)
        }
        .luminaCard(padding: 22, cornerRadius: 30)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("网关状态", systemImage: "server.rack")
                    .font(.title3.bold())
                Spacer()
                StatusPill(online: model.isOnline)
            }
            Divider()
            LabeledContent("设备", value: "\(model.devices.count)")
            LabeledContent("场景", value: "\(model.scenes.count)")
            if let lastUpdated = model.lastUpdated {
                LabeledContent("最近同步", value: lastUpdated.formatted(date: .abbreviated, time: .shortened))
            }
            HStack(spacing: 12) {
                Button {
                    Task { await model.discover() }
                } label: {
                    Label("发现灯具", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("立即同步", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .tint(LuminaTheme.indigo)
        }
        .luminaCard(padding: 22, cornerRadius: 30)
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("局域网优先", systemImage: "lock.shield.fill").font(.headline)
            Text("WiZ UDP 38899 与 Yeelight TCP 55443 不对公网开放。iPad 是控制端；场景、日程和持续运行仍由常开的 Hub 负责。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .luminaCard(padding: 18, cornerRadius: 24)
    }

    @ViewBuilder
    private func secretField(_ title: String, text: Binding<String>) -> some View {
        if revealSecrets {
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .font(.body.monospaced())
        } else {
            SecureField(title, text: text)
                .textInputAutocapitalization(.never)
                .font(.body.monospaced())
        }
    }

    private func load() {
        baseURL = model.connection.baseURL
        token = model.connection.bearerToken
        cloudflareID = model.connection.cloudflareClientID
        cloudflareSecret = model.connection.cloudflareClientSecret
    }
}

private struct LuminaField<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                content
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(LuminaTheme.cloud.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }
}
