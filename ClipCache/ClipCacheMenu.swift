import SwiftUI
import AppKit
import Carbon

struct ClipCacheMenu: View {
    @EnvironmentObject var manager: ClipCacheManager
    @State private var isCapturingShortcut = false
    @State private var isCapturingClearShortcut = false
    @State private var isHoveringHeader = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button {
                        if let url = URL(string: "https://clipcache.app") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("ClipCache")
                            .font(.system(size: 16, weight: .semibold))
                            .underline(isHoveringHeader)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringHeader = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("v\(version)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 0) {
                // Settings Section
                MenuSection(title: "Settings", icon: "gearshape", showResetButton: true, manager: manager) {
                    MenuSetting("Hotkeys") {
                        HStack(spacing: 6) {
                            ShortcutCaptureView(
                                keyCode: $manager.pasteShortcutKey,
                                modifiers: $manager.pasteShortcutModifiers,
                                isCapturing: $isCapturingShortcut
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            .onChange(of: manager.pasteShortcutKey) { _, _ in
                                manager.updateHotKey()
                            }
                            .onChange(of: manager.pasteShortcutModifiers) { _, _ in
                                manager.updateHotKey()
                            }
                            Text("Paste from cache")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 6) {
                            ShortcutCaptureView(
                                keyCode: $manager.clearCacheShortcutKey,
                                modifiers: $manager.clearCacheShortcutModifiers,
                                isCapturing: $isCapturingClearShortcut
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            .onChange(of: manager.clearCacheShortcutKey) { _, _ in
                                manager.updateHotKey()
                            }
                            .onChange(of: manager.clearCacheShortcutModifiers) { _, _ in
                                manager.updateHotKey()
                            }
                            Text("Clear cache")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Capture Options
                    MenuSettingWithHelp("Capture Options", helpContent: {
                        HelpPopoverButton(
                            title: "Capture Options",
                            description: "Choose what types of content to capture from your clipboard. Images captures screenshots and copied images. Text captures copied text content."
                        )
                    }, settingContent: {
                        HStack(spacing: 16) {
                            Toggle("Images", isOn: $manager.captureImages)
                            Toggle("Text", isOn: $manager.captureText)
                        }
                    })
                    
                    // Menu Bar Display
                    MenuSetting("Menu Bar Display Options") {
                        Toggle("No. of images in cache", isOn: $manager.showImageCountInMenuBar)
                            .onChange(of: manager.showImageCountInMenuBar) { _, _ in
                                manager.updateMenuBarTitle()
                            }
                        Toggle("Window timer countdown", isOn: $manager.showTimerInMenuBar)
                            .onChange(of: manager.showTimerInMenuBar) { _, _ in
                                manager.updateMenuBarTitle()
                            }
                    }
                    
                    // Copy Window
                    MenuSettingWithHelp("Copy Window Timer", bottomPadding: -2, helpContent: {
                        HelpPopoverButton(
                            title: "Copy Window",
                            description: "When you copy the first item, a time window opens. Any copies within this window extend it and add to the cache. After the window closes, the cache stays available forever until you copy something new."
                        )
                    }, settingContent: {
                        HStack(spacing: 8) {
                            CustomSlider(value: $manager.copyWindowSeconds, in: 1...60, step: 1)
                            TextField("", value: $manager.copyWindowSeconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 45)
                                .monospacedDigit()
                            Text("s")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 12, alignment: .leading)
                        }
                    })
                    
                    // Paste Cooldown
                    MenuSettingWithHelp("Paste Cooldown", helpContent: {
                        HelpPopoverButton(
                            title: "Paste Cooldown",
                            description: "The delay in milliseconds between pasting multiple items. Lower values paste faster but may cause issues with some applications. Higher values are more reliable but slower."
                        )
                    }, settingContent: {
                        HStack(spacing: 8) {
                            CustomSlider(value: $manager.pasteCooldownMs, in: 50...1000, step: 10)
                            TextField("", value: $manager.pasteCooldownMs, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .monospacedDigit()
                            Text("ms")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 20, alignment: .leading)
                        }
                    })
                    
                    // Open on Startup
                    MenuSetting("Open on startup") {
                        Toggle("Launch app at login", isOn: $manager.openOnStartup)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 0) {
                // Actions Section
                MenuSection(title: "Actions", icon: "bolt") {
                    Button {
                        if manager.isMonitoring {
                            manager.stopMonitoring()
                        } else {
                            manager.startMonitoring()
                        }
                    } label: {
                        Label(manager.isMonitoring ? "Pause Capturing" : "Start Capturing", 
                              systemImage: manager.isMonitoring ? "pause.circle.fill" : "play.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button {
                        manager.clearCache()
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                    .disabled(manager.imageCount == 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 0) {
                // Quit and Buy me a coffee
                HStack {
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                    
                    Spacer()
                    
                    Button {
                        if let url = URL(string: "https://venmo.willwhitehead.com/") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("buy me a redbull")
                            .font(.system(size: 12))
                    }
                   
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
    }
}

// Helper views for better organization
struct MenuSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    let showResetButton: Bool
    let manager: ClipCacheManager?
    
    init(title: String, icon: String, showResetButton: Bool = false, manager: ClipCacheManager? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.showResetButton = showResetButton
        self.manager = manager
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with optional reset button
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                if showResetButton, let manager = manager {
                    Spacer()
                    Button {
                        manager.resetToDefaultSettings()
                    } label: {
                        Text("Reset to Default")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isAtDefaultSettings)
                    .foregroundColor(manager.isAtDefaultSettings ? .secondary.opacity(0.5) : .secondary)
                }
            }
            
            content
        }
    }
}


// Reusable component for standardized menu setting layout
struct MenuSetting<Content: View>: View {
    let label: String
    let content: Content
    let bottomPadding: CGFloat
    
    // Standardized indentation - only controls are indented
    private let controlIndent: CGFloat = 12
    
    init(_ label: String, bottomPadding: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.label = label
        self.bottomPadding = bottomPadding
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Setting label
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            // Control/content
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(.leading, controlIndent)
        }
        .padding(.bottom, bottomPadding)
    }
}

// For settings with optional help button
struct MenuSettingWithHelp<HelpContent: View, SettingContent: View>: View {
    let label: String
    let helpContent: () -> HelpContent
    let settingContent: SettingContent
    let bottomPadding: CGFloat
    
    private let controlIndent: CGFloat = 12
    
    init(_ label: String, bottomPadding: CGFloat = 4, @ViewBuilder helpContent: @escaping () -> HelpContent, @ViewBuilder settingContent: () -> SettingContent) {
        self.label = label
        self.bottomPadding = bottomPadding
        self.helpContent = helpContent
        self.settingContent = settingContent()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Setting label with help button
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                helpContent()
            }
            .padding(.bottom, 2)
            
            // Control/content
            VStack(alignment: .leading, spacing: 6) {
                settingContent
            }
            .padding(.leading, controlIndent)
        }
        .padding(.bottom, bottomPadding)
    }
}

// Reusable help button component with popover
struct HelpPopoverButton: View {
    let title: String
    let description: String
    @State private var isPresented = false
    
    var body: some View {
        Button(action: {
            isPresented.toggle()
        }) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 250)
        }
    }
}

struct CustomSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    
    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        self._value = value
        self.range = range
        self.step = step
    }
    
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.allowsTickMarkValuesOnly = false
        slider.numberOfTickMarks = 0
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        return slider
    }
    
    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.doubleValue = value
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: CustomSlider
        
