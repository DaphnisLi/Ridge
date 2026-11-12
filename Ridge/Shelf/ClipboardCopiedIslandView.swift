import SwiftUI

/// 「已复制」刘海右侧 Ø32 圆形微岛（方案 02：流光绕圈 → 向心聚爆 → 板夹定格 → 绿勾咬合）。
/// 板夹主体始终可见：展开换页会重建 View，若图标从 opacity 0 起播，易卡在「只有黑圆」。
struct ClipboardCopiedIslandView: View {
    /// 无障碍补充（如「已复制 #0070EB」）；视觉为圆岛图标，不展示长文案。
    var detail: String? = nil
    /// 设置预览：跳过入场动效，直接定格终态。
    var compact: Bool = false
    /// 每次投递唯一 id；驱动 `.task` 重播入场，避免 onAppear 抖重建。
    var animationToken: String = "preview"

    /// 稿面 secondary-fixed 翠绿（#6FFB85）。
    private let accentGreen = Color(.sRGB, red: 111 / 255, green: 251 / 255, blue: 133 / 255, opacity: 1)

    private let diameter = IslandChrome.notchRightOrbDiameter

    @State private var orbitProgress: CGFloat = 0
    @State private var orbitOpacity: Double = 0
    @State private var orbitScale: CGFloat = 1
    @State private var sparkleScale: CGFloat = 0.3
    @State private var sparkleOpacity: Double = 0
    @State private var clipboardScale: CGFloat = 1
    @State private var badgeScale: CGFloat = 1
    @State private var badgeOpacity: Double = 1

    var body: some View {
        ZStack {
            // SwiftUI 纯黑底（圆岛不用 AppKit OpaqueFill，以免盖住符号）。
            Circle()
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))

            // Stage 1–2：外环流光 / 向心坍缩（叠在图标之上）
            Circle()
                .trim(from: 0, to: max(0.001, orbitProgress))
                .stroke(
                    AngularGradient(
                        colors: [
                            accentGreen.opacity(0),
                            accentGreen.opacity(0.55),
                            Color.white,
                            accentGreen
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(2)
                .opacity(orbitOpacity)
                .scaleEffect(orbitScale)
                .allowsHitTesting(false)

            // Stage 2：聚光脉冲
            Circle()
                .fill(accentGreen.opacity(0.40))
                .scaleEffect(sparkleScale)
                .opacity(sparkleOpacity)
                .blur(radius: 1.2)
                .allowsHitTesting(false)

            // Stage 3–4：单层板夹 + 绿勾（勿用 doc.on.clipboard 双页叠影）
            ZStack(alignment: .bottomTrailing) {
                SingleClipboardGlyph()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: 15, height: 17)
                    .scaleEffect(clipboardScale)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)

                ZStack {
                    Circle()
                        .fill(accentGreen)
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .frame(width: 11, height: 11)
                .offset(x: 2, y: 2)
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail?.isEmpty == false ? detail! : L10n.Shelf.copied)
        .task(id: animationToken) {
            if compact {
                settleImmediate()
                return
            }
            await playScheme2Entrance()
        }
        .onAppear {
            AppLog.debug("CopiedNotice", "圆岛已显示", [
                "tokenPrefix": String(animationToken.prefix(24)),
                "compact": compact,
                "detailPrefix": String((detail ?? "").prefix(16))
            ])
        }
    }

    private func settleImmediate() {
        orbitOpacity = 0
        orbitProgress = 0
        orbitScale = 1
        sparkleOpacity = 0
        clipboardScale = 1
        badgeScale = 1
        badgeOpacity = 1
    }

    /// 方案 02 时序：0–0.5s 流光 → 向心坍缩 → 板夹轻弹 → 绿勾咬合。
    /// 板夹默认可见；入场只做强调动画，中断时仍有图标。
    @MainActor
    private func playScheme2Entrance() async {
        settleImmediate()
        // 入场：先藏角标、略缩小板夹，再播流光。
        badgeOpacity = 0
        badgeScale = 0.2
        clipboardScale = 0.82

        orbitProgress = 0
        orbitScale = 1
        withAnimation(.easeIn(duration: 0.08)) {
            orbitOpacity = 1
        }
        withAnimation(.easeInOut(duration: 0.50)) {
            orbitProgress = 1
        }

        try? await Task.sleep(nanoseconds: 430_000_000)
        guard !Task.isCancelled else {
            settleImmediate()
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            orbitScale = 0.08
            orbitOpacity = 0
            orbitProgress = 0
        }
        withAnimation(.easeOut(duration: 0.24)) {
            sparkleScale = 1.45
            sparkleOpacity = 0.95
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else {
            settleImmediate()
            return
        }
        withAnimation(.easeOut(duration: 0.16)) {
            sparkleOpacity = 0
            sparkleScale = 1.6
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
            clipboardScale = 1
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else {
            settleImmediate()
            return
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
            badgeScale = 1
            badgeOpacity = 1
        }

        AppLog.info("CopiedNotice", "圆岛方案02入场完成", [
            "tokenPrefix": String(animationToken.prefix(24))
        ])
    }
}

/// 示意稿单层板夹：圆角板身 + 顶部夹扣，非 `doc.on.clipboard` 双文档。
private struct SingleClipboardGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 1, h > 1 else { return Path() }

        let boardInsetX = w * 0.12
        let boardTop = h * 0.22
        let boardCorner = min(w, h) * 0.14
        let clipW = w * 0.46
        let clipH = h * 0.18
        let clipX = (w - clipW) / 2
        let clipCorner = min(clipW, clipH) * 0.28

        var path = Path()
        // 板身
        path.addRoundedRect(
            in: CGRect(
                x: boardInsetX,
                y: boardTop,
                width: w - boardInsetX * 2,
                height: h - boardTop - h * 0.04
            ),
            cornerSize: CGSize(width: boardCorner, height: boardCorner)
        )
        // 顶部夹扣
        path.addRoundedRect(
            in: CGRect(x: clipX, y: h * 0.04, width: clipW, height: clipH),
            cornerSize: CGSize(width: clipCorner, height: clipCorner)
        )
        return path
    }
}
