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
        viewModel.sections = [Section()]
        viewModel.selectedSectionIndex = 0
        
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
    
    @Test func testDeletingTargetRemovesAllReferences() {
        let viewModel = FlowViewModel()
        viewModel.sections = [Section()]
        viewModel.selectedSectionIndex = 0
        
        viewModel.addNode(title: "Target Task")
        guard let target = viewModel.nodes.first(where: { $0.title == "Target Task" }) else {
            #expect(Bool(false), "Failed to create target")
            return
        }
        
        viewModel.addNode(title: "Container A")
        guard let containerA = viewModel.nodes.first(where: { $0.title == "Container A" }) else {
            #expect(Bool(false), "Failed to create container A")
            return
        }
        
        viewModel.addNode(title: "Container B")
        guard let containerB = viewModel.nodes.first(where: { $0.title == "Container B" }) else {
            #expect(Bool(false), "Failed to create container B")
            return
        }
        
        viewModel.addTaskReference(to: containerA.id, referencedTitle: "Target Task")
        viewModel.addTaskReference(to: containerB.id, referencedTitle: "Target Task")
        
        viewModel.deleteNode(target.id)
        
        #expect(viewModel.nodes.first(where: { $0.id == target.id }) == nil)
        
        let freshA = viewModel.nodes.first(where: { $0.id == containerA.id })
        let freshB = viewModel.nodes.first(where: { $0.id == containerB.id })
        
        #expect(freshA?.children.isEmpty == true, "References to deleted target should be removed")
        #expect(freshB?.children.isEmpty == true, "References to deleted target should be removed")
    }
    
    @Test func testDeletingLastReferenceClearsTargetAnchor() {
        let viewModel = FlowViewModel()
        viewModel.sections = [Section()]
        viewModel.selectedSectionIndex = 0
        
        viewModel.addNode(title: "Target Task")
        viewModel.addNode(title: "Container")
        
        guard let target = viewModel.nodes.first(where: { $0.title == "Target Task" }),
              let container = viewModel.nodes.first(where: { $0.title == "Container" }) else {
            #expect(Bool(false), "Setup failed")
            return
        }
        
        viewModel.addTaskReference(to: container.id, referencedTitle: "Target Task")
        
        guard let refNode = viewModel.nodes
            .first(where: { $0.id == container.id })?
            .children
            .first(where: { $0.referenceID != nil }) else {
            #expect(Bool(false), "Reference not created")
            return
        }
        
        let targetWithAnchor = viewModel.nodes.first(where: { $0.id == target.id })
        #expect(targetWithAnchor?.anchorID != nil, "Target should have anchor while reference exists")
        
        viewModel.deleteNode(refNode.id)
        
        let freshTarget = viewModel.nodes.first(where: { $0.id == target.id })
        #expect(freshTarget?.anchorID == nil, "Target anchor should clear after last reference is deleted")
    }
    
    @Test func testDeletingOneReferenceKeepsAnchorIfAnotherReferenceExists() {
        let viewModel = FlowViewModel()
        viewModel.sections = [Section()]
        viewModel.selectedSectionIndex = 0
        
        viewModel.addNode(title: "Target Task")
        viewModel.addNode(title: "Container A")
        viewModel.addNode(title: "Container B")
        
        guard let target = viewModel.nodes.first(where: { $0.title == "Target Task" }),
              let containerA = viewModel.nodes.first(where: { $0.title == "Container A" }),
              let containerB = viewModel.nodes.first(where: { $0.title == "Container B" }) else {
            #expect(Bool(false), "Setup failed")
            return
        }
        
        viewModel.addTaskReference(to: containerA.id, referencedTitle: "Target Task")
        viewModel.addTaskReference(to: containerB.id, referencedTitle: "Target Task")
        
        guard let refA = viewModel.nodes
            .first(where: { $0.id == containerA.id })?
            .children
            .first(where: { $0.referenceID != nil }) else {
            #expect(Bool(false), "Reference A not created")
            return
        }
        
        let anchorBeforeDelete = viewModel.nodes.first(where: { $0.id == target.id })?.anchorID
        #expect(anchorBeforeDelete != nil, "Target should have anchor while references exist")
        
        viewModel.deleteNode(refA.id)
        
        let freshTarget = viewModel.nodes.first(where: { $0.id == target.id })
        #expect(freshTarget?.anchorID == anchorBeforeDelete, "Anchor should remain while another reference exists")
        
        let freshContainerB = viewModel.nodes.first(where: { $0.id == containerB.id })
        #expect(freshContainerB?.children.first?.referenceID == anchorBeforeDelete)
    }
    
    @Test func testJumpToTargetAcrossSectionsSelectsTargetSection() {
        let viewModel = FlowViewModel()
        viewModel.sections = [Section(name: "A"), Section(name: "B")]
        
        viewModel.selectedSectionIndex = 0
        viewModel.addNode(title: "Container")
        guard let container = viewModel.nodes.first else {
            #expect(Bool(false), "Container missing")
            return
        }
        
        viewModel.selectedSectionIndex = 1
        viewModel.addNode(title: "Cross-Section Target")
        guard let target = viewModel.nodes.first else {
            #expect(Bool(false), "Target missing")
            return
        }
        
        viewModel.selectedSectionIndex = 0
        viewModel.addTaskReference(to: container.id, targetNodeID: target.id)
        
        guard let refNodeID = viewModel.nodes.first(where: { $0.id == container.id })?
            .children
            .first?
            .id else {
            #expect(Bool(false), "Reference not created")
            return
        }
        
        viewModel.jumpToTarget(from: refNodeID)
        
        #expect(viewModel.selectedSectionIndex == 1)
        #expect(viewModel.selectedNodeID == target.id)
    }
    
    @Test func testAddReferenceByIDAvoidsDuplicateTitleMismatch() {
        let viewModel = FlowViewModel()
        viewModel.sections = [Section(name: "A"), Section(name: "B")]
        
        viewModel.selectedSectionIndex = 0
        viewModel.addNode(title: "Shared Target")
        viewModel.addNode(title: "Container")
        guard let firstTarget = viewModel.nodes.first(where: { $0.title == "Shared Target" }),
              let container = viewModel.nodes.first(where: { $0.title == "Container" }) else {
            #expect(Bool(false), "Section A setup failed")
            return
        }
        
        viewModel.selectedSectionIndex = 1
        viewModel.addNode(title: "Shared Target")
        guard let secondTarget = viewModel.nodes.first(where: { $0.title == "Shared Target" }) else {
            #expect(Bool(false), "Section B setup failed")
            return
        }
        
        viewModel.addTaskReference(to: container.id, targetNodeID: secondTarget.id)
        
        viewModel.selectedSectionIndex = 0
        guard let reference = viewModel.nodes.first(where: { $0.id == container.id })?
            .children
            .first else {
            #expect(Bool(false), "Reference missing")
            return
        }
        
        viewModel.selectedSectionIndex = 1
        let refreshedSecondTarget = viewModel.nodes.first(where: { $0.id == secondTarget.id })
        let secondAnchor = refreshedSecondTarget?.anchorID
        
        #expect(secondAnchor != nil, "Chosen target should receive anchor")
        #expect(reference.referenceID == secondAnchor, "Reference should point to chosen target ID, not first title match")
        
        viewModel.selectedSectionIndex = 0
        let refreshedFirstTarget = viewModel.nodes.first(where: { $0.id == firstTarget.id })
        #expect(refreshedFirstTarget?.anchorID == nil, "Unchosen duplicate-title target should remain untouched")
    }
    
    @Test func testSearchNodesExcludesReferences() {
        let viewModel = FlowViewModel()
        viewModel.sections = [Section()]
        viewModel.selectedSectionIndex = 0
        
        viewModel.addNode(title: "Target Task")
        viewModel.addNode(title: "Container")
        
        guard let target = viewModel.nodes.first(where: { $0.title == "Target Task" }),
              let container = viewModel.nodes.first(where: { $0.title == "Container" }) else {
            #expect(Bool(false), "Setup failed")
            return
        }
        
        viewModel.addTaskReference(to: container.id, targetNodeID: target.id)
        
        let results = viewModel.searchNodes(query: "Target")
        #expect(results.allSatisfy { !$0.isReference })
    }
}
