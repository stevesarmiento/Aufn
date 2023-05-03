//
//  AufnApp.swift
//  Aufn
//
//  Created by Steven Sarmiento on 5/3/23.
//

import SwiftUI

@main
struct AufnApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appSettings)
        }
    }
}
