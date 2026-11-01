import AppKit
import SwiftUI

/// 浮层 NSPanel 上系统 ScrollView 经常滚不动。
/// 内容用 offset 平移；滚轮 / 触控板走本地监视。不绘制可视滚动条，内容铺满宽度。
struct AlwaysVisibleScrollView<Content: View>: View {
    /// 视口实心底。半透明行在 `.clipped()` 边缘会透出岛黑底，滚动时首尾行会闪色；必须用不透明色垫住。
    var viewportFill: Color? = Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 1))
    @ViewBuilder var content: () -> Content
    @StateObject private var model = ManualScrollModel()

    var body: some View {
        GeometryReader { geo in
            let viewport = geo.size

            ZStack(alignment: .topLeading) {
                if let viewportFill {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(viewportFill)
                }

                content()
                    .frame(width: viewport.width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { contentGeo in
                            Color.clear.preference(
                                key: ScrollContentHeightKey.self,
                                value: contentGeo.size.height
                            )
                        }
                    )
                    .offset(y: -model.offset)
                    .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
                    .clipped()
            }
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .contentShape(Rectangle())
            .background(ScrollViewportFrameReporter(model: model))
            .onAppear {
                model.viewportHeight = viewport.height
                WheelScrollMonitor.shared.acquire(model)
                AppLog.info("Scroll", "手动滚动区已显示", [
                    "viewportH": viewport.height,
                    "contentH": model.contentHeight,
                    "canScroll": model.maxOffset > 1,
                    "hasFill": viewportFill != nil
                ])
            }
            .onDisappear {
                WheelScrollMonitor.shared.release(model)
            }
            .onChange(of: viewport.height) { _, h in
                model.viewportHeight = h
                model.clamp()
            }
            .onPreferenceChange(ScrollContentHeightKey.self) { h in
                model.setContentHeight(h)
            }
        }
    }
}

@MainActor
final class ManualScrollModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var offset: CGFloat = 0
    @Published var contentHeight: CGFloat = 0
    @Published var viewportHeight: CGFloat = 0
    /// 视口在屏幕坐标中的矩形，供滚轮命中左右两栏。
    var screenFrame: CGRect = .zero

    var maxOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    func setContentHeight(_ h: CGFloat) {
        guard abs(contentHeight - h) > 0.5 else { return }
        contentHeight = h
        clamp()
        AppLog.debug("Scroll", "滚动内容高度", [
            "contentH": h,
            "viewportH": viewportHeight,
            "canScroll": maxOffset > 1
        ])
    }

    func applyWheel(deltaY: CGFloat) {
        // 触控板手指上滑 deltaY>0 → 内容上移 → offset 增大。
        let next = min(max(0, offset - deltaY), maxOffset)
        guard abs(next - offset) > 0.05 else { return }
        offset = next
    }

    func clamp() {
        offset = min(max(0, offset), maxOffset)
    }
}

private struct ScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
final class WheelScrollMonitor {
    static let shared = WheelScrollMonitor()

    private var monitor: Any?
    private var models: [UUID: ManualScrollModel] = [:]

    func acquire(_ model: ManualScrollModel) {
        models[model.id] = model
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            guard WidgetRuntime.shared.isControlDeckPage else { return event }
            // 货架 / 项目释放等面板共用；靠指针命中决定滚哪一栏。

            let dx: CGFloat
            let dy: CGFloat
            if event.hasPreciseScrollingDeltas {
                dx = event.scrollingDeltaX
                dy = event.scrollingDeltaY
            } else {
                dx = event.deltaX * 10
                dy = event.deltaY * 10
            }
            guard abs(dy) >= abs(dx), abs(dy) > 0.05 else { return event }

            let mouse = NSEvent.mouseLocation
            // 优先滚指针下方那一栏，避免左右两栏一起动。
            let hit = self.models.values.first {
                $0.maxOffset > 1 && $0.screenFrame.insetBy(dx: -6, dy: -6).contains(mouse)
            }
            if let hit {
                hit.applyWheel(deltaY: dy)
                return nil
            }
            return event
        }
        AppLog.info("Scroll", "滚轮监视已启动", ["regions": models.count])
    }

    func release(_ model: ManualScrollModel) {
        models.removeValue(forKey: model.id)
        guard models.isEmpty, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        AppLog.info("Scroll", "滚轮监视已停止")
    }
}

/// 把 SwiftUI 视口框报到屏幕坐标，给滚轮监视做命中。
private struct ScrollViewportFrameReporter: NSViewRepresentable {
    let model: ManualScrollModel

    func makeNSView(context: Context) -> FrameReportingView {
        let view = FrameReportingView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: FrameReportingView, context: Context) {
        nsView.model = model
        nsView.reportFrame()
    }
}

private final class FrameReportingView: NSView {
    weak var model: ManualScrollModel?

    override func layout() {
        super.layout()
        reportFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrame()
    }

    func reportFrame() {
        guard let window else { return }
        let rectInWindow = convert(bounds, to: nil)
        let screen = window.convertToScreen(rectInWindow)
        model?.screenFrame = screen
    }
}
