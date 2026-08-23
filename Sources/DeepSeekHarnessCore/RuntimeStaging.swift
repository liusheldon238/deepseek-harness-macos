import Foundation

public struct RuntimeStaging {
    public let directory: URL
    public let targetDirectory: URL
    private let fileManager: FileManager

    public static func begin(targetDirectory: URL, fileManager: FileManager = .default) throws -> RuntimeStaging {
        let parent = targetDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let directory = parent.appendingPathComponent(".\(targetDirectory.lastPathComponent)-staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return RuntimeStaging(directory: directory, targetDirectory: targetDirectory, fileManager: fileManager)
    }

    public func discard() throws {
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
    }

    public func promote() throws {
        let parent = targetDirectory.deletingLastPathComponent()
        let backup = parent.appendingPathComponent(".\(targetDirectory.lastPathComponent)-previous-\(UUID().uuidString)", isDirectory: true)
        let hadTarget = fileManager.fileExists(atPath: targetDirectory.path)
        if hadTarget { try fileManager.moveItem(at: targetDirectory, to: backup) }
        do {
            try fileManager.moveItem(at: directory, to: targetDirectory)
            if hadTarget { try fileManager.removeItem(at: backup) }
        } catch {
            if fileManager.fileExists(atPath: targetDirectory.path) { try? fileManager.removeItem(at: targetDirectory) }
            if hadTarget && fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: targetDirectory)
            }
            throw error
        }
    }
}
