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
    
    /// Parse a Markdown string into an array of top-level EventNodes.
    /// Regex to match log lines: `> YYYY-MM-DD HH:MM content`
    private static let logRegex = try! NSRegularExpression(pattern: #"^>\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\s*(.*)$"#)
    
    static func parse(_ text: String) -> [EventNode] {
        let lines = text.components(separatedBy: .newlines)
        var parsedItems: [ParsedItem] = []
        
        for line in lines {
            let raw = line.replacingOccurrences(of: "\t", with: "    ") // normalize tabs
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            
            // Calculate indent level (number of leading spaces / 4)
            let leadingSpaces = raw.prefix(while: { $0 == " " }).count
            let level = leadingSpaces / indentUnit
            
            if trimmed.hasPrefix("- [") {
                guard let node = parseLine(trimmed) else { continue }
                parsedItems.append(.node(level: level, node: node))
            } else if trimmed.hasPrefix(">") {
                if let entry = parseLogLine(trimmed) {
                    parsedItems.append(.log(level: level, entry: entry))
                }
            }
        }
        
        // Build tree recursively from flat list
        return buildTree(from: parsedItems, startIndex: 0, parentLevel: -1).nodes
    }
    
    /// Parse a log line like `> 2026-02-14 15:30 Some content here`
    private static func parseLogLine(_ trimmed: String) -> LogEntry? {
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = logRegex.firstMatch(in: trimmed, range: range) else { return nil }
        guard let tsRange = Range(match.range(at: 1), in: trimmed),
              let contentRange = Range(match.range(at: 2), in: trimmed) else { return nil }
        
        let tsString = String(trimmed[tsRange])
        let content = String(trimmed[contentRange]).trimmingCharacters(in: .whitespaces)
        
        guard let timestamp = LogEntry.timestampFormatter.date(from: tsString) else { return nil }
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
        
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            isChecked = true
            afterBracket = String(trimmed.dropFirst(6))
        } else if trimmed.hasPrefix("- [ ] ") {
            isChecked = false
            afterBracket = String(trimmed.dropFirst(6))
        } else {
            return nil
        }
        
        var remaining = afterBracket
        
        // Extract tags: #word patterns
        var tags: [String] = []
        // Ignore anchor fragments inside markdown links, e.g. "(#target-123)".
        let tagRegex = try! NSRegularExpression(pattern: #"(?<!\()#(\w+)"#)
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
        
        // Extract metadata: key:value patterns (e.g., due:2026-03-15)
        var metadata: [String: String] = [:]
        let metaRegex = try! NSRegularExpression(pattern: #"(\w+):(\d{4}-\d{2}-\d{2})"#)
        let metaMatches = metaRegex.matches(in: afterBracket, range: NSRange(afterBracket.startIndex..., in: afterBracket))
        for match in metaMatches {
            if let keyRange = Range(match.range(at: 1), in: afterBracket),
               let valRange = Range(match.range(at: 2), in: afterBracket) {
                let key = String(afterBracket[keyRange])
                let val = String(afterBracket[valRange])
                if key != "blocked" { // skip tag-like words
                    metadata[key] = val
                }
            }
        }
        // Remove metadata from remaining title
        let metaCleanRegex = try! NSRegularExpression(pattern: #"\w+:\d{4}-\d{2}-\d{2}"#)
        remaining = metaCleanRegex.stringByReplacingMatches(
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
        // Regex: <a\s+(?:id|name)="([^"]+)"\s*>\s*</a>
        let anchorRegex = try! NSRegularExpression(pattern: #"<a\s+(?:id|name)="([^"]+)"\s*>\s*</a>"#, options: .caseInsensitive)
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
        let linkRegex = try! NSRegularExpression(pattern: #"^\[(.*)\]\(#([^)]+)\)$"#)
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
            referenceID: referenceID
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
            
            // Append metadata
            for (key, value) in node.metadata.sorted(by: { $0.key < $1.key }) {
                line += " \(key):\(value)"
            }
        }
        
        lines.append(line)
        
        // Serialize log entries (before children)
        for log in node.logs {
            let ts = LogEntry.timestampFormatter.string(from: log.timestamp)
            let logIndent = String(repeating: " ", count: (depth + 1) * indentUnit)
            lines.append("\(logIndent)> \(ts) \(log.content)")
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
