import AppKit
import SwiftUI

/// 设置页卡片 → 灵动岛的飞入动画（独立浮层窗，不抢正式 Runtime）。
@MainActor
final class WidgetFlyAnimator {
    static let shared = WidgetFlyAnimator()

    private var panel: NSPanel?
    private var completion: (() -> Void)?

    private init() {}

    func cancel() {
        panel?.orderOut(nil)
        panel = nil
        let done = completion
        completion = nil
        done?()
    }

    /// `from` / `to` 均为 AppKit 屏幕坐标（原点左下）。
    func play(
        widgetID: WidgetID,
        from: CGRect,
        to: CGRect,
        completion: @escaping () -> Void
    ) {
        cancel()
        self.completion = completion

        let start = normalized(from)
        let end = normalized(to)
        guard start.width > 2, start.height > 2, end.width > 2, end.height > 2 else {
            AppLog.warn("Island", "飞入动画跳过：无效矩形", [
                "id": widgetID,
                "from": "\(Int(start.width))x\(Int(start.height))",
                "to": "\(Int(end.width))x\(Int(end.height))"
            ])
            finish()
            return
        }

        let palette = IslandSettings.shared.theme.palette
        let root = WidgetFlyPreviewView(
            widgetID: widgetID,
            palette: palette,
            bottomRadius: CGFloat(IslandSettings.shared.bottomCornerRadius)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: start.size)

        let panel = NSPanel(
            contentRect: start,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        panel.setFrame(start, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        AppLog.info("Island", "小组件飞入动画开始", [
            "id": widgetID,
            "duration": 0.48
        ])

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.48
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel?.orderOut(nil)
                self?.panel = nil
                self?.finish()
            }
        })
    }

    private func finish() {
        let done = completion
        completion = nil
        done?()
    }

    private func normalized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: max(rect.width, 1),
            height: max(rect.height, 1)
        )
    }
}

// MARK: - 飞入预览内容

private struct WidgetFlyPreviewView: View {
    let widgetID: WidgetID
    let palette: IslandPalette
    let bottomRadius: CGFloat

    var body: some View {
        let shape = IslandPanelShape(bottomRadius: max(8, bottomRadius * 0.6))
        Group {
            if let view = WidgetPreviewFactory.makeView(for: widgetID) {
                view
                    .padding(.horizontal, 10)
            } else {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(palette.icon)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(palette.fill))
        .clipShape(shape)
        .environment(\.islandPalette, palette)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .padding(4)
    }
}

/// 预览 / 飞入共用：不接入正式 Runtime 的临时实例。
enum WidgetPreviewFactory {
    @MainActor
    static func makeView(for id: WidgetID) -> AnyView? {
        let context = PreviewWidgetContext(widgetID: id)
        guard let widget = WidgetRegistry.shared.make(id: id, context: context) else {
            return nil
        }
        widget.refresh()
        return widget.makeView()
    }
}

@MainActor
final class PreviewWidgetContext: WidgetContext {
    let widgetID: WidgetID

    init(widgetID: WidgetID) {
        self.widgetID = widgetID
    }

    func requestDisplay() {}
    func withdrawDisplay() {}

    func openSettings() {
        SettingsNavigator.shared.open(.widgets)
    }

    func log(_ message: String, fields: [String: Any] = [:]) {
        var merged = fields
        merged["widget"] = widgetID
        merged["preview"] = true
        AppLog.debug("Widget", message, merged)
    }

    func storageKey(_ name: String) -> String {
        "widget.\(widgetID).preview.\(name)"
    }
}
