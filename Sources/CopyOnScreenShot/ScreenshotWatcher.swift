import Foundation
import Darwin

final class ScreenshotWatcher {
    private let fileManager: FileManager
    private let watchQueue = DispatchQueue(label: "CopyOnScreenShot.watch", qos: .utility)
    private var watchers: [DirectoryWatcher] = []
    private var seenPaths: Set<String> = []
    private let matcher = ScreenshotNameMatcher()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func start() {
        stop()

        let directories = ScreenshotLocationResolver.directoriesToWatch(fileManager: fileManager)
        seedSeenPaths(for: directories)

        watchers = directories.compactMap { directory in
            DirectoryWatcher(directoryURL: directory, queue: watchQueue) { [weak self] changedDirectory in
                self?.scanDirectory(changedDirectory)
            }
        }

        watchers.forEach { $0.start() }
    }

    func stop() {
        watchers.forEach { $0.stop() }
        watchers.removeAll()
        seenPaths.removeAll()
    }

    private func seedSeenPaths(for directories: [URL]) {
        seenPaths = Set(directories.flatMap { directory in
            screenshotFiles(in: directory).map(\.path)
        })
    }

    private func scanDirectory(_ directory: URL) {
        let discoveredScreenshots = screenshotFiles(in: directory).sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        for screenshotURL in discoveredScreenshots where !seenPaths.contains(screenshotURL.path) {
            seenPaths.insert(screenshotURL.path)

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .screenshotWatcherDidDetectFile,
                    object: screenshotURL
                )
            }
        }
    }

    private func screenshotFiles(in directory: URL) -> [URL] {
        guard let enumerated = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerated.filter { url in
            guard
                let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                resourceValues.isRegularFile == true
            else {
                return false
            }

            return matcher.matches(url.lastPathComponent)
        }
    }
}

extension Notification.Name {
    static let screenshotWatcherDidDetectFile = Notification.Name("ScreenshotWatcherDidDetectFile")
}

private final class DirectoryWatcher {
    private let directoryURL: URL
    private let fileDescriptor: CInt
    private let source: DispatchSourceFileSystemObject
    private var hasResumed = false
    private var hasStopped = false

    init?(
        directoryURL: URL,
        queue: DispatchQueue,
        onChange: @escaping (URL) -> Void
    ) {
        self.directoryURL = directoryURL

        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return nil
        }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        fileDescriptor = descriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )

        source.setEventHandler { [directoryURL] in
            onChange(directoryURL)
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
    }

    func start() {
        guard !hasResumed else {
            return
        }

        hasResumed = true
        source.resume()
    }

    func stop() {
        guard !hasStopped else {
            return
        }

        hasStopped = true

        if !hasResumed {
            hasResumed = true
            source.resume()
        }

        source.cancel()
    }

    deinit {
        stop()
    }
}

private struct ScreenshotLocationResolver {
    static func directoriesToWatch(fileManager: FileManager) -> [URL] {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let defaultDesktop = homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        let defaultScreenshots = homeDirectory.appendingPathComponent("Pictures/Screenshots", isDirectory: true)

        let candidates = [
            defaultDesktop,
            defaultScreenshots,
            configuredScreenshotDirectory()
        ].compactMap { $0 }

        var uniquePaths: Set<String> = []
        var result: [URL] = []

        for candidate in candidates {
            let normalized = candidate.standardizedFileURL.resolvingSymlinksInPath()

            if uniquePaths.insert(normalized.path).inserted {
                result.append(normalized)
            }
        }

        return result
    }

    private static func configuredScreenshotDirectory() -> URL? {
        let domain = "com.apple.screencapture" as CFString
        let key = "location" as CFString

        CFPreferencesAppSynchronize(domain)

        guard let rawPath = CFPreferencesCopyAppValue(key, domain) as? String else {
            return nil
        }

        let expandedPath = (rawPath as NSString).expandingTildeInPath
        guard !expandedPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: expandedPath, isDirectory: true)
    }
}

private struct ScreenshotNameMatcher {
    private let expression = try? NSRegularExpression(
        pattern: #"^(Screenshot|Screen Shot) \d{4}-\d{2}-\d{2} at .+\.(png|jpe?g|tiff?|heic)$"#,
        options: [.caseInsensitive]
    )

    func matches(_ fileName: String) -> Bool {
        guard let expression else {
            return false
        }

        let range = NSRange(location: 0, length: fileName.utf16.count)
        return expression.firstMatch(in: fileName, options: [], range: range) != nil
    }
}
