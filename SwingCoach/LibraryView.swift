//
//  LibraryView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI

struct LibraryView: View {
    let onNavigateToCapture: () -> Void
    
    var body: some View {
        VStack {
            Image(systemName: "film")
            Text("Library")
            Button("Open a Camera Tab") {
                onNavigateToCapture()
            }
            .padding(.top, 12)
        }
        .font(.title)
        .padding()
    }
}

#Preview {
    LibraryView(onNavigateToCapture: {})
}
