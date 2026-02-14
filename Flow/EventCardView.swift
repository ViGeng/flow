//
//  EventRowView.swift
//  Flow
//
//  A single row in the recursive tree view.
//  Visual styling per EventState. Includes inline controls and double-click editing.
//

import SwiftUI

/// Renders a single EventNode with state-dependent styling and inline controls.
struct EventRowView: View {
    let node: EventNode
    let depth: Int
    let isSelected: Bool
    let allTags: [String]
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void
    let onToggleWait: () -> Void
    let onSetDueDate: (Date?) -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onRename: (String) -> Void
    let onJumpToTarget: () -> Void
    let onAddLog: (String) -> Void
    let onEditLog: (UUID, String) -> Void
    let onDeleteLog: (UUID) -> Void
    let onSetEventType: (EventType) -> Void
    
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showingWaitPopover = false
    @State private var showingTagPopover = false
    @State private var newTagText = ""
    @State private var hasDueDate: Bool
    @State private var waitDueDate: Date
    @State private var showLogs = false
    @State private var showLogInput = false
    @State private var logInputText = ""
    @State private var editingLogID: UUID?
    @State private var editingLogText = ""
    
    init(
        node: EventNode,
        depth: Int,
        isSelected: Bool,
        allTags: [String],
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        onToggleWait: @escaping () -> Void,
        onSetDueDate: @escaping (Date?) -> Void,
        onIndent: @escaping () -> Void,
        onOutdent: @escaping () -> Void,
        onAddTag: @escaping (String) -> Void,
        onRemoveTag: @escaping (String) -> Void,
        onRename: @escaping (String) -> Void,
        onJumpToTarget: @escaping () -> Void,
        onAddLog: @escaping (String) -> Void,
        onEditLog: @escaping (UUID, String) -> Void,
        onDeleteLog: @escaping (UUID) -> Void,
        onSetEventType: @escaping (EventType) -> Void
    ) {
        self.node = node
        self.depth = depth
        self.isSelected = isSelected
        self.allTags = allTags
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onSelect = onSelect
        self.onToggleWait = onToggleWait
        self.onSetDueDate = onSetDueDate
        self.onIndent = onIndent
        self.onOutdent = onOutdent
        self.onAddTag = onAddTag
        self.onRemoveTag = onRemoveTag
        self.onRename = onRename
        self.onJumpToTarget = onJumpToTarget
        self.onAddLog = onAddLog
        self.onEditLog = onEditLog
        self.onDeleteLog = onDeleteLog
        self.onSetEventType = onSetEventType
        self._hasDueDate = State(initialValue: node.dueDate != nil)
        self._waitDueDate = State(initialValue: node.dueDate ?? Date().addingTimeInterval(3 * 86400))
    }
    
    private var isRootLevel: Bool { depth == 0 }
    
