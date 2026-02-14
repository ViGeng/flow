//
//  ContentView.swift
//  Flow
//
//  Main view: search bar, recursive tree, clickable sidebar.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: FlowViewModel
    
    // Section Management
    @State private var isAddingSection = false
    @State private var isRenamingSection = false
    @State private var sectionNameInput = ""
    @State private var sectionToRenameIndex: Int?
    
    // Focus & Shortcuts
    @FocusState private var isComposerFocused: Bool
    
    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            flowTreeView
        }
        .frame(minWidth: 650, minHeight: 450)
        .onAppear {
            if viewModel.needsFolderPicker {
                viewModel.chooseStorageDirectory()
            }
        }
        .alert("New Section", isPresented: $isAddingSection) {
            TextField("Section Name", text: $sectionNameInput)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                viewModel.addSection(name: sectionNameInput)
                sectionNameInput = ""
            }
        }
        .alert("Rename Section", isPresented: $isRenamingSection) {
            TextField("Section Name", text: $sectionNameInput)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let index = sectionToRenameIndex {
                    viewModel.renameSection(index: index, name: sectionNameInput)
                }
                sectionNameInput = ""
                sectionToRenameIndex = nil
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarSelectionBinding: Binding<String> {
        Binding(
            get: { viewModel.activeFilter.map { $0.rawValue } ?? "all" },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if newValue == "all" {
                        viewModel.activeFilter = nil
                    } else if let state = EventState(rawValue: newValue) {
                        viewModel.activeFilter = state
                    }
                }
            }
        )
    }
    
    private var sidebarView: some View {
        List(selection: sidebarSelectionBinding) {
            overviewSection
            tagsSection
            settingsSection
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        .toolbar {
            ToolbarItem {
                Button(action: { viewModel.loadNodes() }) {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload from file")
            }
        }
    }
    
    @ViewBuilder
    private var overviewSection: some View {
        SwiftUI.Section("Overview") {
            sidebarRow(id: "all", label: "All Tasks", icon: "tray.full", count: viewModel.totalTaskCount, color: .primary)
            sidebarRow(id: EventState.active.rawValue, label: "Active", icon: "bolt.fill", count: viewModel.count(for: .active), color: .blue)
            sidebarRow(id: EventState.waiting.rawValue, label: "Waiting", icon: "clock.fill", count: viewModel.count(for: .waiting), color: .orange)
            sidebarRow(id: EventState.blocked.rawValue, label: "Blocked", icon: "lock.fill", count: viewModel.count(for: .blocked), color: .gray)
            sidebarRow(id: EventState.completed.rawValue, label: "Completed", icon: "checkmark.circle.fill", count: viewModel.count(for: .completed), color: .green)
        }
    }
    
    @ViewBuilder
    private var tagsSection: some View {
        if !viewModel.allTags.isEmpty {
            SwiftUI.Section("Tags") {
                ForEach(viewModel.allTags, id: \.self) { tag in
                    Button {
                        withAnimation {
                            viewModel.tagFilter = viewModel.tagFilter == tag ? nil : tag
                        }
                    } label: {
                        HStack {
                            Text("#\(tag)")
                                .font(.system(size: 12))
                            Spacer()
                            if viewModel.tagFilter == tag {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    @ViewBuilder
    private var settingsSection: some View {
        SwiftUI.Section("Settings") {
            Toggle("Start at Login", isOn: Bindable(viewModel).startsAtLogin)
                .font(.system(size: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.storageDirectory)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Button("Change Folder…") {
                    viewModel.chooseStorageDirectory()
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }
    
    private func sidebarRow(id: String, label: String, icon: String, count: Int, color: Color) -> some View {
        Label {
            HStack {
                Text(label)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        } icon: {
            Image(systemName: icon)
                .foregroundColor(color)
        }
        .tag(id)
    }
    
    // MARK: - Flow Tree View
    
    private var flowTreeView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                TextField("Search events or #tags…", text: Bindable(viewModel).searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if let filter = viewModel.activeFilter {
                    Text(filter.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundColor(.accentColor)
                }
                
                if let tag = viewModel.tagFilter {
                    HStack(spacing: 2) {
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                        Button {
                            viewModel.tagFilter = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                    .foregroundColor(.blue)
                }
                
                if viewModel.selectedNodeID != nil {
                    Button("Deselect") {
                        viewModel.selectedNodeID = nil
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.background)
            
            Divider()
            
            // Section tabs
            sectionTabBar
            Divider()
            
            // Tree content
            if viewModel.filteredNodes.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.filteredNodes) { node in
                            RecursiveNodeView(
                                node: node,
                                depth: 0,
                                viewModel: viewModel
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            
            ComposerView(viewModel: viewModel, isFocused: $isComposerFocused)
                .background(
                    VStack {
                        // Keyboard Shortcuts via hidden buttons
                        // Cmd+N: Focus "New Task"
                        Button(action: { isComposerFocused = true }) {
                            EmptyView()
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        
                        // Cmd+T: New Section
                        Button(action: {
                            sectionNameInput = ""
                            isAddingSection = true
                        }) {
                            EmptyView()
                        }
                        .keyboardShortcut("t", modifiers: .command)
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                )
        }
    }
    
    // MARK: - Section Tab Bar
    
    private var sectionTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(viewModel.sections.enumerated()), id: \.element.id) { index, section in
                    sectionTab(for: section, index: index)
                }
                
                // Add Section Button
                Button {
                    sectionNameInput = ""
                    isAddingSection = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.gray.opacity(0.05))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.secondary.opacity(0.1)),
            alignment: .bottom
        )
    }
    
    private func sectionTab(for section: Section, index: Int) -> some View {
        let isSelected = viewModel.selectedSectionIndex == index
        let label = section.name.isEmpty ? "General" : section.name
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedSectionIndex = index
            }
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                
                // Active indicator (underline style)
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
                    .padding(.horizontal, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                sectionNameInput = section.name
                sectionToRenameIndex = index
                isRenamingSection = true
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteSection(index: index)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "water.waves")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))
            
            if viewModel.needsFolderPicker {
                Text("No storage folder set")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Button("Choose Folder…") {
                    viewModel.chooseStorageDirectory()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Text(viewModel.activeFilter != nil || viewModel.tagFilter != nil || !viewModel.searchQuery.isEmpty
                     ? "No matching events"
                     : "No events in the flow")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Add an event below to get started")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Recursive Node View

struct RecursiveNodeView: View {
    let node: EventNode
    let depth: Int
    @Bindable var viewModel: FlowViewModel
    
    @State private var isExpanded: Bool = true
    
    private var hasChildren: Bool { !node.children.isEmpty }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                EventRowView(
                    node: node,
                    depth: depth,
                    isSelected: viewModel.selectedNodeID == node.id,
                    allTags: viewModel.allTags,
                    onToggle: { viewModel.toggleNode(node.id) },
                    onDelete: { viewModel.deleteNode(node.id) },
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedNodeID = viewModel.selectedNodeID == node.id ? nil : node.id
                        }
                    },
                    onToggleWait: { viewModel.toggleWait(node.id) },
                    onSetDueDate: { date in viewModel.setDueDate(node.id, date: date) },
                    onIndent: { viewModel.indentNode(node.id) },
                    onOutdent: { viewModel.outdentNode(node.id) },
                    onAddTag: { tag in viewModel.addTag(tag, to: node.id) },
                    onRemoveTag: { tag in viewModel.removeTag(tag, from: node.id) },
                    onRename: { newTitle in viewModel.renameNode(node.id, newTitle: newTitle) },
                    onJumpToTarget: { viewModel.jumpToTarget(from: node.id) },
                    onAddLog: { content in viewModel.addLog(to: node.id, content: content) },
                    onEditLog: { logID, content in viewModel.editLog(nodeID: node.id, logID: logID, content: content) },
                    onDeleteLog: { logID in viewModel.deleteLog(nodeID: node.id, logID: logID) },
                    onSetEventType: { type in viewModel.setEventType(node.id, type: type) }
                )
                
                if hasChildren {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse" : "Expand")
                }
            }
            
            if hasChildren && isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(node.children) { child in
                        RecursiveNodeView(
                            node: child,
                            depth: depth + 1,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}
