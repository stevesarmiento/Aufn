//
//  EditbaleText.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/27/23.
//

import Foundation
import SwiftUI

struct EditableText: View {
    @Binding var text: String
    @State private var isEditing = false

    var body: some View {
        if isEditing {
            TextField("", text: $text, onCommit: {
                isEditing = false
            })
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.leading)
            .padding(.trailing)
        } else {
            Text(text)
                .onTapGesture {
                    isEditing = true
                }
        }
    }
}