    /// User-visible tags (excluding system tags).
    private var displayTags: [String] {
        node.tags.filter { $0 != "wait" && $0 != "ref" }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            leadingIndicator
            
            // Content Interaction Zone
            // Wrap title and spacer to capture selection taps ONLY here
            HStack(spacing: 0) {
                // Title + metadata (or edit field)
                if isEditing {
                    TextField("Event title", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: isRootLevel ? 14 : 13))
                        .onSubmit { commitEdit() }
                        .onExitCommand { cancelEdit() }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            // Event type icon
                            if node.eventType == .milestone {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.purple)
                            } else if node.eventType == .event {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                    .foregroundColor(.teal)
                            }
                            
                            if node.referenceID != nil {
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Text(.init(node.title))
                                .font(.system(size: isRootLevel ? 14 : 13, weight: isRootLevel ? .semibold : (node.state == .active ? .medium : .regular)))
                                .foregroundColor(foregroundColor)
                                .strikethrough(node.state == .completed)
                                .lineLimit(2)
                        }
                        
                        // Subtitle info
                        HStack(spacing: 6) {
                            if let progress = node.childProgressText {
                                Text(progress)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                            
                            if let dueDate = node.dueDate {
                                let isPast = dueDate < Date()
                                Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                    .font(.system(size: 10))
                                    .foregroundColor(isPast ? .red : .secondary)
                            }
                            
                            if !node.logs.isEmpty {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        showLogs.toggle()
                                    }
                                } label: {
                                    Label("\(node.logs.count)", systemImage: "text.bubble")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            ForEach(displayTags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { startEditing() }
            .simultaneousGesture(TapGesture().onEnded {
                SoundManager.shared.playClick()
                onSelect()
            })
            
            // Inline action buttons (hover or selected)
            if (isHovering || isSelected) && !isEditing {
                HStack(spacing: 4) {
                    // Jump to target (only for refs)
                    if node.referenceID != nil {
                        Button(action: onJumpToTarget) {
                            Image(systemName: "arrow.turn.up.right")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Go to Original")
                    }
                    
                    // Tag button
                    Button {
                        SoundManager.shared.playClick()
                        showingTagPopover.toggle()
                    } label: {
                        Image(systemName: "tag")
                            .font(.system(size: 10))
                            .foregroundColor(displayTags.isEmpty ? .secondary.opacity(0.6) : .blue)
                    }
                    .buttonStyle(.plain)
                    .help("Manage tags")
                    .popover(isPresented: $showingTagPopover, arrowEdge: .trailing) {
                        tagPopoverContent
                    }
                    
                    // Wait toggle
                    Button {
                        SoundManager.shared.playClick()
                        showingWaitPopover.toggle()
                    } label: {
                        Image(systemName: node.isWaiting ? "clock.fill" : "clock")
                            .font(.system(size: 11))
                            .foregroundColor(node.isWaiting ? .orange : .secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(node.isWaiting ? "Remove #wait" : "Set as waiting")
                    .popover(isPresented: $showingWaitPopover, arrowEdge: .trailing) {
                        waitPopoverContent
                    }
                    
                    // Indent
                    Button(action: {
                        SoundManager.shared.playClick()
                        onIndent()
                    }) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Indent")
                    
                    // Outdent
                    Button(action: {
                        SoundManager.shared.playClick()
                        onOutdent()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Outdent")
                    
                    // Delete
                    Button(action: {
                        SoundManager.shared.playDelete()
                        onDelete()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .opacity(node.state == .blocked ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        
        // Log entries section
        if showLogs || isSelected {
            logSection
        }
    }
    
    // MARK: - Inline Editing
    
    private func startEditing() {
        // Reconstruct full text with tags for editing
        var text = node.title
        for tag in displayTags {
            text += " #\(tag)"
        }
        editText = text
        isEditing = true
    }
    
    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
    }
    
    // MARK: - Log Section
    
    @ViewBuilder
    private var logSection: some View {
        if !node.logs.isEmpty || isSelected {
            VStack(alignment: .leading, spacing: 4) {
                // Existing logs
                ForEach(node.logs) { log in
                    LogEntryView(
                        log: log,
                        isEditing: editingLogID == log.id,
                        editingText: $editingLogText,
                        onEditStart: {
                            editingLogText = log.content
                            editingLogID = log.id
                        },
                        onEditCommit: {
                            onEditLog(log.id, editingLogText)
                            editingLogID = nil
                        },
                        onEditCancel: { editingLogID = nil },
                        onDelete: { onDeleteLog(log.id) }
                    )
                }
                
                // Add log input
                if isSelected {
                    if showLogInput {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            TextField("Add work log…", text: $logInputText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .onSubmit {
                                    if !logInputText.isEmpty {
                                        onAddLog(logInputText)
                                        logInputText = ""
                                        showLogInput = false
                                    }
                                }
                                .onExitCommand {
                                    showLogInput = false
                                    logInputText = ""
                                }
                        }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showLogInput = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Add Log")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.leading, isRootLevel ? 36 : 28)
            .padding(.trailing, 8)
            .padding(.bottom, 4)
        }
    }

    
    // MARK: - Tag Popover
    
    private var tagPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 12, weight: .semibold))
            
            if !displayTags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(displayTags, id: \.self) { tag in
                        HStack(spacing: 2) {
                            Text("#\(tag)")
                                .font(.system(size: 11))
                            Button {
                                onRemoveTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                        .foregroundColor(.blue)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 6) {
                TextField("New tag…", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        if !newTagText.isEmpty {
                            onAddTag(newTagText)
                            newTagText = ""
                        }
                    }
                
                Button("Add") {
                    onAddTag(newTagText)
                    newTagText = ""
                }
                .controlSize(.small)
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            
            let available = allTags.filter { !node.tags.contains($0) }
            if !available.isEmpty {
                Text("Existing tags")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                FlowLayout(spacing: 4) {
                    ForEach(available, id: \.self) { tag in
                        Button {
                            onAddTag(tag)
                        } label: {
                            Text("#\(tag)")
                                .font(.system(size: 11))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }
    
    // MARK: - Wait Popover
    
    private var waitPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(node.isWaiting ? "Remove #wait" : "Set #wait") {
                onToggleWait()
                showingWaitPopover = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Divider()
            
            Toggle("Due date", isOn: $hasDueDate)
                .font(.system(size: 12))
            
            if hasDueDate {
                DatePicker("", selection: $waitDueDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                
                HStack(spacing: 6) {
                    Button("+3d") {
                        waitDueDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Button("+1w") {
                        waitDueDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Spacer()
                    
                    Button("Set") {
                        onSetDueDate(waitDueDate)
                        showingWaitPopover = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button("Clear Due Date") {
                    onSetDueDate(nil)
                    showingWaitPopover = false
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
    
    // MARK: - Leading Indicator
    
    @ViewBuilder
    private var leadingIndicator: some View {
        if node.referenceID != nil {
            // Read-only indicator for references
            switch node.state {
            case .active:
                Image(systemName: "circle")
                    .font(.system(size: isRootLevel ? 18 : 16))
                    .foregroundColor(.secondary.opacity(0.5))
            case .waiting:
                Image(systemName: "clock")
                    .font(.system(size: isRootLevel ? 18 : 16))
                    .foregroundColor(.orange.opacity(0.7))
            case .blocked:
                Image(systemName: "lock.fill")
                    .font(.system(size: isRootLevel ? 15 : 13))
                    .foregroundColor(.gray)
                    .frame(width: 20)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: isRootLevel ? 18 : 16))
                    .foregroundColor(.green.opacity(0.4))
            }
        } else {
            // Interactive buttons for normal nodes
            switch node.state {
            case .active:
                Button(action: {
                    SoundManager.shared.playSuccess()
                    onToggle()
                }) {
                    Image(systemName: "circle")
                        .font(.system(size: isRootLevel ? 18 : 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Complete")
                
            case .waiting:
                Button(action: {
                    SoundManager.shared.playClick()
                    onToggle()
                }) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: isRootLevel ? 18 : 16))
                        .foregroundColor(.orange)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .buttonStyle(.plain)
                .help("Resolve waiting")
                
            case .blocked:
                Image(systemName: "lock.fill")
                    .font(.system(size: isRootLevel ? 15 : 13))
                    .foregroundColor(.gray)
                    .frame(width: 20)
                
            case .completed:
                Button(action: {
                    SoundManager.shared.playClick()
                    onToggle()
                }) {
                    Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: isRootLevel ? 18 : 16))
                    .foregroundColor(.green.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Uncheck")
            }
        }
    }
    
    // MARK: - Styling
    
    private var foregroundColor: Color {
        switch node.state {
        case .active: return .primary
        case .waiting: return .primary
        case .blocked: return .gray
        case .completed: return .secondary
        }
    }
    
    private var background: some ShapeStyle {
        if node.state == .waiting {
            return AnyShapeStyle(Color.orange.opacity(0.06))
        } else if isSelected {
            // "Highlighted color" style: Standard Apple tint (approx 10-15%)
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(Color(.controlBackgroundColor))
    }
    
    private var borderColor: Color {
        // Remove "bunny books" (bounding box) for selection
        if isSelected { return .clear }
        if node.state == .waiting { return .orange.opacity(0.3) }
        return .secondary.opacity(0.1)
    }
}

/// A separate view for a single log entry to handle hover state independently
struct LogEntryView: View {
    let log: LogEntry
    let isEditing: Bool
    @Binding var editingText: String
    let onEditStart: () -> Void
    let onEditCommit: () -> Void
    let onEditCancel: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(LogEntry.timestampFormatter.string(from: log.timestamp))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(minWidth: 70, alignment: .leading)
                .padding(.top, 1)
            
            if isEditing {
                TextField("Edit log…", text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit(onEditCommit)
                    .onExitCommand(perform: onEditCancel)
            } else {
                // Use LocalizedStringKey to enable Markdown parsing
                Text(.init(log.content))
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true) // Allow text wrapping
                    .lineLimit(nil)
            }
            
            Spacer()
            
            if isHovering && !isEditing {
                HStack(spacing: 6) {
                    Button(action: onEditStart) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Edit log")
                    
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Delete log")
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}


// MARK: - Flow Layout (for tag chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, proposal: proposal).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, proposal: proposal)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layout(subviews: Subviews, proposal: ProposedViewSize) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }
        
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
