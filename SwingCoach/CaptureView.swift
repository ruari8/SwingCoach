//
//  CaptureView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI

struct CaptureView: View {
    var body: some View {
        VStack {
            Image(systemName: "camera")
            Text("Capture a new swing")
                .font(.title)
                .padding()
                .background(.yellow.opacity(0.2))
                .border(.blue, width: 2)
        }
    }
}

#Preview {
    CaptureView()
}
