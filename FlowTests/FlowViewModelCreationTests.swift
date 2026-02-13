//
//  FlowViewModelCreationTests.swift
//  FlowTests
//
//  Created for testing task creation and renaming logic, specifically tag handling.
//

import Testing
import Foundation
@testable import Flow

@MainActor
struct FlowViewModelCreationTests {

    @Test func testAddNormalTask() {
        let viewModel = FlowViewModel()
        viewModel.nodes = [] // Reset
        
        viewModel.addNode(title: "Buy Milk")
        
        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.nodes[0].title == "Buy Milk")
        #expect(viewModel.nodes[0].tags.isEmpty)
    }

    @Test func testAddTaskWithTags() {
        let viewModel = FlowViewModel()
        viewModel.nodes = []
        
        viewModel.addNode(title: "Buy Milk #urgent")
        
        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.nodes[0].title == "Buy Milk")
        #expect(viewModel.nodes[0].tags == ["urgent"])
    }

    @Test func testAddTaskWithOnlyTags() {
        let viewModel = FlowViewModel()
        viewModel.nodes = []
        
        // This was the bug: previously this would result in empty title and be discarded
        viewModel.addNode(title: "#urgent")
        
        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.nodes[0].title == "#urgent")
        #expect(viewModel.nodes[0].tags == ["urgent"])
    }
    
    @Test func testAddTaskWithOnlyWaitTag() {
        let viewModel = FlowViewModel()
        viewModel.nodes = []
        
        viewModel.addNode(title: "#wait")
        
        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.nodes[0].title == "#wait")
        #expect(viewModel.nodes[0].tags == ["wait"])
    }

    @Test func testAddTaskWithMultipleTags() {
        let viewModel = FlowViewModel()
        viewModel.nodes = []
        
        viewModel.addNode(title: "#urgent #home")
        
        #expect(viewModel.nodes.count == 1)
        #expect(viewModel.nodes[0].title == "#urgent #home")
        #expect(viewModel.nodes[0].tags.sorted() == ["home", "urgent"])
    }
    
    @Test func testRenameNodeWithOnlyTags() {
        let viewModel = FlowViewModel()
        let node = EventNode(title: "Old Title")
        viewModel.nodes = [node]
        
        viewModel.renameNode(node.id, newTitle: "#done")
        
        #expect(viewModel.nodes[0].title == "#done")
        #expect(viewModel.nodes[0].tags.contains("done"))
    }
}
