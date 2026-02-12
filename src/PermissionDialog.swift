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

        let width: CGFloat = 560
        let height: CGFloat = 380
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let x = (screenFrame.width - width) / 2
        let y = (screenFrame.height - height) / 2 + 100

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Code Permission"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        var yPos = height - 16.0

        // -- Project / working directory bar --
        let projectName = extractProjectName(from: cwd)
        let cwdDisplay = abbreviateHome(cwd)

        yPos -= 20
        let projectLabel = NSTextField(labelWithString: "\(projectName)  \u{2014}  \(cwdDisplay)")
        projectLabel.frame = NSRect(x: 20, y: yPos, width: width - 40, height: 18)
        projectLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        projectLabel.textColor = NSColor.secondaryLabelColor
        projectLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(projectLabel)

        // -- Separator --
        yPos -= 10
        let separator = NSBox(frame: NSRect(x: 20, y: yPos, width: width - 40, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        // -- Icon + action description --
        yPos -= 40
        let iconView = NSImageView(frame: NSRect(x: 20, y: yPos, width: 36, height: 36))
        iconView.image = NSImage(named: NSImage.cautionName)
        contentView.addSubview(iconView)

        let actionLabel = NSTextField(wrappingLabelWithString: action)
        actionLabel.frame = NSRect(x: 64, y: yPos - 4, width: width - 84, height: 44)
        actionLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        actionLabel.maximumNumberOfLines = 2
        actionLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(actionLabel)

        // -- Detail in a scroll view --
        let detailTop = yPos - 12
        let detailHeight = detailTop - 64.0  // leave room for buttons

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 64, width: width - 40, height: detailHeight))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width - 56, height: detailHeight))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = detail
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        // -- Buttons --
        let allowButton = NSButton(frame: NSRect(x: width - 130, y: 16, width: 110, height: 36))
        allowButton.title = "Allow  \u{23CE}"
        allowButton.bezelStyle = .rounded
        allowButton.keyEquivalent = "\r"
        allowButton.target = self
        allowButton.action = #selector(allow)
        allowButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(allowButton)

        let denyButton = NSButton(frame: NSRect(x: width - 250, y: 16, width: 110, height: 36))
        denyButton.title = "Deny  \u{238B}"
        denyButton.bezelStyle = .rounded
        denyButton.keyEquivalent = "\u{1b}"
        denyButton.target = self
        denyButton.action = #selector(deny)
        denyButton.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        contentView.addSubview(denyButton)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.contentView)
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
