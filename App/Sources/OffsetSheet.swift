import AVFoundation
import AppKit
import Store
import SwiftUI
import VideoKit

/// Hoja «Ajustar desfase» (mini-spec Fase 6, «Grabar una toma»): vista previa del vídeo con la guitarra grabada,
/// desfase en ms (±500) con ±1 fotograma y ±1 ms, y «Guardar como desfase por defecto de esta cámara».
struct OffsetSheet: View {
    let request: OffsetRequest
    let ctl: RecordController

    @State private var offsetMs: Double
    @State private var makeDefault = true
    @State private var player = AVPlayer()
    @State private var preview: TakePreview?
    @State private var error: String?

    init(request: OffsetRequest, ctl: RecordController) {
        self.request = request
        self.ctl = ctl
        _offsetMs = State(initialValue: (request.initialOffset * 1000).rounded())
    }

    private var range: ClosedRange<Double> { RecordController.offsetRangeMs }
    private var frameMs: Double { 1000 / max(request.fps, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ajustar desfase").font(TF.display(22))
            Text("Dale al play y mueve el desfase hasta que imagen y sonido coincidan (un golpe seco en las cuerdas ayuda). Positivo = la imagen llega tarde.")
                .font(TF.body(13)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            ZStack {
                Color.black
                if preview != nil {
                    PlayerLayerView(player: player)
                } else if let error {
                    Text(error).foregroundStyle(TF.danger).padding()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.line))

            HStack(spacing: 8) {
                Button { Task { await togglePlay() } } label: { Label("Reproducir / pausa", systemImage: "playpause.fill") }
                    .buttonStyle(SecondaryButton(height: 34)).disabled(preview == nil)
                Button { Task { await player.seek(to: .zero) } } label: { Label("Al principio", systemImage: "backward.end.fill") }
                    .buttonStyle(SecondaryButton(height: 34)).disabled(preview == nil)
                Spacer()
            }
            HStack(spacing: 8) {
                step("−1 fotograma", -frameMs)
                step("−1 ms", -1)
                HStack(spacing: 4) {
                    TextField("0", value: Binding(get: { offsetMs }, set: { setOffset($0) }),
                              format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 76)
                        .accessibilityLabel("Desfase en milisegundos")
                    Text("ms").foregroundStyle(TF.muted)
                }
                step("+1 ms", 1)
                step("+1 fotograma", frameMs)
                Spacer()
                Text("Fotograma = \(frameMs.formatted(.number.precision(.fractionLength(0...1)))) ms")
                    .font(TF.body(12)).foregroundStyle(TF.muted)
            }
            Toggle("Guardar como desfase por defecto de esta cámara (\(request.cameraName))", isOn: $makeDefault)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(request.isNew ? "Descartar toma" : "Cancelar") {
                    player.pause()
                    ctl.finishOffset(save: false, offset: 0, makeDefault: false)
                }
                .buttonStyle(SecondaryButton())
                Button(request.isNew ? "Guardar toma" : "Guardar") {
                    player.pause()
                    ctl.finishOffset(save: true, offset: offsetMs / 1000, makeDefault: makeDefault)
                }
                .buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 720)
        .background(TF.card).foregroundStyle(TF.text)
        .interactiveDismissDisabled(true)
        .task { await load() }
        .onDisappear { player.pause() }
    }

    private func togglePlay() async {
        if player.rate != 0 { player.pause(); return }
        if let item = player.currentItem, item.currentTime() >= item.duration - CMTime(value: 1, timescale: 30) {
            await player.seek(to: .zero)
        }
        player.play()
    }

    private func step(_ title: String, _ delta: Double) -> some View {
        Button(title) { setOffset(offsetMs + delta) }.buttonStyle(SecondaryButton(height: 34))
    }

    private func setOffset(_ v: Double) {
        let c = min(max(v, range.lowerBound), range.upperBound)
        guard c != offsetMs else { return }
        offsetMs = c
        Task { await rebuild() }
    }

    private func load() async {
        do {
            preview = try await TakePreview.load(audioURL: request.audioURL, songStart: request.songStart,
                                                 videoURL: request.videoURL, punches: request.punches,
                                                 rotation: VideoRotation(degrees: request.rotation))
            await rebuild()
        } catch {
            self.error = "No se pudo abrir la toma (\(error))."
        }
    }

    /// Rehace la composición con el desfase actual conservando la posición y si estaba sonando.
    private func rebuild() async {
        guard let preview, let comp = try? preview.composition(videoOffset: offsetMs / 1000) else { return }
        let t = player.currentTime()
        let playing = player.rate != 0
        player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
        if t.isValid, t.seconds > 0 { await player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) }
        if playing { player.play() }
    }
}

/// Vídeo de un `AVPlayer` en una `AVPlayerLayer` (sin AVKit: `VideoPlayer` de SwiftUI no carga en esta app).
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = v.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer?.addSublayer(layer)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {}
}
