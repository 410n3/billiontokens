import Cocoa
import Carbon

// MARK: - Models

struct LimitPayload: Codable {
    let timestamp: Int?
    let time_str: String?
    let codex: AppLimitInfo?
    let claude: AppLimitInfo?
    let antigravity: AppLimitInfo?
    let from_cache: Bool?
}

struct AppLimitInfo: Codable {
    let status: String?
    let plan: String?
    let email: String?
    let billing: String?
    let tier: String?
    let active_model: String?
    let primary: WindowInfo?
    let secondary: WindowInfo?
    let reset_credits: Int?
    let conversations_count: Int?
    let last_active: String?
}

struct WindowInfo: Codable {
    let used_percent: Int?
    let reset_str: String?
}

// MARK: - Icon Manager

class IconManager {
    static let shared = IconManager()

    let codexIcon: NSImage
    let claudeIcon: NSImage
    let antigravityIcon: NSImage

    init() {
        let bundle = Bundle.main
        let fallbackPath = "\(FileManager.default.currentDirectoryPath)/assets"

        func loadImage(named name: String) -> NSImage {
            if let path = bundle.path(forResource: name, ofType: "png"),
               let img = NSImage(contentsOfFile: path), img.isValid {
                return img
            }
            if let img = NSImage(contentsOfFile: "\(fallbackPath)/\(name).png"), img.isValid {
                return img
            }
            return NSImage(size: NSSize(width: 32, height: 32))
        }

        codexIcon = loadImage(named: "codex")
        claudeIcon = loadImage(named: "claude")
        antigravityIcon = loadImage(named: "antigravity")
    }

    func resized(image: NSImage, size: CGFloat) -> NSImage {
        let newImg = NSImage(size: NSSize(width: size, height: size))
        newImg.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
        newImg.unlockFocus()
        return newImg
    }
}

// MARK: - Custom Rounded Progress Bar

// Draws single-line text vertically centered (used for badges).
class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        let h = cellSize(forBounds: rect).height
        return NSRect(x: base.minX, y: rect.minY + ((rect.height - h) / 2).rounded(), width: base.width, height: h)
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

class ProgressBarView: NSView {
    var percentage: Double = 0.0 {
        didSet {
            needsDisplay = true
        }
    }

    var barColor: NSColor {
        if percentage >= 85 {
            return NSColor(calibratedRed: 0.92, green: 0.38, blue: 0.34, alpha: 1.0)
        } else if percentage >= 60 {
            return NSColor(calibratedRed: 0.88, green: 0.65, blue: 0.30, alpha: 1.0)
        } else {
            return NSColor(calibratedRed: 0.43, green: 0.78, blue: 0.62, alpha: 1.0)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 2.0
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let trackColor = NSColor(white: 1.0, alpha: 0.09)
        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        trackColor.setFill()
        trackPath.fill()

        let validPercent = min(max(percentage, 0.0), 100.0)
        let fillWidth = bounds.width * CGFloat(validPercent / 100.0)
        if fillWidth > 2 {
            let fillRect = NSRect(x: 0, y: 0, width: fillWidth, height: bounds.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
            barColor.setFill()
            fillPath.fill()
        }
    }
}

// MARK: - Notch Screen & Geometry Helper

struct NotchGeometry {
    let screen: NSScreen
    let hasNotch: Bool
    let notchLeft: CGFloat
    let notchRight: CGFloat
    let notchWidth: CGFloat
    let notchCenterX: CGFloat
    let notchBottomY: CGFloat
    let menuBarHeight: CGFloat

    static func current() -> NotchGeometry {
        var targetScreen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
        if #available(macOS 12.0, *) {
            if let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                targetScreen = notchScreen
            }
        }
        let menuBarH: CGFloat = targetScreen.safeAreaInsets.top > 0 ? targetScreen.safeAreaInsets.top : 24.0
        let bottomY = targetScreen.frame.maxY - menuBarH

        if #available(macOS 12.0, *), targetScreen.safeAreaInsets.top > 0 {
            let left = targetScreen.auxiliaryTopLeftArea?.maxX ?? (targetScreen.frame.midX - 90)
            let right = targetScreen.auxiliaryTopRightArea?.minX ?? (targetScreen.frame.midX + 90)
            return NotchGeometry(
                screen: targetScreen,
                hasNotch: true,
                notchLeft: left,
                notchRight: right,
                notchWidth: right - left,
                notchCenterX: (left + right) / 2.0,
                notchBottomY: bottomY,
                menuBarHeight: menuBarH
            )
        } else {
            return NotchGeometry(
                screen: targetScreen,
                hasNotch: false,
                notchLeft: targetScreen.frame.midX - 90,
                notchRight: targetScreen.frame.midX + 90,
                notchWidth: 180,
                notchCenterX: targetScreen.frame.midX,
                notchBottomY: bottomY,
                menuBarHeight: menuBarH
            )
        }
    }
}

enum PillStyle {
    case flush
    case floating
}

