import Foundation

protocol AnimationExporter {
    func export(_ recording: HandMotionRecording) throws -> URL
}

struct JSONHandMotionExporter: AnimationExporter {
    func export(_ recording: HandMotionRecording) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "LPVT-HandMotion-\(timestamp).lpvt-handmotion.json"
        let url = documents.appendingPathComponent(filename)
        let data = try HandMotionCompactCodec.exportData(from: recording)
        try data.write(to: url, options: .atomic)
        return url
    }
}
