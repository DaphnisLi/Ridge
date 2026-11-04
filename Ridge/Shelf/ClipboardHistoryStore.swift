import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 剪贴板历史：轮询 `NSPasteboard.general`，按类型归类；密码管理器前台时跳过。
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    static let maxItems = 60
    /// 预览缩略图最长边；写回剪贴板始终用原始 pngData。
    private static let previewMaxEdge: CGFloat = 512
    /// 单条图片落盘上限（字节），避免内存爆。
    private static let maxImageBytes = 12 * 1024 * 1024

    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published private(set) var isMonitoring = false

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var started = false
    private init() {}

    func start() {
        guard !started else { return }
        started = true
        lastChangeCount = NSPasteboard.general.changeCount
        isMonitoring = true
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        AppLog.info("Clipboard", "剪贴板监听已启动", ["changeCount": lastChangeCount])
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
        isMonitoring = false
        AppLog.info("Clipboard", "剪贴板监听已停止")
    }

    func items(in category: ClipboardCategory) -> [ClipboardHistoryItem] {
        switch category {
        case .all: return items
        default: return items.filter { $0.category == category }
        }
    }

    /// 置顶 / 取消置顶；置顶条目始终排在列表最前。
    func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? Date() : nil
        let pinned = items[index].isPinned
        resort()
        AppLog.info("Clipboard", pinned ? "已置顶" : "已取消置顶", [
            "id": String(id.uuidString.prefix(8)),
            "category": items.first(where: { $0.id == id })?.category.rawValue ?? "?",
            "pinnedCount": items.filter(\.isPinned).count
        ])
    }

    func copyToPasteboard(_ item: ClipboardHistoryItem) {
        let board = NSPasteboard.general
        board.clearContents()
        switch item.payload {
        case .text(let text):
            board.setString(text, forType: .string)
        case .link(let url):
            board.setString(url.absoluteString, forType: .string)
            board.setString(url.absoluteString, forType: .URL)
        case .color(let color, let hex):
            // 设计工具常粘贴文本色值；系统取色器认 NSColor。
            board.writeObjects([color])
            board.setString(hex, forType: .string)
        case .image(let bytes), .screenshot(let bytes):
            writeImageToPasteboard(bytes.fullPNG, board: board)
        }
        lastChangeCount = board.changeCount
        AppLog.info("Clipboard", "已写回系统剪贴板", [
            "category": item.category.rawValue,
            "id": String(item.id.uuidString.prefix(8))
        ])
        presentCopiedNotice(for: item)
    }

    /// 只写 PNG/TIFF 字节。不要附 file URL：Cursor 等会优先吃路径，临时文件读失败就裂成 PNG 图标。
    private func writeImageToPasteboard(_ stored: Data, board: NSPasteboard) {
        guard let png = Self.imageIONormalizedPNG(stored) else {
            AppLog.error("Clipboard", "写回失败：无法得到合法 PNG", ["bytes": stored.count])
            return
        }
        board.declareTypes([.png, .tiff], owner: nil)
        board.setData(png, forType: .png)
        if let tiff = Self.imageIOTIFF(fromPNG: png) {
            board.setData(tiff, forType: .tiff)
        }
        AppLog.info("Clipboard", "图片写回完成", [
            "pngBytes": png.count,
            "magicOK": Self.isPNG(png),
            "pixel": Self.imageIOPixelSize(png).map { "\($0.w)x\($0.h)" } ?? "?"
        ])
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        AppLog.debug("Clipboard", "已删除历史条目", ["total": items.count])
    }

    func clear() {
        let pinned = items.filter(\.isPinned)
        guard items.count > pinned.count else { return }
        let removed = items.count - pinned.count
        items = pinned
        resort()
        AppLog.info("Clipboard", "剪贴板历史已清空（保留置顶）", [
            "removed": removed,
            "pinned": pinned.count
        ])
    }

    // MARK: - Poll

    private func poll() {
        let board = NSPasteboard.general
        let count = board.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if ClipboardPrivacy.isFrontmostPasswordManager() {
            let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            AppLog.info("Clipboard", "私密过滤：跳过本次复制", ["app": bid])
            return
        }

        guard let captured = Self.capture(from: board) else {
            AppLog.debug("Clipboard", "剪贴板变更但无可归档类型", ["changeCount": count])
            return
        }

        // 全表去重：相同内容只保留一条，并提到对应分区顶部。
        if dedupeExisting(matching: captured) {
            presentCopiedNotice(for: captured)
            return
        }

        let insertAt = items.firstIndex(where: { !$0.isPinned }) ?? items.count
        items.insert(captured, at: insertAt)
        trimToMaxItems()
        AppLog.info("Clipboard", "已记录剪贴板", [
            "category": captured.category.rawValue,
            "total": items.count,
            "insertAt": insertAt,
            "changeCount": count
        ])
        presentCopiedNotice(for: captured)
    }

    /// 任意复制成功后上岛短提示；取色引导进行中时不打断。
    private func presentCopiedNotice(for item: ClipboardHistoryItem) {
        guard ShelfSettings.shared.showCopiedNotice else {
            AppLog.debug("Clipboard", "复制提示已关闭，跳过上岛")
            return
        }
        if IslandNoticeCenter.shared.current?.id == IslandNoticePayload.colorPickTipID {
            AppLog.debug("Clipboard", "取色引导中，跳过复制提示")
            return
        }
        let text = L10n.Shelf.copiedNotice(for: item)
        IslandNoticeCenter.shared.present(
            .clipboardCaptureHint(
                id: "copy.\(item.category.rawValue)",
                text: text,
                symbol: item.category.symbol == "paintpalette" ? "eyedropper" : item.category.symbol
            )
        )
        AppLog.info("Clipboard", "已投递复制提示", [
            "category": item.category.rawValue,
            "preview": String(item.preview.prefix(32))
        ])
    }

    /// - Returns: `true` 表示已命中历史并完成前置，无需再插入新条目。
    @discardableResult
    private func dedupeExisting(matching captured: ClipboardHistoryItem) -> Bool {
        guard let index = items.firstIndex(where: { $0.fingerprint == captured.fingerprint }) else {
            return false
        }
        var existing = items.remove(at: index)
        if existing.isPinned {
            existing.pinnedAt = Date()
            items.insert(existing, at: 0)
            resort()
        } else {
            let insertAt = items.firstIndex(where: { !$0.isPinned }) ?? items.count
            items.insert(existing, at: insertAt)
        }
        AppLog.info("Clipboard", "去重并前置", [
            "category": existing.category.rawValue,
            "id": String(existing.id.uuidString.prefix(8)),
            "pinned": existing.isPinned,
            "total": items.count
        ])
        return true
    }

    private func resort() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.isPinned, rhs.isPinned {
                let leftPin = lhs.pinnedAt ?? lhs.createdAt
                let rightPin = rhs.pinnedAt ?? rhs.createdAt
                if leftPin != rightPin {
                    return leftPin > rightPin
                }
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func trimToMaxItems() {
        guard items.count > Self.maxItems else { return }
        // 优先丢掉最旧的未置顶项；全部置顶时才截断尾部。
        while items.count > Self.maxItems {
            if let index = items.lastIndex(where: { !$0.isPinned }) {
                items.remove(at: index)
            } else {
                items.removeLast()
            }
        }
    }

    // MARK: - Capture

    private static func capture(from board: NSPasteboard) -> ClipboardHistoryItem? {
        // 1) 系统色板 / 取色器写出的 NSColor。
        if let colors = board.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor],
           let color = colors.first {
            let hex = colorPreview(color)
            AppLog.debug("Clipboard", "分类为颜色（NSColor）", ["hex": hex])
            return ClipboardHistoryItem(
                category: .color,
                preview: hex,
                fingerprint: "color:\(hex)",
                payload: .color(color, hex: hex)
            )
        }

        let rawString = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2) 纯色值文本：#b2cfff / rgb() 等（Figma、浏览器 DevTools 常见）。
        if let raw = rawString, let parsed = parseColorString(raw) {
            AppLog.debug("Clipboard", "分类为颜色（文本色值）", ["hex": parsed.hex])
            return ClipboardHistoryItem(
                category: .color,
                preview: parsed.hex,
                fingerprint: "color:\(parsed.hex)",
                payload: .color(parsed.color, hex: parsed.hex)
            )
        }

        let fileURLs = readFileURLs(from: board)
        let types = board.types ?? []

        // 3) 图片 / 截图：保留原始 PNG 字节供写回。
        if let captured = readImagePayload(from: board) {
            let isShot = shouldClassifyAsScreenshot(
                fileURLs: fileURLs,
                types: types,
                hasText: !(rawString?.isEmpty ?? true),
                hasHTML: types.contains(.html)
            )
            if isShot {
                let name = fileURLs.first(where: isScreenshotURL)?.lastPathComponent
                    ?? L10n.Shelf.tabScreenshot
                AppLog.debug("Clipboard", "分类为截图", [
                    "bytes": captured.bytes.fullPNG.count,
                    "file": name
                ])
                return ClipboardHistoryItem(
                    category: .screenshot,
                    preview: name,
                    fingerprint: "shot:\(captured.fingerprint)",
                    payload: .screenshot(captured.bytes)
                )
            }
            let preview = fileURLs.first?.lastPathComponent ?? L10n.Shelf.clipboardImagePreview
            AppLog.debug("Clipboard", "分类为图片", [
                "bytes": captured.bytes.fullPNG.count,
                "file": preview
            ])
            return ClipboardHistoryItem(
                category: .image,
                preview: preview,
                fingerprint: "img:\(captured.fingerprint)",
                payload: .image(captured.bytes)
            )
        }

        // 4) 链接 / 文本。
        if let raw = rawString, !raw.isEmpty {
            if let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" || scheme == "mailto" {
                return ClipboardHistoryItem(
                    category: .link,
                    preview: raw,
                    fingerprint: "link:\(raw)",
                    payload: .link(url)
                )
            }
            let preview = raw.count > 120 ? String(raw.prefix(117)) + "…" : raw
            return ClipboardHistoryItem(
                category: .text,
                preview: preview,
                fingerprint: "text:\(raw)",
                payload: .text(raw)
            )
        }

        if let urlString = board.string(forType: .URL),
           let url = URL(string: urlString) {
            return ClipboardHistoryItem(
                category: .link,
                preview: urlString,
                fingerprint: "link:\(urlString)",
                payload: .link(url)
            )
        }

        return nil
    }

    // MARK: - Image（全程 ImageIO，避免 NSImage 手动画布出假图）

    private struct CapturedImage {
        let bytes: ClipboardImageBytes
        let fingerprint: String
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private static func isPNG(_ data: Data) -> Bool {
        data.count >= 8 && data.prefix(8).elementsEqual(pngSignature)
    }

    private static func readImagePayload(from board: NSPasteboard) -> CapturedImage? {
        // 关键：Finder 复制图片文件时，public.png / public.tiff 常常是「文件图标」
        // （白纸 + PNG 字样），不是像素内容。必须优先读 file URL 指向的真实文件。
        var raw: Data?
        var source = "none"

        let fileURLs = readFileURLs(from: board)
        for url in fileURLs {
            guard url.isFileURL,
                  isLikelyImageFile(url),
                  let fileData = try? Data(contentsOf: url),
                  !fileData.isEmpty,
                  imageIONormalizedPNG(fileData) != nil else { continue }
            raw = fileData
            source = "fileURL"
            AppLog.info("Clipboard", "图片取自文件路径（避免误用图标）", [
                "name": url.lastPathComponent,
                "bytes": fileData.count,
                "pbPng": board.data(forType: .png)?.count ?? 0
            ])
            break
        }

        if raw == nil, let png = board.data(forType: .png), !png.isEmpty, isPNG(png) {
            // 无文件路径时（截屏到剪贴板 / 浏览器复制）才信任 pasteboard PNG。
            raw = png
            source = "pb.png"
        }
        if raw == nil, let tiff = board.data(forType: .tiff), !tiff.isEmpty {
            raw = tiff
            source = "pb.tiff"
        }
        if raw == nil,
           let jpeg = board.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)),
           !jpeg.isEmpty {
            raw = jpeg
            source = "pb.jpeg"
        }

        guard let raw, !raw.isEmpty else { return nil }

        guard var fullPNG = imageIONormalizedPNG(raw) else {
            AppLog.warn("Clipboard", "ImageIO 无法解码剪贴板图片", [
                "bytes": raw.count,
                "source": source
            ])
            return nil
        }
        if fullPNG.count > maxImageBytes {
            AppLog.warn("Clipboard", "图片过大，已跳过", ["bytes": fullPNG.count])
            return nil
        }

        // 超大图压最长边，仍用 ImageIO。
        if fullPNG.count > 2 * 1024 * 1024,
           let smaller = imageIOThumbnailPNG(fullPNG, maxPixel: 2048) {
            fullPNG = smaller
        }

        guard let previewPNG = imageIOThumbnailPNG(fullPNG, maxPixel: Int(previewMaxEdge)),
              isPNG(previewPNG) else {
            AppLog.warn("Clipboard", "生成预览缩略图失败", ["source": source])
            return nil
        }

        let pixel = imageIOPixelSize(fullPNG) ?? (0, 0)
        guard pixel.w > 0, pixel.h > 0 else { return nil }

        // 指纹不含来源路径：同一张图从文件 / 剪贴板进来应视为相同。
        let fp = contentFingerprint(fullPNG, width: pixel.w, height: pixel.h)
        AppLog.info("Clipboard", "已捕获图片", [
            "source": source,
            "fullBytes": fullPNG.count,
            "previewBytes": previewPNG.count,
            "w": pixel.w,
            "h": pixel.h,
            "fp": String(fp.prefix(24))
        ])
        return CapturedImage(
            bytes: ClipboardImageBytes(previewPNG: previewPNG, fullPNG: fullPNG),
            fingerprint: fp
        )
    }

    /// 进程内稳定的图片内容指纹（尺寸 + 采样字节），用于去重。
    private static func contentFingerprint(_ data: Data, width: Int, height: Int) -> String {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(width)
        hasher.combine(height)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count
            guard count > 0 else { return }
            let step = max(1, count / 96)
            var index = 0
            while index < count {
                hasher.combine(bytes[index])
                index += step
            }
            hasher.combine(bytes[count - 1])
        }
        return "img:\(width)x\(height):\(data.count):\(hasher.finalize())"
    }

    private static func isLikelyImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "tif", "tiff", "heic", "bmp"].contains(ext) {
            return true
        }
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .image)
        }
        return false
    }

    /// 任意位图 → 合法 PNG（优先保留已是 PNG 的原始字节）。
    private static func imageIONormalizedPNG(_ data: Data) -> Data? {
        if isPNG(data), imageIOPixelSize(data) != nil {
            return data
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return imageIOEncode(cg, type: .png)
    }

    private static func imageIOThumbnailPNG(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return imageIOEncode(cg, type: .png)
    }

    private static func imageIOTIFF(fromPNG png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return imageIOEncode(cg, type: .tiff)
    }

    private static func imageIOEncode(_ image: CGImage, type: UTType) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out,
            type.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let data = out as Data
        if type == .png, !isPNG(data) { return nil }
        return data
    }

    private static func imageIOPixelSize(_ data: Data) -> (w: Int, h: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return (w, h)
    }

    /// 截图归类：
    /// - 文件名含 Screenshot / 截屏；或
    /// - 系统截屏工具刚写入（bundle / 类型线索）；或
    /// - 剪贴板几乎只有位图、无 Finder 文件 URL、无 HTML（⌘⌃⇧4 典型形态）。
    private static func shouldClassifyAsScreenshot(
        fileURLs: [URL],
        types: [NSPasteboard.PasteboardType],
        hasText: Bool,
        hasHTML: Bool
    ) -> Bool {
        if fileURLs.contains(where: isScreenshotURL) {
            return true
        }

        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
        if front.contains("screenshot") || front.contains("screencapture") {
            return true
        }

        let typeIDs = types.map(\.rawValue).joined(separator: ",")
        if typeIDs.localizedCaseInsensitiveContains("screenshot")
            || typeIDs.localizedCaseInsensitiveContains("screencapture") {
            return true
        }

        // ⌘⌃⇧3/4 → 剪贴板：通常只有 public.tiff / public.png，没有 file URL、没有 HTML。
        let hasFileURL = !fileURLs.isEmpty
        if !hasFileURL && !hasHTML && !hasText {
            return true
        }
        return false
    }

    private static func isScreenshotURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.contains("screenshot")
            || name.contains("screen shot")
            || name.contains("截屏")
            || name.contains("スクリーンショット")
    }

    private static func readFileURLs(from board: NSPasteboard) -> [URL] {
        let fromObjects = (board.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]) ?? []
        if !fromObjects.isEmpty { return fromObjects }

        // 有些截屏只给 public.file-url 字符串。
        if let str = board.string(forType: .fileURL),
           let url = URL(string: str), url.isFileURL {
            return [url]
        }
        return []
    }

    // MARK: - Color parsing

    private struct ParsedColor {
        let color: NSColor
        let hex: String
    }

    /// 识别整段就是色值的文本（避免把正文里偶然出现的 #fff 误伤——要求整串匹配）。
    private static func parseColorString(_ raw: String) -> ParsedColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 64 else { return nil }

        // #RGB / #RRGGBB / #RRGGBBAA
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            if let color = colorFromHexDigits(hex) {
                return ParsedColor(color: color, hex: colorPreview(color))
            }
            return nil
        }

        // rgb(r,g,b) / rgba(r,g,b,a)
        let lower = s.lowercased()
        if lower.hasPrefix("rgb") {
            let nums = lower
                .replacingOccurrences(of: "rgba", with: "")
                .replacingOccurrences(of: "rgb", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count >= 3 else { return nil }
            let r = min(255, max(0, nums[0])) / 255
            let g = min(255, max(0, nums[1])) / 255
            let b = min(255, max(0, nums[2])) / 255
            let a = nums.count >= 4 ? min(1, max(0, nums[3] > 1 ? nums[3] / 255 : nums[3])) : 1
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: a)
            return ParsedColor(color: color, hex: colorPreview(color))
        }

        // 裸 6/8 位 hex（无 #），且整串只有十六进制字符。
        if s.count == 6 || s.count == 8,
           s.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }),
           let color = colorFromHexDigits(s) {
            return ParsedColor(color: color, hex: colorPreview(color))
        }

        return nil
    }

    private static func colorFromHexDigits(_ hex: String) -> NSColor? {
        var h = hex
        if h.count == 3 {
            // #abc → #aabbcc
            h = h.map { "\($0)\($0)" }.joined()
        }
        guard h.count == 6 || h.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&value) else { return nil }
        let hasAlpha = h.count == 8
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        if hasAlpha {
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255
            a = CGFloat(value & 0x0000_00FF) / 255
        } else {
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func colorPreview(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

enum ClipboardCategory: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case color
    case image
    case screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.Shelf.tabAll
        case .text: return L10n.Shelf.tabText
        case .link: return L10n.Shelf.tabLink
        case .color: return L10n.Shelf.tabColor
        case .image: return L10n.Shelf.tabImage
        case .screenshot: return L10n.Shelf.tabScreenshot
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .link: return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .screenshot: return "camera.viewfinder"
        }
    }
}

