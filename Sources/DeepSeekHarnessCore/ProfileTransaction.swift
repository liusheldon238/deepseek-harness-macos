import Foundation

public struct ProfileTransaction {
    public let directory: URL
    public let profileDirectory: URL
    public let profileExisted: Bool
    private let snapshotsDirectory: URL
    private let fileManager: FileManager

    public static func begin(
        profileDirectory: URL,
        snapshotsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> ProfileTransaction {
        try fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        let directory = snapshotsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existed = fileManager.fileExists(atPath: profileDirectory.path)
        if existed {
            try fileManager.copyItem(at: profileDirectory, to: directory.appendingPathComponent("profile", isDirectory: true))
        }
        return ProfileTransaction(
            directory: directory,
            profileDirectory: profileDirectory,
            profileExisted: existed,
            snapshotsDirectory: snapshotsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    public static func recoverPending(
        profileDirectory: URL,
        snapshotsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: snapshotsDirectory.path) else { return false }
        let entries = try fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !entries.isEmpty else { return false }
        let candidate = entries.min { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }!
        let profileExisted = fileManager.fileExists(atPath: candidate.appendingPathComponent("profile", isDirectory: true).path)
        let transaction = ProfileTransaction(
            directory: candidate,
            profileDirectory: profileDirectory,
            profileExisted: profileExisted,
            snapshotsDirectory: snapshotsDirectory,
            fileManager: fileManager
        )
        try transaction.restore()
        for entry in try fileManager.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: entry)
        }
        return true
    }

    public func restore() throws {
        let parent = profileDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let restoreStage = parent.appendingPathComponent(".restore-\(UUID().uuidString)", isDirectory: true)
        let displaced = parent.appendingPathComponent(".displaced-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: restoreStage)
            try? fileManager.removeItem(at: displaced)
        }

        if profileExisted {
            try fileManager.copyItem(at: directory.appendingPathComponent("profile", isDirectory: true), to: restoreStage)
        }
        let currentExists = fileManager.fileExists(atPath: profileDirectory.path)
        if currentExists { try fileManager.moveItem(at: profileDirectory, to: displaced) }
        do {
            if profileExisted { try fileManager.moveItem(at: restoreStage, to: profileDirectory) }
            if currentExists { try fileManager.removeItem(at: displaced) }
            try fileManager.removeItem(at: directory)
        } catch {
            if fileManager.fileExists(atPath: profileDirectory.path) { try? fileManager.removeItem(at: profileDirectory) }
            if currentExists && fileManager.fileExists(atPath: displaced.path) {
                try? fileManager.moveItem(at: displaced, to: profileDirectory)
            }
            throw error
        }
    }

    public func commit() throws {
        guard fileManager.fileExists(atPath: snapshotsDirectory.path) else { return }
        for entry in try fileManager.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: entry)
        }
    }
}
