//
//  FlowViewModelReferenceTests.swift
//  FlowTests
//
//  Created for testing reference syncing logic
//

import Testing
import Foundation
@testable import Flow

@MainActor
struct FlowViewModelReferenceTests {

    @Test func testSyncReferenceOnTargetCompletion() {
        let viewModel = FlowViewModel()
        
        // 1. Create a target task
        // We need to simulate the adding process to ensure anchors are generated
        viewModel.addNode(title: "Target Task")
        let target = viewModel.nodes.last!
        
        // 2. Create a reference to it
        // We'll use the ViewModel method to ensure it's set up correctly
        viewModel.addNode(title: "Container for Ref")
        let container = viewModel.nodes.last!
        
        viewModel.addTaskReference(to: container.id, referencedTitle: "Target Task")
        
        // Reload nodes to get the updated tree (addTaskReference saves and reloads? No, it mutates and saves)
        // But we need to get the refreshed objects to be sure
        // Actually local `nodes` array is updated in place by mutateNode
        
        // Find the reference node
        guard let containerNode = viewModel.nodes.first(where: { $0.id == container.id }),
              let refNode = containerNode.children.first(where: { $0.tags.contains("ref") }) else {
            #expect(Bool(false), "Reference node not created properly")
            return
        }
        
        // 3. Complete the TARGET task
        // We assume we know the target's ID.
        // But wait, `addTaskReference` might have mutated the target to add an anchorID.
        // We need to find the target again.
        guard let targetNode = viewModel.nodes.first(where: { $0.title == "Target Task" }) else {
             #expect(Bool(false), "Target node lost?")
             return
        }
        
        // Check initial state
        #expect(targetNode.isChecked == false)
        #expect(refNode.isChecked == false)
        
        // Toggle Target
        viewModel.toggleNode(targetNode.id)
        
        // 4. Verify Reference is also completed
        // We need to fetch the fresh reference node from the viewModel
        let freshContainer = viewModel.nodes.first(where: { $0.id == container.id })!
        let freshRef = freshContainer.children.first!
        
        #expect(freshRef.isChecked == true, "Reference node should check 'true' after target is checked")
        
        // 5. Uncheck Target
        viewModel.toggleNode(targetNode.id)
        
        let freshContainer2 = viewModel.nodes.first(where: { $0.id == container.id })!
        let freshRef2 = freshContainer2.children.first!
        
        #expect(freshRef2.isChecked == false, "Reference node should check 'false' after target is unchecked")
    }
}
