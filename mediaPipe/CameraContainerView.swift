//
//  CameraContainerView.swift
//  mediaPipe
//
//  Created by Asif Karim on 30/7/25.
//


import SwiftUI
import UIKit

struct CameraContainerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}
