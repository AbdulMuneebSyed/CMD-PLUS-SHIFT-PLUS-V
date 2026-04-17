import AppKit
import CryptoKit
import Foundation

struct ClipboardItem: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case image(Data)
    }

    let id = UUID()
    let content: Content
    let fingerprint: String
    let capturedAt: Date

    init(content: Content, fingerprint: String, capturedAt: Date = Date()) {
        self.content = content
        self.fingerprint = fingerprint
        self.capturedAt = capturedAt
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardItem? {
        if let imageData = pasteboard.data(forType: .png) {
            return ClipboardItem(content: .image(imageData), fingerprint: digest(for: imageData))
        }

        if let imageData = pasteboard.data(forType: .tiff) {
            return ClipboardItem(content: .image(imageData), fingerprint: digest(for: imageData))
        }

        if let stringValue = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .newlines), !stringValue.isEmpty {
            let data = Data(stringValue.utf8)
            return ClipboardItem(content: .text(stringValue), fingerprint: digest(for: data))
        }

        return nil
    }

    var title: String {
        switch content {
        case let .text(value):
            return value
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(56)
                .description
                .nonEmpty ?? "Text"

        case let .image(data):
            let dimensions = imageSizeDescription(from: data)
            return dimensions.map { "Image \($0)" } ?? "Image"
        }
    }

    var subtitle: String {
        switch content {
        case let .text(value):
            let collapsed = value
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if collapsed.count <= 56 {
                return "Text"
            }

            let index = collapsed.index(collapsed.startIndex, offsetBy: 56)
            return String(collapsed[index...]).prefix(64).description

        case .image:
            return "Clipboard image"
        }
    }

    var previewImage: NSImage? {
        switch content {
        case .text:
            return NSImage(
                systemSymbolName: "text.alignleft",
                accessibilityDescription: "Text clipboard item"
            )

        case let .image(data):
            return NSImage(data: data)
        }
    }

    func write(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()

        switch content {
        case let .text(value):
            return pasteboard.setString(value, forType: .string)

        case let .image(data):
            if let image = NSImage(data: data) {
                if pasteboard.writeObjects([image]) {
                    return true
                }
            }

            if pasteboard.setData(data, forType: .png) {
                return true
            }

            return pasteboard.setData(data, forType: .tiff)
        }
    }

    private static func digest(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func imageSizeDescription(from data: Data) -> String? {
        guard let image = NSImage(data: data) else {
            return nil
        }

        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard width > 0, height > 0 else {
            return nil
        }

        return "\(width)x\(height)"
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
