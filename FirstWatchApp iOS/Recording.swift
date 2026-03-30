import Foundation

struct Recording: Identifiable, Codable {
    let key: String
    let size: Int
    let uploadedAt: Date

    var id: String { key }

    var displayName: String {
        // Extract recording ID from key like "userId/recordingId/audio.m4a"
        let parts = key.split(separator: "/")
        if parts.count >= 2 {
            return "Recording \(parts[1].prefix(8))..."
        }
        return key
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

struct RecordingsResponse: Codable {
    let recordings: [Recording]
}
