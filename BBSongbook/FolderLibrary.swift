import Foundation
import Observation
import UIKit

/// One lyric sheet image found in the song folder.
struct LibraryFile: Hashable {
    /// Path relative to the library root, e.g. "สากล/เพลงหนึ่ง.jpg".
    var path: String
    /// First-level subfolder name, or "ทั่วไป" for files in the root.
    var category: String
    var title: String
}

/// Lyric sheets (.png/.jpg) inside a folder the user picks in the Files app
/// (iCloud Drive, On My iPad, Dropbox…). Without a linked folder it uses the
/// app's own Documents folder ("On My iPad › BB Songbook").
@Observable
final class FolderLibrary {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif"]
    private static let bookmarkKey = "libraryBookmark"

    private(set) var rootURL: URL = .documentsDirectory
    private(set) var isLinked = false

    var rootName: String {
        isLinked ? rootURL.lastPathComponent : "ในเครื่อง › BB Songbook"
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
           url.startAccessingSecurityScopedResource() {
            rootURL = url
            isLinked = true
            if stale, let fresh = try? url.bookmarkData() {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
        }
    }

    /// Remember a folder picked with the Files picker (kept across launches).
    func link(_ url: URL) {
        guard url.startAccessingSecurityScopedResource(),
              let bookmark = try? url.bookmarkData() else { return }
        if isLinked { rootURL.stopAccessingSecurityScopedResource() }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        rootURL = url
        isLinked = true
    }

    func unlink() {
        if isLinked { rootURL.stopAccessingSecurityScopedResource() }
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        rootURL = .documentsDirectory
        isLinked = false
    }

    /// All images under the root, or nil when the folder can't be read
    /// (so callers don't mistake a missing folder for an empty one).
    func scan() -> [LibraryFile]? {
        let fm = FileManager.default
        let root = rootURL.resolvingSymlinksInPath()
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsPackageDescendants])
        else { return nil }
        let rootDepth = root.pathComponents.count
        var files: [LibraryFile] = []
        for case let url as URL in walker {
            var name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // iCloud file not downloaded yet: ".เพลง.jpg.icloud" -> "เพลง.jpg"
                name = String(name.dropFirst().dropLast(".icloud".count))
            } else if name.hasPrefix(".") || (name == "Inbox" && url.deletingLastPathComponent().path == root.path) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    walker.skipDescendants()
                }
                continue
            }
            guard Self.imageExtensions.contains((name as NSString).pathExtension.lowercased()) else { continue }
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            let folders = Array(parent.dropFirst(rootDepth))
            files.append(LibraryFile(path: (folders + [name]).joined(separator: "/"),
                                     category: folders.joined(separator: " › "),
                                     title: (name as NSString).deletingPathExtension))
        }
        return Self.droppingWrapperFolder(files)
    }

    /// Every sheet sits in its folder path ("Event 15 › set1"). A single folder
    /// wrapping everything (e.g. "Local Files" copied from another app) is left out.
    private static func droppingWrapperFolder(_ files: [LibraryFile]) -> [LibraryFile] {
        let prefixes = Set(files.map { $0.category.components(separatedBy: " › ").first ?? "" })
        let strip = prefixes.count == 1 && !(prefixes.first ?? "").isEmpty
        return files.map { file in
            var parts = file.category.isEmpty ? [] : file.category.components(separatedBy: " › ")
            if strip { parts.removeFirst() }
            var copy = file
            copy.category = parts.isEmpty ? "ทั่วไป" : parts.joined(separator: " › ")
            return copy
        }
    }

    /// Folder that sheets sent from other apps ("Open in BB Songbook") land in.
    static let importFolder = "นำเข้า"

    /// Copies a sheet another app sent us into "<root>/นำเข้า", never overwriting.
    func importFile(_ url: URL) -> LibraryFile? {
        guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let folder = rootURL.appending(path: Self.importFolder)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let title = url.deletingPathExtension().lastPathComponent
        var dest = folder.appending(path: url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = folder.appending(path: "\(title) (\(n)).\(url.pathExtension)")
            n += 1
        }
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { source in
            copied = (try? fm.copyItem(at: source, to: dest)) != nil
        }
        guard copied else { return nil }
        return LibraryFile(path: "\(Self.importFolder)/\(dest.lastPathComponent)",
                           category: Self.importFolder,
                           title: dest.deletingPathExtension().lastPathComponent)
    }

    /// Loads a sheet, downloading it from iCloud first if needed.
    func loadImage(_ path: String) async -> UIImage? {
        let url = rootURL.appending(path: path)
        return await Task.detached(priority: .userInitiated) {
            var data: Data?
            // The coordinator waits for iCloud to download the file.
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { readURL in
                data = try? Data(contentsOf: readURL)
            }
            return data.flatMap(UIImage.init(data:))?.preparingForDisplay()
        }.value
    }
}
