//
//  ContentBlurView.swift
//  Aufn
//
//  Created by Steven Sarmiento on 1/26/24.
//

import SwiftUI
public struct ContentBlurView<Content:View>: View{
    
    @ViewBuilder var content: () -> Content
    @State private var direction : BlurDirection

    
    public init(direction: BlurDirection = .bottomBlur, content: @escaping () -> Content) {
        self.direction = direction
        self.content = content
    }
    
    public var body: some View {
        ZStack {
            
            content()

            Rectangle()
                .fill(Color.black)
                .background(Material.ultraThin)
                .mask {
                    LinearGradient(colors: [
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(0),
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(0.2),
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(0.4),
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(0.6),
                        //Color(red: 0.141, green: 0.141, blue: 0.141).opacity(0.5),
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(0.8),
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(1),
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(1),
                        Color(red: 0.141, green: 0.141, blue: 0.141).opacity(1),
                    ],
                                   startPoint: direction.start,
                                   endPoint: direction.end)
                }
        }
    }
}


public enum BlurDirection {
    case bottomBlur, topBlur, leadingBlur, trailingBlur
    
    var start: UnitPoint {
        switch self {
        case .bottomBlur:
                .top
        case .topBlur:
                .bottom
        case .leadingBlur:
                .trailing
        case .trailingBlur:
                .leading
        }
    }
    
    var end: UnitPoint {
        switch self {
        case .bottomBlur:
                .bottom
        case .topBlur:
                .top
        case .leadingBlur:
                .leading
        case .trailingBlur:
                .trailing
        }
    }
    
}

