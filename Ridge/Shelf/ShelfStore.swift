import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// 货架：把文件路径暂存在内存里，拖入 / 拖出 / 在 Finder 显示。
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    static let maxItems = 24

    @Published private(set) var items: [ShelfItem] = []

    private init() {}

    @discardableResult
    func add(urls: [URL], source: String) -> Int {
        var added = 0
        for url in urls {
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL else { continue }
            guard !items.contains(where: { $0.url == standardized }) else { continue }
            let item = ShelfItem(url: standardized)
            items.insert(item, at: 0)
            added += 1
        }
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        if added > 0 {
            AppLog.info("Shelf", "货架加入文件", ["count": added, "total": items.count, "source": source])
        }
        return added
    }

    func remove(id: UUID) {
        let before = items.count
        items.removeAll { $0.id == id }
        if items.count != before {
            AppLog.info("Shelf", "货架移除文件", ["total": items.count])
        }
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        AppLog.info("Shelf", "货架已清空")
    }

    func revealInFinder(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let exists = FileManager.default.fileExists(atPath: item.url.path)
        guard exists else {
            AppLog.warn("Shelf", "Finder 显示失败：路径不存在", ["name": item.name])
            remove(id: id)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        AppLog.info("Shelf", "已在 Finder 显示", ["name": item.name])
    }
}

struct ShelfItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    let byteCount: UInt64?

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize,
           size >= 0 {
            self.byteCount = UInt64(size)
        } else {
            self.byteCount = nil
        }
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    var contentType: UTType {
        if isDirectory { return .folder }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        if let type = UTType(filenameExtension: url.pathExtension) { return type }
        return .data
    }

    /// 扩展名徽章（如 PDF / PNG）；文件夹显示 DIR。
    var badgeLabel: String {
        if isDirectory { return "DIR" }
        let ext = url.pathExtension.uppercased()
        if ext.isEmpty { return "FILE" }
        return String(ext.prefix(4))
    }

    var subtitle: String {
        if isDirectory {
            return L10n.Shelf.kindFolder
        }
        var parts: [String] = []
        if let byteCount {
            parts.append(Self.formattedBytes(byteCount))
        }
        let kind = Self.kindLabel(for: contentType, extension: url.pathExtension)
        if !kind.isEmpty {
            parts.append(kind)
        }
        if parts.isEmpty {
            return L10n.Shelf.kindFile
        }
        return parts.joined(separator: " · ")
    }

    private static func formattedBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func kindLabel(for type: UTType, extension ext: String) -> String {
        if type.conforms(to: .pdf) { return L10n.Shelf.kindDocument }
        if type.conforms(to: .image) { return L10n.Shelf.kindImage }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return L10n.Shelf.kindVideo
        }
        if type.conforms(to: .audio) { return L10n.Shelf.kindAudio }
        let lowerExt = ext.lowercased()
        if ["swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "c", "cpp", "h", "m", "mm"].contains(lowerExt) {
            return L10n.Shelf.kindSource
        }
        if type.conforms(to: .archive) || ["zip", "rar", "7z", "tar", "gz"].contains(lowerExt) {
            return L10n.Shelf.kindArchive
        }
        if lowerExt == "svg" {
            return L10n.Shelf.kindVector
        }
        return L10n.Shelf.kindFile
    }

    /// 徽章配色键，由 View 层映射成 Color。
    var badgeStyleKey: String {
        if isDirectory { return "dir" }
        let key = url.pathExtension.lowercased()
        switch key {
        case "pdf": return "pdf"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "image"
        case "svg": return "svg"
        case "zip", "rar", "7z", "tar", "gz": return "archive"
        case "mp4", "mov", "m4v", "mkv": return "video"
        case "ts", "tsx", "js", "jsx", "swift", "py", "go", "rs": return "code"
        default: return "file"
        }
    }

    /// 拖出时用原路径；suggestedName 不要带后缀（系统会按 UTI 再补一次，否则变成 `.jpg.jpg`）。
    func makeDragItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        // Apple：suggestedName 不应含 path extension；扩展名由 typeIdentifier 决定。
        if isDirectory {
            provider.suggestedName = name
        } else {
            let base = (name as NSString).deletingPathExtension
            provider.suggestedName = base.isEmpty ? name : base
        }
        let fileURL = url
        let typeID = contentType.identifier

        provider.registerFileRepresentation(
            forTypeIdentifier: typeID,
            fileOptions: .openInPlace,
            visibility: .all
        ) { completion in
            completion(fileURL, true, nil)
            return nil
        }

        // Finder 还认 file URL 对象，优先走原路径文件名。
        provider.registerObject(fileURL as NSURL, visibility: .all)
        AppLog.debug("Shelf", "拖出 provider 已就绪", [
            "name": name,
            "suggested": provider.suggestedName ?? "",
            "type": typeID
        ])
        return provider
    }
}
