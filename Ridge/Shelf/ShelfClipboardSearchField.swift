import AppKit
import SwiftUI

/// 剪贴板搜索：AppKit 字段热区严格钳在宿主 bounds 内。
/// SwiftUI `TextField` 在浮层 NSPanel 上常把可点区域扩到宿主外。
struct ShelfClipboardSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ShelfClipboardSearchHost {
        let host = ShelfClipboardSearchHost()
        host.searchField.placeholderAttributedString = Self.placeholderAttrs(placeholder)
        host.searchField.stringValue = text
        host.searchField.delegate = context.coordinator
        context.coordinator.field = host.searchField
        return host
    }

    func updateNSView(_ host: ShelfClipboardSearchHost, context: Context) {
        context.coordinator.parent = self
        if host.searchField.stringValue != text {
            host.searchField.stringValue = text
        }
        host.searchField.placeholderAttributedString = Self.placeholderAttrs(placeholder)
    }

    private static func placeholderAttrs(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 10)
            ]
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ShelfClipboardSearchField
        weak var field: NSTextField?

        init(_ parent: ShelfClipboardSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            let value = (obj.object as? NSTextField)?.stringValue ?? ""
            if parent.text != value {
                parent.text = value
            }
        }
    }
}

/// 宿主自己做 hitTest 钳制；内部字段不得超出 bounds 抢点击。
final class ShelfClipboardSearchHost: NSView {
    let searchField: NSTextField = {
        let field = NSTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 10)
        field.textColor = NSColor.white.withAlphaComponent(0.88)
        field.backgroundColor = .clear
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        return field
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(searchField)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 16)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 关键钳在宿主内，避免字段热区外溢盖住右侧工具按钮。
        guard !isHidden, alphaValue > 0.01, bounds.contains(point) else { return nil }
        return searchField
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
