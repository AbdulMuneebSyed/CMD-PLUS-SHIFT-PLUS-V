import AppKit
import Foundation

@MainActor
final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
    var onItemChosen: ((ClipboardItem) -> Void)?
    var onDismissed: (() -> Void)?

    private let tableView = ClipboardHistoryTableView()
    private let titleLabel = NSTextField(labelWithString: "Clipboard History")
    private let hintLabel = NSTextField(labelWithString: "Enter to paste, Esc to close")
    private var items: [ClipboardItem] = []

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 278),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace]

        super.init(window: panel)
        setupWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(with items: [ClipboardItem]) {
        self.items = items
        updateTableLayout()
        tableView.reloadData()
        centerWindow()

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)

        let firstRow = items.isEmpty ? -1 : 0
        if firstRow >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: firstRow), byExtendingSelection: false)
        }

        window?.makeFirstResponder(tableView)
    }

    func dismiss() {
        close()
        onDismissed?()
    }

    private func setupWindow() {
        guard let window else {
            return
        }

        window.delegate = self

        let contentView = NSView(frame: window.contentLayoutRect)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 14

        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = .secondaryLabelColor

        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 56
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.selectionHighlightStyle = .regular
        tableView.frame = NSRect(x: 0, y: 0, width: 388, height: 200)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.action = #selector(handleRowClick)
        tableView.target = self
        tableView.onCommitSelection = { [weak self] in
            self?.commitSelectedRow()
        }
        tableView.onCancel = { [weak self] in
            self?.dismiss()
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = tableView

        let stackView = NSStackView(views: [titleLabel, hintLabel, scrollView])
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            scrollView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }

    func windowWillClose(_ notification: Notification) {
        onDismissed?()
    }

    private func updateTableLayout() {
        let contentHeight = max(200, CGFloat(items.count) * (tableView.rowHeight + tableView.intercellSpacing.height))
        tableView.frame = NSRect(x: 0, y: 0, width: 388, height: contentHeight)

        if let column = tableView.tableColumns.first {
            column.width = 388
        }
    }

    private func centerWindow() {
        guard let window, let screen = NSScreen.main ?? NSApp.mainWindow?.screen else {
            return
        }

        let frame = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - (size.width / 2),
            y: frame.midY - (size.height / 2)
        )
        window.setFrameOrigin(origin)
    }

    @objc
    private func handleRowClick() {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0, clickedRow < items.count else {
            return
        }

        onItemChosen?(items[clickedRow])
    }

    private func commitSelectedRow() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            return
        }

        onItemChosen?(items[selectedRow])
    }
}

extension ClipboardHistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("clipboard-cell")
        let item = items[row]

        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? ClipboardHistoryCellView)
            ?? ClipboardHistoryCellView(frame: .zero)
        cell.identifier = identifier
        cell.configure(with: item, rowNumber: row + 1)
        return cell
    }
}

private final class ClipboardHistoryTableView: NSTableView {
    var onCommitSelection: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommitSelection?()

        case 53:
            onCancel?()

        default:
            super.keyDown(with: event)
        }
    }
}

private final class ClipboardHistoryCellView: NSTableCellView {
    private let thumbnailView = NSImageView(frame: .zero)
    private let rowBadge = NSTextField(labelWithString: "")
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: ClipboardItem, rowNumber: Int) {
        rowBadge.stringValue = "\(rowNumber)"
        titleField.stringValue = item.title
        subtitleField.stringValue = item.subtitle

        if case .image = item.content {
            thumbnailView.imageScaling = .scaleProportionallyUpOrDown
            thumbnailView.image = item.previewImage
        } else {
            thumbnailView.imageScaling = .scaleNone
            thumbnailView.image = item.previewImage
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        rowBadge.translatesAutoresizingMaskIntoConstraints = false
        rowBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        rowBadge.textColor = .secondaryLabelColor

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail

        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.orientation = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rowBadge)
        addSubview(thumbnailView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            rowBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rowBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            thumbnailView.leadingAnchor.constraint(equalTo: rowBadge.trailingAnchor, constant: 12),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 36),
            thumbnailView.heightAnchor.constraint(equalToConstant: 36),

            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
