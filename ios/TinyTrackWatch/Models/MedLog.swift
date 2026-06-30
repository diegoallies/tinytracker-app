import Foundation

/// A record that a medicine was given. Mirrors the phone's med-administration record.
struct MedLog: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var givenAt: Date

    init(id: String = UUID().uuidString, name: String, givenAt: Date = Date()) {
        self.id = id
        self.name = name
        self.givenAt = givenAt
    }
}

// NOTE: scheduled meds arrive from the phone as a plain `[String]` of names
// (`"scheduledMeds": ["Panado", "Vitamin D"]`), handled in `ConnectivityService`.
// No dedicated model is needed for them.
