import Foundation

// REQ-PRS: 9.1 presets / 10.3 PresetContext
public struct PresetContext: Equatable, Sendable, Codable {
    public var presets: [Preset]
    public var activePresetId: String

    public init(presets: [Preset], activePresetId: String) {
        self.presets = presets
        self.activePresetId = activePresetId
    }

    // REQ-PRS-010: on first launch, create the standard preset only, and make it the active one.
    public static func initial() -> PresetContext {
        let standard = Preset.standard()
        return PresetContext(presets: [standard], activePresetId: standard.id)
    }

    public var activePreset: Preset? {
        preset(id: activePresetId)
    }

    public func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    // REQ-PRS-005: duplicates are judged after trimming, NFKC normalisation, and case folding.
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }

    func hasNameConflict(_ name: String, excluding excludedId: String? = nil) -> Bool {
        let normalized = Self.normalizedName(name)
        return presets.contains { $0.id != excludedId && Self.normalizedName($0.name) == normalized }
    }
}
