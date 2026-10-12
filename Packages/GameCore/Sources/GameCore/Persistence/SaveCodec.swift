import Foundation

/// Encodes and decodes saved blobs. A damaged or unreadable blob falls back to a fresh value
/// instead of crashing; newer schema versions than this build knows are also treated as fresh.
public enum SaveCodec {
    public static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    public static func loadProgress(from data: Data?) -> PlayerProgress {
        guard let progress = decode(PlayerProgress.self, from: data),
              progress.schemaVersion <= PlayerProgress.currentSchema else {
            return PlayerProgress()
        }
        return progress
    }

    public static func loadSettings(from data: Data?) -> GameSettings {
        decode(GameSettings.self, from: data) ?? GameSettings()
    }
}
