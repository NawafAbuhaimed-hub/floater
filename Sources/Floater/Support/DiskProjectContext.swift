import FloaterCore
import Foundation

/// Reads a project's conventions, recent commits, and the user's own notes
/// about it off disk. Everything is best-effort: a missing repo, a missing
/// memory folder or a git failure each just contribute nothing.
struct DiskProjectContext: ProjectContextReading {
    /// Files worth handing to a coding agent, in the order they matter.
    private static let conventionFiles = [
        "CLAUDE.md", "AGENTS.md", "REQUIREMENTS.md", "README.md",
    ]
    private static let conventionSuffixes = ["-DESIGN-SYSTEM.md", "-SPEC.md"]

    private let memoryDirectory: URL
    private let maxNotes = 8
    private let maxCommits = 20

    init(memoryDirectory: URL = URL(
        fileURLWithPath: NSHomeDirectory() + "/.claude/projects/-Users-nawaf/memory"
    )) {
        self.memoryDirectory = memoryDirectory
    }

    func context(forRepoAt path: String, projectName: String, matching keywords: [String]) async -> ProjectContext {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return .empty
        }
        let repo = URL(fileURLWithPath: path)
        return ProjectContext(
            projectName: projectName,
            repoPath: path,
            branch: run("git", ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]) ?? "",
            documents: documents(in: repo),
            recentCommits: commits(at: path),
            notes: notes(matching: keywords, projectName: projectName, repoPath: path)
        )
    }

    // MARK: - Repository

    private func documents(in repo: URL) -> [ProjectContext.Document] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: repo.path)) ?? []
        let wanted = names.filter { name in
            Self.conventionFiles.contains(name) || Self.conventionSuffixes.contains { name.hasSuffix($0) }
        }
        return wanted.sorted().compactMap { name in
            guard let body = try? String(contentsOf: repo.appendingPathComponent(name), encoding: .utf8),
                  !body.isEmpty else { return nil }
            return ProjectContext.Document(name: name, body: body)
        }
    }

    private func commits(at path: String) -> [String] {
        guard let log = run("git", ["-C", path, "log", "-\(maxCommits)", "--pretty=%ad %s",
                                    "--date=short"]) else { return [] }
        return log.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - The user's notes

    /// Scores each note by how many of the task's words it mentions, plus a
    /// strong signal for the project name or repo folder, and keeps the best.
    private func notes(matching keywords: [String], projectName: String, repoPath: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: memoryDirectory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let folder = URL(fileURLWithPath: repoPath).lastPathComponent.lowercased()
        let project = projectName.lowercased()

        var scored: [(score: Int, line: String)] = []
        // MEMORY.md is the index over the notes, not a note: it mentions every
        // project so it matches everything, and its first line says nothing.
        let indexNames: Set<String> = ["MEMORY.md", "README.md"]
        for file in files where file.pathExtension == "md" && !indexNames.contains(file.lastPathComponent) {
            guard let body = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let haystack = body.lowercased()
            var score = 0
            if !folder.isEmpty, haystack.contains(folder) { score += 6 }
            if !project.isEmpty, haystack.contains(project) { score += 4 }
            score += keywords.filter { haystack.contains($0) }.count
            guard score >= 4 else { continue }
            scored.append((score, excerpt(of: body, titled: file.deletingPathExtension().lastPathComponent)))
        }
        return scored.sorted { $0.score > $1.score }.prefix(maxNotes).map(\.line)
    }

    /// The note's actual substance. Reducing each one to its `description:`
    /// line threw away the body — the why and the how-to-apply — which is
    /// exactly the part that makes a generated prompt worth having.
    private func excerpt(of body: String, titled title: String) -> String {
        var lines = body.components(separatedBy: "\n")

        // Drop the YAML front matter, keeping the description as a heading.
        var description: String?
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closing = lines.dropFirst().firstIndex(where: {
               $0.trimmingCharacters(in: .whitespaces) == "---"
           }) {
            description = lines[1..<closing]
                .first { $0.hasPrefix("description:") }?
                .replacingOccurrences(of: "description:", with: "")
                .trimmingCharacters(in: .whitespaces)
            lines = Array(lines[(closing + 1)...])
        }

        let content = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = "### \(description ?? title)"
        return content.isEmpty ? heading : heading + "\n" + content
    }

    private func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
