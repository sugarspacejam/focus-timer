import Foundation

struct FocusTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var isFinished: Bool
}
