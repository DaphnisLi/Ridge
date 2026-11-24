import Foundation
import SwiftUI

/// 浏览器下载（产品 **C**）：单独全岛；与计时左下右计；与音乐左音右下；不做假进度条。
@MainActor
final class DownloadCompleteTipWidget: IslandWidget {
    static let manifest = WidgetManifest(
        id: "builtin.downloadComplete",
        displayName: L10n.DownloadComplete.widgetName,
        summary: L10n.DownloadComplete.widgetSummary,
        source: .builtin,
        kind: .content,
        supportsPinning: false,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    var title: String { "" }

    init(context: WidgetContext) {
        self.context = context
        DownloadCompleteSession.shared.start()
        context.log("下载完成小组件已创建（常驻待命模式）")
    }

    func makeView() -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: 1))
    }

    func onAppear() {
        context.log("下载完成 onAppear（不占内容分页）")
        DownloadCompleteSession.shared.start()
    }

    func onDisappear() {
        context.log("下载完成 onDisappear")
    }

    func refresh() {
        // 目录监视自驱；无主动 refresh。
    }
}
