//
//  ContentView.swift
//  Flow
//
//  Main view: search bar, recursive tree, clickable sidebar.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: FlowViewModel
    
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
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        List(selection: Binding(
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
        )) {
            Section("Overview") {
                sidebarRow(id: "all", label: "All Tasks", icon: "tray.full", count: viewModel.totalTaskCount, color: .primary)
                sidebarRow(id: EventState.active.rawValue, label: "Active", icon: "bolt.fill", count: viewModel.count(for: .active), color: .blue)
                sidebarRow(id: EventState.waiting.rawValue, label: "Waiting", icon: "clock.fill", count: viewModel.count(for: .waiting), color: .orange)
                sidebarRow(id: EventState.blocked.rawValue, label: "Blocked", icon: "lock.fill", count: viewModel.count(for: .blocked), color: .gray)
                sidebarRow(id: EventState.completed.rawValue, label: "Completed", icon: "checkmark.circle.fill", count: viewModel.count(for: .completed), color: .green)
            }
            
            if !viewModel.allTags.isEmpty {
                Section("Tags") {
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
            
            Section("Settings") {
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
            
            ComposerView(viewModel: viewModel)
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
                    onJumpToTarget: { viewModel.jumpToTarget(from: node.id) }
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
                VStack(alignment: .leading, spacing: 2) {
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
