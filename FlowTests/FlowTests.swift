//
//  FlowTests.swift
//  FlowTests
//

import Testing
import Foundation
@testable import Flow

// MARK: - Parser Tests

struct MarkdownParserTests {
    
    @Test func parseActiveNode() throws {
        let markdown = "- [ ] Buy groceries\n"
        let nodes = MarkdownParser.parse(markdown)
        #expect(nodes.count == 1)
        #expect(nodes[0].title == "Buy groceries")
        #expect(nodes[0].isChecked == false)
        #expect(nodes[0].tags.isEmpty)
        #expect(nodes[0].children.isEmpty)
    }
    
    @Test func parseCompletedNode() throws {
        let markdown = "- [x] Buy groceries\n"
        let nodes = MarkdownParser.parse(markdown)
        #expect(nodes.count == 1)
        #expect(nodes[0].isChecked == true)
    }
    
    @Test func parseWaitingNode() throws {
        let markdown = "- [ ] Wait for reply #wait due:2026-03-15\n"
        let nodes = MarkdownParser.parse(markdown)
        #expect(nodes.count == 1)
        #expect(nodes[0].title == "Wait for reply")
        #expect(nodes[0].tags.contains("wait"))
        #expect(nodes[0].metadata["due"] == "2026-03-15")
    }
    
    @Test func parseNestedTree() throws {
        let markdown = """
        - [ ] Project A
            - [ ] Design
            - [x] Research
                - [ ] Read papers
            - [ ] Build prototype
        - [ ] Project B
        """
        let nodes = MarkdownParser.parse(markdown)
        #expect(nodes.count == 2)
        #expect(nodes[0].title == "Project A")
        #expect(nodes[0].children.count == 3)
        #expect(nodes[0].children[0].title == "Design")
        #expect(nodes[0].children[1].title == "Research")
        #expect(nodes[0].children[1].isChecked == true)
        #expect(nodes[0].children[1].children.count == 1)
        #expect(nodes[0].children[1].children[0].title == "Read papers")
        #expect(nodes[0].children[2].title == "Build prototype")
        #expect(nodes[1].title == "Project B")
        #expect(nodes[1].children.isEmpty)
    }
    
    @Test func parseSpecExample() throws {
        let markdown = """
        - [ ] Insurance Claim Project
            - [x] Step 1: Gather Receipts (Completed)
            - [ ] Step 2: Submit to Portal
            - [ ] Step 3: Wait for Approval Email #wait
            - [ ] Step 4: Confirm Bank Transfer
        """
        let nodes = MarkdownParser.parse(markdown)
        #expect(nodes.count == 1)
        #expect(nodes[0].children.count == 4)
        #expect(nodes[0].children[0].isChecked == true)
        #expect(nodes[0].children[2].tags.contains("wait"))
    }
    
    @Test func parseEmptyInput() throws {
        let nodes = MarkdownParser.parse("")
        #expect(nodes.isEmpty)
    }
    
    @Test func parseMultipleTags() throws {
        let markdown = "- [ ] Critical task #wait #urgent\n"
        let nodes = MarkdownParser.parse(markdown)
        #expect(nodes[0].tags.contains("wait"))
        #expect(nodes[0].tags.contains("urgent"))
        #expect(nodes[0].title == "Critical task")
    }
    
    @Test func serializeActiveNode() throws {
        let node = EventNode(title: "Buy groceries")
        let result = MarkdownParser.serialize([node])
        #expect(result == "- [ ] Buy groceries\n")
    }
    
    @Test func serializeCompletedNode() throws {
        let node = EventNode(title: "Buy groceries", isChecked: true)
        let result = MarkdownParser.serialize([node])
        #expect(result == "- [x] Buy groceries\n")
    }
    
    @Test func serializeWaitingNode() throws {
        let node = EventNode(title: "Wait for reply", tags: ["wait"], metadata: ["due": "2026-03-15"])
        let result = MarkdownParser.serialize([node])
        #expect(result == "- [ ] Wait for reply #wait due:2026-03-15\n")
    }
    
