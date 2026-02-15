//
//  MarkdownParser.swift
//  Flow
//
//  Stack-based recursive parser for Markdown → EventNode tree.
//  Uses 4-space indentation to determine parent-child relationships.
//

import Foundation

/// Parses and serializes EventNode trees to/from Markdown format.
///
/// Format:
/// ```
/// - [ ] Parent Task
///     - [ ] Child Event #wait
///     - [x] Done child
///         - [ ] Grandchild
/// ```
///
/// Indentation: 4 spaces per level.
/// Tags: `#wait`, `#urgent`, etc.
/// Metadata: `due:YYYY-MM-DD` becomes `metadata["due"]`
struct MarkdownParser {
    
    /// Indent unit: 4 spaces per level.
    static let indentUnit = 4
    
    // MARK: - Parsing
    
    /// A parsed line with its indent level (used internally).
    private enum ParsedItem {
        case node(level: Int, node: EventNode)
        case log(level: Int, entry: LogEntry)
    }
    
    // MARK: - Regex Patterns
    
    /// Regex to match log lines: `> [created: YYYY-MM-DD HH:mm] content`
    /// Group 1: Timestamp, Group 2: Content
    private static let logRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^>\s*\[created:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\]\s*(.*)$"#)
    }()
    
    /// Regex to match tags: `#tag` (excluding headers/anchors)
    private static let tagRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"(?<!\()#(\w+)"#)
    }()
    
    /// Regex to match metadata: `[key: value]` or `[key: yyyy-MM-dd HH:mm]`
    private static let metaRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"\s*\[(.*?):\s*(.*?)\]"#)
    }()
    
    /// Regex to match legacy metadata: `key:value` (e.g., due:2026-01-01)
    private static let legacyMetaRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"(\w+):(\d{4}-\d{2}-\d{2})"#)
    }()
    
    /// Regex to match cleaned metadata strings for removal
    private static let legacyMetaCleanRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"\w+:\d{4}-\d{2}-\d{2}"#)
    }()
    
    /// Regex to match HTML anchors: `<a id="..."></a>`
    private static let anchorRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"<a\s+(?:id|name)="([^"]+)"\s*>\s*</a>"#, options: .caseInsensitive)
    }()
    
    /// Regex to match Markdown links: `[Title](#id)`
    private static let linkRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^\[(.*)\]\(#([^)]+)\)$"#)
    }()
    
    // MARK: - Parsing

    
    static func parse(_ text: String) -> [EventNode] {
        let lines = text.components(separatedBy: .newlines)
        var parsedItems: [ParsedItem] = []
        
        for line in lines {
            let raw = line.replacingOccurrences(of: "\t", with: "    ") // normalize tabs
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            
            // Calculate indent level with rounding (flexible indentation)
            // 0-1 spaces -> level 0
            // 2-5 spaces -> level 1 (4 spaces standard)
            // 6-9 spaces -> level 2
            let leadingSpaces = raw.prefix(while: { $0 == " " }).count
            let level = Int((Double(leadingSpaces) / 4.0).rounded())
            
            if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") {
                guard let node = parseLine(trimmed) else { continue }
                parsedItems.append(.node(level: level, node: node))
            } else if trimmed.hasPrefix(">") {
                if let entry = parseLogLine(trimmed) {
                    parsedItems.append(.log(level: level, entry: entry))
                }
            }
        }
        
        }
        
        // Build tree recursively from flat list
        return buildTree(from: parsedItems, startIndex: 0, parentLevel: -1).nodes
    }
    
    /// Parse a log line like `> [time: 2026-02-14 15:30] Some content here`
    private static func parseLogLine(_ trimmed: String) -> LogEntry? {
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = logRegex.firstMatch(in: trimmed, range: range) else { return nil }
        guard let tsRange = Range(match.range(at: 1), in: trimmed),
              let contentRange = Range(match.range(at: 2), in: trimmed) else { return nil }
        
        let tsString = String(trimmed[tsRange])
        let content = String(trimmed[contentRange]).trimmingCharacters(in: .whitespaces)
        
        guard let timestamp = LogEntry.storageFormatter.date(from: tsString) else { return nil }
        return LogEntry(timestamp: timestamp, content: content)
    }

    /// Recursively build a tree from a flat list of parsed items.
    /// Returns the nodes at `parentLevel + 1` and the index where parsing stopped.
    private static func buildTree(
        from items: [ParsedItem],
        startIndex: Int,
        parentLevel: Int
    ) -> (nodes: [EventNode], nextIndex: Int) {
        var result: [EventNode] = []
        var i = startIndex
        let childLevel = parentLevel + 1
        
        while i < items.count {
            // Check level of current item — if at or below parent, we're done
            let itemLevel: Int
            switch items[i] {
            case .node(let level, _): itemLevel = level
            case .log(let level, _): itemLevel = level
            }
            
            if itemLevel <= parentLevel {
                break // Left this scope
            }
            
            switch items[i] {
            case .node(let level, let node) where level == childLevel:
                var node = node
                i += 1
                
                // Collect log entries that follow this node
                var logs: [LogEntry] = []
                while i < items.count {
                    if case .log(_, let entry) = items[i] {
                        logs.append(entry)
                        i += 1
                    } else {
                        break
                    }
                }
                node.logs = logs
                
                // Collect deeper children recursively
                let (children, nextI) = buildTree(from: items, startIndex: i, parentLevel: childLevel)
                node.children = children
                i = nextI
                
                result.append(node)
                
            default:
                i += 1 // Skip unexpected items
            }
        }
        
        return (result, i)
    }
    
    // MARK: - Parsing Helpers

    /// Parse a single trimmed Markdown line into an EventNode (without children).
    private static func parseLine(_ trimmed: String) -> EventNode? {
        let isChecked: Bool
        let afterBracket: String
        
        // Flexible Checkbox Parsing
        // Regex: (dash or star) (space?) [ (x or X or space) ] (space?)
        // But we need to handle manually to extract "afterBracket"
        
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        
        // Match "- [ ]", "- [x]", "* [ ]", "* [x]", and variations with missing spaces
        // Group 1: Bullet (- or *)
        // Group 2: State (space, x, X)
        // Group 3: Rest of string
        let laxCheckboxRegex = try! NSRegularExpression(pattern: #"^\s*([-*])\s*\[([ xX])\]\s*(.*)$"#)
        
        if let match = laxCheckboxRegex.firstMatch(in: trimmed, range: range) {
            if let stateRange = Range(match.range(at: 2), in: trimmed),
               let restRange = Range(match.range(at: 3), in: trimmed) {
                
                let state = String(trimmed[stateRange]).lowercased()
                isChecked = (state == "x")
                afterBracket = String(trimmed[restRange])
            } else {
                return nil
            }
        } else {
            return nil
        }
        
        var remaining = afterBracket
        
        // Extract tags: #word patterns
        var tags: [String] = []
        // Ignore anchor fragments inside markdown links, e.g. "(#target-123)".
        let tagMatches = tagRegex.matches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining))
        for match in tagMatches {
            if let range = Range(match.range(at: 1), in: remaining) {
                tags.append(String(remaining[range]))
            }
        }
        // Remove tags from title
        remaining = tagRegex.stringByReplacingMatches(
            in: remaining,
            range: NSRange(remaining.startIndex..., in: remaining),
            withTemplate: ""
        )
        
        // Extract metadata: [key: value] patterns (Unified Timestamp Format)
        var metadata: [String: String] = [:]
        
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
                } else if key == "due" {
                    // Try unified first, then simple date fallback
                    if let date = EventNode.unifiedFormatter.date(from: val) {
                        metadata["due"] = EventNode.unifiedFormatter.string(from: date)
                    } else if let date = EventNode.dateFormatter.date(from: val) {
                        metadata["due"] = EventNode.dateFormatter.string(from: date)
                    } else {
                         metadata[key] = val
                    }
                } else {
                     metadata[key] = val
                }
            }
        }
        
        // Remove metadata from remaining title
        remaining = metaRegex.stringByReplacingMatches(
            in: remaining,
            range: NSRange(remaining.startIndex..., in: remaining),
            withTemplate: ""
        )
        
        // Legacy Support: metadata like `due:YYYY-MM-DD` (without brackets)
        let legacyMatches = legacyMetaRegex.matches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining))
        for match in legacyMatches {
            if let keyRange = Range(match.range(at: 1), in: remaining),
               let valRange = Range(match.range(at: 2), in: remaining) {
                let key = String(remaining[keyRange])
                let val = String(remaining[valRange])
                if key != "blocked" && metadata[key] == nil { // Don't overwrite bracketed
                    metadata[key] = val
                }
            }
        }
        remaining = legacyMetaCleanRegex.stringByReplacingMatches(
            in: remaining,
            range: NSRange(remaining.startIndex..., in: remaining),
            withTemplate: ""
        )
        
        // Clean up title (trim whitespace before parsing anchors/links)
        var title = remaining
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        
        var anchorID: String?
        var referenceID: String?
        
        // Check for HTML Anchor: <a id="..."></a>
        if let match = anchorRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            if let idRange = Range(match.range(at: 1), in: title) {
                anchorID = String(title[idRange])
            }
            // Remove anchor tag from title
            title = anchorRegex.stringByReplacingMatches(
                in: title,
                range: NSRange(title.startIndex..., in: title),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
        }
        
        // Check for Markdown Link: [Title](#id)
        if let match = linkRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            if let titleRange = Range(match.range(at: 1), in: title),
               let idRange = Range(match.range(at: 2), in: title) {
                let extractedTitle = String(title[titleRange])
                referenceID = String(title[idRange])
                title = extractedTitle
            }
        }
        
        // Parse event type from emoji suffix
        let (cleanTitle, eventType) = EventType.parse(from: title)
        title = cleanTitle
        
        guard !title.isEmpty else { return nil }
        
        return EventNode(
            title: title,
            isChecked: isChecked,
            tags: tags,
            metadata: metadata,
            eventType: eventType,
            anchorID: anchorID,
            referenceID: referenceID,
            createdAt: createdAt,
            completedAt: completedAt
        )
    }
    
    // MARK: - Serialization
    
    /// Serialize an array of top-level EventNodes to Markdown.
    static func serialize(_ nodes: [EventNode]) -> String {
        var lines: [String] = []
        for node in nodes {
            serializeNode(node, depth: 0, into: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }
    
    /// Recursively serialize a single node and its children.
    private static func serializeNode(_ node: EventNode, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: " ", count: depth * indentUnit)
        
        // Base line: "- [x] "
        var line = "\(indent)- [\(node.isChecked ? "x" : " ")] "
        
        if let refID = node.referenceID {
            line += "[\(node.title)](#\(refID))"
            line += " #ref"
        } else {
            line += node.title
            
            // Append event type emoji
            if !node.eventType.emoji.isEmpty {
                line += " \(node.eventType.emoji)"
            }
            
            // Append Anchor if present: <a name="anchorID"></a>
            if let anchorID = node.anchorID {
                line += " <a name=\"\(anchorID)\"></a>"
            }
            
            // Append tags
            for tag in node.tags {
                line += " #\(tag)"
            }
            
            // Append unified timestamps [key: value]
            if let created = node.createdAt {
                let ts = EventNode.unifiedFormatter.string(from: created)
                line += " [created: \(ts)]"
            }
            
            if let done = node.completedAt {
                let ts = EventNode.unifiedFormatter.string(from: done)
                line += " [done: \(ts)]"
            }
            
            // Append metadata (including due)
            for (key, value) in node.metadata.sorted(by: { $0.key < $1.key }) {
                // If value matches unified format (basically due), wrap in brackets [key: val]
                // Else use legacy format or bracket? Spec says [key: value]. 
                // Let's adopt consistent [key: value] for all metadata if possible, but keep simple space separation for now?
                // The parser supports [key: value].
                if key == "due" {
                    line += " [\(key): \(value)]"
                } else {
                    // Start migrating other metadata to brackets too?
                    // For now, only enforce on due/timestamps.
                    line += " [\(key): \(value)]"
                }
            }
        }
        
        lines.append(line)
        
        // Serialize log entries (before children)
        for log in node.logs {
            let ts = LogEntry.storageFormatter.string(from: log.timestamp)
            let logIndent = String(repeating: " ", count: (depth + 1) * indentUnit)
            lines.append("\(logIndent)> [created: \(ts)] \(log.content)")
        }
        
        // Recurse into children
        for child in node.children {
            serializeNode(child, depth: depth + 1, into: &lines)
        }
    }
    
    // MARK: - Section Parsing
    
    /// Parse a Markdown string into sections delimited by `## Heading` lines.
    /// Tasks before any `##` go into a default section with an empty name.
    static func parseSections(_ text: String) -> [Section] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [Section] = []
        var currentName = ""
        var currentLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                // Flush previous section
                let content = currentLines.joined(separator: "\n")
                let nodes = parse(content)
                if !nodes.isEmpty || !currentName.isEmpty {
                    sections.append(Section(name: currentName, nodes: nodes))
                }
                currentName = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        
        // Flush last section
        let content = currentLines.joined(separator: "\n")
        let nodes = parse(content)
        if !nodes.isEmpty || !currentName.isEmpty {
            sections.append(Section(name: currentName, nodes: nodes))
        }
        
        // If empty file, return one default section
        if sections.isEmpty {
            sections.append(Section(name: "", nodes: []))
        }
        
        return sections
    }
    
    /// Serialize an array of sections to Markdown with `## Heading` delimiters.
    static func serializeSections(_ sections: [Section]) -> String {
        var result = ""
        for (i, section) in sections.enumerated() {
            if !section.name.isEmpty {
                if i > 0 { result += "\n" }
                result += "## \(section.name)\n\n"
            }
            if !section.nodes.isEmpty {
                result += serialize(section.nodes)
            }
        }
        // Ensure trailing newline
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }
}
