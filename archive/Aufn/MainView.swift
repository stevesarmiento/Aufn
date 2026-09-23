//
//  MainView.swift
//  Aufn
//
//  Created by Steven Sarmiento on 4/25/23.
//

import SwiftUI

struct MainView: View {
    @State private var selectedView = 0
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        TabView(selection: $selectedView) {
            RecordingView(appSettings: appSettings)
                .tag(0)
            PlaybackView()
                .tag(1)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .edgesIgnoringSafeArea(.all)
    }
}

