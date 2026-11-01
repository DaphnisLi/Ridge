import Foundation
import SwiftUI

typealias WidgetID = String

// MARK: - Manifest（目录 / 热加载 / AI 生成共用）

/// 小组件来源。用户与 AI 自定义走 `user` / `generated`，热加载同一注册通道。
enum WidgetSource: String, Codable, Hashable {
    case builtin
    case user
    case generated
}

/// 内容型参与调度；系统空态不进用户库、不参与排序。
enum WidgetKind: String, Codable, Hashable {
    case content
    case systemEmpty
}

/// 可序列化元数据：内置、用户包、AI 生成包均以此描述，便于目录与校验。
struct WidgetManifest: Identifiable, Hashable, Codable {
    let id: WidgetID
    let displayName: String
    let summary: String
    let version: String
    let source: WidgetSource
    let kind: WidgetKind
    /// 是否允许「常驻」pin。
    let supportsPinning: Bool
    /// 默认占格；用户稍后可改尺寸，本阶段只用默认值。
    let defaultGridSize: WidgetGridSize

    /// 出现在设置「显示优先级」列表中。
    var showsInLibrary: Bool { kind == .content }

    init(
        id: WidgetID,
        displayName: String,
        summary: String,
        version: String = "1.0.0",
        source: WidgetSource = .builtin,
        kind: WidgetKind = .content,
        supportsPinning: Bool = true,
        defaultGridSize: WidgetGridSize = .oneByOne
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.version = version
        self.source = source
        self.kind = kind
        self.supportsPinning = supportsPinning
        self.defaultGridSize = defaultGridSize
    }
}

// MARK: - Context（widget 唯一允许依赖的运行时面）

/// 注入给每个实例。自定义 / AI widget 只应依赖此协议，勿直连 Runtime 单例。
@MainActor
protocol WidgetContext: AnyObject {
    var widgetID: WidgetID { get }
    /// 有内容要占用灵动岛时调用。
    func requestDisplay()
    /// 内容结束，退出争夺。
    func withdrawDisplay()
    /// 打开设置（默认小组件页）。
    func openSettings()
    func log(_ message: String, fields: [String: Any])
    /// 按 widget 隔离的持久化前缀键。
    func storageKey(_ name: String) -> String
}

extension WidgetContext {
    func log(_ message: String) {
        log(message, fields: [:])
    }
}

// MARK: - Widget 协议

/// 所有小组件（内置 / 用户 / AI）必须实现。
///
/// 约定：
/// 1. 用 `static var manifest` 声明身份，勿在实例里改 id。
/// 2. 展示争夺只通过 `context.requestDisplay/withdrawDisplay`。
/// 3. `priority` 由框架写入，widget 内不要抢占。
/// 4. `makeView` 保持轻量；重活放 `refresh` / 后台任务。
@MainActor
protocol IslandWidget: AnyObject {
    static var manifest: WidgetManifest { get }

    init(context: WidgetContext)

    var priority: Int { get set }
    /// 是否正在争夺展示（有实时内容）。系统空态恒为 false。
    var wantsDisplay: Bool { get }
    var requestedAt: Date { get }

    func makeView() -> AnyView
    func onAppear()
    func onDisappear()
    func refresh()
}

extension IslandWidget {
    var id: WidgetID { Self.manifest.id }
    var title: String { Self.manifest.displayName }
}

// MARK: - Module（打包注册单元，热加载 / AI 落盘后 register 此类型）

@MainActor
protocol WidgetModule {
    var manifest: WidgetManifest { get }
    func makeWidget(context: WidgetContext) -> any IslandWidget
}

/// 用类型擦除包装任意 `IslandWidget` 类型，便于 Registry 存工厂。
struct TypedWidgetModule<W: IslandWidget>: WidgetModule {
    var manifest: WidgetManifest { W.manifest }

    func makeWidget(context: WidgetContext) -> any IslandWidget {
        W(context: context)
    }
}

typealias WidgetFactory = @MainActor (WidgetContext) -> any IslandWidget

enum SystemWidgetID {
    /// 系统空态岛：无用户小组件争夺时展示，不进设置排序列表。
    static let empty = "system.empty"
}
