import Foundation

/// Everything known about the project a task belongs to. Gathered from disk by
/// the app layer; behind a protocol so the prompt can be built and tested
/// without touching a real repository.
public struct ProjectContext: Equatable, Sendable {
    public struct Document: Equatable, Sendable {
        public let name: String
        public let body: String
        public init(name: String, body: String) {
            self.name = name
            self.body = body
        }
    }

    public let projectName: String
    public let repoPath: String
    public let branch: String
    /// CLAUDE.md, design systems, requirements — the conventions to respect.
    public let documents: [Document]
    public let recentCommits: [String]
    /// Lines from the user's own notes that mention this project.
    public let notes: [String]

    public init(projectName: String, repoPath: String, branch: String = "",
                documents: [Document] = [], recentCommits: [String] = [], notes: [String] = []) {
        self.projectName = projectName
        self.repoPath = repoPath
        self.branch = branch
        self.documents = documents
        self.recentCommits = recentCommits
        self.notes = notes
    }

    public static let empty = ProjectContext(projectName: "", repoPath: "")
    public var isEmpty: Bool {
        repoPath.isEmpty && documents.isEmpty && recentCommits.isEmpty && notes.isEmpty
    }
}

public protocol ProjectContextReading: Sendable {
    /// Context for a task, or `.empty` when its category has no repository.
    func context(forRepoAt path: String, projectName: String, matching keywords: [String]) async -> ProjectContext
}

/// Turns a task plus its project's context into the brief Claude is asked to
/// write a Claude Code prompt from.
public enum PromptBuilder {
    /// Caps so a single generation cannot balloon: per document, and overall.
    public static let documentLimit = 3_500
    public static let totalLimit = 24_000

    public static func keywords(for task: TaskItem, categoryName: String?) -> [String] {
        let stop: Set<String> = [
            "the", "a", "an", "and", "or", "to", "for", "of", "in", "on", "at", "is", "it",
            "with", "that", "this", "fix", "add", "make", "do", "new", "my", "me", "we",
        ]
        let source = ([task.title, task.note, categoryName ?? ""]).joined(separator: " ")
        let words = source
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stop.contains($0) }
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }

    public static let system = """
    You write prompts for Claude Code, a coding agent that works in a terminal \
    inside a repository.

    You are given one task from the user's task list and real context about the \
    project it belongs to. Produce a single prompt the user can paste straight \
    into Claude Code.

    Rules:
    - Write the prompt itself. No preamble, no explanation, no code fences.
    - Address Claude Code directly, in the second person.
    - Open with what to achieve, not how. Let it choose the approach.
    - Fold in the project's real conventions, file paths and constraints from \
    the context. Those are the point — a prompt that ignores them is worthless.
    - Call out any gotcha in the notes that would bite, such as a migration that \
    is written but not applied, or a deploy that gets reverted.
    - If the context is thin, say plainly in the prompt what it should read first \
    to orient itself, rather than inventing detail.
    - End with how it should verify the work.
    - Never invent file paths, scripts or commands that are not in the context.
    - Do not end with a question. The prompt gets pasted into a terminal and \
    run; there is nobody there to answer it.
    """

    /// The brief: the task, then the project context, truncated to the budget.
    public static func brief(
        task: TaskItem,
        categoryName: String?,
        dueDescription: String?,
        context: ProjectContext
    ) -> String {
        var lines: [String] = ["# The task", "", task.title]
        if !task.note.isEmpty { lines.append(contentsOf: ["", task.note]) }
        lines.append("")
        lines.append("Status: \(task.status.title)")
        if let categoryName { lines.append("Project: \(categoryName)") }
        if let dueDescription { lines.append("Due: \(dueDescription)") }

        guard !context.isEmpty else {
            lines.append(contentsOf: [
                "", "# Project context", "",
                "None — this task has no project attached, so do not assume a repository.",
            ])
            return lines.joined(separator: "\n")
        }

        lines.append(contentsOf: ["", "# Project context", ""])
        lines.append("Repository: \(context.repoPath)")
        if !context.branch.isEmpty { lines.append("Branch: \(context.branch)") }

        if !context.notes.isEmpty {
            lines.append(contentsOf: ["", "## The user's own notes on this project", ""])
            lines.append(contentsOf: context.notes.map { "- \($0)" })
        }
        if !context.recentCommits.isEmpty {
            lines.append(contentsOf: ["", "## Recent commits", ""])
            lines.append(contentsOf: context.recentCommits.map { "- \($0)" })
        }
        for document in context.documents {
            lines.append(contentsOf: ["", "## \(document.name)", "", truncate(document.body, to: documentLimit)])
        }

        return truncate(lines.joined(separator: "\n"), to: totalLimit)
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<cut]) + "\n…[truncated]"
    }
}
