import AppKit
import Foundation
import SwiftUI

/// 系统 Focus / 勿扰瞬时 tip 两态（与 Ridge「专注计时」无关）。
enum SystemFocusTipKind: String, Equatable, CaseIterable {
    case on
    case off
}

/// 某一 Focus 模式的展示元数据（来自 ModeConfigurations）。
struct SystemFocusModeInfo: Equatable, Hashable {
    var modeIdentifier: String
    var name: String
    /// 图标名：多为公开 SF Symbol（`moon.fill`）；自定义专注常见私有名（`emoji.face.grinning`、`rocket.fill`）。
    var symbolImageName: String
    /// 如 `systemIndigoColor`。
    var tintColorName: String
}

/// 解析 Focus 图标：先公开 SF Symbol，再私有 CoreGlyphs（系统 Focus 自用），再回退。
enum SystemFocusSymbol {
    /// 是否能解析为可绘制图像（公开或私有）。
    static func canResolve(_ name: String) -> Bool {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        if NSImage(systemSymbolName: raw, accessibilityDescription: nil) != nil { return true }
        return privateSystemSymbolImage(named: raw) != nil
    }

    /// 按候选名依次尝试；全部失败则用 `moon.fill`。
    static func nsImage(
        named preferred: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .semibold,
        fallbacks: [String] = []
    ) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        var tried: [String] = []
        for name in ([preferred] + fallbacks + ["moon.fill"]) {
            let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !tried.contains(raw) else { continue }
            tried.append(raw)
            if let img = configuredImage(named: raw, configuration: config) {
                return img
            }
        }
        AppLog.warn("SystemFocus", "Focus 图标无法解析，已回退空图", [
            "preferred": preferred,
            "tried": tried.joined(separator: ",")
        ])
        return NSImage(size: NSSize(width: pointSize, height: pointSize))
    }

    private static func configuredImage(
        named name: String,
        configuration: NSImage.SymbolConfiguration
    ) -> NSImage? {
        if let publicImg = NSImage(systemSymbolName: name, accessibilityDescription: nil),
           let configured = publicImg.withSymbolConfiguration(configuration) {
            return configured
        }
        if let privateImg = privateSystemSymbolImage(named: name),
           let configured = privateImg.withSymbolConfiguration(configuration) {
            return configured
        }
        return nil
    }

    /// 系统 Focus 自定义图标（emoji.* / 部分内置）落在私有 SF Symbols。
    private static func privateSystemSymbolImage(named name: String) -> NSImage? {
        let selector = NSSelectorFromString("imageWithPrivateSystemSymbolName:")
        guard NSImage.responds(to: selector) else { return nil }
        return NSImage.perform(selector, with: name)?.takeUnretainedValue() as? NSImage
    }
}

/// 当前系统 Focus 快照。
struct SystemFocusSnapshot: Equatable {
    var isActive: Bool
    /// 当前（或刚关闭前记住的）模式。
    var mode: SystemFocusModeInfo?
    /// 可读到的结束时刻；「一直开到手动关」为 nil。
    var endsAt: Date?
    /// 能否读 DoNotDisturb 库（完全磁盘访问）。
    var canReadStore: Bool

    static let unread = SystemFocusSnapshot(
        isActive: false,
        mode: nil,
        endsAt: nil,
        canReadStore: false
    )
}

/// 岛上 tip 载荷：左图标+名称 / 右「直到 HH:mm」|「已打开」|「已关闭」+状态点。
struct SystemFocusNotice: Identifiable, Hashable {
    let id: String
    let kind: SystemFocusTipKind
    let name: String
    let symbolImageName: String
    let tintColorName: String
    /// 右翼文案。
    let detail: String
    let endsAt: Date?

    init(
        id: String,
        kind: SystemFocusTipKind,
        name: String,
        symbolImageName: String,
        tintColorName: String,
        detail: String,
        endsAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.symbolImageName = symbolImageName
        self.tintColorName = tintColorName
        self.detail = detail
        self.endsAt = endsAt
    }
}

enum SystemFocusPalette {
    /// 稿面开启态淡紫 / indigo（未知 tint 时兜底）。
    static let activeAccent = Color(red: 0.72, green: 0.68, blue: 0.95)
    /// 关闭态图标（neutral-500）。
    static let offIcon = Color.white.opacity(0.45)
    /// 关闭态标题（neutral-400）。
    static let offTitle = Color.white.opacity(0.55)
    /// 关闭态空心环描边（neutral-600）。
    static let offRing = Color.white.opacity(0.35)
    /// 兼容旧调用。
    static let inactiveAccent = offIcon

    static func accent(for tintColorName: String, active: Bool) -> Color {
        guard active else { return inactiveAccent }
        let key = tintColorName
            .replacingOccurrences(of: "system", with: "")
            .replacingOccurrences(of: "Color", with: "")
            .lowercased()
        switch key {
        case "indigo": return Color(nsColor: .systemIndigo)
        case "purple": return Color(nsColor: .systemPurple)
        case "blue": return Color(nsColor: .systemBlue)
        case "teal": return Color(nsColor: .systemTeal)
        case "mint": return Color(nsColor: .systemMint)
        case "cyan": return Color(nsColor: .systemCyan)
        case "green": return Color(nsColor: .systemGreen)
        case "orange": return Color(nsColor: .systemOrange)
        case "red": return Color(nsColor: .systemRed)
        case "pink": return Color(nsColor: .systemPink)
        case "yellow": return Color(nsColor: .systemYellow)
        case "gray", "grey", "gray2", "gray3": return Color(nsColor: .systemGray)
        default:
            return activeAccent
        }
    }

    /// 关闭态尽量用 slash 变体名；无该变体时由 `SystemFocusSymbol` 回退原图 / `moon.fill`。
    static func offSymbol(from symbolImageName: String) -> String {
        let raw = symbolImageName.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "moon.slash.fill" }
        // 自定义表情图标无 slash 变体；关闭态沿用原名，靠颜色透明度区分。
        if raw.hasPrefix("emoji.") { return raw }
        if raw.contains("moon") { return "moon.slash.fill" }
        if raw.hasSuffix(".slash") || raw.hasSuffix(".slash.fill") { return raw }
        if raw.hasSuffix(".fill") {
            let base = String(raw.dropLast(5))
            return "\(base).slash.fill"
        }
        return "\(raw).slash"
    }
}
