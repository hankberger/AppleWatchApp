//
//  ContentView.swift
//  FirstWatchApp Watch App
//
//  Created by Hank Berger on 3/29/26.
//

import AuthenticationServices
import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingURL: URL?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isUploading = false
    @State private var uploadStatus: String?
    @State private var showSignInPrompt = false

    var body: some View {
        VStack(spacing: 16) {
            if isRecording {
                Text(timeString(from: elapsedTime))
                    .font(.title2)
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }

            Button(action: toggleRecording) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(isRecording ? .red : .green)
            }
            .buttonStyle(.plain)
            .disabled(isUploading)

            if isUploading {
                ProgressView()
                Text("Uploading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let status = uploadStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.starts(with: "Upload") ? .green : .red)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            uploadStatus = nil
                        }
                    }
            } else {
                Text(isRecording ? "Recording..." : "Tap to Record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .sheet(isPresented: $showSignInPrompt) {
            SignInPromptView(authManager: authManager, isPresented: $showSignInPrompt)
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }

        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
            elapsedTime = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                elapsedTime += 1
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        timer?.invalidate()
        timer = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }

        if let url = recordingURL {
            uploadRecording(fileURL: url)
        }
    }

    private func uploadRecording(fileURL: URL) {
        guard let audioData = try? Data(contentsOf: fileURL) else {
            uploadStatus = "Failed to read file"
            return
        }

        isUploading = true
        uploadStatus = nil

        var request = URLRequest(url: URL(string: "https://firstwatch-backend.hanksberger.workers.dev/upload")!)
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")
        request.setValue(authManager.userId, forHTTPHeaderField: "X-User-ID")
        request.httpBody = audioData

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isUploading = false

                if let error = error {
                    uploadStatus = "Error: \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    uploadStatus = "Invalid response"
                    return
                }

                if httpResponse.statusCode == 201 {
                    uploadStatus = "Uploaded!"
                    try? FileManager.default.removeItem(at: fileURL)
                    authManager.incrementRecordingCount()

                    if authManager.shouldPromptSignIn {
                        showSignInPrompt = true
                    }
                } else {
                    uploadStatus = "Failed (\(httpResponse.statusCode))"
                }
            }
        }.resume()
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct SignInPromptView: View {
    @ObservedObject var authManager: AuthManager
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                Text("Save Your Recordings")
                    .font(.headline)

                Text("Sign in to keep your recordings safe across devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = []
                } onCompletion: { result in
                    authManager.handleSignIn(result: result)
                    isPresented = false
                }
                .frame(height: 45)

                Button("Not Now") {
                    isPresented = false
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
