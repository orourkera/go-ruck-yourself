//
//  GRYApp.swift
//  GRY Watch App
//
//  Created by Rory on 6/5/25.
//

import SwiftUI

@main
struct GRY_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(watchOS)
            ContentView()
            #else
            Text("Not a watchOS build")
            #endif
        }
    }
}