final class CircularProgressView: NSView {
    var percentage: Int = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let lineWidth: CGFloat = 2.5
        let circleRect = bounds.insetBy(dx: lineWidth + 1, dy: lineWidth + 1)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(circleRect.width, circleRect.height) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -270, clockwise: true)
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        NSColor(white: 1.0, alpha: 0.16).setStroke()
        track.stroke()

        let progress = NSBezierPath()
        let endAngle = 90 - (360 * CGFloat(min(max(percentage, 0), 100)) / 100)
        progress.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: endAngle, clockwise: true)
        progress.lineWidth = lineWidth
        progress.lineCapStyle = .round
        let color = percentage >= 85
            ? NSColor(calibratedRed: 0.92, green: 0.38, blue: 0.34, alpha: 1.0)
            : NSColor(calibratedRed: 0.43, green: 0.78, blue: 0.62, alpha: 1.0)
        color.setStroke()
        progress.stroke()

        let value = "\(percentage)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .bold),
            .foregroundColor: NSColor(white: 0.94, alpha: 1.0)
        ]
        let size = value.size(withAttributes: attributes)
        value.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}

final class LiquidGlassTintView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset = bounds.insetBy(dx: 0.75, dy: 0.75)
        let shape = NSBezierPath(roundedRect: inset, xRadius: 20, yRadius: 20)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.09, alpha: 0.78),
            NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.035, alpha: 0.62)
        ])?.draw(in: shape, angle: 270)

        shape.lineWidth = 1
        NSColor(white: 1.0, alpha: 0.16).setStroke()
        shape.stroke()

        let inner = NSBezierPath(roundedRect: inset.insetBy(dx: 1, dy: 1), xRadius: 19, yRadius: 19)
        inner.lineWidth = 1
        NSColor(white: 1.0, alpha: 0.055).setStroke()
        inner.stroke()
    }
}

// MARK: - Notch Island Pill View

class NotchPillView: NSView {
    var notchGapWidth: CGFloat = 180 {
        didSet { needsLayout = true }
    }

    var style: PillStyle = .flush {
        didSet {
            needsDisplay = true
        }
    }

    var codexPercent: Int = 0 { didSet { updateLabels() } }
    var codexReset: String = "" { didSet { updateLabels() } }

    var claudePercent: Int = 0 { didSet { updateLabels() } }
    var claudeReset: String = "" { didSet { updateLabels() } }

    var antigravityPercent: Int = 0 { didSet { updateLabels() } }
    var antigravityReset: String = "" { didSet { updateLabels() } }

    var isHovered: Bool = false {
        didSet {
            updateLabels()
        }
    }

    var onClick: (() -> Void)?
    var onRightClick: ((NSPoint) -> Void)?

    private var providerIndex = 0

    // Indexes (0 Codex, 1 Claude, 2 Antigravity) that currently have data
    var activeProviders: [Int] = [0, 1, 2] {
        didSet {
            if !activeProviders.contains(providerIndex) { providerIndex = activeProviders.first ?? 0 }
            updateLabels()
        }
    }
    private var providerIcon: NSImageView!
    private var progressRing: CircularProgressView!

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if style == .flush {
            // Dynamic Island attached flush to notch:
            // Flat top edge, rounded bottom corners
            let w = bounds.width
            let h = bounds.height
            let r: CGFloat = 12.0

            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: h))
            path.line(to: NSPoint(x: w, y: h))
            path.line(to: NSPoint(x: w, y: r))
            path.appendArc(from: NSPoint(x: w, y: 0), to: NSPoint(x: w - r, y: 0), radius: r)
            path.line(to: NSPoint(x: r, y: 0))
            path.appendArc(from: NSPoint(x: 0, y: 0), to: NSPoint(x: 0, y: r), radius: r)
            path.close()

            // Pure black with no rim so it blends into the hardware notch
            NSColor.black.setFill()
            path.fill()
        } else {
            // Fully rounded capsule (floating / menu bar)
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            NSColor.black.setFill()
            path.fill()

            path.lineWidth = 1.0
            NSColor(white: 1.0, alpha: isHovered ? 0.22 : 0.12).setStroke()
            path.stroke()
        }
    }

    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false

        providerIcon = createIconView(image: IconManager.shared.codexIcon, size: 17)
        providerIcon.wantsLayer = true
        addSubview(providerIcon)

        progressRing = CircularProgressView(frame: .zero)
        progressRing.wantsLayer = true
        addSubview(progressRing)

        updateToolTip()
    }

    override func layout() {
        super.layout()
        let wingWidth = max(48, (bounds.width - notchGapWidth) / 2)
        let leftCenterX = wingWidth / 2
        let rightCenterX = bounds.width - (wingWidth / 2)
        providerIcon.frame = NSRect(x: leftCenterX - 9, y: bounds.midY - 9, width: 18, height: 18).integral
        progressRing.frame = NSRect(x: rightCenterX - 14, y: bounds.midY - 14, width: 28, height: 28).integral
    }

    private func createIconView(image: NSImage, size: CGFloat) -> NSImageView {
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        iv.image = IconManager.shared.resized(image: image, size: size)
        iv.imageScaling = .scaleProportionallyUpOrDown
        return iv
    }

    private func createLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor(white: 0.92, alpha: 1.0)
        return label
    }

    func updateLabels() {
        let providers = [
            ("CODEX", IconManager.shared.codexIcon, codexPercent),
            ("CLAUDE", IconManager.shared.claudeIcon, claudePercent),
            ("ANTIGRAVITY", IconManager.shared.antigravityIcon, antigravityPercent)
        ]
        let provider = providers[providerIndex]
        providerIcon.image = IconManager.shared.resized(image: provider.1, size: 17)
        progressRing.percentage = provider.2
        updateToolTip()
    }

    func updateToolTip() {
        let lines = [
            (0, "Codex", codexPercent, codexReset),
            (1, "Claude", claudePercent, claudeReset),
            (2, "Antigravity", antigravityPercent, antigravityReset)
        ].filter { activeProviders.contains($0.0) }
         .map { "• \($0.1): \($0.2)% (\($0.3.isEmpty ? "Active" : $0.3))" }
        let body = lines.isEmpty ? "No providers connected" : lines.joined(separator: "\n")
        toolTip = "AI Limits:\n\(body)\n\nClick: Next provider\nDouble-click: Open HUD (Fn + Control)"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1 {
            flipToNextProvider()
        } else if event.clickCount == 2 {
            onClick?()
        }
    }

    private func flipToNextProvider() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            providerIcon.animator().alphaValue = 0
            progressRing.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            let list = self.activeProviders.isEmpty ? [0, 1, 2] : self.activeProviders
            let pos = list.firstIndex(of: self.providerIndex) ?? -1
            self.providerIndex = list[(pos + 1) % list.count]
            self.updateLabels()
            self.providerIcon.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.82, y: 0.82))
            self.progressRing.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.82, y: 0.82))
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                self.providerIcon.animator().alphaValue = 1
                self.progressRing.animator().alphaValue = 1
                self.providerIcon.animator().layer?.setAffineTransform(.identity)
                self.progressRing.animator().layer?.setAffineTransform(.identity)
            }
        })
    }

    override func rightMouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        onRightClick?(loc)
    }
}

