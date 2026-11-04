import AppKit
import Foundation
import Vision

/// 全屏半透明框选 → 截取区域 → 本地 Vision OCR。
@MainActor
final class ScreenRegionOCRController {
    enum OCRError: Error {
        case cancelled
        case captureFailed
        case recognitionFailed
    }

    static let shared = ScreenRegionOCRController()

    private var windows: [OCRSelectionWindow] = []
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?
    private var completion: ((Result<String, OCRError>) -> Void)?
    private var isActive = false

    private init() {}

    func begin(completion: @escaping (Result<String, OCRError>) -> Void) {
        cancel(emitting: false)
        self.completion = completion
        isActive = true

        for screen in NSScreen.screens {
            let window = OCRSelectionWindow(screen: screen) { [weak self] rectInScreen in
                self?.handleSelection(rectInScreen)
            } onCancel: { [weak self] in
                AppLog.info("ShelfCapture", "OCR 取消（右键/单击）")
                self?.finish(.failure(.cancelled))
            }
            windows.append(window)
            window.start()
        }

        // nonactivating / 其它 App 前台时 local 收不到 Esc，必须再挂 global。
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            AppLog.info("ShelfCapture", "OCR Esc（local）")
            self?.finish(.failure(.cancelled))
            return nil
        }
        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            AppLog.info("ShelfCapture", "OCR Esc（global）")
            Task { @MainActor in
                self?.finish(.failure(.cancelled))
            }
        }

        AppLog.info("ShelfCapture", "OCR 框选层已显示", ["screens": windows.count])
    }

    func cancel() {
        cancel(emitting: true)
    }

    private func cancel(emitting: Bool) {
        guard isActive || !windows.isEmpty else { return }
        teardownUI()
        if emitting {
            let cb = completion
            completion = nil
            isActive = false
            cb?(.failure(.cancelled))
        }
    }

    private func handleSelection(_ rect: CGRect) {
        guard isActive else { return }
        // 先拆掉遮罩，避免截进半透明层。
        teardownUI()

        let integral = rect.integral
        guard integral.width >= 4, integral.height >= 4 else {
            finish(.failure(.cancelled))
            return
        }

        AppLog.info("ShelfCapture", "OCR 选区确定", [
            "w": Int(integral.width),
            "h": Int(integral.height)
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.captureAndRecognize(integral)
        }
    }

    private func captureAndRecognize(_ screenRect: CGRect) {
        // AppKit 原点在左下；CGWindowListCreateImage 用的是左上为原点的全局坐标。
        let cgRect = Self.cgScreenRect(fromAppKit: screenRect)
        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenBelowWindow,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            finish(.failure(.captureFailed))
            return
        }

        Task.detached(priority: .userInitiated) {
            let text = Self.recognizeText(in: cgImage)
            await MainActor.run {
                if let text {
                    self.finish(.success(text))
                } else {
                    self.finish(.failure(.recognitionFailed))
                }
            }
        }
    }

    private func finish(_ result: Result<String, OCRError>) {
        teardownUI()
        let cb = completion
        completion = nil
        isActive = false
        cb?(result)
    }

    private func teardownUI() {
        if let escapeLocalMonitor {
            NSEvent.removeMonitor(escapeLocalMonitor)
            self.escapeLocalMonitor = nil
        }
        if let escapeGlobalMonitor {
            NSEvent.removeMonitor(escapeGlobalMonitor)
            self.escapeGlobalMonitor = nil
        }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private static func cgScreenRect(fromAppKit rect: CGRect) -> CGRect {
        // 多屏：global AppKit y 相对主屏左下；CG 用主屏左上。
        guard let primary = NSScreen.screens.first else { return rect }
        let primaryHeight = primary.frame.height
        let bottomY = rect.origin.y
        let topFromBottom = bottomY + rect.height
        let cgY = primaryHeight - topFromBottom
        return CGRect(x: rect.origin.x, y: cgY, width: rect.width, height: rect.height)
    }

    /// 只输出文字：截屏仅作识别输入，不会把图案/图片写入剪贴板。
    /// 图案误识别用置信度 + 字符类型过滤掉。
    nonisolated private static func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // 相对选区高度过小的笔画像素（图标装饰）直接忽略。
        request.minimumTextHeight = 0.018
        if #available(macOS 13.0, *) {
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return ""
        }

        let minConfidence: Float = 0.45
        var kept: [(box: CGRect, text: String)] = []
        var droppedLowConfidence = 0
        var droppedNoise = 0

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            if candidate.confidence < minConfidence {
                droppedLowConfidence += 1
                continue
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard isLikelyRealText(text) else {
                droppedNoise += 1
                continue
            }
            kept.append((observation.boundingBox, text))
        }

        // 从上到下、从左到右排版（Vision boundingBox 原点在左下）。
        kept.sort { lhs, rhs in
            if abs(lhs.box.maxY - rhs.box.maxY) > 0.02 {
                return lhs.box.maxY > rhs.box.maxY
            }
            return lhs.box.minX < rhs.box.minX
        }

        let joined = kept.map(\.text).joined(separator: "\n")
        AppLog.info("ShelfCapture", "OCR 仅保留文字行", [
            "raw": observations.count,
            "kept": kept.count,
            "dropConfidence": droppedLowConfidence,
            "dropNoise": droppedNoise,
            "chars": joined.count
        ])
        return joined
    }

    /// 过滤图标/纹理被误读成的纯符号噪声；须含字母、数字或汉字等正文。
    nonisolated private static func isLikelyRealText(_ text: String) -> Bool {
        var hasLetterOrDigit = false
        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                hasLetterOrDigit = true
                break
            }
            let v = scalar.value
            // CJK 统一表意、扩展 A、假名、全角字母数字
            if (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0x3040...0x30FF).contains(v)
                || (0xFF10...0xFF19).contains(v)
                || (0xFF21...0xFF3A).contains(v)
                || (0xFF41...0xFF5A).contains(v)
            {
                hasLetterOrDigit = true
                break
            }
        }
        return hasLetterOrDigit
    }
}

