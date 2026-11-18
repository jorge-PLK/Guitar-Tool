import AVFoundation
import Foundation
import Observation
import Store
import SwiftUI
import VideoKit

// Visor de una toma (mini-spec Fase 7b, punto 9). Lo usan Grabar (lista de tomas) y la página del tema
// (`ProjectRecordingsView`). Vídeo, toma procesada y backing salen del mismo camino que el montaje: un `MontagePlan`
// de una sola parte en plano único, sin fundidos ni rótulo, abierto con `MontageBuilder` en un único `AVPlayerItem`
// con su mezcla. Así comparten reloj por construcción y no hay otra sincronía que mantener.

/// Qué toma abre el visor (para `.sheet(item:)`).
struct TakeViewRequest: Identifiable, Equatable {
    var id: UUID { takeID }
    let takeID: UUID
    /// «Toma 2 · Robe rítmica».
    let title: String
}

/// Plan del visor de una toma.
struct TakeViewPlan {
    var plan: MontagePlan
    /// false: solo audio (recuadro negro).
    var hasVideo: Bool
}

enum TakeViewPlanning {
    /// Cadencia del plan si la toma no la guarda (la rejilla de fotogramas solo ajusta el final del tramo).
    static let fallbackFPS = 30.0
    /// Sin fundidos, el compás no se usa (mini-spec 7b, punto 9); un valor cualquiera.
    static let unusedBarDuration = 2.0

    /// Plan de la toma `takeID`: una parte, plano único, sin fundidos, rótulo ni nombres. Suena la toma (con el volumen
    /// de su canal «Tú · parte») y, con `includeBacking`, los stems con la mezcla de Grabar; la guitarra que la parte
    /// sustituye queda silenciada durante la toma, como en el montaje. `nil` si la toma no tiene audio procesado.
    static func plan(project: Project, layout: ProjectLayout, takeID: UUID, includeBacking: Bool, takeDuration: Double,
                     fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> TakeViewPlan? {
        guard let take = project.takes.first(where: { $0.id == takeID }), let rel = take.processedFile,
              let start = take.songStart, takeDuration > 0 else { return nil }
        let rec = project.recordingOrInitial()
        let part = rec.part(containingTake: takeID)
        let span = VideoSpan(start: start, end: start + takeDuration)
        let punches = (take.punches ?? []).map {
            PreviewPunch(start: $0.start, end: $0.end, videoURL: $0.videoFile.map { layout.url(relative: $0) },
                         videoOffset: $0.videoOffset ?? take.videoOffset ?? 0)
        }
        let hasImage = take.videoFile != nil || punches.contains { $0.videoURL != nil }
        let video = hasImage ? MontagePartVideo(url: take.videoFile.map { layout.url(relative: $0) }, videoOffset: take.videoOffset ?? 0,
                                                punches: punches, take: span, rotation: VideoRotation(degrees: take.videoRotation ?? 0)) : nil
        let partID = (part?.id ?? takeID).uuidString
        let montagePart = MontagePart(id: partID, name: part?.name ?? "Toma", isSolo: false, presence: [span], video: video)

        var audio: [MontageAudioTrack] = []
        if includeBacking {
            let replaced = part?.replaces
            let separated = project.guitarTracks.filter { g in g.file.map { fileExists(layout.url(relative: $0)) } == true }
            let anySolo = rec.mix.contains { $0.solo }
            func audible(_ m: StemMix) -> Bool { !m.muted && (!anySolo || m.solo) }
            for s in project.stems where !s.isEmpty {
                let kind = s.kind
                guard !(kind == .guitar && !separated.isEmpty), fileExists(layout.stemURL(kind)) else { continue }
                let m = rec.mix.first { $0.kind == kind && $0.guitarRole == nil } ?? StemMix(kind: kind)
                guard audible(m) else { continue }
                let silenced = kind == .guitar && replaced != nil
                audio.append(MontageAudioTrack(url: layout.stemURL(kind), songStart: 0, volume: MontagePlanning.linear(m.gainDB),
                                               gate: silenced ? .except([span]) : .always))
            }
            for g in separated {
                let m = rec.mix.first { $0.guitarRole == g.role } ?? StemMix(kind: .guitar, guitarRole: g.role)
                guard audible(m) else { continue }
                audio.append(MontageAudioTrack(url: layout.guitarURL(g.role), songStart: 0, volume: MontagePlanning.linear(m.gainDB),
                                               gate: g.role == replaced ? .except([span]) : .always))
            }
        }
        let gain = rec.partMix(for: part?.id ?? takeID).gainDB
        audio.append(MontageAudioTrack(url: layout.url(relative: rel), songStart: start, volume: MontagePlanning.linear(gain), gate: .always))

        let plan = MontagePlan(canvas: .landscape, fps: take.videoFormat?.fps ?? fallbackFPS, layout: .singleLandscape, span: span,
                               barDuration: unusedBarDuration, fadeIn: false, fadeOut: false, parts: [montagePart],
                               singleRhythmPartID: partID, audio: audio, caption: nil, showPartLabels: false, keepVideoAspect: true)
        return TakeViewPlan(plan: plan, hasVideo: hasImage)
    }

    /// Duración del WAV procesado (s), o `nil` si no se puede leer.
    static func duration(of url: URL) -> Double? {
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return nil }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    /// Toma sin vídeo: una composición solo de audio con el mismo reparto de pistas del plan (tiempo 0 = inicio del
    /// tramo de la toma; las pistas se recortan a ese tramo y las compuertas `.except` se silencian).
    @MainActor
    static func audioOnlyItem(_ plan: MontagePlan) async throws -> (item: AVPlayerItem, duration: Double) {
        guard let span = plan.segments.first else { throw TakeViewError.noAudio }
        let comp = AVMutableComposition()
        var params: [AVMutableAudioMixInputParameters] = []
        func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 48_000) }
        for a in plan.audio {
            let asset = AVURLAsset(url: a.url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw TakeViewError.audio(a.url.lastPathComponent)
            }
            let range = try await source.load(.timeRange)
            let fileDur = CMTimeGetSeconds(range.duration)
            let lo = max(a.songStart, span.start), hi = min(a.songStart + fileDur, span.end)
            guard hi > lo else { comp.removeTrack(track); continue }
            try track.insertTimeRange(CMTimeRange(start: CMTimeAdd(range.start, t(lo - a.songStart)), duration: t(hi - lo)),
                                      of: source, at: t(lo - span.start))
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(Float(a.volume), at: .zero)
            if case .except(let spans) = a.gate {
                for s in spans {
                    let r = CMTimeRange(start: t(max(0, s.start - span.start)), end: t(max(0, s.end - span.start)))
                    p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 0, timeRange: r)
                    p.setVolume(Float(a.volume), at: r.end)
                }
            }
            params.append(p)
        }
        let item = AVPlayerItem(asset: comp)
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        item.audioMix = mix
        return (item, span.duration)
    }
}

