import Foundation
import VideoKit

/// Adaptador de `VideoKit.CameraProviding` (en Windows `MediaFoundationCameraProvider`) al `SettingsCameraProviding` de Ajustes
/// (W2-C; W2-A lo definió sin depender de VideoKit). Portátil: en el Mac se prueba con cualquier `CameraProviding`.
public final class VideoKitCameraAdapter: SettingsCameraProviding, @unchecked Sendable {
    private let base: any CameraProviding

    public init(_ base: any CameraProviding) { self.base = base }

    public func cameras() -> [SettingsCamera] { base.cameras().map(Self.convert) }

    public func defaultCamera() -> SettingsCamera? { base.defaultCamera().map(Self.convert) }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) { base.setChangeHandler(handler) }

    static func convert(_ c: CameraDevice) -> SettingsCamera {
        SettingsCamera(id: c.id, name: c.name, kind: c.kind.rawValue, formats: c.formats.map { f in
            SettingsCameraFormat(width: f.width, height: f.height,
                                 frameRates: f.frameRates.map { SettingsFrameRange(min: $0.min, max: $0.max) })
        })
    }
}