// MARK: - Overlay window

@MainActor
private final class OCRSelectionWindow: NSPanel {
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        let frame = screen.frame
        // 不用 nonactivatingPanel：否则经常拿不到 key，Esc / 键盘取消会失效。
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.setFrame(frame, display: false)
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isReleasedWhenClosed = false

        let view = OCRSelectionView(frame: CGRect(origin: .zero, size: frame.size))
        view.onDragCompleted = { [weak self] localRect in
            guard let self else { return }
            self.onComplete(self.screenRect(fromLocal: localRect))
        }
        view.onCancel = { [weak self] in
            self?.onCancel()
        }
        contentView = view
    }

    func start() {
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func screenRect(fromLocal local: CGRect) -> CGRect {
        guard let contentView else { return local }
        let windowRect = contentView.convert(local, to: nil)
        return convertToScreen(windowRect)
    }
}

@MainActor
private final class OCRSelectionView: NSView {
    var onDragCompleted: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let startPoint, let currentPoint else {
            NSColor.black.withAlphaComponent(0.45).setFill()
            bounds.fill()
            drawHint()
            return
        }

        let rect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )

        // 镂空选区
        let path = NSBezierPath(rect: bounds)
        path.appendRect(rect)
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()

        // 尺寸提示
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        let labelOrigin = CGPoint(
            x: rect.midX - size.width / 2,
            y: min(rect.maxY + 8, bounds.maxY - size.height - 4)
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        CGRect(
            x: labelOrigin.x - 6,
            y: labelOrigin.y - 3,
            width: size.width + 12,
            height: size.height + 6
        ).fill()
        label.draw(at: labelOrigin, withAttributes: attrs)
    }

    private func drawHint() {
        let text = L10n.Shelf.ocrDragHint
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let paddingX: CGFloat = 22
        let paddingY: CGFloat = 14
        let bgSize = CGSize(
            width: size.width + paddingX * 2,
            height: size.height + paddingY * 2
        )
        let bgOrigin = CGPoint(
            x: (bounds.width - bgSize.width) / 2,
            y: bounds.height * 0.58 - bgSize.height / 2
        )
        let bg = CGRect(origin: bgOrigin, size: bgSize)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 14, yRadius: 14).fill()
        text.draw(
            at: CGPoint(x: bg.midX - size.width / 2, y: bg.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        guard let startPoint, let currentPoint else {
            onCancel?()
            return
        }
        let rect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        self.startPoint = nil
        self.currentPoint = nil
        if rect.width < 4 || rect.height < 4 {
            onCancel?()
        } else {
            onDragCompleted?(rect)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
