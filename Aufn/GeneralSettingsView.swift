//
//  GeneralSettingsView.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/28/23.
//
import Foundation
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.dismiss) var dismiss

    
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Text("General Settings")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()

                // Credits and links
                VStack {
                    HStack(alignment: .top) {
                        Image("AppIcon")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .padding()

                        VStack(alignment: .leading, spacing: 5) {
                            Text("The quickest way to ship a sound. Record, share, delete.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Aufn is open-source", action: {
                                // Open the GitHub repository URL
                            })
                        }.padding(.horizontal)
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                
                // App Icon link
                NavigationLink(destination: IconSelectionView()) {
                    HStack {
                        Image(systemName: "app.fill") // Placeholder image
                            .foregroundColor(.blue)
                            .font(.system(size: 20))
                            .padding(.trailing, 8)
                        Text("Choose your vibe")
                            .font(.headline)
                            .foregroundColor(Color(.label))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(Color(.systemGray4))
                            .font(Font.system(size: 14, weight: .medium))
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(16)
                }
                .padding(.horizontal)
               
                Text("Aufn was built by the power of AI, GPT4 and GPT3.5 - We are all just prompt developers now. You can be the cash (AI), i'll be the rubberband (Human)")
                   .font(.subheadline)
                   .foregroundColor(.gray)
                   .multilineTextAlignment(.leading)
                   .padding(.top)
                   .padding(.horizontal)

                // Subscription CTA
                VStack {
                    HStack {
                        Image(systemName: "star.fill") // Placeholder image
                            .foregroundColor(.yellow)
                            .font(.system(size: 20))
                            .padding(.trailing, 8)
                        Text("Subscribe")
                            .font(.headline)
                            .foregroundColor(Color(.label))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(Color(.systemGray4))
                            .font(Font.system(size: 14, weight: .medium))
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                
                // Permissions
                NavigationLink(destination: PermissionsView()) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                            .padding(.trailing, 8)
                        Text("Permissions")
                            .font(.headline)
                            .foregroundColor(Color(.label))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(Color(.systemGray4))
                            .font(Font.system(size: 14, weight: .medium))
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(16)
                }
                .padding(.horizontal)
            
                Spacer()
                
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(.systemGray4))
                    }
                }
            }
        }
    }
}


//icon selection
struct IconSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appIcon") var appIcon: String = "default"

    let appIcons = ["Aufn", "Minimo", "1975", "A"]

    var body: some View {
        VStack {
            HStack {
                Text("App Icon")
                    .font(.headline)
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding()

            HStack {
                ForEach(appIcons, id: \.self) { iconName in
                    VStack {
                        Image(iconName)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .cornerRadius(12)
                            .onTapGesture {
                                appIcon = iconName
                                UIApplication.shared.setAlternateIconName(iconName == "default" ? nil : iconName) { error in
                                    if let error = error {
                                        print("Error changing app icon: \(error)")
                                    } else {
                                        print("App icon changed to \(iconName)")
                                    }
                                }
                                dismiss()
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(appIcon == iconName ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        Text(iconName.capitalized)
                    }
                    .padding(.horizontal)
                }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("App Icon")
    }
}

//Permission selection
struct PermissionsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appIcon") var appIcon: String = "default"
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: .constant(true)) {
                Label("Allow Access to Microphone", systemImage: "mic")
            }
        }
        .padding(.horizontal)
    }

}
