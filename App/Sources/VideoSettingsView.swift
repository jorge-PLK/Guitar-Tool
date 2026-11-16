import AppKit
import AVFoundation
import Observation
import Store
import SwiftUI
import VideoKit

/// Lista de cámaras del selector; se relee cuando el proveedor avisa de un cambio (sin sondeo). Solo escucha mientras
/// la pestaña está a la vista (`stop()` suelta el aviso para que otra pantalla pueda usar el suyo).
@MainActor @Observable
final class CameraList {
    private(set) var cameras: [CameraDevice] = []
    private(set) var systemDefault: CameraDevice?
    /// Nombres vistos en esta sesión, para seguir nombrando una cámara elegida que ya no está conectada.
    private(set) var names: [String: String] = [:]
    @ObservationIgnored private let provider: CameraProviding

    init(provider: CameraProviding) {
        self.provider = provider
        refresh()
        provider.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        cameras = provider.cameras()
        systemDefault = provider.defaultCamera()
        for c in cameras { names[c.id] = c.name }
    }

    func stop() { provider.setChangeHandler(nil) }

    /// La cámara que se usaría con esta elección del perfil (`nil` = la del sistema); nil si no está conectada.
    func effective(_ uid: String?) -> CameraDevice? {
        guard let uid else { return systemDefault }
        return cameras.first { $0.id == uid }
    }
}

/// Opciones de resolución y fps que ofrece una cámara (mini-spec Fase 6: «solo las que la cámara admite»).
enum CameraChoices {
    /// Resoluciones del producto (720p, 1080p, 4K) que la cámara admite; si no admite ninguna, las distintas que tenga.
    static let presets: [VideoResolution] = [.hd720, .fullHD, .uhd4K]
    /// Frecuencias habituales; se ofrecen las que caen dentro de algún rango del formato.
    static let commonFPS: [Double] = [24, 25, 30, 50, 60, 120]

    static func resolutions(of camera: CameraDevice?) -> [VideoResolution] {
        guard let camera else { return [] }
        let all = Set(camera.formats.map { VideoResolution(width: $0.width, height: $0.height) })
        let known = presets.filter(all.contains)
        return known.isEmpty ? all.sorted { $0.width * $0.height < $1.width * $1.height } : known
    }

    static func frameRates(of camera: CameraDevice?, at resolution: VideoResolution) -> [Double] {
        guard let camera else { return [] }
        let ranges = camera.formats.filter { $0.width == resolution.width && $0.height == resolution.height }.flatMap(\.frameRates)
        let fps = commonFPS.filter { f in ranges.contains { f >= $0.min - 1e-6 && f <= $0.max + 1e-6 } }
        return fps.isEmpty ? Array(Set(ranges.map(\.max))).sorted() : fps
    }

    static func label(_ r: VideoResolution) -> String {
        switch r {
        case .hd720: "720p"
        case .fullHD: "1080p"
        case .uhd4K: "4K"
        default: "\(r.width)×\(r.height)"
        }
    }

    static func label(fps: Double) -> String { "\(fps.formatted(.number.precision(.fractionLength(0...2)))) fps" }

    /// Lo que se enseña como elegido: el valor del perfil si la cámara lo admite; si no, lo más cercano que ofrece
    /// (el perfil no se toca hasta que el usuario elige).
    static func shown(_ r: VideoResolution, fps: Double, camera: CameraDevice?) -> (VideoResolution, Double)? {
        guard let camera, let match = camera.closestFormat(to: CameraRequest(width: r.width, height: r.height, fps: fps)) else { return nil }
        return (VideoResolution(width: match.format.width, height: match.format.height), match.fps)
    }
}

/// Vista previa en vivo de la cámara elegida. Arranca al entrar en la pestaña y para al salir; con cámara simulada
/// no abre nada y enseña un patrón.
@MainActor @Observable
final class CameraPreviewModel {
    enum State {
        case idle, noCamera, denied, simulated, failed(String)
        case live(AVCaptureSession)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var capture: AVCameraCapture?
    @ObservationIgnored private var generation = 0

    func start(camera: CameraDevice?, request: CameraRequest, simulated: Bool) {
        stop()
        generation += 1
        let mine = generation
        guard let camera else { state = .noCamera; return }
        if simulated { state = .simulated; return }
        Task {
            guard await AVCameraProvider.ensureAccess() else {
                if mine == generation { state = .denied }
                return
            }
            guard mine == generation else { return }
            let result = await Task.detached { () -> Result<AVCameraCapture, Error> in
                do {
                    let c = try AVCameraCapture(cameraID: camera.id)
                    _ = try c.start(request) { _ in }
                    return .success(c)
                } catch { return .failure(error) }
            }.value
            switch result {
            case .success(let c):
                if mine == generation { capture = c; state = .live(c.session) } else { Task.detached { c.stop() } }
            case .failure(let e):
                if mine == generation { state = .failed("No se pudo abrir la cámara (\(e)).") }
            }
        }
    }

