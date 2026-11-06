import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 瞬时暂存区：左栏空态用方案一；整岛拖入用左右双舱（暂存 / 隔空传送）。
struct ShelfDropStagingView: View {
    var highlighted: Bool = false
    /// 整岛拖入态（方案三吸附）。
    var fillsIsland: Bool = false
    /// 铺满左栏矩形（方案一静息）。
    var fillsContainer: Bool = false

    @State private var shelfZoneTargeted = false
    @State private var airDropZoneTargeted = false

    private let accent = Color(red: 0.23, green: 0.51, blue: 0.96)
    private let accentBright = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let airDropAccent = Color(red: 0.20, green: 0.78, blue: 0.90)
    private let emerald = Color(red: 0.31, green: 0.83, blue: 0.40)
    private let glassHover = Color(red: 0.055, green: 0.106, blue: 0.192)

    var body: some View {
        Group {
            if fillsIsland {
                magneticActiveBody
            } else {
                idleSchemeOneBody
            }
        }
        .animation(.easeOut(duration: 0.18), value: highlighted || fillsIsland)
        .animation(.easeOut(duration: 0.12), value: shelfZoneTargeted || airDropZoneTargeted)
        .accessibilityElement(children: fillsIsland ? .contain : .combine)
        .accessibilityLabel(fillsIsland ? L10n.Shelf.dropActiveHint : L10n.Shelf.dropHint)
        .accessibilityHint(fillsIsland ? L10n.Shelf.dropActiveDetail : L10n.Shelf.dropHintDetail)
    }

    // MARK: - 方案一：左栏空态（垂直居中）

    private var idleSchemeOneBody: some View {
        VStack(spacing: 10) {
            idleIcon

            VStack(spacing: 4) {
                Text(L10n.Shelf.dropHint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L10n.Shelf.dropHintDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ramBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: fillsContainer ? .infinity : nil, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            accent.opacity(0.32),
                            style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                        )
                )
        )
    }

    private var idleIcon: some View {
        BobbingBadge(amplitude: 2.5, period: 2.0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: NSColor(calibratedWhite: 0.22, alpha: 0.85)),
                                Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 0.90))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)
        }
    }

    private var ramBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(emerald)
                .frame(width: 5, height: 5)
            Text(L10n.Shelf.dropRamBadge)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.top, 2)
    }

    // MARK: - 方案三：整岛拖入 · 左暂存 / 右隔空传送

    private var magneticActiveBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(glassHover.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.40), lineWidth: 1.5)
                )
                .shadow(color: accentBright.opacity(0.22), radius: 28, y: 8)

            HStack(spacing: 10) {
                dropZone(
                    title: L10n.Shelf.dropActiveHint,
                    detail: L10n.Shelf.dropActiveDetail,
                    symbol: "plus",
                    tint: accent,
                    targeted: shelfZoneTargeted,
                    accessibilityLabel: L10n.Shelf.dropActiveHint
                )
                .onDrop(of: [.fileURL], isTargeted: $shelfZoneTargeted) { providers in
                    AppLog.info("Shelf", "左舱接收拖入（暂存）", ["providers": providers.count])
                    return ShelfClipboardDeckView.ingestDrop(providers: providers, into: ShelfStore.shared)
                }

                dropZone(
                    title: L10n.Shelf.dropAirDropHint,
                    detail: L10n.Shelf.dropAirDropDetail,
                    symbol: "dot.radiowaves.left.and.right",
                    tint: airDropAccent,
                    targeted: airDropZoneTargeted,
                    accessibilityLabel: L10n.Shelf.dropAirDropHint
                )
                .onDrop(of: [.fileURL], isTargeted: $airDropZoneTargeted) { providers in
                    AppLog.info("Shelf", "右舱接收拖入（隔空传送）", ["providers": providers.count])
                    return Self.ingestAirDrop(providers: providers)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: shelfZoneTargeted) { _, targeted in
            if targeted {
                IslandController.shared?.setShelfDropTargeted(true)
            }
        }
        .onChange(of: airDropZoneTargeted) { _, targeted in
            if targeted {
                IslandController.shared?.setShelfDropTargeted(true)
            }
        }
    }

    private func dropZone(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        targeted: Bool,
        accessibilityLabel: String
    ) -> some View {
        VStack(spacing: 10) {
            BobbingBadge(amplitude: targeted ? 3.2 : 2.4, period: targeted ? 0.85 : 1.1) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint)
                        .shadow(color: tint.opacity(targeted ? 0.65 : 0.45), radius: targeted ? 14 : 10, y: 3)

                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            }

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .tracking(0.2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(targeted ? 0.92 : 0.70))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(targeted ? 0.22 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(targeted ? 0.95 : 0.55), lineWidth: targeted ? 2 : 1.4)
                )
                .shadow(color: tint.opacity(targeted ? 0.35 : 0.18), radius: targeted ? 16 : 10, y: 0)
        )
        .scaleEffect(targeted ? 1.02 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(detail)
    }

    // MARK: - AirDrop

    /// 解析拖入文件并唤起系统隔空传送。
    static func ingestAirDrop(providers: [NSItemProvider]) -> Bool {
        var claimed = false
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            let typeID: String?
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                typeID = UTType.fileURL.identifier
            } else if let first = provider.registeredTypeIdentifiers.first {
                typeID = first
            } else {
                typeID = nil
            }
            guard let typeID else { continue }
            claimed = true
            group.enter()
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, error in
                defer { group.leave() }
                if let error {
                    AppLog.warn("Shelf", "隔空传送：读取拖入文件失败", [
                        "error": error.localizedDescription
                    ])
                    return
                }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                }
                guard let resolved = url?.standardizedFileURL else { return }
                lock.lock()
                urls.append(resolved)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            IslandController.shared?.setShelfDropTargeted(false)
            ShelfDropSession.shared.setActive(false, reason: "airDropComplete")
            guard !urls.isEmpty else {
                AppLog.warn("Shelf", "隔空传送：无有效文件 URL")
                return
            }
            guard let service = NSSharingService(named: .sendViaAirDrop) else {
                AppLog.warn("Shelf", "隔空传送：系统服务不可用", ["urls": urls.count])
                return
            }
            guard service.canPerform(withItems: urls) else {
                AppLog.warn("Shelf", "隔空传送：当前项目不可发送", ["urls": urls.count])
                return
            }
            // 松手后再抢前台，避免拖拽过程中 activate 掐断 Finder；面板需要前台才能弹出。
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
            AppLog.info("Shelf", "隔空传送：唤起系统面板", ["urls": urls.count])
            service.perform(withItems: urls)
        }
        return claimed
    }
}

/// 整块徽章上下轻浮（蓝底 + 符号一起动）。
private struct BobbingBadge<Content: View>: View {
    var amplitude: CGFloat = 2.5
    var period: Double = 2.0
    @ViewBuilder var content: () -> Content

    @State private var bobbing = false

    var body: some View {
        content()
            .offset(y: bobbing ? amplitude : -amplitude)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    bobbing = true
                }
            }
    }
}