    @Test func serializeNestedTree() throws {
        let grandchild = EventNode(title: "Read papers")
        let child1 = EventNode(title: "Design")
        let child2 = EventNode(title: "Research", isChecked: true, children: [grandchild])
        let parent = EventNode(title: "Project A", children: [child1, child2])
        
        let result = MarkdownParser.serialize([parent])
        let lines = result.components(separatedBy: "\n")
        #expect(lines[0] == "- [ ] Project A")
        #expect(lines[1] == "    - [ ] Design")
        #expect(lines[2] == "    - [x] Research")
        #expect(lines[3] == "        - [ ] Read papers")
    }
    
    @Test func roundTripParseSerialization() throws {
        let grandchild = EventNode(title: "Read papers", tags: ["wait"])
        let child1 = EventNode(title: "Design")
        let child2 = EventNode(title: "Research", isChecked: true, children: [grandchild])
        let parent = EventNode(title: "Project", children: [child1, child2])
        let root2 = EventNode(title: "Other task")
        
        let serialized = MarkdownParser.serialize([parent, root2])
        let reparsed = MarkdownParser.parse(serialized)
        
        #expect(reparsed.count == 2)
        #expect(reparsed[0].title == "Project")
        #expect(reparsed[0].children.count == 2)
        #expect(reparsed[0].children[1].children.count == 1)
        #expect(reparsed[0].children[1].children[0].tags.contains("wait"))
        #expect(reparsed[1].title == "Other task")
    }
}

// MARK: - State Propagation Tests

struct EventStateTests {
    
    @Test func activeState() throws {
        let node = EventNode(title: "Do something")
        #expect(node.state == .active)
    }
    
    @Test func completedState() throws {
        let node = EventNode(title: "Done", isChecked: true)
        #expect(node.state == .completed)
    }
    
    @Test func waitingState() throws {
        let node = EventNode(title: "Wait", tags: ["wait"])
        #expect(node.state == .waiting)
    }
    
    @Test func blockedByChildWaiting() throws {
        let child = EventNode(title: "Wait for reply", tags: ["wait"])
        let parent = EventNode(title: "Project", children: [child])
        #expect(parent.state == .blocked)
        #expect(child.state == .waiting)
    }
    
    @Test func blockedByGrandchildWaiting() throws {
        // Grandchild is #wait → child is blocked → root is blocked
        let grandchild = EventNode(title: "Approval", tags: ["wait"])
        let child = EventNode(title: "Submit", children: [grandchild])
        let root = EventNode(title: "Insurance Claim", children: [child])
        
        #expect(grandchild.state == .waiting)
        #expect(child.state == .blocked)
        #expect(root.state == .blocked)
    }
    
    @Test func parentActiveWhenChildrenDone() throws {
        let child1 = EventNode(title: "A", isChecked: true)
        let child2 = EventNode(title: "B", isChecked: true)
        let parent = EventNode(title: "Project", children: [child1, child2])
        #expect(parent.state == .active) // All children done, parent is active
    }
    
    @Test func parentBlockedWhenAnyChildBlocked() throws {
        let grandchild = EventNode(title: "Wait", tags: ["wait"])
        let child1 = EventNode(title: "Blocked child", children: [grandchild])
        let child2 = EventNode(title: "Active child")
        let parent = EventNode(title: "Project", children: [child1, child2])
        
        #expect(parent.state == .blocked) // child1 is blocked → parent is blocked
    }
    
    @Test func completedOverridesChildren() throws {
        // If manually checked, state is completed regardless of children
        let child = EventNode(title: "Wait", tags: ["wait"])
        let parent = EventNode(title: "Done", isChecked: true, children: [child])
        #expect(parent.state == .completed)
    }
    
    @Test func childProgressComputation() throws {
        let child1 = EventNode(title: "A")
        let child2 = EventNode(title: "B", isChecked: true)
        let child3 = EventNode(title: "C", isChecked: true)
        let parent = EventNode(title: "Task", children: [child1, child2, child3])
        
        #expect(parent.childProgress! == 2.0 / 3.0)
        #expect(parent.childProgressText == "2/3 events")
    }
    
    @Test func noChildProgressWhenEmpty() throws {
        let node = EventNode(title: "Solo")
        #expect(node.childProgress == nil)
        #expect(node.childProgressText == nil)
    }
}
