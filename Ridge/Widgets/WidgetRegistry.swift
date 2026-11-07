import Foundation

/// 小组件注册表。内置启动登记；用户包 / AI 生成包热加载同样调用 `register`。
@MainActor
final class WidgetRegistry {
    static let shared = WidgetRegistry()

    private(set) var manifests: [WidgetManifest] = []
    private var factories: [WidgetID: WidgetFactory] = [:]

    private init() {}

    func register(_ module: WidgetModule) {
        register(manifest: module.manifest, factory: module.makeWidget)
    }

    func register(manifest: WidgetManifest, factory: @escaping WidgetFactory) {
        if factories[manifest.id] != nil {
            AppLog.warn("Widget", "重复注册，覆盖工厂", ["id": manifest.id])
            manifests.removeAll { $0.id == manifest.id }
        }
        manifests.append(manifest)
        factories[manifest.id] = factory
        AppLog.info("Widget", "已注册小组件", [
            "id": manifest.id,
            "title": manifest.displayName,
            "source": manifest.source.rawValue,
            "kind": manifest.kind.rawValue,
            "total": manifests.count
        ])
    }

    func unregister(_ id: WidgetID) {
        factories.removeValue(forKey: id)
        manifests.removeAll { $0.id == id }
        AppLog.info("Widget", "已注销小组件", ["id": id])
    }

    func make(id: WidgetID, context: WidgetContext) -> (any IslandWidget)? {
        guard let factory = factories[id] else {
            AppLog.warn("Widget", "工厂不存在，无法创建", ["id": id])
            return nil
        }
        let widget = factory(context)
        AppLog.debug("Widget", "已创建实例", ["id": id])
        return widget
    }

    func manifest(for id: WidgetID) -> WidgetManifest? {
        manifests.first { $0.id == id }
    }

    /// 设置列表 / 排序用（不含系统空态）。
    var libraryManifests: [WidgetManifest] {
        manifests.filter(\.showsInLibrary)
    }

    func registerBuiltins() {
        guard factories[SystemWidgetID.empty] == nil else { return }

        register(TypedWidgetModule<EmptyIslandWidget>())
        register(TypedWidgetModule<IslandNoticeWidget>())
        register(TypedWidgetModule<MeetingCountdownWidget>())
        register(TypedWidgetModule<MediaNowPlayingWidget>())
        register(TypedWidgetModule<FocusTimerWidget>())
        register(TypedWidgetModule<AIUsageWidget>())
        register(TypedWidgetModule<MoveReminderWidget>())

        // 用户 / AI 包：校验 manifest 后 register(manifest:factory:)，无需改 Runtime。
    }
}
