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
    /// The single folder wrapping every sheet ("Local Files"), left out of categories.
    /// New sheets go inside it so they don't add a second top-level folder.
    private(set) var wrapperFolder: String?

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
        let (sheets, wrapper) = Self.droppingWrapperFolder(files)
        wrapperFolder = wrapper
        return sheets
    }

    /// Every sheet sits in its folder path ("Event 15 › set1"). A single folder
    /// wrapping everything (e.g. "Local Files" copied from another app) is left out.
    private static func droppingWrapperFolder(_ files: [LibraryFile]) -> ([LibraryFile], String?) {
        let prefixes = Set(files.map { $0.category.components(separatedBy: " › ").first ?? "" })
        let strip = prefixes.count == 1 && !(prefixes.first ?? "").isEmpty
        let sheets = files.map { file in
            var parts = file.category.isEmpty ? [] : file.category.components(separatedBy: " › ")
            if strip { parts.removeFirst() }
            var copy = file
            copy.category = parts.isEmpty ? "ทั่วไป" : parts.joined(separator: " › ")
            return copy
        }
        return (sheets, strip ? prefixes.first : nil)
    }

    /// Folder that sheets sent from other apps ("Open in BB Songbook") land in.
    static let importFolder = "นำเข้า"

    /// Copies a sheet (from another app or the Files picker) into the category's
    /// folder, "นำเข้า" by default, never overwriting.
    func importFile(_ url: URL, into category: String = importFolder) -> LibraryFile? {
        guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dest = freeDestination(name: url.deletingPathExtension().lastPathComponent,
                                   ext: url.pathExtension, category: category)
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { source in
            copied = (try? FileManager.default.copyItem(at: source, to: dest)) != nil
        }
        return copied ? libraryFile(at: dest, category: category) : nil
    }

    /// Saves image data (e.g. from the Photos library) as a new sheet.
    func importImage(_ data: Data, name: String, ext: String, into category: String) -> LibraryFile? {
        let dest = freeDestination(name: name, ext: ext, category: category)
        guard (try? data.write(to: dest)) != nil else { return nil }
        return libraryFile(at: dest, category: category)
    }

    /// "<root>/<wrapper>/<category folders>/<name>.<ext>", adding " (2)" if taken.
    private func freeDestination(name: String, ext: String, category: String) -> URL {
        let fm = FileManager.default
        let parts = category.components(separatedBy: " › ")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-") }
            .filter { !$0.isEmpty }
        var folder = rootURL
        for part in [wrapperFolder].compactMap({ $0 }) + (parts.isEmpty ? [Self.importFolder] : parts) {
            folder = folder.appending(path: part)
        }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        var dest = folder.appending(path: "\(safeName).\(ext)")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = folder.appending(path: "\(safeName) (\(n)).\(ext)")
            n += 1
        }
        return dest
    }

    private func libraryFile(at url: URL, category: String) -> LibraryFile {
        let root = rootURL.resolvingSymlinksInPath().pathComponents
        let path = url.resolvingSymlinksInPath().pathComponents.dropFirst(root.count).joined(separator: "/")
        let folders = url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            .dropFirst(root.count).dropFirst(wrapperFolder == nil ? 0 : 1)
        return LibraryFile(path: path,
                           category: folders.isEmpty ? "ทั่วไป" : folders.joined(separator: " › "),
                           title: url.deletingPathExtension().lastPathComponent)
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
