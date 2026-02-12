import Cocoa

// Claude Code Permission Dialog — Spotlight-style floating panel
// Input (stdin JSON): { "tool_name", "action", "detail", "cwd" }
// Prints "allow" or "deny" to stdout.

// Custom view to intercept arrow keys and Enter for Spotlight-style row selection
class KeyHandlerView: NSView {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onArrowUp?()    // up arrow
        case 125: onArrowDown?()  // down arrow
        case 36:  onConfirm?()    // return
        case 53:  onEscape?()     // escape
        default: super.keyDown(with: event)
        }
    }
}

struct OptionRow {
    let label: String
    let shortcut: String
    let icon: String
    let value: String  // what gets printed to stdout
}

class PermissionDialog: NSObject, NSApplicationDelegate {
    var toolName: String = "Unknown"
    var action: String = ""
    var detail: String = ""
    var cwd: String = ""
    var window: NSWindow!

    let options: [OptionRow] = [
        OptionRow(label: "Allow", shortcut: "\u{23CE}", icon: "checkmark.circle", value: "allow"),
        OptionRow(label: "Deny", shortcut: "\u{238B}", icon: "xmark.circle", value: "deny"),
    ]
    var selectedIndex = 0
    var rowViews: [NSView] = []
    var labelFields: [NSTextField] = []
    var shortcutFields: [NSTextField] = []
    var iconViews: [NSImageView] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = FileHandle.standardInput.availableData as Data?,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            toolName = json["tool_name"] as? String ?? "Unknown"
            action = json["action"] as? String ?? ""
            detail = json["detail"] as? String ?? ""
            cwd = json["cwd"] as? String ?? ""
        }

        let width: CGFloat = 680
        let padding: CGFloat = 16
        let rowHeight: CGFloat = 36
        let footerHeight: CGFloat = 32
        let optionsHeight = rowHeight * CGFloat(options.count)
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        // --- Measure action text to compute dynamic height ---
        let actionFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let textAreaWidth = width - padding - 32 - 12 - padding
        let measureLabel = NSTextField(wrappingLabelWithString: action)
        measureLabel.font = actionFont
        measureLabel.maximumNumberOfLines = 0
        let measuredSize = measureLabel.sizeThatFits(NSSize(width: textAreaWidth, height: .greatestFiniteMagnitude))
        let actionHeight = max(measuredSize.height, 24)

        let iconSize: CGFloat = 32
        let topBlockHeight = max(iconSize, actionHeight)
        let topSectionHeight = padding + topBlockHeight + padding
        let detailHeight: CGFloat = 180
        let totalHeight = topSectionHeight + 1 + detailHeight + 1 + optionsHeight + 1 + footerHeight

        let x = (screenFrame.width - width) / 2
        let y = (screenFrame.height - totalHeight) / 2 + 140

        // --- Window ---
        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: totalHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = ""
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // --- Key handler as content view base ---
        let keyHandler = KeyHandlerView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        keyHandler.onArrowUp = { [weak self] in self?.moveSelection(-1) }
        keyHandler.onArrowDown = { [weak self] in self?.moveSelection(1) }
        keyHandler.onConfirm = { [weak self] in self?.confirmSelection() }
        keyHandler.onEscape = { [weak self] in
            self?.selectedIndex = self?.options.firstIndex(where: { $0.value == "deny" }) ?? 1
            self?.confirmSelection()
        }

        // --- Frosted glass background ---
        let visualEffect = NSVisualEffectView(frame: keyHandler.bounds)
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        keyHandler.addSubview(visualEffect)
        window.contentView = keyHandler

        // ============================================================
        // TOP SECTION: icon + action description
        // ============================================================
        let topY = totalHeight - topSectionHeight

        let toolIconView = NSImageView(frame: NSRect(
            x: padding, y: topY + (topSectionHeight - iconSize) / 2,
            width: iconSize, height: iconSize
        ))
        let symbolName = sfSymbolName(for: toolName)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolName) {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            toolIconView.image = img.withSymbolConfiguration(config)
            toolIconView.contentTintColor = NSColor.secondaryLabelColor
        }
        visualEffect.addSubview(toolIconView)

        let actionLabel = NSTextField(wrappingLabelWithString: action)
        actionLabel.font = actionFont
        actionLabel.textColor = NSColor.labelColor
        actionLabel.lineBreakMode = .byWordWrapping
        actionLabel.maximumNumberOfLines = 0
        actionLabel.drawsBackground = false
        actionLabel.isBezeled = false
        actionLabel.isEditable = false
        actionLabel.frame = NSRect(
            x: padding + iconSize + 12,
            y: topY + (topSectionHeight - actionHeight) / 2,
            width: textAreaWidth, height: actionHeight
        )
        visualEffect.addSubview(actionLabel)

        // ============================================================
        // SEPARATOR
        // ============================================================
        let sep1 = NSBox(frame: NSRect(x: 0, y: topY, width: width, height: 1))
        sep1.boxType = .separator
        visualEffect.addSubview(sep1)

        // ============================================================
        // DETAIL AREA
        // ============================================================
        let detailY = footerHeight + 1 + optionsHeight + 1

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: detailY, width: width, height: detailHeight))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: detailHeight))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.string = detail
        textView.textContainerInset = NSSize(width: padding, height: 12)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false

        scrollView.documentView = textView
        visualEffect.addSubview(scrollView)

        // ============================================================
        // SEPARATOR above options
        // ============================================================
        let sep2 = NSBox(frame: NSRect(x: 0, y: footerHeight + optionsHeight + 1, width: width, height: 1))
        sep2.boxType = .separator
        visualEffect.addSubview(sep2)

        // ============================================================
        // OPTION ROWS (Spotlight-style selectable list)
        // ============================================================
        for (i, option) in options.enumerated() {
            let rowY = footerHeight + optionsHeight - rowHeight * CGFloat(i + 1)

            // Row background (highlight container)
            let rowBg = NSView(frame: NSRect(x: 4, y: rowY + 2, width: width - 8, height: rowHeight - 4))
            rowBg.wantsLayer = true
            rowBg.layer?.cornerRadius = 6
            visualEffect.addSubview(rowBg)
            rowViews.append(rowBg)

            // Row icon
            let rowIcon = NSImageView(frame: NSRect(x: padding + 4, y: rowY + (rowHeight - 18) / 2, width: 18, height: 18))
            if let img = NSImage(systemSymbolName: option.icon, accessibilityDescription: option.label) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                rowIcon.image = img.withSymbolConfiguration(cfg)
            }
            visualEffect.addSubview(rowIcon)
            iconViews.append(rowIcon)

            // Row label
            let label = NSTextField(labelWithString: option.label)
            label.frame = NSRect(x: padding + 28, y: rowY + (rowHeight - 20) / 2, width: width - 140, height: 20)
            label.font = NSFont.systemFont(ofSize: 14, weight: .regular)
            visualEffect.addSubview(label)
            labelFields.append(label)

            // Shortcut hint
            let shortcut = NSTextField(labelWithString: option.shortcut)
            shortcut.frame = NSRect(x: width - padding - 30, y: rowY + (rowHeight - 18) / 2, width: 30, height: 18)
            shortcut.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            shortcut.alignment = .right
            visualEffect.addSubview(shortcut)
            shortcutFields.append(shortcut)
        }

        // ============================================================
        // SEPARATOR above footer
        // ============================================================
        let sep3 = NSBox(frame: NSRect(x: 0, y: footerHeight, width: width, height: 1))
        sep3.boxType = .separator
        visualEffect.addSubview(sep3)

        // ============================================================
        // FOOTER: project info
        // ============================================================
        let projectName = extractProjectName(from: cwd)
        let cwdDisplay = abbreviateHome(cwd)

        let projectLabel = NSTextField(labelWithString: "")
        projectLabel.frame = NSRect(x: padding, y: (footerHeight - 16) / 2, width: width - padding * 2, height: 16)
        projectLabel.lineBreakMode = .byTruncatingMiddle

        let projectString = NSMutableAttributedString()
        let folderAttachment = NSTextAttachment()
        if let folderImg = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            folderAttachment.image = folderImg.withSymbolConfiguration(cfg)
        }
        projectString.append(NSAttributedString(attachment: folderAttachment))
        projectString.append(NSAttributedString(string: " \(projectName)  \u{2014}  \(cwdDisplay)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        projectLabel.attributedStringValue = projectString
        visualEffect.addSubview(projectLabel)

        // --- Apply initial selection highlight ---
        updateSelection()

        // --- Show and activate ---
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(keyHandler)
    }

    func moveSelection(_ delta: Int) {
        selectedIndex = max(0, min(options.count - 1, selectedIndex + delta))
        updateSelection()
    }

    func updateSelection() {
        for (i, rowBg) in rowViews.enumerated() {
            let isSelected = (i == selectedIndex)
            rowBg.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.clear.cgColor

            labelFields[i].textColor = isSelected ? NSColor.white : NSColor.labelColor
            labelFields[i].font = isSelected
                ? NSFont.systemFont(ofSize: 14, weight: .medium)
                : NSFont.systemFont(ofSize: 14, weight: .regular)

            shortcutFields[i].textColor = isSelected
                ? NSColor.white.withAlphaComponent(0.8)
                : NSColor.tertiaryLabelColor

            iconViews[i].contentTintColor = isSelected ? NSColor.white : NSColor.secondaryLabelColor
        }
    }

    func confirmSelection() {
        print(options[selectedIndex].value)
        NSApp.terminate(nil)
    }

    func sfSymbolName(for tool: String) -> String {
        let lowered = tool.lowercased()
        if lowered == "bash" { return "terminal" }
        if lowered == "edit" || lowered == "write" { return "doc.text" }
        if lowered == "read" { return "doc" }
        if lowered == "webfetch" || lowered == "websearch" { return "globe" }
        if lowered == "grep" { return "magnifyingglass" }
        if lowered == "glob" { return "doc.text.magnifyingglass" }
        if lowered == "task" { return "cpu" }
        if lowered.hasPrefix("mcp") { return "puzzlepiece" }
        return "questionmark.circle"
    }

    func extractProjectName(from path: String) -> String {
        let cleaned = path.hasSuffix("/") ? String(path.dropLast()) : path
        let components = cleaned.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return "Unknown project" }
        if let codeIdx = components.lastIndex(of: "code") ?? components.lastIndex(of: "projects") ?? components.lastIndex(of: "repos") {
            let projectIdx = components.index(after: codeIdx)
            if projectIdx < components.endIndex {
                return components[projectIdx]
            }
        }
        return components.last ?? "Unknown project"
    }

    func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    func applicationWillTerminate(_ notification: Notification) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = PermissionDialog()
app.delegate = delegate
app.run()
