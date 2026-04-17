import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteCoordinator {
    private let notificationManager: NotificationManager

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    func pasteSelectedItem(
        _ item: ClipboardItem,
        using historyStore: ClipboardHistoryStore,
        into targetApplication: NSRunningApplication?
    ) {
        guard historyStore.promoteAndWrite(item) else {
            notificationManager.postClipboardNotification(title: "Could not copy clipboard item")
            return
        }

        guard let targetApplication else {
            notificationManager.postClipboardNotification(title: "Copied to clipboard")
            return
        }

        guard requestAccessibilityIfNeeded() else {
            notificationManager.postClipboardNotification(
                title: "Copied to clipboard",
                body: "Enable Accessibility for automatic paste."
            )
            return
        }

        targetApplication.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [self, notificationManager] in
            guard self.sendPasteKeystroke() else {
                notificationManager.postClipboardNotification(
                    title: "Copied to clipboard",
                    body: "Automatic paste was blocked by macOS."
                )
                return
            }
        }
    }

    private func requestAccessibilityIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func sendPasteKeystroke() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand

        guard let keyDown, let keyUp else {
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
