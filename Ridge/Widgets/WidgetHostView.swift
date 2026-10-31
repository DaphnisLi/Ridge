import SwiftUI

/// 岛展开区宿主：当前 widget + 底部分页点。
/// 左右切换由 `IslandHitTestView` 的 AppKit 拖拽 / 触控板横滑处理（SwiftUI DragGesture 在本 Panel 上无效）。
struct WidgetHostView: View {
    @ObservedObject var runtime: WidgetRuntime

    var body: some View {
        VStack(spacing: 8) {
            runtime.activeView()
                .id(runtime.contentEpoch)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.18), value: runtime.pageIndex)

            if !runtime.isShowingEmpty, runtime.pageIDs.count > 1 {
                HStack(spacing: 5) {
                    ForEach(Array(runtime.pageIDs.indices), id: \.self) { index in
                        Circle()
                            .fill(index == runtime.pageIndex
                                  ? Color.white.opacity(0.9)
                                  : Color.white.opacity(0.22))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.bottom, 2)
                .accessibilityLabel("小组件分页")
            }
        }
        .contentShape(Rectangle())
    }
}
