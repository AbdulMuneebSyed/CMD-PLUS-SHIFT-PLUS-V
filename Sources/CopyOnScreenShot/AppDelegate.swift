import AppKit
import Foundation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let watcher = ScreenshotWatcher()
    private let historyStore = ClipboardHistoryStore()
    private let notificationManager = NotificationManager()
    private let launchAgentManager = LaunchAgentManager()
    private lazy var pasteCoordinator = PasteCoordinator(notificationManager: notificationManager)
    private let hotKeyMonitor = HotKeyMonitor()
    private let historyWindowController = ClipboardHistoryWindowController()

    private var statusItem: NSStatusItem?
    private let showHistoryItem = NSMenuItem()
    private let autoCopyItem = NSMenuItem()
    private let deleteAfterCopyItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()
    private var lastActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        setupClipboardHistory()
        setupHotKey()
        setupHistoryWindow()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenshotNotification(_:)),
            name: .screenshotWatcherDidDetectFile,
            object: nil
        )
        notificationManager.requestAuthorizationIfNeeded()
        synchronizeLaunchAtLoginRegistration()
        refreshWatcherState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        historyStore.stopMonitoring()
        hotKeyMonitor.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "CopyOnScreenShot"
        statusItem = item
    }

    private func setupMenu() {
        showHistoryItem.title = "Show Clipboard History"
        showHistoryItem.keyEquivalent = "V"
        showHistoryItem.keyEquivalentModifierMask = [.command, .shift]
        showHistoryItem.target = self
        showHistoryItem.action = #selector(showClipboardHistory)

        autoCopyItem.target = self
        autoCopyItem.action = #selector(toggleAutoCopy)

        deleteAfterCopyItem.target = self
        deleteAfterCopyItem.action = #selector(toggleDeleteAfterCopy)

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        let menu = NSMenu()
        menu.addItem(showHistoryItem)
        menu.addItem(.separator())
        menu.addItem(autoCopyItem)
        menu.addItem(deleteAfterCopyItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem?.menu = menu
        updateMenuState()
    }

    private func refreshWatcherState() {
        watcher.stop()

        guard preferences.autoCopyEnabled else {
            return
        }

        watcher.start()
    }

    private func setupClipboardHistory() {
        historyStore.startMonitoring()
    }

    private func setupHotKey() {
        hotKeyMonitor.onHotKeyPressed = { [weak self] in
            self?.showClipboardHistory()
        }
        hotKeyMonitor.start()
    }

    private func setupHistoryWindow() {
        historyWindowController.onItemChosen = { [weak self] item in
            self?.paste(item)
        }

        historyWindowController.onDismissed = { [weak self] in
            guard let self, let application = self.lastActiveApplication else {
                return
            }

            application.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func updateMenuState() {
        autoCopyItem.title = "Auto-copy Screenshots: \(preferences.autoCopyEnabled ? "On" : "Off")"
        autoCopyItem.state = preferences.autoCopyEnabled ? .on : .off

        deleteAfterCopyItem.title = "Delete After Copy: \(preferences.deleteAfterCopyEnabled ? "On" : "Off")"
        deleteAfterCopyItem.state = preferences.deleteAfterCopyEnabled ? .on : .off

        launchAtLoginItem.title = "Launch at Login: \(preferences.launchAtLoginEnabled ? "On" : "Off")"
        launchAtLoginItem.state = preferences.launchAtLoginEnabled ? .on : .off
    }

    private func menuBarImage() -> NSImage? {
        let symbolNames = ["doc.on.clipboard", "camera.viewfinder", "camera"]

        for symbolName in symbolNames {
            if let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "CopyOnScreenShot"
            ) {
                image.isTemplate = true
                return image
            }
        }

        return nil
    }

    private func scheduleCopy(for screenshotURL: URL, retriesRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.copyScreenshotIfReady(at: screenshotURL, retriesRemaining: retriesRemaining)
        }
    }

    private func copyScreenshotIfReady(at screenshotURL: URL, retriesRemaining: Int) {
        guard preferences.autoCopyEnabled else {
            return
        }

        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            return
        }

        guard let image = NSImage(contentsOf: screenshotURL) else {
            if retriesRemaining > 0 {
                scheduleCopy(for: screenshotURL, retriesRemaining: retriesRemaining - 1)
            }
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let wroteImage = pasteboard.writeObjects([image])
        if !wroteImage, let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }

        if preferences.deleteAfterCopyEnabled {
            try? FileManager.default.removeItem(at: screenshotURL)
        }

        notificationManager.postCopiedNotification()
        historyStore.recordCurrentPasteboardIfNeeded()
    }

    private func synchronizeLaunchAtLoginRegistration() {
        guard preferences.launchAtLoginEnabled else {
            return
        }

        do {
            try launchAgentManager.setEnabled(true)
        } catch {
            preferences.launchAtLoginEnabled = false
        }

        updateMenuState()
    }

    @objc
    private func handleScreenshotNotification(_ notification: Notification) {
        guard let screenshotURL = notification.object as? URL else {
            return
        }

        scheduleCopy(for: screenshotURL, retriesRemaining: 4)
    }

    @objc
    private func showClipboardHistory() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastActiveApplication = frontmost
        }

        historyWindowController.present(with: historyStore.items)
    }

    private func paste(_ item: ClipboardItem) {
        historyWindowController.close()
        pasteCoordinator.pasteSelectedItem(
            item,
            using: historyStore,
            into: lastActiveApplication
        )
    }

    @objc
    private func toggleAutoCopy() {
        preferences.autoCopyEnabled.toggle()
        updateMenuState()
        refreshWatcherState()
    }

    @objc
    private func toggleDeleteAfterCopy() {
        preferences.deleteAfterCopyEnabled.toggle()
        updateMenuState()
    }

    @objc
    private func toggleLaunchAtLogin() {
        let nextValue = !preferences.launchAtLoginEnabled

        do {
            try launchAgentManager.setEnabled(nextValue)
            preferences.launchAtLoginEnabled = nextValue
        } catch {
            preferences.launchAtLoginEnabled = false
        }

        updateMenuState()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

final class NotificationManager {
    private let center = UNUserNotificationCenter.current()
    private var hasRequestedAuthorization = false

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else {
            return
        }

        hasRequestedAuthorization = true

        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func postCopiedNotification() {
        postClipboardNotification(title: "Screenshot copied to clipboard")
    }

    func postClipboardNotification(title: String, body: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body ?? ""

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}

private final class LaunchAgentManager {
    private let fileManager: FileManager
    private let label: String

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        label = Bundle.main.bundleIdentifier ?? "com.muneeb.CopyOnScreenShot"
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgent()
        } else {
            uninstallLaunchAgent()
        }
    }

    private func installLaunchAgent() throws {
        let plistURL = launchAgentPlistURL()
        let executableURL = try executableURLForLaunchAgent()

        let plistContents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "ProcessType": "Interactive",
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "WorkingDirectory": executableURL.deletingLastPathComponent().path
        ]

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistContents,
            format: .xml,
            options: 0
        )

        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try plistData.write(to: plistURL, options: .atomic)

        refreshLaunchAgentRegistration(plistURL: plistURL)
    }

    private func uninstallLaunchAgent() {
        let plistURL = launchAgentPlistURL()
        refreshLaunchAgentRemoval(plistURL: plistURL)
        try? fileManager.removeItem(at: plistURL)
    }

    private func executableURLForLaunchAgent() throws -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
        }

        let fallback = URL(fileURLWithPath: CommandLine.arguments[0])
        guard fileManager.fileExists(atPath: fallback.path) else {
            throw LaunchAgentError.missingExecutable
        }

        return fallback
    }

    private func launchAgentPlistURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private func refreshLaunchAgentRegistration(plistURL: URL) {
        _ = runLaunchCtl(arguments: ["bootout", launchDomain(), plistURL.path], allowFailure: true)
        _ = runLaunchCtl(arguments: ["bootstrap", launchDomain(), plistURL.path], allowFailure: true)
    }

    private func refreshLaunchAgentRemoval(plistURL: URL) {
        _ = runLaunchCtl(arguments: ["bootout", launchDomain(), plistURL.path], allowFailure: true)
    }

    private func launchDomain() -> String {
        "gui/\(getuid())"
    }

    @discardableResult
    private func runLaunchCtl(arguments: [String], allowFailure: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 || allowFailure
        } catch {
            return allowFailure
        }
    }
}

private enum LaunchAgentError: Error {
    case missingExecutable
}
