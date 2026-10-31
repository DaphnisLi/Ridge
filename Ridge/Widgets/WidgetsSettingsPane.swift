import SwiftUI

struct WidgetsSettingsPane: View {
    @ObservedObject var settings: WidgetSettings
    private let registry = WidgetRegistry.shared

    private var libraryOrder: [WidgetID] {
        settings.order.filter { registry.manifest(for: $0)?.showsInLibrary == true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("显示优先级")
                            .font(.headline)

                        if libraryOrder.isEmpty {
                            Text("暂无可用小组件。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            List {
                                ForEach(libraryOrder, id: \.self) { id in
                                    if let manifest = registry.manifest(for: id) {
                                        WidgetOrderRow(manifest: manifest)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                    }
                                }
                                .onMove(perform: settings.move)
                            }
                            .listStyle(.plain)
                            .frame(minHeight: CGFloat(max(libraryOrder.count, 1)) * 56)
                            .environment(\.defaultMinListRowHeight, 52)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .background(Color.white)
        .onAppear {
            settings.reconcile(with: registry)
        }
    }
}

private struct WidgetOrderRow: View {
    let manifest: WidgetManifest

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(manifest.displayName)
                    .font(.body.weight(.medium))
                Text(manifest.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 28)
                .contentShape(Rectangle())
                .help("拖拽排序")
        }
        .padding(.vertical, 4)
    }
}
