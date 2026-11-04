import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 控制台：瞬时货架（左）+ 剪贴板历史（右）。
struct ShelfClipboardDeckView: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var clipboard = ClipboardHistoryStore.shared
    @State private var clipboardSearch = ""
    @State private var bouncingShelfID: UUID?
    @State private var bouncingClipboardID: UUID?

    private let accentBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    private let accentPurple = Color(red: 0.545, green: 0.361, blue: 0.965)
    /// 稿面左右栏玻璃底：`rgba(14, 15, 20)`，比岛黑略抬一点灰。
    private let panelFill = Color(red: 14 / 255, green: 15 / 255, blue: 20 / 255)
    /// 稿面条目底：`bg-white/[0.03]` + `border-white/[0.05]`。
    private let itemFill = Color.white.opacity(0.03)
    private let itemBorder = Color.white.opacity(0.05)
    private let clipFill = Color.white.opacity(0.02)
    private let clipBorder = Color.white.opacity(0.06)

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 10
            let leftW = min(250, max(200, geo.size.width * 0.36))
            HStack(alignment: .top, spacing: gap) {
                shelfColumn
                    .frame(width: leftW, height: geo.size.height, alignment: .topLeading)
                clipboardColumn
                    .frame(
                        width: max(0, geo.size.width - leftW - gap),
                        height: geo.size.height,
                        alignment: .topLeading
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            clipboard.start()
            AppLog.info("Shelf", "货架页已显示", [
                "shelf": shelf.items.count,
                "clipboard": clipboard.items.count
            ])
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Shelf.deckTitle)
    }

    // MARK: - Shelf

    private var shelfColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            shelfHeader

            if shelf.items.isEmpty {
                ShelfDropStagingView(highlighted: false, fillsContainer: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 视口垫与栏底同色，半透明卡片滚动时不透出岛纯黑。
                AlwaysVisibleScrollView(viewportFill: panelFill) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(shelf.items) { item in
                            shelfRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .background(panelBackground(corner: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var shelfHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentBlue.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(accentBlue.opacity(0.30), lineWidth: 1)
                    )
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentBlue)
            }
            .frame(width: 28, height: 28)

            Text(L10n.Shelf.shelfTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            if !shelf.items.isEmpty {
                Button {
                    shelf.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.Shelf.clearShelf)
            }
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .offset(y: 8)
        }
        .padding(.bottom, 8)
    }

    private func shelfRow(_ item: ShelfItem) -> some View {
        let tint = badgeColors(for: item.badgeStyleKey)
        return HStack(spacing: 10) {
            Text(item.badgeLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(tint.fg)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(tint.fg.opacity(0.35), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                shelf.remove(id: item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.40))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.Shelf.removeItem)
            .opacity(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(itemFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(itemBorder, lineWidth: 1)
                )
        )
        .compositingGroup()
        .scaleEffect(bouncingShelfID == item.id ? 1.045 : 1)
        .offset(y: bouncingShelfID == item.id ? -2.5 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.42), value: bouncingShelfID == item.id)
        .contentShape(Rectangle())
        .onTapGesture {
            playBounce(id: item.id, shelf: true) {
                shelf.revealInFinder(id: item.id)
            }
        }
        .onDrag {
            AppLog.info("Shelf", "开始拖出货架项", ["name": item.name, "path": item.url.path])
            return item.makeDragItemProvider()
        }
        .contextMenu {
            Button(L10n.Shelf.showInFinder) {
                shelf.revealInFinder(id: item.id)
            }
            Button(L10n.Common.delete, role: .destructive) {
                shelf.remove(id: item.id)
            }
        }
    }

    private func badgeColors(for key: String) -> (bg: Color, fg: Color) {
        switch key {
        case "dir": return (Color.cyan.opacity(0.15), Color.cyan.opacity(0.9))
        case "pdf": return (Color.red.opacity(0.15), Color.red.opacity(0.9))
        case "image": return (Color.blue.opacity(0.15), Color.blue.opacity(0.9))
        case "svg": return (Color.orange.opacity(0.15), Color.orange.opacity(0.95))
        case "archive": return (Color.green.opacity(0.15), Color.green.opacity(0.9))
        case "video", "code": return (Color.purple.opacity(0.15), Color.purple.opacity(0.9))
        default: return (Color.white.opacity(0.08), Color.white.opacity(0.72))
        }
    }

    // MARK: - Clipboard

    private var clipboardColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            clipboardHeader

            let rows = filteredClipboardRows
            let hasQuery = !clipboardSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if clipboard.items.isEmpty {
                Text(L10n.Shelf.clipboardEmpty)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.40))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if rows.isEmpty {
                Text(L10n.Shelf.clipboardSearchEmpty)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.40))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                AlwaysVisibleScrollView(viewportFill: panelFill) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows) { item in
                            clipboardRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(hasQuery ? "search:\(clipboardSearch)" : "browse")
            }
        }
        .onChange(of: clipboardSearch) { _, query in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            AppLog.debug("Clipboard", "搜索筛选", [
                "queryLen": trimmed.count,
                "matches": filteredClipboardRows.count
            ])
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(corner: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var clipboardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentPurple.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(accentPurple.opacity(0.30), lineWidth: 1)
                        )
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentPurple)
                }
                .frame(width: 28, height: 28)

                Text(L10n.Shelf.clipboardTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                clipboardSearchField

                if !clipboard.items.isEmpty {
                    Button {
                        clipboard.clear()
                        clipboardSearch = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(L10n.Shelf.clearClipboard)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var clipboardSearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.40))
            TextField(
                "",
                text: $clipboardSearch,
                prompt: Text(L10n.Shelf.clipboardSearchPlaceholder)
                    .foregroundStyle(.white.opacity(0.35))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.88))
            .frame(minWidth: 96, maxWidth: 180)
            if !clipboardSearch.isEmpty {
                Button {
                    clipboardSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help(L10n.Shelf.clipboardSearchClear)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityLabel(L10n.Shelf.clipboardSearchPlaceholder)
    }

    private var filteredClipboardRows: [ClipboardHistoryItem] {
        let base = clipboard.items
        let query = clipboardSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { Self.matchesClipboardItem($0, query: query) }
    }

    private static func matchesClipboardItem(_ item: ClipboardHistoryItem, query: String) -> Bool {
        let needle = query.lowercased()
        if item.preview.lowercased().contains(needle) {
            return true
        }
        switch item.payload {
        case .text(let text):
            return text.lowercased().contains(needle)
        case .link(let url):
            return url.absoluteString.lowercased().contains(needle)
        case .color(_, let hex):
            return hex.lowercased().contains(needle)
        case .image, .screenshot:
            return false
        }
    }

    /// 稿面单行条目：左图标/摘要，右相对时间；无「刚刚复制 / 直贴」。
    private func clipboardRow(_ item: ClipboardHistoryItem) -> some View {
        HStack(spacing: 10) {
            clipboardLeadingGlyph(item)

            clipboardSummary(item)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accentBlue)
            }

            Text(relativeTime(item.createdAt))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(clipFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(clipBorder, lineWidth: 1)
                )
        )
        .compositingGroup()
        .scaleEffect(bouncingClipboardID == item.id ? 1.045 : 1)
        .offset(y: bouncingClipboardID == item.id ? -2.5 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.42), value: bouncingClipboardID == item.id)
        .contentShape(Rectangle())
        .onTapGesture {
            playBounce(id: item.id, shelf: false) {
                pasteClipboardItem(item)
            }
        }
        .contextMenu {
            Button(L10n.Shelf.copyAgain) {
                pasteClipboardItem(item)
            }
            Button(item.isPinned ? L10n.Shelf.unpin : L10n.Shelf.pin) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    clipboard.togglePin(id: item.id)
                }
            }
            Button(L10n.Common.delete, role: .destructive) {
                clipboard.remove(id: item.id)
            }
        }
    }

    @ViewBuilder
    private func clipboardLeadingGlyph(_ item: ClipboardHistoryItem) -> some View {
        switch item.payload {
        case .color(let color, _):
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: color))
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
        case .image(let bytes), .screenshot(let bytes):
            if let image = NSImage(data: bytes.previewPNG) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentPurple)
                    .frame(width: 16, height: 16)
            }
        case .link:
            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentBlue)
                .frame(width: 16, height: 16)
        case .text(let text):
            Image(systemName: looksLikeCode(text) ? "chevron.left.forwardslash.chevron.right" : "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(looksLikeCode(text) ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private func clipboardSummary(_ item: ClipboardHistoryItem) -> some View {
        switch item.payload {
        case .text(let text):
            Text(text)
                .font(.system(size: 11, design: looksLikeCode(text) ? .monospaced : .default))
                .foregroundStyle(.white.opacity(0.86))
        case .link:
            Text(item.preview)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.86))
        case .color(let color, let hex):
            Text(colorMeta(color, hex: hex))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.70))
        case .image, .screenshot:
            Text(item.preview)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    private func pasteClipboardItem(_ item: ClipboardHistoryItem) {
        clipboard.copyToPasteboard(item)
    }

    /// 点击条目轻跳一下（放大 + 上移，弹簧回弹）。
    private func playBounce(id: UUID, shelf: Bool, action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
            if shelf {
                bouncingShelfID = id
            } else {
                bouncingClipboardID = id
            }
        }
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.42)) {
                if shelf {
                    if bouncingShelfID == id { bouncingShelfID = nil }
                } else if bouncingClipboardID == id {
                    bouncingClipboardID = nil
                }
            }
        }
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 24, !trimmed.contains(" ") { return true }
        if trimmed.hasPrefix("sk_") || trimmed.hasPrefix("http") { return true }
        if trimmed.contains("{") || trimmed.contains("=>") { return true }
        return false
    }

    private func colorMeta(_ color: NSColor, hex: String) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return "\(hex) · rgb(\(r), \(g), \(b))"
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// 左右栏略灰于岛黑，对齐稿面 `island-glass`。
    private func panelBackground(corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(panelFill)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    // MARK: - Drop helper

    static func ingestDrop(providers: [NSItemProvider], into shelf: ShelfStore) -> Bool {
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
            let suggested = provider.suggestedName
            group.enter()
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, error in
                defer { group.leave() }
                if let error {
                    AppLog.warn("Shelf", "读取拖入文件失败", ["error": error.localizedDescription])
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
                guard var url else { return }
                if let suggested, !suggested.isEmpty,
                   url.lastPathComponent != suggested,
                   url.path.contains("/tmp") || url.path.contains("TemporaryItems") {
                    AppLog.debug("Shelf", "拖入为临时副本", [
                        "temp": url.lastPathComponent,
                        "suggested": suggested
                    ])
                }
                url = url.standardizedFileURL
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let n = shelf.add(urls: urls, source: "drop")
            IslandController.shared?.setShelfDropTargeted(false)
            ShelfDropSession.shared.setActive(false, reason: "dropComplete")
            AppLog.info("Shelf", "拖入完成", ["added": n, "urls": urls.count])
        }
        return claimed
    }
}
