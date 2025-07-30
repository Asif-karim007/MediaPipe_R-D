//
//  ContentView.swift
//  mediaPipe
//
//  Created by Asif Karim on 30/7/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedModel: Model = InferenceConfigurationManager.sharedInstance.model
    @State private var selectedDelegate: PoseLandmarkerDelegate = InferenceConfigurationManager.sharedInstance.delegate

    var body: some View {
        VStack(spacing: 0) {
            CameraContainerView()
                .frame(height: UIScreen.main.bounds.height * 0.7)
                .edgesIgnoringSafeArea(.top)

            VStack(spacing: 16) {
                Text("PoseLandmarker Settings")
                    .font(.headline)

                // Model Picker
                Picker("Model", selection: $selectedModel) {
                    ForEach(Model.allCases, id: \.self) { model in
                        Text(model.name).tag(model)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedModel) { newValue in
                    InferenceConfigurationManager.sharedInstance.model = newValue
                }

                // Delegate Picker
                Picker("Delegate", selection: $selectedDelegate) {
                    ForEach(PoseLandmarkerDelegate.allCases, id: \.self) { delegate in
                        Text(delegate.name).tag(delegate)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedDelegate) { newValue in
                    InferenceConfigurationManager.sharedInstance.delegate = newValue
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
        }
    }
}


