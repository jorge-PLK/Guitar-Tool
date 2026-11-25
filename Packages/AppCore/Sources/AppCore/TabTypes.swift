import Foundation
import TabKit

// Tipos JSON de `tab.*` (parte 8.7). Contrato: `Temp/win/step8-contract.md`, «8.7 Tablatura».

struct TabTuningInfo: Codable, Sendable, Equatable {
    var preset: String
    var name: String
    var strings: [Int]
}

struct TabTrackInfo: Codable, Sendable {
    var id: String
    var name: String
    var kind: String
    var tuning: TabTuningInfo?
    var customTuning: TabTuningInfo?
    var origin: String
    var playerTrack: String?
    /// ready | queued | transcribing | missing | failed
    var transcription: String
    var progress: Double?
    var error: String?
    var fingerprint: TrackSourceFingerprint?
    var noteCount: Int
    var muted: Bool
    var solo: Bool
    var dimmed: Bool
    var listening: Bool
    var synth: String?
}

struct TabSelectionInfo: Codable, Sendable {
    var track: String
    var beat: Int
    var tick: Int
    var string: Int?
    var summary: String?
    /// Compás de la selección (0-based) y su rango en segundos: lo usa el bucle «Compás N» (Mac `selectedBarRange`).
    var barRange: TabBarRange?
    /// Hay una nota bajo la selección (habilita «Añadir nota»/«–»/«+»/«Borrar» en la barra de edición).
    var hasNote: Bool
}

struct TabBarRange: Codable, Sendable {
    var bar: Int
    var start: Double
    var end: Double
}

struct TabSpanInfo: Codable, Sendable {
    var startTick: Int
    var endTick: Int
}

struct TabState: Codable, Sendable {
    var projectId: String
    var phase: String
    var error: String?
    var header: String?
    var source: String?
    var tracks: [TabTrackInfo]
    var selectedTrack: String?
    var notices: [String]
    var canUndo: Bool
    var canRedo: Bool
    var editMode: Bool
    var graceMode: Bool
    var listenMode: String
    var anySolo: Bool
    var selection: TabSelectionInfo?
    var span: TabSpanInfo?
    var revision: Int
    var flash: String?
    /// Solo `tab.edit {op:"key"}`: la tecla se usó (la página hace `preventDefault`).
    var handled: Bool?
}

struct TabScoreResult: Codable, Sendable {
    var json: String
    var trackIndex: Int
    var trackIDs: [String]
    var revision: Int
}

struct TabProgressEvent: Codable, Sendable {
    /// transcribing | done | failed | cancelled
    var state: String
    var track: String
    var fraction: Double
    var error: String?
}

struct TabSelectionEvent: Codable, Sendable { var bar: Int; var fraction: Double }
struct TabRangeEvent: Codable, Sendable {
    var startBar: Int
    var startFraction: Double
    var endBar: Int
    var endFraction: Double
}

struct TabQueuedResult: Codable, Sendable { var queued: [String] }
struct TabExportNameResult: Codable, Sendable { var fileName: String }
struct TabExportResult: Codable, Sendable {
    var saved: Bool
    var path: String?
}

struct TabOpenParams: Decodable, Sendable { var projectId: String }
struct TabTrackParams: Decodable, Sendable { var track: String? }
struct TabSourceParams: Decodable, Sendable { var source: String }
struct TabClickParams: Decodable, Sendable {
    var track: Int
    var bar: Int
    var beat: Int
    var shift: Bool?
    var string: Int?
}
struct TabSelectParams: Decodable, Sendable { var track: String; var beat: Int; var tick: Int; var string: Int? }
struct TabSpanParams: Decodable, Sendable { var action: String }
struct TabListeningParams: Decodable, Sendable { var track: String?; var on: Bool }
struct TabExportParams: Decodable, Sendable { var data: String; var path: String? }
struct TabEditParams: Decodable, Sendable {
    var op: String
    var value: Int?
    var up: Bool?
    var sign: Int?
    var piece: String?
    var name: String?
    var key: String?
    var shift: Bool?
    var ctrl: Bool?
    var alt: Bool?
    var forward: Bool?
    var track: String?
    var preset: String?
    var on: Bool?
}