enum TakeViewError: Error, CustomStringConvertible {
    case noAudio
    case audio(String)
    var description: String {
        switch self {
        case .noAudio: "la toma no tiene audio procesado"
        case .audio(let f): "no se pudo leer el audio \(f)"
        }
    }
}

@MainActor @Observable
final class TakeViewerModel {
    let player = AVPlayer()
    private(set) var ready = false
    private(set) var error: String?
    private(set) var hasVideo = false
    private(set) var isPlaying = false
    /// Segundos desde el inicio de la toma.
    private(set) var position = 0.0
    private(set) var duration = 0.0
    /// El backing suena junto a la toma (botón del visor).
    var backingOn = true
    /// Hay stems con los que mezclar (si no, el botón no tiene nada que silenciar).
    private(set) var hasBacking = false

    private let project: Project
    private let layout: ProjectLayout
    private let takeID: UUID
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var loadedBacking: Bool?

    init(project: Project, layout: ProjectLayout, takeID: UUID) {
        self.project = project
        self.layout = layout
        self.takeID = takeID
    }

    func open() async {
        closed = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem != nil, self.ready else { return }
                if self.player.rate != 0 || self.isPlaying { self.position = min(max(CMTimeGetSeconds(t), 0), self.duration) }
                self.isPlaying = self.player.rate != 0
            }
        }
        await load()
    }

    func close() {
        closed = true
        player.pause()
        isPlaying = false
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    /// Cambia el backing (silenciar o no) rehaciendo la composición en el mismo instante y con el mismo estado.
    func setBacking(_ on: Bool) async {
        guard on != backingOn else { return }
        backingOn = on
        await load()
    }

    private func load() async {
        loadGeneration += 1
        let gen = loadGeneration
        let wasPlaying = isPlaying, keep = position
        guard let rel = project.takes.first(where: { $0.id == takeID })?.processedFile,
              let dur = TakeViewPlanning.duration(of: layout.url(relative: rel)),
              let built = TakeViewPlanning.plan(project: project, layout: layout, takeID: takeID, includeBacking: backingOn, takeDuration: dur)
        else { error = "Esta toma no tiene audio que reproducir."; return }
        hasVideo = built.hasVideo
        // Hay backing si el plan suena algo más que la toma (calculado con el backing encendido).
        if backingOn { hasBacking = built.plan.audio.count > 1 }
        else if let all = TakeViewPlanning.plan(project: project, layout: layout, takeID: takeID, includeBacking: true, takeDuration: dur) {
            hasBacking = all.plan.audio.count > 1
        }
        do {
            let item: AVPlayerItem
            if built.hasVideo {
                let builder = try await MontageBuilder.load(built.plan, includeAudio: true)
                let size = MontageBuilder.renderSize(canvas: built.plan.canvas, maxDimension: MontagePlanning.previewMaxDimension)
                let preview = try builder.make(renderSize: size, includeAudio: true)
                item = preview.makePlayerItem()
                duration = preview.duration
            } else {
                let audioOnly = try await TakeViewPlanning.audioOnlyItem(built.plan)
                item = audioOnly.item
                duration = audioOnly.duration
            }
            guard !closed, gen == loadGeneration else { return }
            player.replaceCurrentItem(with: item)
            ready = true
            error = nil
            position = min(keep, duration)
            await player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            if wasPlaying { player.play() }
        } catch {
            guard !closed, gen == loadGeneration else { return }
            ready = false
            self.error = "No se pudo preparar la toma (\(error))."
        }
    }

    func togglePlay() {
        guard ready else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if position >= duration - 0.1 { seek(to: 0) }
            player.play()
            isPlaying = true
        }
    }

    func seek(to t: Double) {
        guard ready else { return }
        let t = min(max(t, 0), duration)
        position = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

/// Visor de una toma: vídeo y audio procesado sincronizados (más el backing), reproducir/pausa, barra de posición,
/// marcar como mejor, eliminar y cerrar. No decide nada por su cuenta: las acciones las ejecuta quien lo abre.
struct TakeViewer: View {
    let title: String
    let isBest: Bool
    let onMarkBest: () -> Void
    /// Elimina la toma (ya confirmado en el visor); quien lo abre la borra y cierra el visor.
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var model: TakeViewerModel
    @State private var confirmDelete = false

    init(project: Project, layout: ProjectLayout, takeID: UUID, title: String, isBest: Bool,
         onMarkBest: @escaping () -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.title = title
        self.isBest = isBest
        self.onMarkBest = onMarkBest
        self.onDelete = onDelete
        self.onClose = onClose
        _model = State(initialValue: TakeViewerModel(project: project, layout: layout, takeID: takeID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            screen
            controls
            if let e = model.error { Text(e).font(TF.body(12)).foregroundStyle(TF.danger) }
            actions
        }
        .padding(20)
        .frame(width: 720)
        .background(TF.bg)
        .task { await model.open() }
        .onDisappear { model.close() }
        .confirmationDialog("¿Eliminar la toma?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar toma", role: .destructive) { model.close(); onDelete() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borra su carpeta (audio y vídeo). No se puede deshacer.")
        }
    }

    private var header: some View {
        HStack {
            Text(title).font(TF.display(18))
            if isBest {
                Text("★ mejor").font(TF.body(11, .semibold)).foregroundStyle(TF.ok)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(TF.okBg, in: Capsule())
            }
            Spacer()
            Button { model.close(); onClose() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(TF.text2).help("Cerrar").keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cerrar")
        }
    }

    /// 16:9 como el lienzo del plan; sin vídeo, recuadro negro.
    private var screen: some View {
        ZStack {
            Color.black
            if model.hasVideo {
                PlayerLayerView(player: model.player)
            } else if model.ready {
                Text("Sin vídeo: solo audio").font(TF.body(12)).foregroundStyle(TF.muted)
            } else if model.error == nil {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.line))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15))
                    .frame(width: 36, height: 36).background(TF.accent, in: Circle()).foregroundStyle(TF.accentInk)
            }
            .buttonStyle(.plain).disabled(!model.ready)
            .accessibilityLabel(model.isPlaying ? "Pausa" : "Reproducir")
            Text(Fmt.clock(model.position)).font(TF.body(12)).monospacedDigit().foregroundStyle(TF.muted)
            Slider(value: Binding(get: { model.position }, set: { model.seek(to: $0) }), in: 0...max(model.duration, 0.1))
                .disabled(!model.ready)
            Text(Fmt.clock(model.duration)).font(TF.body(12)).monospacedDigit().foregroundStyle(TF.muted)
            Button { Task { await model.setBacking(!model.backingOn) } } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.backingOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    Text(model.backingOn ? "Backing" : "Backing mudo").font(TF.body(12, .semibold))
                }
                .foregroundStyle(model.backingOn ? TF.text2 : TF.accent)
                .padding(.horizontal, 10).frame(height: 32)
                .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
            }
            .buttonStyle(.plain).disabled(!model.ready || !model.hasBacking)
            .help(model.backingOn ? "Silenciar el backing" : "Oír el backing")
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Marcar como mejor") { onMarkBest() }.buttonStyle(SecondaryButton()).disabled(isBest)
            Spacer()
            Button("Eliminar…", role: .destructive) { confirmDelete = true }.buttonStyle(SecondaryButton())
        }
    }
}
