//
//  FlowViewModelTests.swift
//  FlowTests
//
//  Created for testing specific ViewModel logic
//

import Testing
import Foundation
@testable import Flow

@MainActor
struct FlowViewModelTests {

    @Test func testWaitingCountExcludesRefs() {
        let viewModel = FlowViewModel()
        
        // 1. Create a task that IS waiting (valid blocker)
        // Nested: Root -> Active -> Waiting
        let waitingNode = EventNode(title: "Blocking event", tags: ["wait"])
        let activeNode = EventNode(title: "Active task", children: [waitingNode])
        
        // 2. Create a task that is a REFERENCE (should NOT count as waiting)
        // Nested: Root -> Task 2 -> Ref (ref to blocking event)
        // Note: references have "ref" tag. Even if they point to a waiting node, 
        // the reference ITSELF should not double-count to the global "Waiting" metric.
        let refNode = EventNode(title: "Ref to blocking", tags: ["ref", "wait"]) // Refs inherit wait state in UI but shouldn't count? 
        // Actually, looking at EventNode.swift:
        // if tags.contains("ref") { return .waiting }
        // So a ref node returns .waiting state.
        // We want to exclude it from the COUNT.
        
        let task2 = EventNode(title: "Task 2", children: [refNode])
        
        viewModel.nodes = [activeNode, task2]
        
        // Current behavior (Root level only? or Recursive?)
        // The existing count(for:) uses `nodes.filter`. `nodes` are just root nodes.
        // So existing logic:
        // activeNode.state -> .blocked (because child is waiting)
        // task2.state -> .blocked (because child ref is waiting)
        // So root level waiting count is 0.
        
        // BUT the user screenshot shows "Waiting 0". 
        // The user wants "Blocking event" (nested) to count as 1.
        // And "ref" (nested) to NOT count.
        
        // So we are changing `count(for: .waiting)` to be RECURSIVE.
        
        let waitingCount = viewModel.count(for: .waiting)
        
        // Expectation: 1 (The "Blocking event" node)
        // If we count refs, it would be 2.
        // If we only count roots, it would be 0.
        
        #expect(waitingCount == 1)
    }
    
    @Test func testFilePathsRespectDebugFlag() {
        let viewModel = FlowViewModel()
        let fileName = viewModel.fileURL.lastPathComponent
        
        #if DEBUG
        #expect(fileName == "flow_debug.md")
        // Check directory suffix (might be absolute path, so checking suffix is safer)
        // fileURL is .../Flow_Debug/flow_debug.md
        // storageDirectory is .../Flow_Debug
        #expect(viewModel.storageDirectory.hasSuffix("Flow_Debug"))
        #else
        #expect(fileName == "flow.md")
        #expect(viewModel.storageDirectory.hasSuffix("Flow"))
        #endif
    }
}
