//
//  FlowViewModel.swift
//  Flow
//
//  ViewModel managing the recursive event tree — file I/O, tree operations, selection.
//

import Foundation
import Combine
import AppKit
import ServiceManagement

/// Safe subscript for collections.
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// ViewModel for the Flow app. Manages the recursive EventNode tree.
@Observable
@MainActor
final class FlowViewModel {
    
    // MARK: - State
    
    /// All sections (each has a name + nodes).
    var sections: [Section] = [Section()]
    
    /// Currently selected section tab index.
    var selectedSectionIndex: Int = 0
    
    /// Convenience: nodes of the active section.
    var nodes: [EventNode] {
        get { sections[safe: selectedSectionIndex]?.nodes ?? [] }
        set {
            guard sections.indices.contains(selectedSectionIndex) else { return }
            sections[selectedSectionIndex].nodes = newValue
        }
    }
    
    /// Currently selected node ID.
    var selectedNodeID: UUID?
    
    /// Active sidebar filter (nil = show all).
    var activeFilter: EventState?
    
    /// Search query for title/tag filtering.
    var searchQuery: String = ""
    
    /// Active tag filter (nil = no tag filter).
    var tagFilter: String?
    
    /// Error message for file I/O issues.
    var errorMessage: String?
    
    /// Whether to show folder picker on permission failure.
    var needsFolderPicker = false
    
    /// Whether the app is set to start at login.
    var startsAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                errorMessage = "Login item: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - File Management
    
    private var fileURL: URL
    private var scopedResource: ScopedResource?
    
    // Helper to manage security-scoped resource lifecycle
    private final class ScopedResource {
        let url: URL
        private let fileDescriptor: Int32
        private var monitorSource: DispatchSourceFileSystemObject?
        
        init(url: URL, onChange: @escaping @MainActor () -> Void) {
            self.url = url
            
            // Start accessing
            let accessing = url.startAccessingSecurityScopedResource()
            if !accessing {
                print("FlowViewModel: Failed to access security scoped resource: \(url)")
            }
            
            // Setup monitoring
            // We monitor the directory containing the file, or the file itself?
            // If file doesn't exist yet, we might monitor directory.
            // Existing logic monitored the file directly.
            
            let fm = FileManager.default
            let dir = url.appendingPathComponent("flow.md").deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = url.appendingPathComponent("flow.md").path
            
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: nil)
            }
            
            let fd = open(path, O_EVTONLY)
            self.fileDescriptor = fd
            
            if fd >= 0 {
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: [.write, .rename],
                    queue: .main
                )
                
                source.setEventHandler {
                    Task { @MainActor in
                        onChange()
                    }
                }
                
                source.setCancelHandler {
                    close(fd)
                }
                
