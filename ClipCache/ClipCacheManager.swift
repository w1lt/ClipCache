import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import Carbon
import ApplicationServices
import ServiceManagement
internal import Combine

@MainActor
class ClipCacheManager: ObservableObject {
    @Published var isMonitoring = false
    @Published var imageCount = 0
    @Published var lastCaptureDate: Date? = nil
    @Published var copyWindowSeconds: Double = 30.0
    @Published var pasteShortcutKey: UInt32 = 0x07
    @Published var pasteShortcutModifiers: UInt32 = 0x0300
    @Published var clearCacheShortcutKey: UInt32 = 0x2F // Period (.) key
    @Published var clearCacheShortcutModifiers: UInt32 = 0x0300 // Cmd+Shift
    @Published var removeLastItemShortcutKey: UInt32 = 0x2B // Comma (,) key
    @Published var removeLastItemShortcutModifiers: UInt32 = 0x0300 // Cmd+Shift
    @Published var menuBarTitle: String = ""
    @Published var showImageCountInMenuBar: Bool = true
    @Published var showTimerInMenuBar: Bool = true
    @Published var captureFilesAndImages: Bool = true
    @Published var captureText: Bool = true
    @Published var openOnStartup: Bool = true {
        didSet {
            if !isInitializing {
                updateLoginItem()
            }
        }
    }
    @Published var pasteCooldownMs: Double = 200.0
    
    private var isInitializing = true
    private var isMovingToApplications = false
    
    private var clipboardCache: [NSImage] = []
    private var textCache: [String] = []
    private var fileCache: [URL] = []
    private var pasteboardChangeCount: Int = NSPasteboard.general.changeCount
    private var monitorTimer: Timer?
    private var titleUpdateTimer: Timer?
    private var permissionCheckTimer: Timer?
    private var firstCaptureDate: Date? = nil
    private var copyWindowEndDate: Date? = nil
    private var eventTap: CFMachPort?
    private var eventTapDataPtr: UnsafeMutableRawPointer?
    private var lastPastedImageHash: Int? = nil // Track last image we pasted to ignore it
    private var lastPastedText: String? = nil // Track last text we pasted to ignore it
    private var lastPastedFileURL: URL? = nil // Track last file we pasted to ignore it
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        clipboardCache.removeAll()
        textCache.removeAll()
        fileCache.removeAll()
        imageCount = 0
        lastCaptureDate = nil
        firstCaptureDate = nil
        copyWindowEndDate = nil
        pasteboardChangeCount = NSPasteboard.general.changeCount
        
