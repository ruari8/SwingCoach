//
//  CaptureView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI
import AVKit
import Combine
import AVFoundation

final class CameraSession: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session.queue")
    private let movieOutput = AVCaptureMovieFileOutput()
    @Published var lastRecordingURL: URL?

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        session.commitConfiguration()
    }

    func start() {
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func startRecording() {
        queue.async {
            guard !self.movieOutput.isRecording else { return }
            let url = Self.tempURL()
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async {
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    private static func tempURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString + ".mov"
        return directory.appendingPathComponent(filename)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            guard error == nil else {
                self.lastRecordingURL = nil
                return
            }
            self.lastRecordingURL = outputFileURL
        }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) { }
}

struct CaptureView: View {
    @StateObject private var camera = CameraSession()
    @State private var isRecording = false
    @State private var player: AVPlayer?
    @State private var currentRecordingURL: URL?

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            if let player {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VideoPlayer(player: player)
                    .onTapGesture {
                        self.player = nil
                    }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            clearCurrentRecording()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }
                        .padding()
                    }
                    Spacer()
                }
            }

            if player == nil {
                VStack {
                    Spacer()
                    Button {
                        toggleRecording()
                    } label: {
                        Circle()
                            .fill(isRecording ? Color.red : Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                    }
                    .padding(.bottom, 24)
                }
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onReceive(camera.$lastRecordingURL) { url in
            guard let url else { return }
            player = AVPlayer(url: url)
            player?.play()
            currentRecordingURL = url
            isRecording = false
        }
    }

    private func toggleRecording() {
        if isRecording {
            camera.stopRecording()
        } else {
            player = nil
            camera.startRecording()
        }
        currentRecordingURL = nil
        isRecording.toggle()
    }

    private func clearCurrentRecording() {
        player?.pause()
        player = nil
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
        camera.lastRecordingURL = nil
    }
}

#Preview {
    CaptureView()
}