    func stop() {
        generation += 1
        if let c = capture { Task.detached { c.stop() } }
        capture = nil
        state = .idle
    }
}

/// `AVCaptureVideoPreviewLayer` sobre la sesión de `AVCameraCapture`.
struct CameraPreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.frame = v.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer?.addSublayer(layer)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if let l = v.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer, l.session !== session { l.session = session }
    }
}

struct VideoSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var list: CameraList?
    @State private var preview = CameraPreviewModel()

    /// Rango del desfase por defecto (mini-spec Fase 6, «Ajustes · Cámara y vídeo»: ±500 ms).
    static let offsetRangeMs: ClosedRange<Double> = -500...500

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let list {
                cameraGroup(list)
                syncGroup(list)
                exportGroup
            }
        }
        .onAppear {
            if list == nil { list = CameraList(provider: model.cameraProvider) }
            list?.refresh()
            restartPreview()
        }
        .onDisappear {
            preview.stop()
            list?.stop()
            list = nil
        }
        // Cambia la cámara, la resolución, los fps o la lista conectada: la vista previa se rehace.
        .onChange(of: previewKey) { restartPreview() }
    }

    // MARK: Perfil

    private var video: VideoSettings { model.profile.video ?? VideoSettings() }

    private func update(_ change: (inout VideoSettings) -> Void) {
        var v = video
        change(&v)
        model.profile.video = v
        model.saveProfile()
    }

    private var previewKey: String {
        let v = video
        let ids = list?.cameras.map(\.id).joined(separator: ",") ?? ""
        return "\(v.cameraUID ?? "-")|\(v.resolution.width)x\(v.resolution.height)|\(v.fps)|\(ids)"
    }

    private func restartPreview() {
        guard let list else { return }
        let camera = list.effective(video.cameraUID)
        let shown = CameraChoices.shown(video.resolution, fps: video.fps, camera: camera)
        let r = shown?.0 ?? video.resolution
        preview.start(camera: camera, request: CameraRequest(width: r.width, height: r.height, fps: shown?.1 ?? video.fps),
                      simulated: !(model.cameraProvider is AVCameraProvider))
    }

    // MARK: Cámara

    private struct CameraOption { var uid: String; var label: String }

    private func cameraOptions(_ list: CameraList) -> [CameraOption] {
        var result = list.cameras.map { CameraOption(uid: $0.id, label: $0.name) }
        if let chosen = video.cameraUID, !list.cameras.contains(where: { $0.id == chosen }) {
            result.append(CameraOption(uid: chosen, label: "\(list.names[chosen] ?? "Cámara elegida") · desconectada"))
        }
        return result
    }

    private func cameraGroup(_ list: CameraList) -> some View {
        let camera = list.effective(video.cameraUID)
        let resolutions = CameraChoices.resolutions(of: camera)
        let shown = CameraChoices.shown(video.resolution, fps: video.fps, camera: camera)
        let fpsChoices = shown.map { CameraChoices.frameRates(of: camera, at: $0.0) } ?? []
        return SettingsGroup(title: "Cámara", note: "Webcam USB o iPhone con Continuity Camera.") {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 10) {
                    InfoRow(label: "Cámara") {
                        Picker("Cámara", selection: Binding(
                            get: { video.cameraUID }, set: { uid in update { $0.cameraUID = uid } })) {
                            Text("Por defecto del sistema").tag(String?.none)
                            ForEach(cameraOptions(list), id: \.uid) { Text($0.label).tag(String?.some($0.uid)) }
                        }
                        .labelsHidden().frame(maxWidth: 280)
                    }
                    InfoRow(label: "Resolución") {
                        Picker("Resolución", selection: Binding(
                            get: { shown?.0 ?? video.resolution }, set: { r in update { $0.resolution = r } })) {
                            ForEach(resolutions, id: \.self) { Text(CameraChoices.label($0)).tag($0) }
                        }
                        .labelsHidden().frame(maxWidth: 160)
                        .disabled(camera == nil)
                    }
                    InfoRow(label: "Fotogramas por segundo") {
                        Picker("Fotogramas por segundo", selection: Binding(
                            get: { shown?.1 ?? video.fps }, set: { f in update { $0.fps = f } })) {
                            ForEach(fpsChoices, id: \.self) { Text(CameraChoices.label(fps: $0)).tag($0) }
                        }
                        .labelsHidden().frame(maxWidth: 160)
                        .disabled(camera == nil)
                    }
                }
                .frame(maxWidth: .infinity)
                previewBox.frame(width: 240)
            }
        }
    }

    private var previewBox: some View {
        ZStack {
            Color.black
            switch preview.state {
            case .live(let session): CameraPreviewLayerView(session: session)
            case .simulated: ColorBars().overlay(alignment: .bottom) { caption("Vista previa simulada") }
            case .idle: ProgressView().controlSize(.small)
            case .noCamera: message("camera.fill", "No hay ninguna cámara conectada.")
            case .failed(let m): message("exclamationmark.triangle", m)
            case .denied:
                VStack(spacing: 8) {
                    message("lock.fill", "ToneForge no tiene permiso para usar la cámara.")
                    Button("Abrir Ajustes del Sistema") { Self.openCameraPrivacy() }.buttonStyle(SecondaryButton())
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }

    private func message(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(TF.muted)
            Text(text).font(TF.body(12)).foregroundStyle(TF.text2).multilineTextAlignment(.center)
        }
        .padding(8)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(TF.body(11, .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.6), in: Capsule()).padding(6)
    }

    static func openCameraPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Sincronía

    private func syncGroup(_ list: CameraList) -> some View {
        let uid = list.effective(video.cameraUID)?.id ?? video.cameraUID
        let ms = Binding<Double>(
            get: { uid.map { (video.defaultOffset(for: $0) * 1000).rounded() } ?? 0 },
            set: { value in
                guard let uid else { return }
                let clamped = min(max(value, Self.offsetRangeMs.lowerBound), Self.offsetRangeMs.upperBound)
                update { $0.setDefaultOffset(clamped / 1000, for: uid) }
            })
        return SettingsGroup(title: "Sincronía",
                             note: "Se ajusta al terminar cada toma; este es el valor con el que empieza la siguiente.") {
            InfoRow(label: "Desfase por defecto de esta cámara") {
                TextField("ms", value: ms, format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 70)
                Text("ms").foregroundStyle(TF.muted)
                Stepper("Desfase", value: ms, in: Self.offsetRangeMs, step: 1).labelsHidden()
            }
            .disabled(uid == nil)
        }
    }

    // MARK: Exportación

    private var exportGroup: some View {
        SettingsGroup(title: "Exportación por defecto", note: "Se puede cambiar en cada montaje.") {
            InfoRow(label: "Formato de vídeo") {
                Picker("Formato", selection: Binding(
                    get: { video.export.codec }, set: { c in update { $0.export.codec = c } })) {
                    Text("HEVC").tag(VideoCodec.hevc)
                    Text("H.264").tag(VideoCodec.h264)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                Picker("Resolución de exportación", selection: Binding(
                    get: { video.export.resolution }, set: { r in update { $0.export.resolution = r } })) {
                    ForEach(CameraChoices.presets, id: \.self) { Text(CameraChoices.label($0)).tag($0) }
                }
                .labelsHidden().frame(width: 100)
            }
            InfoRow(label: "Volumen") {
                Text("normalizado a −14 LUFS").fontWeight(.semibold).foregroundStyle(TF.text2)
            }
            InfoRow(label: "Rótulo con el título del tema") {
                Toggle("Rótulo con el título del tema", isOn: Binding(
                    get: { video.export.titleOverlay }, set: { on in update { $0.export.titleOverlay = on } }))
                    .toggleStyle(.switch).labelsHidden()
            }
            InfoRow(label: "WAV de cada pista") {
                Toggle("WAV de cada pista", isOn: Binding(
                    get: { video.export.exportStemWAVs }, set: { on in update { $0.export.exportStemWAVs = on } }))
                    .toggleStyle(.switch).labelsHidden()
            }
        }
    }
}

/// Patrón de barras para la vista previa simulada.
private struct ColorBars: View {
    private static let colors: [Color] = [.white, .yellow, .cyan, .green, .pink, .red, .blue, .black]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.colors.enumerated()), id: \.offset) { _, c in Rectangle().fill(c.opacity(0.85)) }
        }
    }
}

#if DEBUG
import Foundation

/// `--screen settings-video`: dos cámaras simuladas y un perfil de vídeo de ejemplo, sin cámara real ni permiso.
enum VideoDemo {
    static let provider = SimulatedCameraProvider(cameras: [
        .simulated,
        CameraDevice(id: "sim-iphone", name: "iPhone (Continuity Camera)", kind: .continuity, formats: [
            CameraFormat(width: 1280, height: 720, frameRates: [FrameRateRange(min: 24, max: 60)]),
            CameraFormat(width: 1920, height: 1080, frameRates: [FrameRateRange(min: 24, max: 60)]),
            CameraFormat(width: 3840, height: 2160, frameRates: [FrameRateRange(min: 24, max: 30)]),
        ]),
    ])

    static var profile: VideoSettings {
        var v = VideoSettings(cameraUID: "sim-iphone", resolution: .fullHD, fps: 30)
        v.setDefaultOffset(0.065, for: "sim-iphone")
        return v
    }
}
#endif