struct ClipboardHistoryItem: Identifiable {
    let id: UUID
    let createdAt: Date
    let category: ClipboardCategory
    let preview: String
    let fingerprint: String
    let payload: ClipboardPayload
    var isPinned: Bool
    var pinnedAt: Date?

    init(
        category: ClipboardCategory,
        preview: String,
        fingerprint: String,
        payload: ClipboardPayload,
        isPinned: Bool = false,
        pinnedAt: Date? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.category = category
        self.preview = preview
        self.fingerprint = fingerprint
        self.payload = payload
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
    }
}

/// 图片载荷：预览与全文都是 ImageIO 产出的合法 PNG 字节（不用 NSImage 缓存）。
struct ClipboardImageBytes {
    let previewPNG: Data
    let fullPNG: Data
}

enum ClipboardPayload {
    case text(String)
    case link(URL)
    /// hex 便于写回文本色值（Figma 等）。
    case color(NSColor, hex: String)
    case image(ClipboardImageBytes)
    case screenshot(ClipboardImageBytes)
}

enum ClipboardPrivacy {
    private static let blockedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.1password.1password-launcher",
        "com.1password.safari",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "org.keepassx.keepassxc",
        "com.dashlane.dashlanephonefinal",
        "com.apple.keychainaccess",
        "pw.proton.pass",
        "me.proton.pass.electron",
        "com.nordpass.macos.NordPass",
        "com.nordpass.macos",
        "in.sinew.Enpass-Desktop",
        "com.enpass.desktop",
        "com.roboform.mac",
        "com.stickypassword.Stickypassword"
    ]

    private static let blockedBundlePrefixes = [
        "com.1password.",
        "com.agilebits.onepassword",
        "com.bitwarden.",
        "com.lastpass.",
        "pw.proton.pass"
    ]

    static func isFrontmostPasswordManager() -> Bool {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() else {
            return false
        }
        if blockedBundleIDs.contains(where: { $0.lowercased() == bid }) {
            return true
        }
        return blockedBundlePrefixes.contains { bid.hasPrefix($0.lowercased()) }
    }
}
