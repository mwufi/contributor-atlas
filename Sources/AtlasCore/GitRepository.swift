import Foundation

public enum GitError: LocalizedError {
    case command(String), malformed(String)
    public var errorDescription: String? {
        switch self { case .command(let s), .malformed(let s): return s }
    }
}

public enum GitRepository {
    public static func run(_ args: [String], path: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["--no-pager", "-C", path] + args
        // Drain stdout while Git runs; redirect stderr to a file to avoid pipe deadlocks.
        let output = Pipe()
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorFile = try FileHandle(forWritingTo: errorURL)
        defer { try? errorFile.close(); try? FileManager.default.removeItem(at: errorURL) }
        p.standardOutput = output; p.standardError = errorFile
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        p.environment = environment
        try p.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "Git exited with status \(p.terminationStatus)."
            throw GitError.command(message)
        }
        return String(decoding: data, as: UTF8.self)
    }
    public static func load(path: String) throws -> RepositorySnapshot {
        let root = try run(["rev-parse", "--show-toplevel"], path: path).trimmingCharacters(in: .whitespacesAndNewlines)
        // Pin the revision so a concurrent fetch/checkout cannot mix metadata and history.
        let head = try run(["rev-parse", "HEAD"], path: root).trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = try run(["rev-parse", "--abbrev-ref", "HEAD"], path: root).trimmingCharacters(in: .whitespacesAndNewlines)
        let shallow = try run(["rev-parse", "--is-shallow-repository"], path: root).hasPrefix("true")
        let log = try run(["-c", "core.quotePath=false", "log", "--format=%x1e%H%x00%aN%x00%aE%x00%aI%x00%P%x00%s", "--name-only", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", head, "--"], path: root)
        return RepositorySnapshot(path: root, branch: branch, head: head, shallow: shallow, commits: try parse(log))
    }
    public static func parse(_ log: String) throws -> [Commit] {
        let formatter = ISO8601DateFormatter()
        return try log.split(separator: "\u{1e}", omittingEmptySubsequences: true).map { record in
            let fields = record.components(separatedBy: "\0")
            guard fields.count >= 6, let date = formatter.date(from: fields[3]), fields[0].count == 40 || fields[0].count == 64 else {
                throw GitError.malformed("Could not decode Git history. No partial results were used.")
            }
            let stamp = fields[3]
            var offset = 0
            if stamp.count >= 6 {
                let zone = String(stamp.suffix(6))
                let digits = zone.dropFirst().split(separator: ":")
                if digits.count == 2, let h = Int(digits[0]), let m = Int(digits[1]) { offset = (zone.first == "-" ? -1 : 1) * (h * 3600 + m * 60) }
            }
            var paths = Array(fields.dropFirst(6))
            if let first = paths.first, first.hasPrefix("\n") { paths[0].removeFirst() }
            paths = paths.filter { !$0.isEmpty }
            return Commit(id: fields[0], name: fields[1], email: fields[2], date: date, offset: offset, parents: fields[4].split(separator: " ").map(String.init), subject: fields[5], files: paths)
        }
    }
}
