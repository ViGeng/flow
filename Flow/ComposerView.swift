//
//  ComposerView.swift
//  Flow
//
//  Bottom input bar. Text input + Add button + event search autocomplete.
//  Typing in the field shows matching existing events to add as task references.
//

import SwiftUI

/// The bottom input bar for creating new events and adding task references.
struct ComposerView: View {
    @Bindable var viewModel: FlowViewModel
    @FocusState.Binding var isFocused: Bool
    
    @State private var eventTitle: String = ""
    @State private var showSearchResults = false
    
    private var hasSelection: Bool {
        viewModel.selectedNodeID != nil
    }
    
    /// Search results matching current input text.
    private var searchResults: [EventNode] {
        guard hasSelection, eventTitle.count >= 2 else { return [] }
        return viewModel.searchNodes(query: eventTitle)
            .prefix(6)
            .map { $0 }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search results dropdown (above the input)
            if showSearchResults && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Link existing event")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("⌘⏎ to link  •  ⏎ to add new")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    
                    ForEach(searchResults) { result in
                        Button {
                            addReference(result)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                                
                                Text(result.title)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(result.state.displayName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.accentColor.opacity(0.04))
                    }
                }
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            
            Divider()
            
            HStack(spacing: 10) {
                // Input field
                TextField(
                    hasSelection ? "Add event or search to link..." : "Add top-level event...",
                    text: $eventTitle
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { addEvent() }
                .onChange(of: eventTitle) { _, newValue in
                    showSearchResults = hasSelection && newValue.count >= 2
                }
                
                // [+ Add]
                Button(action: addEvent) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(eventTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(hasSelection ? "Add as child of selected" : "Add at root level")
                
                // Hidden button for Cmd+Enter (Add Reference)
                Button(action: addReferenceShortcut) {
                    EmptyView()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.background)
    }
    
    // MARK: - Actions
    
    private func addEvent() {
        SoundManager.shared.playEnter()
        viewModel.addNode(title: eventTitle)
        eventTitle = ""
        showSearchResults = false
    }
    
    /// Handle Cmd+Enter shortcut.
    private func addReferenceShortcut() {
        // 1. If search results visible, pick top
        if showSearchResults, let first = searchResults.first {
            addReference(first)
            return
        }
        
        // 2. If exact match exists (even if not shown), pick it
        if let match = viewModel.searchNodes(query: eventTitle)
            .first(where: { $0.title.lowercased() == eventTitle.lowercased() }) {
            addReference(match)
            return
        }
        
        // 3. Otherwise... maybe nothing? User said "cmd+enter link", implies linking.
        // If no match, we can't link.
    }
    
    /// Add a reference to an existing event as a blocking child.
    private func addReference(_ referencedNode: EventNode) {
        guard let parentID = viewModel.selectedNodeID else { return }
        SoundManager.shared.playEnter()
        viewModel.addTaskReference(to: parentID, targetNodeID: referencedNode.id)
        eventTitle = ""
        showSearchResults = false
    }
}
