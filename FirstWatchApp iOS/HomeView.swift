import AuthenticationServices
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var recordings: [Recording] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading recordings...")
                } else if recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "waveform",
                        description: Text("Record audio on your Apple Watch to see it here.")
                    )
                } else {
                    List(recordings) { recording in
                        RecordingRow(recording: recording)
                    }
                }
            }
            .navigationTitle("FirstWatch")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if authManager.isSignedIn {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            authManager.showSignIn = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadRecordings() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $authManager.showSignIn) {
                SignInView(authManager: authManager)
            }
            .task {
                await loadRecordings()
            }
        }
    }

    private func loadRecordings() async {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "https://firstwatch-backend.hanksberger.workers.dev/recordings?userId=\(authManager.userId)") else {
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(RecordingsResponse.self, from: data)
            recordings = decoded.recordings
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.displayName)
                    .font(.body)
                Text(recording.uploadedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(recording.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SignInView: View {
    @ObservedObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Save Your Recordings")
                    .font(.title2.bold())

                Text("Sign in to keep your recordings safe across devices and never lose your data.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = []
                } onCompletion: { result in
                    authManager.handleSignIn(result: result)
                    authManager.showSignIn = false
                }
                .frame(height: 50)
                .padding(.horizontal, 40)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authManager.showSignIn = false
                    }
                }
            }
        }
    }
}
