//
//  EventNode.swift
//  Flow
//
//  The recursive data model for the Flow app.
//  Every item is an EventNode in a tree. State propagates upward (bubble-up rule).
//

import Foundation

/// The type of event node.
enum EventType: String, Codable, CaseIterable {
    case task       // Default: a regular task
    case milestone  // A milestone marker (🏁)
    case event      // A calendar/scheduled event (📅)
    
    var emoji: String {
        switch self {
        case .task: return ""
        case .milestone: return "🏁"
        case .event: return "📅"
        }
    }
    
    var iconName: String {
        switch self {
        case .task: return "checklist"
        case .milestone: return "flag.fill"
        case .event: return "calendar"
        }
    }
    
    var displayName: String {
        switch self {
        case .task: return "Task"
        case .milestone: return "Milestone"
        case .event: return "Event"
        }
    }
    
    /// Parse emoji suffix from title, returning (cleanTitle, type).
    static func parse(from title: String) -> (String, EventType) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("🏁") {
            return (String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces), .milestone)
        }
        if trimmed.hasSuffix("📅") {
            return (String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces), .event)
        }
        return (trimmed, .task)
    }
}

/// A timestamped work log entry attached to an EventNode.
struct LogEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var content: String  // Markdown text
    
    init(id: UUID = UUID(), timestamp: Date = Date(), content: String) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
    }
    
    static let timestampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}

/// The possible states an event node can be in.
enum EventState: String, CaseIterable {
    case active     // Ready to be worked on
    case waiting    // The actual blocker (has #wait tag)
    case blocked    // Parent blocked by child, or has unresolved waiting descendants
    case completed  // Done
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .waiting: return "Waiting"
        case .blocked: return "Blocked"
        case .completed: return "Done"
        }
    }
    
    var iconName: String {
        switch self {
        case .active: return "circle"
        case .waiting: return "clock.fill"
        case .blocked: return "lock.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

/// A single event node in the recursive task tree.
struct EventNode: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var isChecked: Bool
    var tags: [String]              // e.g., ["wait", "urgent"]
    var metadata: [String: String]  // e.g., ["due": "2026-03-15"]
    var children: [EventNode]       // Recursive children
    var logs: [LogEntry]            // Timestamped work log entries
    var eventType: EventType        // task, milestone, or event
    var anchorID: String?           // e.g., "task-123" (HTML anchor on this node)
    var referenceID: String?        // e.g., "task-123" (This node links to that anchor)
    
    init(
        id: UUID = UUID(),
        title: String,
        isChecked: Bool = false,
        tags: [String] = [],
        metadata: [String: String] = [:],
        children: [EventNode] = [],
        logs: [LogEntry] = [],
        eventType: EventType = .task,
        anchorID: String? = nil,
        referenceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isChecked = isChecked
        self.tags = tags
        self.metadata = metadata
        self.children = children
        self.logs = logs
        self.eventType = eventType
        self.anchorID = anchorID
        self.referenceID = referenceID
    }
    
    // MARK: - Computed State (Bubble-Up Rule)
    
    /// The computed state of this node.
    /// 1. If checked → completed
    /// 2. If has #wait tag → waiting (the leaf blocker)
    /// 3. If ANY child is waiting or blocked → this node is blocked
    /// 4. Otherwise → active
    var state: EventState {
        // 1. Completed
        if isChecked { return .completed }
        
        // 2. Explicitly Waiting (leaf node with #wait)
        if tags.contains("wait") { return .waiting }
        
        // 3. Reference to another task (blocks parent until resolved)
        if tags.contains("ref") { return .waiting }
        
        // 4. Blocked by Children (bubble-up)
        if children.contains(where: { $0.state == .waiting || $0.state == .blocked }) {
            return .blocked
        }
        
        // 5. Active
        return .active
    }
    
    // MARK: - Convenience
    
    /// Whether this node has the #wait tag.
    var isWaiting: Bool {
        tags.contains("wait")
    }
    
    /// Whether this node is a task reference (e.g. [[Task Title]]).
    var isReference: Bool {
        tags.contains("ref")
    }
    
    /// Due date parsed from metadata, if present.
    var dueDate: Date? {
        guard let dateString = metadata["due"] else { return nil }
        return EventNode.dateFormatter.date(from: dateString)
    }
    
    /// Progress: fraction of children completed (nil if no children).
    var childProgress: Double? {
        guard !children.isEmpty else { return nil }
        let done = children.filter(\.isChecked).count
        return Double(done) / Double(children.count)
    }
    
    /// Summary string like "2/5 events"
    var childProgressText: String? {
        guard !children.isEmpty else { return nil }
        let done = children.filter(\.isChecked).count
        return "\(done)/\(children.count) events"
    }
    
    /// Sort priority: Active(0) > Waiting(1) > Blocked(2) > Done(3)
    var sortOrder: Int {
        switch state {
        case .active: return 0
        case .waiting: return 1
        case .blocked: return 2
        case .completed: return 3
        }
    }
    
    // MARK: - Date Formatting
    
    static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}

/// A named section grouping top-level EventNodes.
/// Maps to `## Heading` in the Markdown file.
struct Section: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var nodes: [EventNode]
    
    init(id: UUID = UUID(), name: String = "", nodes: [EventNode] = []) {
        self.id = id
        self.name = name
        self.nodes = nodes
    }
}
