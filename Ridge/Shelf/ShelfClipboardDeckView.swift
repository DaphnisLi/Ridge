import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 控制台：货架（左）+ 剪贴板历史（右）。
struct ShelfClipboardDeckView: View {
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var clipboard = ClipboardHistoryStore.shared
    @State private var category: ClipboardCategory = .all
    @State private var copiedFlashID: UUID?
    @State private var clipboardSearch = ""

    private let accent = Color(red: 0.678, green: 0.776, blue: 1.0)

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 12
            let leftW = min(220, geo.size.width * 0.34)
            HStack(alignment: .top, spacing: gap) {
                shelfColumn
                    .frame(width: leftW, height: geo.size.height, alignment: .topLeading)
                // 必须显式高度：top 对齐的 HStack 不会把 maxHeight 撑到兄弟等高，
                // 否则滚动视口高度为 0 / 内容理想高度，表现为怎么滑都不变。
                clipboardColumn
                    .frame(width: max(0, geo.size.width - leftW - gap), height: geo.size.height, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(L10n.Shelf.shelfTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                if !shelf.items.isEmpty {
                    Button {
                        shelf.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.Shelf.clearShelf)
                }
            }

            if shelf.items.isEmpty {
                emptyShelfDropZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                AlwaysVisibleScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(shelf.items) { item in
                            shelfRow(item)
                        }
                        dropHintBar
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyShelfDropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(accent.opacity(0.85))
            Text(L10n.Shelf.dropHint)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Text(L10n.Shelf.dropHintDetail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 8)
    }

    private var dropHintBar: some View {
        Text(L10n.Shelf.dropMore)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.32))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private func shelfRow(_ item: ShelfItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                Text(item.isDirectory ? L10n.Shelf.kindFolder : L10n.Shelf.kindFile)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1)))
        )
        .compositingGroup()
        .contentShape(Rectangle())
        .onTapGesture {
            shelf.revealInFinder(id: item.id)
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

    // MARK: - Clipboard

    private var clipboardColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(L10n.Shelf.clipboardTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 4)
                if !clipboard.items.isEmpty {
                    clipboardSearchField
                    Button {
                        clipboard.clear()
                        clipboardSearch = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.Shelf.clearClipboard)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            categoryTabs
                .fixedSize(horizontal: false, vertical: true)

            let rows = filteredClipboardRows
            let hasQuery = !clipboardSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if clipboard.items(in: category).isEmpty {
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
                // 必须限高，否则滚动区被内容撑开、无法在视口内滑动。
                AlwaysVisibleScrollView {
                    VStack(alignment: .leading, spacing: 5) {
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
                "matches": filteredClipboardRows.count,
                "category": category.rawValue
            ])
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var clipboardSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.40))
            TextField("", text: $clipboardSearch, prompt: Text(L10n.Shelf.clipboardSearchPlaceholder)
                .foregroundStyle(.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.88))
                .frame(minWidth: 72, maxWidth: 128)
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
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .accessibilityLabel(L10n.Shelf.clipboardSearchPlaceholder)
    }

    private var filteredClipboardRows: [ClipboardHistoryItem] {
        let base = clipboard.items(in: category)
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

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ClipboardCategory.allCases) { tab in
                    let selected = category == tab
                    Button {
                        category = tab
                        AppLog.debug("Clipboard", "切换分类 Tab", ["tab": tab.rawValue])
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(selected ? Color.black.opacity(0.85) : Color.white.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selected ? accent : Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func clipboardRow(_ item: ClipboardHistoryItem) -> some View {
        let flashed = copiedFlashID == item.id
        // 略提高不透明度，滚动裁切时不透出纯黑岛底。
        let rowFill = flashed
            ? accent.opacity(0.18)
            : item.isPinned
                ? Color(nsColor: NSColor(calibratedWhite: 0.22, alpha: 1))
                : Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 1))
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                clipboardLeading(item)
                    .frame(width: 28, height: 28)

                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if flashed {
                    Text(L10n.Shelf.copied)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                clipboard.copyToPasteboard(item)
                withAnimation(.easeOut(duration: 0.15)) {
                    copiedFlashID = item.id
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    if copiedFlashID == item.id {
                        withAnimation { copiedFlashID = nil }
                    }
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    clipboard.togglePin(id: item.id)
                }
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.isPinned ? accent : Color.white.opacity(0.32))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? L10n.Shelf.unpin : L10n.Shelf.pin)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        // 背景与内容先合成再裁切，避免可视区首尾行在滚动时背景「掉色」变黑。
        .compositingGroup()
        .contextMenu {
            Button(L10n.Shelf.copyAgain) {
                clipboard.copyToPasteboard(item)
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
    private func clipboardLeading(_ item: ClipboardHistoryItem) -> some View {
        switch item.payload {
        case .color(let color, _):
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: color))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        case .image(let bytes), .screenshot(let bytes):
            if let image = NSImage(data: bytes.previewPNG) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "photo")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        case .link:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.18))
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
            }
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
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
                // 若落到临时副本且 suggestedName 可用，仍以真实可读路径入库；展示名用路径 lastPathComponent。
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
            AppLog.info("Shelf", "拖入完成", ["added": n, "urls": urls.count])
        }
        return claimed
    }
}
