import Foundation

enum AwayVoiceMode: String, Codable, CaseIterable, Identifiable {
    case supportive
    case strict

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .supportive:
            return "Supportive"
        case .strict:
            return "Strict"
        }
    }

    var description: String {
        switch self {
        case .supportive:
            return "Clear reminders that pull you back into the block."
        case .strict:
            return "Sharper accountability lines that make the contract feel heavier."
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
        case .strict:
            return [
                "You're drifting. Back to work.",
                "This block is still live. Get back in frame.",
                "Leave again and this contract fails.",
                "You started this. Stay with it until the timer ends."
            ]
        }
    }
}
