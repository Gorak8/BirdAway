import AppKit
import UniformTypeIdentifiers

protocol ManageSoundsDelegate: AnyObject {
    func soundListDidChange()
}

class ManageSoundsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    weak var delegate: ManageSoundsDelegate?

    private var tableView: NSTableView!
    private var paths: [String] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Manage Sounds"
        window.center()

        self.init(window: window)

        loadPaths()
        setupUI()
    }

    private func loadPaths() {
        paths = UserDefaults.standard.stringArray(forKey: "soundFilePaths") ?? []
    }

    private func savePaths() {
        UserDefaults.standard.set(paths, forKey: "soundFilePaths")
        delegate?.soundListDidChange()
    }

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = contentView

        // Scroll View & Table View
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: 360, height: 220))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PathColumn"))
        column.title = "Sound Files"
        column.width = 340
        tableView.addTableColumn(column)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // Buttons
        let addButton = NSButton(title: "+", target: self, action: #selector(addSound))
        addButton.frame = NSRect(x: 20, y: 20, width: 40, height: 24)
        addButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(addButton)

        let removeButton = NSButton(title: "-", target: self, action: #selector(removeSound))
        removeButton.frame = NSRect(x: 70, y: 20, width: 40, height: 24)
        removeButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(removeButton)

        let upButton = NSButton(title: "↑", target: self, action: #selector(moveUp))
        upButton.frame = NSRect(x: 120, y: 20, width: 40, height: 24)
        upButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(upButton)

        let downButton = NSButton(title: "↓", target: self, action: #selector(moveDown))
        downButton.frame = NSRect(x: 170, y: 20, width: 40, height: 24)
        downButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(downButton)

        let previewButton = NSButton(title: "Preview", target: self, action: #selector(previewSound))
        previewButton.frame = NSRect(x: 220, y: 20, width: 80, height: 24)
        previewButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(previewButton)
    }

    // MARK: - Actions

    @objc private func addSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Choose sound files"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            if !paths.contains(url.path) {
                paths.append(url.path)
            }
        }

        savePaths()
        tableView.reloadData()
    }

    @objc private func removeSound() {
        let row = tableView.selectedRow
        guard row >= 0 && row < paths.count else { return }
        paths.remove(at: row)
        savePaths()
        tableView.reloadData()
    }

    @objc private func moveUp() {
        let row = tableView.selectedRow
        guard row > 0 && row < paths.count else { return }
        paths.swapAt(row, row - 1)
        savePaths()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: row - 1), byExtendingSelection: false)
    }

    @objc private func moveDown() {
        let row = tableView.selectedRow
        guard row >= 0 && row < paths.count - 1 else { return }
        paths.swapAt(row, row + 1)
        savePaths()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: row + 1), byExtendingSelection: false)
    }

    @objc private func previewSound() {
        let row = tableView.selectedRow
        guard row >= 0 && row < paths.count else { return }
        let url = URL(fileURLWithPath: paths[row])
        let player = AudioPlayer.shared
        player.setSoundFile(url)
        do {
            try player.play()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Playback failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - NSTableViewDataSource & NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return paths.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let url = URL(fileURLWithPath: paths[row])
        return url.lastPathComponent
    }
}
