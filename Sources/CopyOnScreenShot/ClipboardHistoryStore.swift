import AppKit
import Foundation

extension Notification.Name {
    static let clipboardHistoryDidChange = Notification.Name("ClipboardHistoryDidChange")
}

@MainActor
final class ClipboardHistoryStore {
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var observedChangeCount: Int

    private(set) var items: [ClipboardItem] = []

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        observedChangeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        stopMonitoring()
        recordCurrentPasteboardIfNeeded()

        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordCurrentPasteboardIfNeeded()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func recordCurrentPasteboardIfNeeded() {
        guard pasteboard.changeCount != observedChangeCount else {
            return
        }

        observedChangeCount = pasteboard.changeCount
        guard let item = ClipboardItem.fromPasteboard(pasteboard) else {
            return
        }

        push(item)
    }

    func promoteAndWrite(_ item: ClipboardItem) -> Bool {
        push(item)

        let result = item.write(to: pasteboard)
        observedChangeCount = pasteboard.changeCount
        return result
    }

    private func push(_ item: ClipboardItem) {
        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)
        items = Array(items.prefix(5))

        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }
}
