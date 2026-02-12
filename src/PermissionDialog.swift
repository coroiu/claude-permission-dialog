import Cocoa

// Claude Code Permission Dialog
// A floating, always-on-top dialog that grabs keyboard focus immediately.
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

        let width: CGFloat = 580
        let height: CGFloat = 380
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let x = (screenFrame.width - width) / 2
        let y = (screenFrame.height - height) / 2 + 100

        // 1. Sleek titlebar
        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude permission request"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        // 6. NSVisualEffectView background
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        window.contentView = visualEffect

        var yPos = height - 38.0  // extra top padding for titlebar inset

        // -- Project / working directory bar --
        let projectName = extractProjectName(from: cwd)
        let cwdDisplay = abbreviateHome(cwd)

        yPos -= 20
        let projectLabel = NSTextField(labelWithString: "")
        projectLabel.frame = NSRect(x: 20, y: yPos, width: width - 40, height: 18)
        projectLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        projectLabel.textColor = NSColor.secondaryLabelColor
        projectLabel.lineBreakMode = .byTruncatingMiddle

        // Project label with folder icon prefix
        let projectString = NSMutableAttributedString()
        let folderAttachment = NSTextAttachment()
        if let folderImage = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            folderAttachment.image = folderImage.withSymbolConfiguration(config)
        }
        let folderStr = NSAttributedString(attachment: folderAttachment)
        projectString.append(folderStr)
        projectString.append(NSAttributedString(string: " \(projectName)  \u{2014}  \(cwdDisplay)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        projectLabel.attributedStringValue = projectString
        visualEffect.addSubview(projectLabel)

        // -- Separator --
        yPos -= 10
        let separator = NSBox(frame: NSRect(x: 20, y: yPos, width: width - 40, height: 1))
        separator.boxType = .separator
        visualEffect.addSubview(separator)

        // 2. SF Symbol icon per tool type + action label (vertically centered)
        yPos -= 8

        let actionLabel = NSTextField(wrappingLabelWithString: action)
        actionLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        actionLabel.lineBreakMode = .byWordWrapping
        actionLabel.maximumNumberOfLines = 0
        let textMaxWidth = width - 84
        let textSize = actionLabel.sizeThatFits(NSSize(width: textMaxWidth, height: CGFloat.greatestFiniteMagnitude))
        let textHeight = max(textSize.height, 20)

        let iconSize: CGFloat = 36
        let blockHeight = max(iconSize, textHeight)

        yPos -= blockHeight

        let iconView = NSImageView(frame: NSRect(x: 20, y: yPos + (blockHeight - iconSize) / 2, width: iconSize, height: iconSize))
        let symbolName = sfSymbolName(for: toolName)
        if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolName) {
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            iconView.image = symbolImage.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor.secondaryLabelColor
        }
        visualEffect.addSubview(iconView)

        actionLabel.frame = NSRect(x: 64, y: yPos + (blockHeight - textHeight) / 2, width: textMaxWidth, height: textHeight)
        visualEffect.addSubview(actionLabel)

        // 4. Rounded detail area
        let detailTop = yPos - 12
        let detailHeight = max(detailTop - 64.0, 80)

        // Container with rounded corners and subtle border
        let detailContainer = NSView(frame: NSRect(x: 20, y: 64, width: width - 40, height: detailHeight))
        detailContainer.wantsLayer = true
        detailContainer.layer?.cornerRadius = 8
        detailContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        detailContainer.layer?.borderWidth = 0.5
        detailContainer.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        detailContainer.layer?.masksToBounds = true
        visualEffect.addSubview(detailContainer)

        let scrollView = NSScrollView(frame: detailContainer.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: detailContainer.bounds.width - 16, height: detailHeight))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = detail
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false

        scrollView.documentView = textView
        detailContainer.addSubview(scrollView)

        // 3. Accent-colored Allow button
        let allowButton = NSButton(frame: NSRect(x: width - 130, y: 16, width: 110, height: 32))
        allowButton.title = ""
        allowButton.isBordered = false
        allowButton.wantsLayer = true
        allowButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        allowButton.layer?.cornerRadius = 6
        allowButton.attributedTitle = NSAttributedString(string: "Allow  \u{23CE}", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        allowButton.keyEquivalent = "\r"
        allowButton.target = self
        allowButton.action = #selector(allow)
        visualEffect.addSubview(allowButton)

        // Subtle Deny button
        let denyButton = NSButton(frame: NSRect(x: width - 250, y: 16, width: 110, height: 32))
        denyButton.title = ""
        denyButton.isBordered = false
        denyButton.wantsLayer = true
        denyButton.layer?.backgroundColor = NSColor.controlColor.cgColor
        denyButton.layer?.cornerRadius = 6
        denyButton.attributedTitle = NSAttributedString(string: "Deny  \u{238B}", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.controlTextColor
        ])
        denyButton.keyEquivalent = "\u{1b}"
        denyButton.target = self
        denyButton.action = #selector(deny)
        visualEffect.addSubview(denyButton)

        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)
    }

    /// Map tool names to SF Symbol names
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

    /// Extract a project name from the cwd (last path component, or second-to-last if inside a subfolder)
    func extractProjectName(from path: String) -> String {
        let cleaned = path.hasSuffix("/") ? String(path.dropLast()) : path
        let components = cleaned.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return "Unknown project" }

        // If the path looks like it's inside a known structure, try to find the project root
        // e.g. ~/code/my-project/src -> "my-project"
        if let codeIdx = components.lastIndex(of: "code") ?? components.lastIndex(of: "projects") ?? components.lastIndex(of: "repos") {
            let projectIdx = components.index(after: codeIdx)
            if projectIdx < components.endIndex {
                return components[projectIdx]
            }
        }

        return components.last ?? "Unknown project"
    }

    /// Replace home directory with ~
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
