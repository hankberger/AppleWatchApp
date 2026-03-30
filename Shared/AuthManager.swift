import AuthenticationServices
import SwiftUI

@MainActor
class AuthManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var appleUserId: String?
    @Published var showSignIn = false

    private let deviceIdKey = "device_id"
    private let appleUserIdKey = "apple_user_id"
    private let recordingCountKey = "recording_count"

    var deviceId: String {
        if let existing = KeychainHelper.read(key: deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        KeychainHelper.save(key: deviceIdKey, value: newId)
        return newId
    }

    /// The ID used for uploads — Apple user ID if signed in, otherwise device ID
    var userId: String {
        appleUserId ?? deviceId
    }

    var recordingCount: Int {
        UserDefaults.standard.integer(forKey: recordingCountKey)
    }

    var shouldPromptSignIn: Bool {
        !isSignedIn && recordingCount >= 3
    }

    init() {
        if let storedAppleId = KeychainHelper.read(key: appleUserIdKey) {
            appleUserId = storedAppleId
            isSignedIn = true
        }
    }

    func incrementRecordingCount() {
        let count = recordingCount + 1
        UserDefaults.standard.set(count, forKey: recordingCountKey)
    }

    func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                return
            }
            let newAppleUserId = credential.user
            let oldDeviceId = deviceId

            KeychainHelper.save(key: appleUserIdKey, value: newAppleUserId)
            appleUserId = newAppleUserId
            isSignedIn = true

            linkAccount(oldDeviceId: oldDeviceId, newUserId: newAppleUserId)

        case .failure(let error):
            print("Sign in with Apple failed: \(error)")
        }
    }

    private func linkAccount(oldDeviceId: String, newUserId: String) {
        guard let url = URL(string: "https://firstwatch-backend.hanksberger.workers.dev/link-account") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "oldUserId": oldDeviceId,
            "newUserId": newUserId,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to link account: \(error)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Account linked successfully")
            }
        }.resume()
    }
}
