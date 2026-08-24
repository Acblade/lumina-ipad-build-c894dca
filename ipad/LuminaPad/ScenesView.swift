import SwiftUI
import UIKit

struct ScenesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                SceneManagementView()
                    .padding(28)
            }
            .luminaPageBackground()
            .navigationBarHidden(true)
        }
    }
}

struct SceneManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editorScene: Scene?
    @State private var showingNewScene = false
    @State private var deletingScene: Scene?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LuminaSectionHeader("场景", subtitle: "场景、小组件与周计划") {
                Button {
                    showingNewScene = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(LuminaTheme.indigo, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if !model.activeRuns.isEmpty { activeRuns }

            if model.scenes.isEmpty {
                Text("还没有场景。创建后可自由设置每盏灯和时间变化。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .luminaCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 18)],
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(model.scenes) { scene in
                        SettingsSceneTile(
                            scene: scene,
                            isRunning: model.activeRuns.contains { $0.sceneId == scene.id },
                            run: { Task { await model.runScene(scene) } },
                            edit: { editorScene = scene },
                            delete: { deletingScene = scene }
                        )
                    }
                }
            }
        }
        .sheet(item: $editorScene) { scene in SceneEditorView(scene: scene) }
        .sheet(isPresented: $showingNewScene) { SceneEditorView(scene: nil) }
        .confirmationDialog(
            "删除“\(deletingScene?.name ?? "")”？",
            isPresented: Binding(get: { deletingScene != nil }, set: { if !$0 { deletingScene = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除场景", role: .destructive) {
                guard let scene = deletingScene else { return }
                Task {
                    _ = await model.deleteScene(scene)
                    deletingScene = nil
                }
            }
            Button("取消", role: .cancel) { deletingScene = nil }
        } message: {
            Text("Hub 中的场景和关联周计划都会被删除。")
        }
    }

    private var activeRuns: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.activeRuns) { run in
                HStack(spacing: 12) {
                    ProgressView().tint(LuminaTheme.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.scene(id: run.sceneId ?? "")?.name ?? "场景运行").font(.headline)
                        Text(run.status == "scheduled" ? "等待后续关键帧" : "正在执行")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("停止", role: .destructive) { Task { await model.stopRun(run) } }
                }
                .luminaCard(padding: 14, cornerRadius: 20)
            }
        }
    }
}

private struct SettingsSceneTile: View {
    let scene: Scene
    let isRunning: Bool
    let run: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: run) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [sceneColor(scene.color).opacity(0.72), sceneColor(scene.color)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 108, height: 138)
                    .overlay {
                        if isRunning {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: sceneSymbol(scene.icon, name: scene.name))
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }

                Text(scene.name)
                    .font(.headline)
                    .foregroundStyle(LuminaTheme.midnight)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: edit)
            Button("删除", systemImage: "trash", role: .destructive, action: delete)
        }
        .accessibilityHint("轻点运行，长按编辑或删除")
    }
}

func sceneSymbol(_ icon: String?, name: String = "") -> String {
    switch icon {
    case "scene_focus", "scene_concentrate": "viewfinder"
    case "scene_sleep": "moon.stars.fill"
    case "scene_relax": "leaf.fill"
    case "scene_cozy": "flame.fill"
    case "scene_true_colors": "paintpalette.fill"
    case "scene_off", "scene_all_off", "scene_close": "power"
    case let value? where UIImage(systemName: value) != nil: value
    default:
        let normalized = name.lowercased()
        if normalized.contains("关") || normalized.contains("off") { return "power" }
        if normalized.contains("睡") || normalized.contains("夜") { return "moon.stars.fill" }
        if normalized.contains("专注") || normalized.contains("集中") || normalized.contains("focus") { return "viewfinder" }
        if normalized.contains("放松") || normalized.contains("舒适") { return "leaf.fill" }
        if normalized.contains("原色") || normalized.contains("颜色") { return "paintpalette.fill" }
        if normalized.contains("暖") { return "cup.and.saucer.fill" }
        return "sparkles"
    }
}

func sceneColor(_ hex: String?) -> Color {
    Color(hex: hex ?? "") ?? LuminaTheme.indigo
}
