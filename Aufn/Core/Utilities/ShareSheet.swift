//
//  ShareSheet.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/26/23.
//

import Foundation
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = context.coordinator.completionHandler
        print("Sharing items: \(items)") // Add this line to log the items being shared
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    class Coordinator: NSObject {
        var parent: ShareSheet

        init(_ parent: ShareSheet) {
            self.parent = parent
        }

        func completionHandler(activityType: UIActivity.ActivityType?, completed: Bool, items: [Any]?, error: Error?) {
            // You can add custom logic here if needed when the sharing is completed or canceled.
        }
    }
}
