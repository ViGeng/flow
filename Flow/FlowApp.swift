//
//  FlowApp.swift
//  Flow
//

import SwiftUI

@main
struct FlowApp: App {
    @State private var viewModel = FlowViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 800, height: 600)
    }
}
