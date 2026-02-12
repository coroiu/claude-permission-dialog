import Cocoa

// Claude Code Permission Dialog — Spotlight-style floating panel
// Input (stdin JSON): { "tool_name", "action", "detail", "cwd" }
// Prints "allow" or "deny" to stdout.

class PermissionDialog: NSObject, NSApplicationDelegate {
    var toolName: String = "Unknown"
    var action: String = ""
    var detail: String = ""
    var cwd: String = ""
    var window: NSWindow!

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
        let footerHeight: CGFloat = 44
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        // --- Measure action text to compute dynamic height ---
        let actionFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let textAreaWidth = width - padding - 32 - 12 - padding  // left pad + icon + gap + right pad
        let measureLabel = NSTextField(wrappingLabelWithString: action)
        measureLabel.font = actionFont
        measureLabel.maximumNumberOfLines = 0
        let measuredSize = measureLabel.sizeThatFits(NSSize(width: textAreaWidth, height: .greatestFiniteMagnitude))
        let actionHeight = max(measuredSize.height, 24)

        let iconSize: CGFloat = 32
        let topBlockHeight = max(iconSize, actionHeight)
        let topSectionHeight = padding + topBlockHeight + padding
        let detailHeight: CGFloat = 200
        let totalHeight = topSectionHeight + 1 + detailHeight + 1 + footerHeight

        let x = (screenFrame.width - width) / 2
        let y = (screenFrame.height - totalHeight) / 2 + 140  // upper third like Spotlight

        // --- Window: titled but chrome-free (ensures text rendering works) ---
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

        // Hide the titlebar buttons (close/minimize/zoom)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // --- Frosted glass background ---
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        window.contentView = visualEffect

        // ============================================================
        // TOP SECTION: icon + action description
        // ============================================================
        let topY = totalHeight - topSectionHeight

        let iconView = NSImageView(frame: NSRect(
            x: padding,
            y: topY + (topSectionHeight - iconSize) / 2,
            width: iconSize, height: iconSize
        ))
        let symbolName = sfSymbolName(for: toolName)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolName) {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor.secondaryLabelColor
        }
        visualEffect.addSubview(iconView)

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
        let sep = NSBox(frame: NSRect(x: 0, y: topY, width: width, height: 1))
        sep.boxType = .separator
        visualEffect.addSubview(sep)

        // ============================================================
        // DETAIL AREA: scrollable command/content preview
        // ============================================================
        let detailY = footerHeight + 1

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
        // FOOTER: project info (left) + buttons (right)
        // ============================================================
        let footerSep = NSBox(frame: NSRect(x: 0, y: footerHeight, width: width, height: 1))
        footerSep.boxType = .separator
        visualEffect.addSubview(footerSep)

        // Project label with folder icon
        let projectName = extractProjectName(from: cwd)
        let cwdDisplay = abbreviateHome(cwd)

        let projectLabel = NSTextField(labelWithString: "")
        projectLabel.frame = NSRect(x: padding, y: (footerHeight - 18) / 2, width: width * 0.5, height: 18)
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

        // Allow button (accent pill)
        let allowBtn = NSButton(frame: NSRect(x: width - padding - 90, y: (footerHeight - 26) / 2, width: 90, height: 26))
        allowBtn.title = ""
        allowBtn.isBordered = false
        allowBtn.wantsLayer = true
        allowBtn.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        allowBtn.layer?.cornerRadius = 6
        allowBtn.attributedTitle = NSAttributedString(string: "Allow  \u{23CE}", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        allowBtn.keyEquivalent = "\r"
        allowBtn.target = self
        allowBtn.action = #selector(allow)
        visualEffect.addSubview(allowBtn)

        // Deny button (subtle pill)
        let denyBtn = NSButton(frame: NSRect(x: width - padding - 90 - 8 - 80, y: (footerHeight - 26) / 2, width: 80, height: 26))
        denyBtn.title = ""
        denyBtn.isBordered = false
        denyBtn.wantsLayer = true
        denyBtn.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        denyBtn.layer?.cornerRadius = 6
        denyBtn.attributedTitle = NSAttributedString(string: "Deny  \u{238B}", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        denyBtn.keyEquivalent = "\u{1b}"
        denyBtn.target = self
        denyBtn.action = #selector(deny)
        visualEffect.addSubview(denyBtn)

        // --- Show and activate ---
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)
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

    @objc func allow() {
        print("allow")
        NSApp.terminate(nil)
    }

    @objc func deny() {
        print("deny")
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = PermissionDialog()
app.delegate = delegate
app.run()
