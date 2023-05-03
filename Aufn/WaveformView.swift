//
//  WaveformView.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/25/23.
//

import Foundation
import SwiftUI

struct WaveformView: View {
    @Binding var audioLevels: [CGFloat]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width / CGFloat(audioLevels.count)
                for (index, level) in audioLevels.enumerated() {
                    let x = CGFloat(index) * width
                    let y = geometry.size.height * (1 - level)
                    path.addRect(CGRect(x: x, y: y, width: width, height: level * geometry.size.height))
                }
            }
            .fill(Color.blue)
        }
    }
}
