
import Foundation

// Mock EventNode structure for standalone testing (copying relevant parts)
enum EventType: String, CaseIterable, Codable {
    case task, milestone, event
    var emoji: String {
        switch self {
        case .task: return ""
        case .milestone: return "🏁"
        case .event: return "📅"
        }
    }
    static func parse(from title: String) -> (String, EventType) {
        if title.hasSuffix(" 🏁") { return (String(title.dropLast(2)), .milestone) }
        if title.hasSuffix(" 📅") { return (String(title.dropLast(2)), .event) }
        return (title, .task)
    }
}

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var content: String
    
    init(id: UUID = UUID(), timestamp: Date = Date(), content: String) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
    }
    
    static let storageFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}

struct EventNode {
    let id: UUID
    var title: String
    var isChecked: Bool
    var tags: [String]
    var metadata: [String: String]
    var children: [EventNode]
    var logs: [LogEntry]
    var eventType: EventType
    var anchorID: String?
    var referenceID: String?
    var createdAt: Date?
    var completedAt: Date?
    
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
        referenceID: String? = nil,
        createdAt: Date? = nil,
        completedAt: Date? = nil
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
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
    
    static let unifiedFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
    
    static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}

// Mock Parser logic (copying relevant logic from MarkdownParser)
struct MarkdownParser {
    static let indentUnit = 4
    static let logRegex = try! NSRegularExpression(pattern: #"^>\s*\[created:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\]\s*(.*)$"#)

    static func parseLine(_ trimmed: String) -> EventNode? {
        // ... (Simplified for this test to focus on specific logic) ...
        // We'll trust the full parser implementation if we can reproduce logic here or test via full file
        // Replicating key regex logic:
        
         let isChecked = trimmed.hasPrefix("- [x] ")
         let afterBracket = String(trimmed.dropFirst(6))
         var remaining = afterBracket
         
         // Tags
         var tags: [String] = []
         let tagRegex = try! NSRegularExpression(pattern: #"(?<!\()#(\w+)"#)
         let tagMatches = tagRegex.matches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining))
         for match in tagMatches {
             if let range = Range(match.range(at: 1), in: remaining) {
                 tags.append(String(remaining[range]))
             }
         }
         remaining = tagRegex.stringByReplacingMatches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining), withTemplate: "")
         
         // Metadata Unified
         var metadata: [String: String] = [:]
         let metaRegex = try! NSRegularExpression(pattern: #"\s*\[(.*?):\s*(.*?)\]"#)
         var createdAt: Date?
         var completedAt: Date?
         
         let metaMatches = metaRegex.matches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining))
         for match in metaMatches {
             if let keyRange = Range(match.range(at: 1), in: remaining),
                let valRange = Range(match.range(at: 2), in: remaining) {
                 let key = String(remaining[keyRange]).trimmingCharacters(in: .whitespaces)
                 let val = String(remaining[valRange]).trimmingCharacters(in: .whitespaces)
                 
                 if key == "created" {
                     createdAt = EventNode.unifiedFormatter.date(from: val)
                 } else if key == "done" {
                     completedAt = EventNode.unifiedFormatter.date(from: val)
                 } else {
                     metadata[key] = val
                 }
             }
         }
         
         remaining = metaRegex.stringByReplacingMatches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining), withTemplate: "")
         
         let title = remaining.trimmingCharacters(in: .whitespaces)
         
         return EventNode(title: title, isChecked: isChecked, tags: tags, metadata: metadata, createdAt: createdAt, completedAt: completedAt)
    }
}

// Test Case
let testLine = "- [x] Finished Task #urgent [created: 2026-02-15 10:00] [done: 2026-02-15 12:00] [priority: high]"
if let node = MarkdownParser.parseLine(testLine) {
    print("Title: \(node.title)")
    print("Tags: \(node.tags)")
    print("Metadata: \(node.metadata)")
    if let created = node.createdAt {
        print("Created: \(EventNode.unifiedFormatter.string(from: created))")
    }
    if let done = node.completedAt {
        print("Done: \(EventNode.unifiedFormatter.string(from: done))")
    }
} else {
    print("Failed to parse line")
}

let logLine = "> [created: 2026-02-15 14:00] Log content"
let logRegex = try! NSRegularExpression(pattern: #"^>\s*\[created:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\]\s*(.*)$"#)
let range = NSRange(logLine.startIndex..., in: logLine)
if let match = logRegex.firstMatch(in: logLine, range: range) {
    if let tsRange = Range(match.range(at: 1), in: logLine),
       let contentRange = Range(match.range(at: 2), in: logLine) {
        print("Log Timestamp: \(logLine[tsRange])")
        print("Log Content: \(logLine[contentRange])")
    }
} else {
    print("Failed to parse log")
}