        init(_ parent: CustomSlider) {
            self.parent = parent
        }
        
        @objc func valueChanged(_ sender: NSSlider) {
            let newValue = round(sender.doubleValue / parent.step) * parent.step
            parent.value = newValue
        }
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var isCapturing: Bool
    
    func makeNSView(context: Context) -> ShortcutCaptureTextField {
        let textField = ShortcutCaptureTextField()
        textField.keyCode = $keyCode
        textField.modifiers = $modifiers
        textField.isCapturing = $isCapturing
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.alignment = .center
        textField.backgroundColor = .textBackgroundColor
        return textField
    }
    
    func updateNSView(_ nsView: ShortcutCaptureTextField, context: Context) {
        nsView.keyCode = $keyCode
        nsView.modifiers = $modifiers
        nsView.isCapturing = $isCapturing
        nsView.updateDisplay()
    }
}

class ShortcutCaptureTextField: NSTextField {
    var keyCode: Binding<UInt32>?
    var modifiers: Binding<UInt32>?
    var isCapturing: Binding<Bool>?
    
    // Store original values when editing starts
    private var originalKeyCode: UInt32 = 0
    private var originalModifiers: UInt32 = 0
    
    override var acceptsFirstResponder: Bool { true }
    
    override var intrinsicContentSize: NSSize {
        let displayText = formatShortcut(keyCode: keyCode?.wrappedValue ?? 0, modifiers: modifiers?.wrappedValue ?? 0)
        let text = displayText.isEmpty ? "Click to set shortcut" : displayText
        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]
        )
        let textSize = attributedString.size()
        return NSSize(width: textSize.width*1.5, height: 22)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        updateDisplay()
    }
    
    func updateDisplay() {
        let displayText = formatShortcut(keyCode: keyCode?.wrappedValue ?? 0, modifiers: modifiers?.wrappedValue ?? 0)
        stringValue = displayText.isEmpty ? "Click to set shortcut" : displayText
        
        if isCapturing?.wrappedValue == true {
            textColor = .secondaryLabelColor
        } else {
            textColor = .labelColor
        }
        
        invalidateIntrinsicContentSize()
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        updateDisplay()
    }
    
    override func becomeFirstResponder() -> Bool {
        // Store original values when editing starts
        originalKeyCode = keyCode?.wrappedValue ?? 0
        originalModifiers = modifiers?.wrappedValue ?? 0
        isCapturing?.wrappedValue = true
        updateDisplay()
        return super.becomeFirstResponder()
    }
    
    override func resignFirstResponder() -> Bool {
        isCapturing?.wrappedValue = false
        updateDisplay()
        return super.resignFirstResponder()
    }
    
    override func keyDown(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        
        // Handle Escape key to cancel editing
        if keyCode == 0x35 { // Escape key
            // Restore original values
            self.keyCode?.wrappedValue = originalKeyCode
            self.modifiers?.wrappedValue = originalModifiers
            self.window?.makeFirstResponder(nil)
            updateDisplay()
            return
        }
        
        var modifiers: UInt32 = 0
        
        if event.modifierFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if event.modifierFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        
        // Require at least one modifier key
        if modifiers != 0 {
            self.keyCode?.wrappedValue = keyCode
            self.modifiers?.wrappedValue = modifiers
            self.window?.makeFirstResponder(nil)
            updateDisplay()
        }
    }
    
    private func formatShortcut(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined(separator: " ")
    }
    
    private func keyCodeToString(_ keyCode: UInt32) -> String {
        // Common key codes
        switch keyCode {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x24: return "Return"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x32: return "`"
        case 0x33: return "Delete"
        case 0x35: return "Esc"
        case 0x37: return "⌘"
        case 0x38: return "⇧"
        case 0x39: return "Caps Lock"
        case 0x3A: return "⌥"
        case 0x3B: return "⌃"
        case 0x3C: return "⇧"
        case 0x3D: return "⌥"
        case 0x3E: return "⌃"
        case 0x3F: return "Fn"
        case 0x40: return "F17"
        case 0x41: return "."
        case 0x43: return "*"
        case 0x45: return "+"
        case 0x47: return "Clear"
        case 0x4C: return "Enter"
        case 0x4F: return "="
        case 0x50: return "0"
        case 0x51: return "1"
        case 0x52: return "2"
        case 0x53: return "3"
        case 0x54: return "4"
        case 0x55: return "5"
        case 0x56: return "6"
        case 0x57: return "7"
        case 0x58: return "8"
        case 0x59: return "9"
        case 0x5A: return "/"
        case 0x5B: return "F1"
        case 0x5C: return "F2"
        case 0x5D: return "F3"
        case 0x5E: return "F4"
        case 0x5F: return "F5"
        case 0x60: return "F6"
        case 0x61: return "F7"
        case 0x62: return "F8"
        case 0x63: return "F9"
        case 0x64: return "F10"
        case 0x65: return "F11"
        case 0x66: return "F12"
        default: return "Key \(keyCode)"
        }
    }
}