// MARK: - App Delegate & HUD Window Controller

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var hudPanel: NSPanel!
    var notchPanel: NSPanel!
    var notchView: NotchPillView!
    var visualEffectView: NSVisualEffectView!
    var hotKeyRef1: EventHotKeyRef?
    var hotKeyRef2: EventHotKeyRef?
    var localKeyMonitor: Any?

    var showNotchBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showNotchBar, forKey: "showNotchBar")
            updateNotchVisibility()
        }
    }

    var showMenuBarTicker: Bool = true {
        didSet {
            UserDefaults.standard.set(showMenuBarTicker, forKey: "showMenuBarTicker")
            updateMenuBarTitle()
        }
    }

    // UI elements
    var timeLabel: NSTextField!
    var refreshButton: NSButton!
    var copyButton: NSButton!
    var islandButton: NSButton!

    // Codex UI
    var codexPlanBadge: NSTextField!
    var codexPrimaryLabel: NSTextField!
    var codexPrimaryBar: ProgressBarView!
    var codexSecondaryLabel: NSTextField!
    var codexSecondaryBar: ProgressBarView!
    var codexMetaLabel: NSTextField!

    // Claude UI
    var claudePlanBadge: NSTextField!
    var claudePrimaryLabel: NSTextField!
    var claudePrimaryBar: ProgressBarView!
    var claudeSecondaryLabel: NSTextField!
    var claudeSecondaryBar: ProgressBarView!
    var claudeMetaLabel: NSTextField!

    // Antigravity UI
    var antigravityBadge: NSTextField!
    var antigravityPrimaryLabel: NSTextField!
    var antigravityPrimaryBar: ProgressBarView!
    var antigravitySecondaryLabel: NSTextField!
    var antigravitySecondaryBar: ProgressBarView!
    var antigravityMetaLabel: NSTextField!

    var latestData: LimitPayload?
    var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHUDWindow()
        setupNotchPanel()

        if UserDefaults.standard.object(forKey: "showNotchBar") != nil {
            showNotchBar = UserDefaults.standard.bool(forKey: "showNotchBar")
        }
        if UserDefaults.standard.object(forKey: "showMenuBarTicker") != nil {
            showMenuBarTicker = UserDefaults.standard.bool(forKey: "showMenuBarTicker")
        }

        registerGlobalHotKeys()
        setupLocalKeyMonitor()
        loadData(force: false)

        Timer.scheduledTimer(withTimeInterval: 180.0, repeats: true) { [weak self] _ in
            self?.loadData(force: false)
        }
    }

    // MARK: - Status Item (Menu Bar) with Brand Icons
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateMenuBarTitle()
    }

    func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }
        if showMenuBarTicker, let data = latestData {
            let entries: [(Int, NSImage, Int)] = [
                (0, IconManager.shared.codexIcon, data.codex?.primary?.used_percent ?? 0),
                (1, IconManager.shared.claudeIcon, data.claude?.primary?.used_percent ?? 0),
                (2, IconManager.shared.antigravityIcon, data.antigravity?.primary?.used_percent ?? 0)
            ]
            let active = activeProviderIndexes(data)
            let attrStr = NSMutableAttributedString()
            for (i, entry) in entries.filter({ active.contains($0.0) }).enumerated() {
                if i > 0 { attrStr.append(NSAttributedString(string: "   ")) }
                attrStr.append(makeIconAttachment(image: entry.1, size: 13))
                attrStr.append(NSAttributedString(string: " \(entry.2)%", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.white
                ]))
            }
            if active.isEmpty {
                attrStr.append(NSAttributedString(string: "Limits", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.white
                ]))
            }

            button.attributedTitle = attrStr
            button.title = ""
        } else {
            let attrStr = NSMutableAttributedString()
            attrStr.append(makeIconAttachment(image: IconManager.shared.codexIcon, size: 13))
            attrStr.append(NSAttributedString(string: " Limits", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]))
            button.attributedTitle = attrStr
            button.title = ""
        }
    }

    private func makeIconAttachment(image: NSImage, size: CGFloat) -> NSAttributedString {
        let resized = IconManager.shared.resized(image: image, size: size)
        let attachment = NSTextAttachment()
        let cell = NSTextAttachmentCell(imageCell: resized)
        attachment.attachmentCell = cell
        return NSAttributedString(attachment: attachment)
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Toggle Full HUD (Fn + Control)", action: #selector(toggleHUD), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())

            let notchItem = NSMenuItem(title: "Show Notch Companion", action: #selector(toggleNotchOption), keyEquivalent: "")
            notchItem.state = showNotchBar ? .on : .off
            menu.addItem(notchItem)

            let tickerItem = NSMenuItem(title: "Show Live Menu Bar Ticker", action: #selector(toggleTickerOption), keyEquivalent: "")
            tickerItem.state = showMenuBarTicker ? .on : .off
            menu.addItem(tickerItem)


            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Refresh Limits Now", action: #selector(refreshClicked), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit BillionTokens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleHUD()
        }
    }

    @objc func toggleNotchOption() {
        showNotchBar.toggle()
        islandButton?.title = showNotchBar ? "Notch: On" : "Notch: Off"
    }

    @objc func toggleTickerOption() {
        showMenuBarTicker.toggle()
    }

    // MARK: - Notch Island Panel

    func setupNotchPanel() {
        let pillWidth: CGFloat = 246
        let pillHeight: CGFloat = 30

        notchPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        notchPanel.level = .statusBar
        notchPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        notchPanel.isOpaque = false
        notchPanel.backgroundColor = .clear
        notchPanel.hasShadow = false // A shadow leaves a grey halo around the notch
        notchPanel.isMovable = false // Pinned to the notch; not draggable
        notchPanel.delegate = self
        notchPanel.acceptsMouseMovedEvents = true

        notchView = NotchPillView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        notchView.onClick = { [weak self] in
            self?.toggleHUD()
        }
        notchView.onRightClick = { [weak self] loc in
            self?.showNotchContextMenu(at: loc)
        }
        notchPanel.contentView = notchView

        positionNotch()
        updateNotchVisibility()

        // Re-pin when displays change (external monitor, resolution, lid open/close)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.positionNotch()
        }
        // Drop position settings from older versions that allowed dragging
        for key in ["notchPreset", "notchX", "notchY"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // Pins the pill flush around the hardware notch, filling the menu bar height.
    func positionNotch() {
        guard let panel = notchPanel else { return }
        let geom = NotchGeometry.current()
        let size = NSSize(width: geom.notchWidth + 120, height: geom.menuBarHeight)
        notchView.notchGapWidth = geom.notchWidth + 8
        notchView.style = .flush
        panel.setContentSize(size)
        notchView.frame = NSRect(origin: .zero, size: size)
        panel.setFrameOrigin(NSPoint(x: geom.notchCenterX - size.width / 2, y: geom.notchBottomY))
        notchView.needsDisplay = true
    }

    func updateNotchVisibility() {
        guard let panel = notchPanel else { return }
        if showNotchBar {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func showNotchContextMenu(at point: NSPoint) {
        let menu = NSMenu(title: "Notch Companion")

        let hudItem = NSMenuItem(title: "Open BillionTokens (Fn + Control)", action: #selector(toggleHUD), keyEquivalent: "")
        menu.addItem(hudItem)

        let refreshItem = NSMenuItem(title: "↻ Refresh Limits Now", action: #selector(refreshClicked), keyEquivalent: "r")
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "✕ Hide Notch Companion", action: #selector(toggleNotchOption), keyEquivalent: "")
        menu.addItem(hideItem)

        menu.popUp(positioning: nil, at: point, in: notchView)
    }

    // MARK: - HUD Window Creation
    func setupHUDWindow() {
        let width: CGFloat = 540
        let height: CGFloat = 482

        hudPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hudPanel.isFloatingPanel = true
        hudPanel.level = .floating
        hudPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hudPanel.isOpaque = false
        hudPanel.backgroundColor = .clear
        hudPanel.hasShadow = true
        hudPanel.titlebarAppearsTransparent = true
        hudPanel.titleVisibility = .hidden
        hudPanel.isMovableByWindowBackground = true

        visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.appearance = NSAppearance(named: .darkAqua)
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 20.0
        visualEffectView.layer?.masksToBounds = true

        hudPanel.contentView = visualEffectView

        let glassTint = LiquidGlassTintView(frame: visualEffectView.bounds)
        glassTint.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(glassTint)

        buildHUDLayout(in: visualEffectView)
    }

    // HUD layout is built top-down in a flipped view on one spacing grid,
    // then the window is sized to fit the content.
    func buildHUDLayout(in container: NSVisualEffectView) {
        let padX: CGFloat = 24
        let width = container.frame.width
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        var y: CGFloat = 18

        // Header: title + last updated on the left, Refresh + close on the right
        let headerH: CGFloat = 22
        let titleLabel = createLabel(text: "BILLIONTOKENS", fontSize: 14, isBold: true, color: NSColor(white: 0.97, alpha: 1.0))
        place(titleLabel, in: content, x: padX, rowY: y, rowH: headerH)

        timeLabel = createLabel(text: "Syncing...", fontSize: 11, isBold: false, color: NSColor(white: 0.6, alpha: 1.0))
        place(timeLabel, in: content, x: titleLabel.frame.maxX + 10, rowY: y, rowH: headerH, width: 160)

        let closeButton = makeButton(title: "×", action: #selector(closeHUD))
        closeButton.toolTip = "Close (Esc)"
        place(closeButton, in: content, x: width - padX - closeButton.frame.width, rowY: y, rowH: headerH)

        refreshButton = makeButton(title: "Refresh", action: #selector(refreshClicked))
        place(refreshButton, in: content, x: closeButton.frame.minX - 6 - refreshButton.frame.width, rowY: y, rowH: headerH)
        y += headerH

        y = addDivider(in: content, y: y)

        let codex = addSection(in: content, y: &y, icon: IconManager.shared.codexIcon, title: "OPENAI CODEX",
                               badge: "Plus", rows: ["5-hour window", "Weekly quota"])
        codexPlanBadge = codex.badge
        codexPrimaryLabel = codex.values[0]; codexPrimaryBar = codex.bars[0]
        codexSecondaryLabel = codex.values[1]; codexSecondaryBar = codex.bars[1]
        codexMetaLabel = codex.meta
        y = addDivider(in: content, y: y)

        let claude = addSection(in: content, y: &y, icon: IconManager.shared.claudeIcon, title: "ANTHROPIC CLAUDE",
                                badge: "Claude", rows: ["Current session", "All models · weekly"])
        claudePlanBadge = claude.badge
        claudePrimaryLabel = claude.values[0]; claudePrimaryBar = claude.bars[0]
        claudeSecondaryLabel = claude.values[1]; claudeSecondaryBar = claude.bars[1]
        claudeMetaLabel = claude.meta
        y = addDivider(in: content, y: y)

        let agy = addSection(in: content, y: &y, icon: IconManager.shared.antigravityIcon, title: "GOOGLE ANTIGRAVITY",
                             badge: "Consumer", rows: ["5-hour window", "Weekly quota"])
        antigravityBadge = agy.badge
        antigravityPrimaryLabel = agy.values[0]; antigravityPrimaryBar = agy.bars[0]
        antigravitySecondaryLabel = agy.values[1]; antigravitySecondaryBar = agy.bars[1]
        antigravityMetaLabel = agy.meta
        y = addDivider(in: content, y: y)

        // Footer: hint on the left, Copy on the right (presets, notch and Quit live in the right-click menu)
        let footerH: CGFloat = 20
        let footerLabel = createLabel(text: "Fn + Control to show or hide", fontSize: 10, isBold: false, color: NSColor(white: 0.5, alpha: 1.0))
        place(footerLabel, in: content, x: padX, rowY: y, rowH: footerH)

        copyButton = makeButton(title: "Copy", action: #selector(copyLimits))
        copyButton.toolTip = "Copy usage summary to clipboard"
        place(copyButton, in: content, x: width - padX - copyButton.frame.width, rowY: y, rowH: footerH)

        islandButton = makeButton(title: "Notch: Off", action: #selector(toggleNotchOption))
        islandButton.toolTip = "Show or hide the notch display"
        place(islandButton, in: content, x: copyButton.frame.minX - 6 - islandButton.frame.width, rowY: y, rowH: footerH)
        islandButton.title = showNotchBar ? "Notch: On" : "Notch: Off"
        y += footerH + 16

        // Size window to content
        content.frame.size.height = y
        content.autoresizingMask = [.width, .minYMargin]
        hudPanel.setContentSize(NSSize(width: width, height: y))
        container.frame = NSRect(x: 0, y: 0, width: width, height: y)
        content.frame.origin = .zero
        container.addSubview(content)
    }

    private func addSection(in c: NSView, y: inout CGFloat, icon: NSImage, title: String, badge: String,
                            rows: [String]) -> (badge: NSTextField, values: [NSTextField], bars: [ProgressBarView], meta: NSTextField) {
        let padX: CGFloat = 24
        let width = c.frame.width
        let fullWidth = width - (2 * padX)

        // Section header row: icon, title, plan badge (all vertically centered)
        let rowH: CGFloat = 20
        let iconView = NSImageView(frame: NSRect(x: padX, y: y + 1, width: 18, height: 18))
        iconView.image = IconManager.shared.resized(image: icon, size: 18)
        c.addSubview(iconView)

        let header = createLabel(text: title, fontSize: 12, isBold: true, color: NSColor(white: 0.92, alpha: 1.0))
        place(header, in: c, x: padX + 26, rowY: y, rowH: rowH)

        let badgeField = createBadge(text: badge, color: NSColor(calibratedWhite: 1.0, alpha: 0.10))
        badgeField.frame = NSRect(x: width - padX - 84, y: y + 1, width: 84, height: 18)
        c.addSubview(badgeField)
        y += rowH + 10

        // Metric rows: label + value on one line, bar directly under, same gap every time
        var values: [NSTextField] = []
        var bars: [ProgressBarView] = []
        let lineH: CGFloat = 15
        for (i, name) in rows.enumerated() {
            if i > 0 { y += 12 }
            let label = createLabel(text: name, fontSize: 11, isBold: false, color: NSColor(white: 0.72, alpha: 1.0))
            place(label, in: c, x: padX, rowY: y, rowH: lineH, width: 170)

            let value = createLabel(text: "--%", fontSize: 11, isBold: true, color: .white, alignment: .right)
            place(value, in: c, x: padX + 170, rowY: y, rowH: lineH, width: fullWidth - 170)
            y += lineH + 5

            let bar = ProgressBarView(frame: NSRect(x: padX, y: y, width: fullWidth, height: 6))
            c.addSubview(bar)
            y += 6
            values.append(value)
            bars.append(bar)
        }

        y += 10
        let meta = createLabel(text: "Account: --", fontSize: 10, isBold: false, color: NSColor(white: 0.65, alpha: 1.0))
        place(meta, in: c, x: padX, rowY: y, rowH: 14, width: fullWidth)
        y += 14
        return (badgeField, values, bars, meta)
    }

    // Vertically centers a view in a row using its natural height.
    private func place(_ view: NSView, in c: NSView, x: CGFloat, rowY: CGFloat, rowH: CGFloat, width: CGFloat? = nil) {
        if let control = view as? NSControl { control.sizeToFit() }
        let h = view.frame.height
        // Text fields draw with a 2pt inset; pull them out so text lines up with bars and dividers.
        let inset: CGFloat = (view is NSTextField) ? 2 : 0
        view.frame = NSRect(x: x - inset, y: rowY + ((rowH - h) / 2).rounded(), width: (width ?? view.frame.width) + 2 * inset, height: h)
        c.addSubview(view)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.sizeToFit()
        return button
    }

    func createLabel(text: String, fontSize: CGFloat, isBold: Bool, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = alignment
        label.textColor = color
        if alignment == .right {
            label.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: isBold ? .semibold : .regular)
        } else {
            label.font = isBold ? NSFont.systemFont(ofSize: fontSize, weight: .semibold) : NSFont.systemFont(ofSize: fontSize, weight: .regular)
        }
        return label
    }

    func createBadge(text: String, color: NSColor) -> NSTextField {
        let badge = NSTextField(labelWithString: text)
        badge.cell = CenteredTextFieldCell(textCell: text)
        badge.isEditable = false
        badge.isBezeled = false
        badge.drawsBackground = false
        badge.textColor = .white
        badge.alignment = .center
        badge.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        // Background on the layer so it fills the whole badge with rounded corners.
        badge.wantsLayer = true
        badge.layer?.backgroundColor = color.cgColor
        badge.layer?.cornerRadius = 4.0
        badge.layer?.masksToBounds = true
        return badge
    }

    // Adds a separator with equal space above and below; returns the next y.
    func addDivider(in container: NSView, y: CGFloat) -> CGFloat {
        let gap: CGFloat = 12
        let divider = NSBox(frame: NSRect(x: 24, y: y + gap, width: container.frame.width - 48, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)
        return y + gap + 1 + gap
    }

    // MARK: - HotKeys & Key Monitoring (Fn + Control)
    var isFnCtrlTriggered = false
    var globalFlagsMonitor: Any?
    var localFlagsMonitor: Any?

    func registerGlobalHotKeys() {
        // Monitor Fn + Control globally across all applications
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkFnControl(flags: event.modifierFlags)
        }

        // Also monitor locally when HUD or app is active
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.checkFnControl(flags: event.modifierFlags)
            return event
        }

        // Backup Carbon HotKeys (Option + Space & Cmd + Shift + L)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let appPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let mySelf = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    mySelf.toggleHUD()
                }
                return noErr
            },
            1,
            &eventType,
            appPointer,
            nil
        )

        let hotKeyID1 = EventHotKeyID(signature: OSType(0x41494C31), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), hotKeyID1, GetApplicationEventTarget(), 0, &hotKeyRef1)

        let hotKeyID2 = EventHotKeyID(signature: OSType(0x41494C32), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | shiftKey), hotKeyID2, GetApplicationEventTarget(), 0, &hotKeyRef2)
    }

    private func checkFnControl(flags: NSEvent.ModifierFlags) {
        let hasCtrl = flags.contains(.control)
        let hasFn = flags.contains(.function)

        if hasCtrl && hasFn {
            if !isFnCtrlTriggered {
                isFnCtrlTriggered = true
                DispatchQueue.main.async { [weak self] in
                    self?.toggleHUD()
                }
            }
        } else {
            isFnCtrlTriggered = false
        }
    }

    func setupLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.closeHUD()
                return nil
            }
            return event
        }
    }

    // MARK: - HUD Display
    @objc func toggleHUD() {
        if hudPanel.isVisible {
            closeHUD()
        } else {
            showHUD()
        }
    }

    func showHUD() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? hudPanel.screen

        if let screenFrame = screen?.visibleFrame {
            let x = screenFrame.midX - hudPanel.frame.width / 2
            let y = screenFrame.midY - hudPanel.frame.height / 2 + 30
            hudPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        hudPanel.alphaValue = 0
        hudPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hudPanel.animator().alphaValue = 1.0
        }

        loadData(force: false)
    }

    @objc func closeHUD() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            hudPanel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.hudPanel.orderOut(nil)
        })
    }

    @objc func refreshClicked() {
        loadData(force: true)
    }

    @objc func copyLimits() {
        guard let data = latestData else { return }
        var summary = "=== BILLIONTOKENS USAGE SUMMARY ===\n"
        if let codex = data.codex {
            summary += "\n⚡ OpenAI Codex (\(codex.plan ?? "Plus")):\n"
            if let pri = codex.primary {
                summary += "• 5h Window: \(pri.used_percent ?? 0)% used (\(pri.reset_str ?? ""))\n"
            }
            if let sec = codex.secondary {
                summary += "• Weekly: \(sec.used_percent ?? 0)% used (\(sec.reset_str ?? ""))\n"
            }
            summary += "• Reset Credits: \(codex.reset_credits ?? 0)\n"
        }
        if let claude = data.claude {
            summary += "\n✦ Anthropic Claude (\(claude.plan ?? "Pro")):\n"
            if let pri = claude.primary {
                summary += "• Session: \(pri.used_percent ?? 0)% used (\(pri.reset_str ?? ""))\n"
            }
            if let sec = claude.secondary {
                summary += "• Weekly: \(sec.used_percent ?? 0)% used (\(sec.reset_str ?? ""))\n"
            }
            summary += "• Account: \(claude.email ?? "")\n"
        }
        if let agy = data.antigravity {
            summary += "\n🪐 Google Antigravity (\(agy.plan ?? "Consumer")):\n"
            if let pri = agy.primary {
                summary += "• 5h Window: \(pri.used_percent ?? 0)% used (\(pri.reset_str ?? ""))\n"
            }
            if let sec = agy.secondary {
                summary += "• Weekly: \(sec.used_percent ?? 0)% used (\(sec.reset_str ?? ""))\n"
            }
            summary += "• Account: \(agy.email ?? "")  •  Model: \(agy.active_model ?? "")\n"
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summary, forType: .string)

        copyButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy"
        }
    }

    // MARK: - Data Fetching
    func loadData(force: Bool) {
        if isRefreshing { return }
        isRefreshing = true
        refreshButton.isEnabled = false
        timeLabel.stringValue = "Syncing..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scriptPath = Bundle.main.path(forResource: "collector", ofType: "py")
                ?? "\(FileManager.default.currentDirectoryPath)/collector.py"
            var args = [scriptPath]
            if force {
                args.append("--force")
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = args
            proc.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()

            var payload: LimitPayload? = nil
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let decoded = try? JSONDecoder().decode(LimitPayload.self, from: data) {
                    payload = decoded
                }
            } catch {
                print("Failed to run collector:", error)
            }

            DispatchQueue.main.async {
                self?.isRefreshing = false
                self?.refreshButton.isEnabled = true
                if let payload = payload {
                    self?.latestData = payload
                    self?.updateUI(with: payload)
                } else {
                    self?.timeLabel.stringValue = "Sync error"
                }
            }
        }
    }

    func activeProviderIndexes(_ data: LimitPayload) -> [Int] {
        [data.codex?.status, data.claude?.status, data.antigravity?.status]
            .enumerated()
            .filter { $0.element == "connected" }
            .map { $0.offset }
    }

    // Replaces a section's numbers with a short explanation when there is no data.
    // Returns false when the provider is connected and should render normally.
    func showStatusMessage(_ status: String?, installHint: String, badge: NSTextField,
                           primary: NSTextField, primaryBar: ProgressBarView,
                           secondary: NSTextField, secondaryBar: ProgressBarView,
                           meta: NSTextField) -> Bool {
        let messages: [String: (String, String)] = [
            "not_installed": ("Not installed", installHint),
            "disabled": ("Disabled", "Turn on in config.json"),
            "token_expired": ("Token expired", "Open the app to refresh"),
            "error": ("Unavailable", "Check the CLI is signed in"),
            "offline": ("Unavailable", "Check the CLI is signed in")
        ]
        guard let status = status, let msg = messages[status] else { return false }
        badge.stringValue = "—"
        primary.stringValue = msg.0
        secondary.stringValue = msg.1
        primaryBar.percentage = 0
        secondaryBar.percentage = 0
        meta.stringValue = ""
        return true
    }

    func updateUI(with data: LimitPayload) {
        timeLabel.stringValue = "Updated: \(data.time_str ?? "Now")"

        let cPct = data.codex?.primary?.used_percent ?? 0
        let cReset = data.codex?.primary?.reset_str ?? ""
        let clPct = data.claude?.primary?.used_percent ?? 0
        let clReset = data.claude?.primary?.reset_str ?? ""
        let agPct = data.antigravity?.primary?.used_percent ?? 0
        let agReset = data.antigravity?.primary?.reset_str ?? ""

        // Update Notch Island (only providers that returned data)
        notchView?.activeProviders = activeProviderIndexes(data)
        notchView?.codexPercent = cPct
        notchView?.codexReset = cReset
        notchView?.claudePercent = clPct
        notchView?.claudeReset = clReset
        notchView?.antigravityPercent = agPct
        notchView?.antigravityReset = agReset

        // Update Menu Bar Ticker with Brand Icons
        updateMenuBarTitle()

        // 1. Update Codex
        if let codex = data.codex, !showStatusMessage(codex.status, installHint: "Install the codex CLI",
                badge: codexPlanBadge, primary: codexPrimaryLabel, primaryBar: codexPrimaryBar,
                secondary: codexSecondaryLabel, secondaryBar: codexSecondaryBar, meta: codexMetaLabel) {
            codexPlanBadge.stringValue = codex.plan ?? "Plus"
            if let pri = codex.primary {
                let pct = Double(pri.used_percent ?? 0)
                codexPrimaryBar.percentage = pct
                codexPrimaryLabel.stringValue = "\(Int(pct))% (\(pri.reset_str ?? ""))"
            }
            if let sec = codex.secondary {
                let pct = Double(sec.used_percent ?? 0)
                codexSecondaryBar.percentage = pct
                codexSecondaryLabel.stringValue = "\(Int(pct))% (\(sec.reset_str ?? ""))"
            }
            let credits = codex.reset_credits ?? 0
            codexMetaLabel.stringValue = "Credits: \(credits) available  •  Plan: \(codex.plan ?? "Plus")"
        }

        // 2. Update Claude
        if let claude = data.claude, !showStatusMessage(claude.status, installHint: "Install Claude Code",
                badge: claudePlanBadge, primary: claudePrimaryLabel, primaryBar: claudePrimaryBar,
                secondary: claudeSecondaryLabel, secondaryBar: claudeSecondaryBar, meta: claudeMetaLabel) {
            claudePlanBadge.stringValue = claude.plan ?? "Claude Pro"
            if let pri = claude.primary {
                let pct = Double(pri.used_percent ?? 0)
                claudePrimaryBar.percentage = pct
                claudePrimaryLabel.stringValue = "\(Int(pct))% (\(pri.reset_str ?? ""))"
            }
            if let sec = claude.secondary {
                let pct = Double(sec.used_percent ?? 0)
                claudeSecondaryBar.percentage = pct
                claudeSecondaryLabel.stringValue = "\(Int(pct))% (\(sec.reset_str ?? ""))"
            }
            claudeMetaLabel.stringValue = "Account: \(claude.email ?? "apple_sub")  •  \(claude.tier ?? "default_tier")"
        }

        // 3. Update Antigravity
        if let agy = data.antigravity, !showStatusMessage(agy.status, installHint: "Install Antigravity",
                badge: antigravityBadge, primary: antigravityPrimaryLabel, primaryBar: antigravityPrimaryBar,
                secondary: antigravitySecondaryLabel, secondaryBar: antigravitySecondaryBar, meta: antigravityMetaLabel) {
            antigravityBadge.stringValue = agy.plan ?? "Consumer"
            if let pri = agy.primary {
                let pct = Double(pri.used_percent ?? 0)
                antigravityPrimaryBar.percentage = pct
                antigravityPrimaryLabel.stringValue = "\(Int(pct))% (\(pri.reset_str ?? ""))"
            }
            if let sec = agy.secondary {
                let pct = Double(sec.used_percent ?? 0)
                antigravitySecondaryBar.percentage = pct
                antigravitySecondaryLabel.stringValue = "\(Int(pct))% (\(sec.reset_str ?? ""))"
            }
            var meta = ["Account: \((agy.email ?? "").isEmpty ? "--" : agy.email!)"]
            if let model = agy.active_model, !model.isEmpty { meta.append("Model: \(model)") }
            if let lastAct = agy.last_active, !lastAct.isEmpty { meta.append("Last active \(lastAct)") }
            antigravityMetaLabel.stringValue = meta.joined(separator: "  •  ")
        }
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