        startClipboardTimer()
        startTitleUpdateTimer()
        registerHotKey()
        updateMenuBarTitle()
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.invalidate()
        titleUpdateTimer?.invalidate()
        permissionCheckTimer?.invalidate()
        monitorTimer = nil
        titleUpdateTimer = nil
        permissionCheckTimer = nil
        menuBarTitle = ""
        unregisterHotKey()
    }
    
    func clearCache() {
        clipboardCache.removeAll()
        textCache.removeAll()
        fileCache.removeAll()
        imageCount = 0
        lastCaptureDate = nil
        firstCaptureDate = nil
        copyWindowEndDate = nil
    }
    
    func removeLastItem() {
        // Remove from the most recently added cache
        if !fileCache.isEmpty {
            fileCache.removeLast()
        } else if !textCache.isEmpty {
            textCache.removeLast()
        } else if !clipboardCache.isEmpty {
            clipboardCache.removeLast()
        }
        
        // Update count
        imageCount = clipboardCache.count + textCache.count + fileCache.count
        
        // If cache is empty, reset window
        if imageCount == 0 {
            firstCaptureDate = nil
            copyWindowEndDate = nil
            lastCaptureDate = nil
        }
        
        updateMenuBarTitle()
    }
    
    // Default values
    private let defaultCopyWindowSeconds: Double = 30.0
    private let defaultPasteShortcutKey: UInt32 = 0x07 // X key
    private let defaultPasteShortcutModifiers: UInt32 = 0x0300 // Cmd+Shift
    private let defaultClearCacheShortcutKey: UInt32 = 0x2F // Period (.) key
    private let defaultClearCacheShortcutModifiers: UInt32 = 0x0300 // Cmd+Shift
    private let defaultRemoveLastItemShortcutKey: UInt32 = 0x2B // Comma (,) key
    private let defaultRemoveLastItemShortcutModifiers: UInt32 = 0x0300 // Cmd+Shift
    private let defaultShowImageCountInMenuBar: Bool = true
    private let defaultShowTimerInMenuBar: Bool = true
    private let defaultCaptureFilesAndImages: Bool = true
    private let defaultCaptureText: Bool = true
    private let defaultOpenOnStartup: Bool = true
    private let defaultPasteCooldownMs: Double = 200.0
    
    private let hasShownFirstRunPermissionPromptKey = "hasShownFirstRunPermissionPrompt"
    private let hasShownMoveToApplicationsPromptKey = "hasShownMoveToApplicationsPrompt"
    
    init() {
        // Check if we have a stored preference
        if UserDefaults.standard.object(forKey: "isLoginItemEnabled") != nil {
            // Use stored preference
            openOnStartup = UserDefaults.standard.bool(forKey: "isLoginItemEnabled")
        } else {
            // First run - default to true
            openOnStartup = defaultOpenOnStartup
            UserDefaults.standard.set(defaultOpenOnStartup, forKey: "isLoginItemEnabled")
        }
        
        isInitializing = false
        
        // Sync with system on initialization
        // This ensures the system state matches our preference
        if openOnStartup {
            updateLoginItem()
        }
        
        // Start the startup flow
        // Use a small delay to ensure all initialization is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.handleStartupFlow()
        }
    }
    
    func handleStartupFlow() {
        // Don't proceed if we're in the process of moving
        guard !isMovingToApplications else {
            return
        }
        
        // 1. Ensure app is in Applications folder first
        if !isInApplicationsFolder() {
            checkAndPromptToMoveToApplicationsIfNeeded()
            return
        }

        // 2. Request the macOS native accessibility prompt
        requestAccessibilityIfNeeded()

        // 3. Start monitoring if permissions are already granted
        // Otherwise, the permission check timer will start monitoring when permissions are granted
        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startMonitoring()
            }
        }
    }
    
    func checkAndPromptForPermissionsIfNeeded() {
        // Check if accessibility permissions are granted
        let hasPermissions = AXIsProcessTrusted()
        
        if hasPermissions {
            // Permissions granted, stop any permission checking timer
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            return
        }
        
        // Start periodic check for permissions (in case user grants them without restarting)
        // The native prompt was already shown by requestAccessibilityIfNeeded()
        startPermissionCheckTimer()
    }
    
    private func startPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Check if permissions are now granted
                if AXIsProcessTrusted() {
                    // Permissions granted! Stop checking and start monitoring
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    
                    // Start monitoring if not already started
                    if !self.isMonitoring {
                        self.startMonitoring()
                    }
                }
            }
        }
        
        RunLoop.main.add(permissionCheckTimer!, forMode: .common)
    }
    
    func checkAndPromptToMoveToApplicationsIfNeeded() {
        // Check if we've already shown this prompt before
        let hasShownPrompt = UserDefaults.standard.bool(forKey: hasShownMoveToApplicationsPromptKey)
        if hasShownPrompt {
            return
        }
        
        // Check if already in Applications folder
        if isInApplicationsFolder() {
            return
        }
        
        // Activate the app to ensure alerts can be shown
        NSApp.activate(ignoringOtherApps: true)
        
        // Add a small delay to ensure the app is fully activated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.askToMoveToApplications { shouldMove in
                // Mark that we've shown the prompt (regardless of which option they chose)
                UserDefaults.standard.set(true, forKey: self.hasShownMoveToApplicationsPromptKey)
                
                if shouldMove {
                    self.moveToApplicationsAndRelaunch()
                }
            }
        }
    }
    
    private func isInApplicationsFolder() -> Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.hasPrefix("/Applications")
    }
    private func requestAccessibilityIfNeeded() {
    let hasPermissions = AXIsProcessTrusted()
    if hasPermissions {
            // Permissions granted, stop any permission checking timer
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            return
        }
        // Start periodic check for permissions (in case user grants them without restarting)
        startPermissionCheckTimer()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    
    private func askToMoveToApplications(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "This app works best when placed in the Applications folder. ClipCache will reopen from Applications after moving."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        completion(response == .alertFirstButtonReturn)
    }
    
    private func moveToApplicationsAndRelaunch() {
        isMovingToApplications = true
        
        let appPath = Bundle.main.bundlePath
        let appName = (appPath as NSString).lastPathComponent
        let destPath = "/Applications/\(appName)"
        
        // Write a self-move + relaunch script
        let script = """
        #!/bin/bash
        sleep 0.5
        rm -rf "\(destPath)"
        mv "\(appPath)" "\(destPath)"
        open "\(destPath)"
        """
        
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("move_and_launch.sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        chmod(scriptURL.path, 0o755)
        
        // Run script detached
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [scriptURL.path]
        try? task.run()
        
        // Quit so the script can move us
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    
    
    private func openAccessibilitySettings() {
        // Open System Settings/Preferences to Accessibility page
        if #available(macOS 13.0, *) {
            // macOS 13+ uses new Settings app - open directly to Privacy & Security > Accessibility
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // macOS 12 and earlier use System Preferences
            // Use AppleScript to open System Preferences to Accessibility pane
            let script = """
                tell application "System Preferences"
                    activate
                    set current pane to pane id "com.apple.preference.security"
                    reveal anchor "Privacy_Accessibility" of pane id "com.apple.preference.security"
                end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        }
    }
    
    var isAtDefaultSettings: Bool {
        return copyWindowSeconds == defaultCopyWindowSeconds &&
               pasteShortcutKey == defaultPasteShortcutKey &&
               pasteShortcutModifiers == defaultPasteShortcutModifiers &&
               clearCacheShortcutKey == defaultClearCacheShortcutKey &&
               clearCacheShortcutModifiers == defaultClearCacheShortcutModifiers &&
               removeLastItemShortcutKey == defaultRemoveLastItemShortcutKey &&
               removeLastItemShortcutModifiers == defaultRemoveLastItemShortcutModifiers &&
               showImageCountInMenuBar == defaultShowImageCountInMenuBar &&
               showTimerInMenuBar == defaultShowTimerInMenuBar &&
               captureFilesAndImages == defaultCaptureFilesAndImages &&
               captureText == defaultCaptureText &&
               openOnStartup == defaultOpenOnStartup &&
               pasteCooldownMs == defaultPasteCooldownMs
    }
    
    func resetToDefaultSettings() {
        copyWindowSeconds = defaultCopyWindowSeconds
        pasteShortcutKey = defaultPasteShortcutKey
        pasteShortcutModifiers = defaultPasteShortcutModifiers
        clearCacheShortcutKey = defaultClearCacheShortcutKey
        clearCacheShortcutModifiers = defaultClearCacheShortcutModifiers
        removeLastItemShortcutKey = defaultRemoveLastItemShortcutKey
        removeLastItemShortcutModifiers = defaultRemoveLastItemShortcutModifiers
        showImageCountInMenuBar = defaultShowImageCountInMenuBar
        showTimerInMenuBar = defaultShowTimerInMenuBar
        captureFilesAndImages = defaultCaptureFilesAndImages
        captureText = defaultCaptureText
        openOnStartup = defaultOpenOnStartup
        pasteCooldownMs = defaultPasteCooldownMs
        
        updateHotKey()
        updateMenuBarTitle()
    }
    
    // Login Items management using modern ServiceManagement framework
    private func isInLoginItems() -> Bool {
        if #available(macOS 13.0, *) {
            // Use modern SMAppService API for macOS 13+
            let status = SMAppService.mainApp.status
            return status == .enabled
        } else {
            // For older macOS versions, check UserDefaults (fallback)
            return UserDefaults.standard.bool(forKey: "isLoginItemEnabled")
        }
    }
    
    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            // Use SMAppService API for macOS 13+
            do {
                if openOnStartup {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                // Track the state in UserDefaults as a backup
                UserDefaults.standard.set(openOnStartup, forKey: "isLoginItemEnabled")
            } catch {
                // If registration fails, it might be due to signing or permissions
                print("Failed to update login item: \(error.localizedDescription)")
                // Still save the preference so the UI reflects the user's choice
                UserDefaults.standard.set(openOnStartup, forKey: "isLoginItemEnabled")
            }
        } else {
            // Fallback for macOS 12 and earlier - would need helper app approach
            // For now, just track the preference
            UserDefaults.standard.set(openOnStartup, forKey: "isLoginItemEnabled")
        }
    }
    
    func batchPasteGroup() {
        guard !clipboardCache.isEmpty || !textCache.isEmpty || !fileCache.isEmpty else { return }
        
        // Paste images first
        for image in clipboardCache {
            // Store hash of image we're about to paste
            let imageHash = image.tiffRepresentation?.hashValue ?? 0
            lastPastedImageHash = imageHash
            
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            // Update change count immediately so we don't detect our own pasteboard changes
            pasteboardChangeCount = NSPasteboard.general.changeCount
            sendCmdV()
            // Convert milliseconds to microseconds for usleep
            usleep(UInt32(pasteCooldownMs * 1000))
        }
        
        // Paste text items
        for text in textCache {
            lastPastedText = text
            
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            // Update change count immediately so we don't detect our own pasteboard changes
            pasteboardChangeCount = NSPasteboard.general.changeCount
            sendCmdV()
            // Convert milliseconds to microseconds for usleep
            usleep(UInt32(pasteCooldownMs * 1000))
        }
        
        // Paste files
        for fileURL in fileCache {
            lastPastedFileURL = fileURL
            
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([fileURL as NSURL])
            // Update change count immediately so we don't detect our own pasteboard changes
            pasteboardChangeCount = NSPasteboard.general.changeCount
            sendCmdV()
            // Convert milliseconds to microseconds for usleep
            usleep(UInt32(pasteCooldownMs * 1000))
        }
        
        // Clear the tracking after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.lastPastedImageHash = nil
            self.lastPastedText = nil
            self.lastPastedFileURL = nil
        }
    }
    
    private func startClipboardTimer() {
        monitorTimer?.invalidate()

        // Capture the MainActor-isolated self *outside* of the concurrent closure
        let manager = self

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                manager.checkPasteboard()
            }
        }

        RunLoop.main.add(monitorTimer!, forMode: .common)
    }

    
    private func checkPasteboard() {
        guard isMonitoring else { return }
        
        let pb = NSPasteboard.general
        guard pb.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pb.changeCount
        
        let now = Date()
        var hasNewContent = false
        
        // Check for files and images if enabled
        // First check if there are file URLs - if so, we'll handle them as files
        // Otherwise, check for image data (screenshots, copied image content)
        var hasFileURLs = false
        if captureFilesAndImages {
            if let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               !fileURLs.isEmpty {
                let validFileURLs = fileURLs.filter { url in
                    url.isFileURL && FileManager.default.fileExists(atPath: url.path)
                }
                hasFileURLs = !validFileURLs.isEmpty
            }
        }
        
        // Only treat as image data if there are no file URLs (to differentiate image data from image files)
        if captureFilesAndImages && !hasFileURLs {
            if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
               !images.isEmpty {
                // Check if this is an image we just pasted (ignore it)
                if let firstImage = images.first,
                   let imageHash = firstImage.tiffRepresentation?.hashValue,
                   imageHash == lastPastedImageHash {
                    // This is our own paste, skip images but continue to check text
                } else {
                    hasNewContent = true
                    
                    // Check if we're starting a new batch (empty cache)
                    if clipboardCache.isEmpty && textCache.isEmpty && fileCache.isEmpty {
                        // Starting fresh - start new batch
                        firstCaptureDate = now
                        copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                    } else if let windowEnd = copyWindowEndDate, now <= windowEnd {
                        // Still within copy window - extend the window
                        copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                    } else {
                        // Copy window closed - new copy resets everything
                        clipboardCache.removeAll()
                        textCache.removeAll()
                        fileCache.removeAll()
                        firstCaptureDate = now
                        copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                    }
                    
                    // Add the new images
                    clipboardCache.append(contentsOf: images)
                    imageCount = clipboardCache.count + textCache.count + fileCache.count
                    lastCaptureDate = now
                }
            }
        }
        
        // Check for text if enabled
        if captureText {
            if let strings = pb.readObjects(forClasses: [NSString.self], options: nil) as? [String],
               !strings.isEmpty,
               let text = strings.first,
               !text.isEmpty {
                // Check if this is text we just pasted (ignore it)
                if text == lastPastedText {
                    // This is our own paste, skip it
                } else {
                    // Only process if we didn't already process images (to avoid double-processing)
                    if !hasNewContent {
                        hasNewContent = true
                        
                        // Check if we're starting a new batch (empty cache)
                        if clipboardCache.isEmpty && textCache.isEmpty && fileCache.isEmpty {
                            // Starting fresh - start new batch
                            firstCaptureDate = now
                            copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                        } else if let windowEnd = copyWindowEndDate, now <= windowEnd {
                            // Still within copy window - extend the window
                            copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                        } else {
                            // Copy window closed - new copy resets everything
                            clipboardCache.removeAll()
                            textCache.removeAll()
                            fileCache.removeAll()
                            firstCaptureDate = now
                            copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                        }
                    }
                    
                    // Add the new text (avoid duplicates)
                    if !textCache.contains(text) {
                        textCache.append(text)
                    }
                    imageCount = clipboardCache.count + textCache.count + fileCache.count
                    lastCaptureDate = now
                }
            }
        }
        
        // Check for files if enabled
        if captureFilesAndImages {
            if let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               !fileURLs.isEmpty {
                // Filter to only file URLs (not web URLs)
                let validFileURLs = fileURLs.filter { url in
                    url.isFileURL && FileManager.default.fileExists(atPath: url.path)
                }
                
                if !validFileURLs.isEmpty {
                    // Check if this is a file we just pasted (ignore it)
                    if let firstFileURL = validFileURLs.first,
                       let lastPasted = lastPastedFileURL,
                       firstFileURL == lastPasted {
                        // This is our own paste, skip it
                    } else {
                        // Only process if we didn't already process images or text (to avoid double-processing)
                        if !hasNewContent {
                            hasNewContent = true
                            
                            // Check if we're starting a new batch (empty cache)
                            if clipboardCache.isEmpty && textCache.isEmpty && fileCache.isEmpty {
                                // Starting fresh - start new batch
                                firstCaptureDate = now
                                copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                            } else if let windowEnd = copyWindowEndDate, now <= windowEnd {
                                // Still within copy window - extend the window
                                copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                            } else {
                                // Copy window closed - new copy resets everything
                                clipboardCache.removeAll()
                                textCache.removeAll()
                                fileCache.removeAll()
                                firstCaptureDate = now
                                copyWindowEndDate = now.addingTimeInterval(copyWindowSeconds)
                            }
                        }
                        
                        // Add the new files (avoid duplicates)
                        for fileURL in validFileURLs {
                            if !fileCache.contains(fileURL) {
                                fileCache.append(fileURL)
                            }
                        }
                        imageCount = clipboardCache.count + textCache.count + fileCache.count
                        lastCaptureDate = now
                    }
                }
            }
        }
        
        if hasNewContent {
            updateMenuBarTitle()
        }
    }
    
    private func startTitleUpdateTimer() {
        titleUpdateTimer?.invalidate()
        
        let manager = self
        
        titleUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                manager.updateMenuBarTitle()
            }
        }
        
        RunLoop.main.add(titleUpdateTimer!, forMode: .common)
    }
    
    func updateMenuBarTitle() {
        guard isMonitoring else {
            menuBarTitle = ""
            return
        }
        
        let now = Date()
        var titleParts: [String] = []
        
        // Add image count if enabled
        if showImageCountInMenuBar && imageCount > 0 {
            titleParts.append("\(imageCount)")
        }
        
        // Add countdown if enabled and within copy window
        if showTimerInMenuBar, let windowEnd = copyWindowEndDate, now <= windowEnd {
            let remaining = max(0, Int(windowEnd.timeIntervalSince(now)))
            titleParts.append("\(remaining)s")
        }
        
        if titleParts.isEmpty {
            menuBarTitle = ""
        } else {
            menuBarTitle = titleParts.joined(separator: " • ")
        }
    }
    
    
    func updateHotKey() {
        if isMonitoring {
            unregisterHotKey()
            registerHotKey()
        }
    }
    
    private func registerHotKey() {
        unregisterHotKey()
        setupCGEventTap()
    }
    
    private func setupCGEventTap() {
        // Check if accessibility permissions are granted (required for global monitoring)
        let trusted = AXIsProcessTrusted()
        if !trusted {
            // Request accessibility permissions
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            // Note: User needs to grant permission in System Settings > Privacy & Security > Accessibility
        }
        
        // Use CGEventTap for more reliable global hotkey detection
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        // Create a class to hold the data we need in the callback (must be a class, not struct, for AnyObject)
        class EventTapData {
            let manager: ClipCacheManager
            
            init(manager: ClipCacheManager) {
                self.manager = manager
            }
        }
        
        let tapData = EventTapData(manager: self)
        eventTapDataPtr = Unmanaged.passRetained(tapData).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }
                
                let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                // Get the tap data from refcon
                guard let dataPtr = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                
                let tapData = Unmanaged<AnyObject>.fromOpaque(dataPtr).takeUnretainedValue() as! EventTapData
                let manager = tapData.manager
                
                // Convert CGEventFlags to Carbon modifiers
                var eventModifiers: UInt32 = 0
                if flags.contains(.maskCommand) {
                    eventModifiers |= UInt32(cmdKey)
                }
                if flags.contains(.maskShift) {
                    eventModifiers |= UInt32(shiftKey)
                }
                if flags.contains(.maskAlternate) {
                    eventModifiers |= UInt32(optionKey)
                }
                if flags.contains(.maskControl) {
                    eventModifiers |= UInt32(controlKey)
                }
                
                // Check if this matches paste shortcut
                if UInt32(eventKeyCode) == manager.pasteShortcutKey && eventModifiers == manager.pasteShortcutModifiers {
                    // Check if monitoring is active (this is safe to access from callback)
                    if manager.isMonitoring {
                        Task { @MainActor in
                            manager.batchPasteGroup()
                        }
                        // Consume the event so it doesn't reach other apps
                        return nil
                    }
                }
                
                // Check if this matches clear cache shortcut
                if UInt32(eventKeyCode) == manager.clearCacheShortcutKey && eventModifiers == manager.clearCacheShortcutModifiers {
                    Task { @MainActor in
                        manager.clearCache()
                    }
                    // Consume the event so it doesn't reach other apps
                    return nil
                }
                
                // Check if this matches remove last item shortcut
                if UInt32(eventKeyCode) == manager.removeLastItemShortcutKey && eventModifiers == manager.removeLastItemShortcutModifiers {
                    Task { @MainActor in
                        manager.removeLastItem()
                    }
                    // Consume the event so it doesn't reach other apps
                    return nil
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: eventTapDataPtr
        )
        
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    private func unregisterHotKey() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        // Clean up the retained tap data
        if let dataPtr = eventTapDataPtr {
            Unmanaged<AnyObject>.fromOpaque(dataPtr).release()
            eventTapDataPtr = nil
        }
    }
    
    private func sendCmdV() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        
        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

// Global event handler setup - using CGEventTap for hotkey detection
func setupGlobalHotKeyHandler(manager: ClipCacheManager) {
    // The hotkey will be registered when monitoring starts via registerHotKey()
    // which uses CGEventTap (CoreGraphics) for reliable global hotkey detection
}