                source.resume()
                self.monitorSource = source
            }
        }
        
        deinit {
            monitorSource?.cancel()
            // If fd was not managed by source cancel handler (e.g. source never created), close it?
            // But cancel handler handles close. 
            // If source was created, cancelling triggers handler.
            // If source NOT created but fd open:
            if monitorSource == nil && fileDescriptor >= 0 {
                close(fileDescriptor)
            }
            
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    private static let bookmarkKey = "flowFolderBookmark"
    
    // MARK: - Init
    
    init() {
        // Initialize with default or restored path
        let (resolvedFile, resolvedDir) = Self.resolveInitialURLs()
        self.fileURL = resolvedFile
        
        // Setup resource access and monitoring
        if let dir = resolvedDir {
            self.scopedResource = ScopedResource(url: dir) { [weak self] in
                self?.loadNodes()
            }
        } else {
            // Fallback paths (Documents) — still need file monitoring
        }
        
        if self.scopedResource == nil {
            self.startFallbackMonitor()
        }
        
        loadNodes()
        
        if !canWriteToStorage() {
            needsFolderPicker = true
        }
    }
    
    private func startFallbackMonitor() {
        // Use ScopedResource (robust logic) with the directory
        let dir = fileURL.deletingLastPathComponent()
        self.scopedResource = ScopedResource(url: dir) { [weak self] in
            self?.loadNodes()
        }
    }
    
    var storageDirectory: String {
        fileURL.deletingLastPathComponent().path
    }
    
    // MARK: - File Path Resolution
    
    private static func resolveInitialURLs() -> (file: URL, dir: URL?) {
        // 1. Try restoring security-scoped bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                // Refresh stale bookmark
                if isStale {
                    if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(newBookmark, forKey: bookmarkKey)
                    }
                }
                let flowFile = url.appendingPathComponent("flow.md")
                return (flowFile, url)
            }
        }
        
        // 2. Try iCloud default
        let userName = NSUserName()
        let iCloudPath = "/Users/\(userName)/Library/Mobile Documents/com~apple~CloudDocs/Flow"
        let iCloudURL = URL(fileURLWithPath: iCloudPath)
        let fm = FileManager.default
        
        if fm.isWritableFile(atPath: iCloudPath) {
            return (iCloudURL.appendingPathComponent("flow.md"), nil)
        }
        
        // 3. Fall back to Documents
        let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let flowDir = documentsURL.appendingPathComponent("Flow")
        try? fm.createDirectory(at: flowDir, withIntermediateDirectories: true)
        return (flowDir.appendingPathComponent("flow.md"), nil)
    }
    
    private func canWriteToStorage() -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: dir.path)
    }
    
    func chooseStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Flow storage folder"
        panel.prompt = "Select"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            
            // cleanup old (by replacing the optional)
            self.scopedResource = nil
            
            // Create bookmark
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: FlowViewModel.bookmarkKey)
            }
            
            self.fileURL = url.appendingPathComponent("flow.md")
            
            // Start accessing/monitoring new
            self.scopedResource = ScopedResource(url: url) { [weak self] in
                self?.loadNodes()
            }
            
            self.needsFolderPicker = false
            self.errorMessage = nil
            
            self.saveNodes()
            self.loadNodes()
        }
    }
    
    // MARK: - Section Management
    
    func addSection(name: String) {
        let newSection = Section(name: name, nodes: [])
        sections.append(newSection)
        selectedSectionIndex = sections.count - 1
        saveNodes()
    }
    
    func renameSection(index: Int, name: String) {
        guard sections.indices.contains(index) else { return }
        sections[index].name = name
        saveNodes()
    }
    
    func deleteSection(index: Int) {
        guard sections.indices.contains(index) else { return }
        sections.remove(at: index)
        
        // Adjust selection if needed
        if selectedSectionIndex >= sections.count {
            selectedSectionIndex = max(0, sections.count - 1)
        }
        
        // Ensure at least one section exists
        if sections.isEmpty {
            sections = [Section()]
            selectedSectionIndex = 0
        }
        
        saveNodes()
    }

    // MARK: - Computed Properties (Root-Level Counts)
    
    /// Count of root-level tasks only.
    var totalTaskCount: Int { nodes.count }
    
    /// Count root-level tasks matching a given state.
    func count(for state: EventState) -> Int {
        if state == .waiting {
            return allNodesFlat().filter { $0.state == .waiting && !$0.isReference }.count
        }
        return nodes.filter { $0.state == state }.count
    }
    
    /// All unique user tags across the entire tree (excluding system tags).
    var allTags: [String] {
        var tags = Set<String>()
        collectTags(from: nodes, into: &tags)
        return tags.sorted()
    }
    
    private func collectTags(from nodes: [EventNode], into tags: inout Set<String>) {
        for node in nodes {
            for tag in node.tags where tag != "wait" && tag != "ref" {
                tags.insert(tag)
            }
            collectTags(from: node.children, into: &tags)
        }
    }
    
    /// Filtered nodes based on activeFilter, searchQuery, and tagFilter.
    var filteredNodes: [EventNode] {
        var result = nodes
        
        // 1. State filter (root-level state matching)
        if let filter = activeFilter {
            result = filterTree(result, matching: filter)
        }
        
        // 2. Tag filter
        if let tag = tagFilter {
            result = filterByTag(result, tag: tag)
        }
        
        // 3. Search query
        if !searchQuery.isEmpty {
            result = filterBySearch(result, query: searchQuery.lowercased())
        }
        
        return result
    }
    
    private func filterTree(_ nodes: [EventNode], matching state: EventState) -> [EventNode] {
        nodes.compactMap { node in
            // For Completed: only show root nodes that are themselves completed
            if state == .completed {
                return node.state == state ? node : nil
            }
            // For other states: show root if its own state matches, or if it has matching descendants
            if node.state == state { return node }
            if containsState(node, state: state) { return node }
            return nil
        }
    }
    
    private func containsState(_ node: EventNode, state: EventState) -> Bool {
        for child in node.children {
            if child.state == state { return true }
            if containsState(child, state: state) { return true }
        }
        return false
    }
    
    private func filterByTag(_ nodes: [EventNode], tag: String) -> [EventNode] {
        nodes.compactMap { node in
            if node.tags.contains(tag) { return node }
            let filtered = filterByTag(node.children, tag: tag)
            if !filtered.isEmpty {
                var copy = node
                copy.children = filtered
                return copy
            }
            return nil
        }
    }
    
    private func filterBySearch(_ nodes: [EventNode], query: String) -> [EventNode] {
        nodes.compactMap { node in
            let titleMatch = node.title.lowercased().contains(query)
            let tagMatch = node.tags.contains { $0.lowercased().contains(query) }
            if titleMatch || tagMatch { return node }
            let filtered = filterBySearch(node.children, query: query)
            if !filtered.isEmpty {
                var copy = node
                copy.children = filtered
                return copy
            }
            return nil
        }
    }
    
    // MARK: - Search & References
    
    func allNodesFlat() -> [EventNode] {
        var result: [EventNode] = []
        collectNodes(from: nodes, into: &result)
        return result
    }
    
    /// All nodes across ALL sections (for cross-section references).
    private func allNodesFlatGlobal() -> [EventNode] {
        var result: [EventNode] = []
        for section in sections {
            collectNodes(from: section.nodes, into: &result)
        }
        return result
    }
    
    private func collectNodes(from nodes: [EventNode], into result: inout [EventNode]) {
        for node in nodes {
            result.append(node)
            collectNodes(from: node.children, into: &result)
        }
    }
    
    func searchNodes(query: String) -> [EventNode] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return allNodesFlatGlobal().filter {
            $0.title.lowercased().contains(q) && !$0.isChecked && !$0.isReference
        }
    }
    
    /// Navigate to the target of a reference node.
    func jumpToTarget(from referenceNodeID: UUID) {
        guard let refNode = findNodeGlobal(id: referenceNodeID),
              let targetID = refNode.referenceID else { return }
        
        // Find node with matching anchorID across sections.
        if let (target, sectionIndex) = findNodeByAnchorGlobal(targetID) {
            selectedSectionIndex = sectionIndex
            selectedNodeID = target.id
            activeFilter = nil
            searchQuery = ""
        }
    }
    
    private func findNodeByAnchor(_ anchorID: String, in nodes: [EventNode]) -> EventNode? {
        for node in nodes {
            if node.anchorID == anchorID { return node }
            if let found = findNodeByAnchor(anchorID, in: node.children) { return found }
        }
        return nil
    }
    
    private func findNodeGlobal(id: UUID) -> EventNode? {
        for section in sections {
            if let found = findNode(id: id, in: section.nodes) {
                return found
            }
        }
        return nil
    }
    
    private func findNodeByAnchorGlobal(_ anchorID: String) -> (node: EventNode, sectionIndex: Int)? {
        for index in sections.indices {
            if let found = findNodeByAnchor(anchorID, in: sections[index].nodes) {
                return (found, index)
            }
        }
        return nil
    }
    
    /// Add a reference to an existing event.
    /// Ensures target has an anchor ID, then creates a linking node.
    func addTaskReference(to parentID: UUID, referencedTitle: String) {
        // Find first concrete (non-reference) target globally.
        guard let target = allNodesFlatGlobal().first(where: {
            $0.title == referencedTitle && !$0.isReference
        }) else { return }
        addTaskReference(to: parentID, targetNodeID: target.id)
    }
    
    /// Add a reference to an existing event by stable node ID.
    /// This avoids title-collision bugs and prevents linking to reference nodes.
    func addTaskReference(to parentID: UUID, targetNodeID: UUID) {
        guard var target = allNodesFlatGlobal().first(where: { $0.id == targetNodeID }),
              !target.isReference else { return }
        
        // Ensure target has an anchor ID
        if target.anchorID == nil {
            let newAnchor = generateAnchorID(from: target.title)
            // We need to mutate the actual node in the tree (search all sections)
            for i in sections.indices {
                let found = mutateNode(id: target.id, in: &sections[i].nodes, { n in
                    n.anchorID = newAnchor
                })
                if found { break }
            }
            // Update local copy
            target.anchorID = newAnchor
        }
        
        guard let anchorID = target.anchorID else { return }
        
        // Create reference node
        // Title matches target, referenceID points to anchor.
        // STRICT: No other tags or metadata.
        let refNode = EventNode(
            title: target.title,
            tags: ["ref"], // Mark as ref for UI styling
            referenceID: anchorID
        )
        
        var didInsert = false
        for i in sections.indices {
            let found = mutateNode(id: parentID, in: &sections[i].nodes) { parent in
                parent.children.append(refNode)
            }
            if found {
                didInsert = true
                break
            }
        }
        guard didInsert else { return }
        
        syncReferences()
        saveNodes()
    }
    
    private func generateAnchorID(from title: String) -> String {
        let safeTitle = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(safeTitle)-\(timestamp)"
    }
    
    // MARK: - Sync State
    
    /// Sync state of reference nodes with their targets.
    private func syncReferences() {
        // 1. Build map of anchors from ALL sections
        var anchorMap: [String: EventNode] = [:]
        
        func collectAnchors(from nodes: [EventNode]) {
            for node in nodes {
                // Anchors are owned by concrete nodes, not reference nodes.
                if node.referenceID == nil, let anchor = node.anchorID {
                    anchorMap[anchor] = node
                }
                collectAnchors(from: node.children)
            }
        }
        
        for section in sections {
            collectAnchors(from: section.nodes)
        }
        
        // 2. Sync valid references and prune dangling references whose targets no longer exist.
        var referencedAnchors = Set<String>()
        
        func updateAndPruneRefs(in nodes: inout [EventNode]) {
            var index = 0
            while index < nodes.count {
                if let refID = nodes[index].referenceID {
                    guard let target = anchorMap[refID] else {
                        // Target deleted (or missing): drop the dangling reference node.
                        nodes.remove(at: index)
                        continue
                    }
                    
                    referencedAnchors.insert(refID)
                    
                    if nodes[index].title != target.title {
                        nodes[index].title = target.title
                    }
                    if nodes[index].isChecked != target.isChecked {
                        nodes[index].isChecked = target.isChecked
                    }
                    let expectedTags = ["ref"]
                    if nodes[index].tags != expectedTags {
                        nodes[index].tags = expectedTags
                    }
                    if !nodes[index].metadata.isEmpty {
                        nodes[index].metadata = [:]
                    }
                    if nodes[index].anchorID != nil {
                        nodes[index].anchorID = nil
                    }
                }
                
                updateAndPruneRefs(in: &nodes[index].children)
                index += 1
            }
        }
        
        for i in sections.indices {
            updateAndPruneRefs(in: &sections[i].nodes)
        }
        
        // 3. Clear anchor IDs that no remaining reference points to.
        func clearUnusedAnchors(in nodes: inout [EventNode]) {
            for i in nodes.indices {
                if let anchor = nodes[i].anchorID, !referencedAnchors.contains(anchor) {
                    nodes[i].anchorID = nil
                }
                clearUnusedAnchors(in: &nodes[i].children)
            }
        }
        
        for i in sections.indices {
            clearUnusedAnchors(in: &sections[i].nodes)
        }
    }
    
    // MARK: - Tag Management
    
    func addTag(_ tag: String, to nodeID: UUID) {
        let cleanTag = tag.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "#", with: "")
        guard !cleanTag.isEmpty, cleanTag != "wait", cleanTag != "ref" else { return }
        
        mutateNode(id: nodeID, in: &nodes) { n in
            if !n.tags.contains(cleanTag) {
                n.tags.append(cleanTag)
            }
        }
        saveNodes()
    }
    
    func removeTag(_ tag: String, from nodeID: UUID) {
        mutateNode(id: nodeID, in: &nodes) { n in
            n.tags.removeAll { $0 == tag }
        }
        saveNodes()
    }
    
    // MARK: - File I/O
    
    func loadNodes() {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error) { url in
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                self.sections = MarkdownParser.parseSections(content)
                self.syncReferences() // Sync on load
                if self.selectedSectionIndex >= self.sections.count {
                    self.selectedSectionIndex = 0
                }
                self.errorMessage = nil
                self.needsFolderPicker = false
            } catch {
                if (error as NSError).code == NSFileReadNoSuchFileError {
                    self.sections = [Section()]
                    self.errorMessage = nil
                } else {
                    self.errorMessage = "Failed to load: \(error.localizedDescription)"
                }
            }
        }
        
        if let error {
            self.errorMessage = "Coordination error: \(error.localizedDescription)"
        }
    }
    
    private func saveNodes() {
        syncReferences() // Sync before save
        
        let coordinator = NSFileCoordinator()
        var error: NSError?
        let content = MarkdownParser.serializeSections(sections)
        
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &error) { url in
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                self.errorMessage = nil
            } catch {
                self.errorMessage = "Failed to save: \(error.localizedDescription)"
                needsFolderPicker = true
            }
        }
        
        if let error {
            self.errorMessage = "Coordination error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - File Monitoring
    
    // Monitoring is now handled by ScopedResource

    
    // MARK: - Tree Mutation Helpers
    
    @discardableResult
    private func mutateNode(id: UUID, in nodes: inout [EventNode], _ transform: (inout EventNode) -> Void) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id {
                transform(&nodes[i])
                return true
            }
            if mutateNode(id: id, in: &nodes[i].children, transform) {
                return true
            }
        }
        return false
    }
    
    private func findNode(id: UUID, in nodes: [EventNode]) -> EventNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(id: id, in: node.children) { return found }
        }
        return nil
    }
    
    @discardableResult
    private func removeNode(id: UUID, from nodes: inout [EventNode]) -> EventNode? {
        for i in nodes.indices {
            if nodes[i].id == id {
                return nodes.remove(at: i)
            }
            if let removed = removeNode(id: id, from: &nodes[i].children) {
                return removed
            }
        }
        return nil
    }
    
    private func findLocation(of id: UUID, in nodes: [EventNode], parentID: UUID? = nil) -> (parentID: UUID?, index: Int)? {
        for (i, node) in nodes.enumerated() {
            if node.id == id {
                return (parentID, i)
            }
            if let found = findLocation(of: id, in: node.children, parentID: node.id) {
                return found
            }
        }
        return nil
    }
    
    // MARK: - Node Actions
    
    /// Add a new node, auto-extracting #tags from the title text.
    func addNode(title: String) {
        let raw = title.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        
        // Extract tags from text
        var (cleanTitle, tags) = Self.extractTags(from: raw)
        
        // If title became empty (e.g. input was just "#urgent"), revert to raw text
        if cleanTitle.isEmpty {
            cleanTitle = raw
        }
        
        let newNode = EventNode(title: cleanTitle, tags: tags)
        
        if let parentID = selectedNodeID {
            mutateNode(id: parentID, in: &nodes) { parent in
                parent.children.append(newNode)
            }
        } else {
            nodes.append(newNode)
        }
        saveNodes()
    }
    
    /// Extract #tags from text, returning (cleanTitle, tags).
    static func extractTags(from text: String) -> (title: String, tags: [String]) {
        var tags: [String] = []
        let regex = try! NSRegularExpression(pattern: #"#(\w+)"#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            if let range = Range(match.range(at: 1), in: text) {
                let tag = String(text[range]).lowercased()
                // We allow "wait" as it's user-toggleable. "ref" is system-only.
                if tag != "ref" && !tags.contains(tag) {
                    tags.append(tag)
                }
            }
        }
        
        // Remove tags from title
        let cleanTitle = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "  ", with: " ")
        
        return (cleanTitle, tags)
    }
    
    /// Rename a node's title, auto-extracting tags.
    func renameNode(_ nodeID: UUID, newTitle: String) {
        let raw = newTitle.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        
        var (cleanTitle, newTags) = Self.extractTags(from: raw)
        
        // If title became empty (e.g. renamed to "#done"), keep it as is
        if cleanTitle.isEmpty {
            cleanTitle = raw
        }
        
        mutateNode(id: nodeID, in: &nodes) { n in
            n.title = cleanTitle
            // Merge: keep ref (system only), replace others with parsed tags
            // Since "wait" is now parsed from text, we don't treat it as "invisible" system tag.
            let systemTags = n.tags.filter { $0 == "ref" }
            n.tags = systemTags + newTags
        }
        saveNodes()
    }
    
    func toggleNode(_ nodeID: UUID) {
        guard let node = findNode(id: nodeID, in: nodes) else { return }
        if node.state == .blocked { return }
        
        mutateNode(id: nodeID, in: &nodes) { n in
            n.isChecked.toggle()
            if n.isChecked {
                n.tags.removeAll { $0 == "wait" }
            }
        }
        saveNodes()
    }
    
    func deleteNode(_ nodeID: UUID) {
        removeNode(id: nodeID, from: &nodes)
        if selectedNodeID == nodeID { selectedNodeID = nil }
        saveNodes()
    }
    
    func toggleWait(_ nodeID: UUID) {
        mutateNode(id: nodeID, in: &nodes) { n in
            if n.tags.contains("wait") {
                n.tags.removeAll { $0 == "wait" }
            } else {
                n.tags.append("wait")
            }
        }
        saveNodes()
    }
    
    func setDueDate(_ nodeID: UUID, date: Date?) {
        mutateNode(id: nodeID, in: &nodes) { n in
            if let date {
                n.metadata["due"] = EventNode.dateFormatter.string(from: date)
            } else {
                n.metadata.removeValue(forKey: "due")
            }
        }
        saveNodes()
    }
    
    func indentNode(_ nodeID: UUID) {
        guard let (parentID, index) = findLocation(of: nodeID, in: nodes) else { return }
        guard index > 0 else { return }
        
        if let parentID {
            mutateNode(id: parentID, in: &nodes) { parent in
                let node = parent.children.remove(at: index)
                parent.children[index - 1].children.append(node)
            }
        } else {
            let node = nodes.remove(at: index)
            nodes[index - 1].children.append(node)
        }
        saveNodes()
    }
    
    func outdentNode(_ nodeID: UUID) {
        guard let (parentID, _) = findLocation(of: nodeID, in: nodes) else { return }
        guard let parentID else { return }
        guard let (grandparentID, parentIndex) = findLocation(of: parentID, in: nodes) else { return }
        guard let node = removeNode(id: nodeID, from: &nodes) else { return }
        
        if let grandparentID {
            mutateNode(id: grandparentID, in: &nodes) { grandparent in
                grandparent.children.insert(node, at: parentIndex + 1)
            }
        } else {
            nodes.insert(node, at: parentIndex + 1)
        }
        saveNodes()
    }
}
