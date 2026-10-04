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
    public static let noteLimit = 900
    public static let totalLimit = 26_000

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

    /// Skills bundled with the app, loaded by the host. Editing the markdown
    /// changes how prompts are written without touching code.
    public static var skills: [String: String] = [:]

    static let baseSystem = """
    You write prompts for Claude Code, a coding agent that works in a terminal \
    inside a repository.

    You are given one task and REAL context about the project it belongs to: \
    its conventions, its recent commits, and the user's own notes about it. \
    That context is the whole point. Your job is to pour it into the prompt so \
    the agent starts already knowing it.

    Hard rules:
    - Output the prompt itself. No preamble, no explanation, no code fences, \
    no sign-off.
    - Address the agent directly, in the second person.
    - NEVER tell it to go and read something to orient itself, familiarise \
    itself, or understand the conventions. You have those conventions in front \
    of you. State them, inline, as instructions. A prompt that delegates its \
    own research has failed.
    - NEVER ask the user a question, and never end with one. The prompt is \
    pasted into a terminal; nobody is there to answer.
    - NEVER say the context is limited, thin, or unclear. Write the best prompt \
    the context supports and stop.
    - Name specific files, directories, commands and constraints when the \
    context gives them. Invent none that it does not.
    - Put anything that would waste an hour near the top: a migration written \
    but not applied, a deploy that gets reverted, a required flag.
    - End with how to verify the work.
    """

    /// Keywords that mean the task touches a screen, so taste guidance applies.
    static let uiWords: Set<String> = [
        "ui", "ux", "design", "component", "page", "screen", "view", "layout",
        "css", "style", "styles", "styling", "button", "modal", "dialog", "form",
        "card", "table", "chart", "dashboard", "colour", "color", "font", "icon",
        "responsive", "dark", "theme", "animation", "frontend",
    ]

    public static func isUITask(_ task: TaskItem, categoryName: String?) -> Bool {
        let words = Set(keywords(for: task, categoryName: categoryName))
        return !words.isDisjoint(with: uiWords)
    }

    /// The base rules, plus whichever skills apply to this task.
    public static func system(includeUITaste: Bool) -> String {
        var parts = [baseSystem]
        if let engineering = skills["prompt-engineering"] {
            parts.append("# How to write it\n\n" + engineering)
        }
        if includeUITaste, let taste = skills["ui-taste"] {
            parts.append("# This task touches a screen\n\n" + taste)
        }
        return parts.joined(separator: "\n\n")
    }

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
                "This task has no project attached. Write the prompt from the task alone,",
                "without naming a repository, a file or a command.",
            ])
            return lines.joined(separator: "\n")
        }

        lines.append(contentsOf: ["", "# Project context", ""])
        lines.append("Repository: \(context.repoPath)")
        if !context.branch.isEmpty { lines.append("Branch: \(context.branch)") }

        if !context.notes.isEmpty {
            lines.append(contentsOf: [
                "", "## The user's own notes on this project",
                "", "These are hard-won and often contain the traps. Fold the relevant ones",
                "into the prompt as statements of fact.", "",
            ])
            for note in context.notes {
                lines.append(truncate(note, to: noteLimit))
                lines.append("")
            }
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
