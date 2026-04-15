import Foundation

enum AwayVoiceMode: String, Codable, CaseIterable, Identifiable {
    case supportive

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .supportive:
            return "Supportive"
        }
    }

    var description: String {
        switch self {
        case .supportive:
            return "Clear reminders that pull you back into the block."
        }
    }

    var utterances: [String] {
        switch self {
        case .supportive:
            return [
                "Get back to your task.",
                "You're away. Get back in frame.",
                "Stay with this block.",
                "Done in 5 only works if you stay with the task."
            ]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? AwayVoiceMode.supportive.rawValue
        self = AwayVoiceMode(rawValue: rawValue) ?? .supportive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
