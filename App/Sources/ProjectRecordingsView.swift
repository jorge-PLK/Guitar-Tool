import AVFoundation
import Store
import SwiftUI

/// Lista «Grabaciones» de la página del tema (mini-spec Fase 7b, punto 6): por parte, sus tomas con número, fecha,
/// duración, mejor ★, vídeo sí/no y punches; cada una con ▶ «Ver toma» (`TakeViewer`) y «Eliminar» con confirmación.
/// El orquestador la coloca en `ProjectDetailView`.
struct ProjectRecordingsView: View {
    let detail: ProjectDetail
    @Environment(AppModel.self) private var model
    /// Proyecto releído tras marcar la mejor o eliminar (hasta que `detail` se actualice).
    @State private var refreshed: Project?
    @State private var viewing: TakeViewRequest?
    @State private var deleting: DeleteRequest?
    @State private var failure: String?

    private struct DeleteRequest: Identifiable {
        let id: UUID
        let label: String
    }

    private var project: Project { refreshed ?? detail.project }
    private var layout: ProjectLayout { ProjectLayout(folder: detail.folder) }
    private var parts: [RecordingPart] { (project.recording?.parts ?? []).filter { !$0.takeIDs.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grabaciones").font(TF.display(18))
            if parts.isEmpty {
                Text("Este tema aún no tiene tomas grabadas.").font(TF.body(13)).foregroundStyle(TF.muted)
            } else {
                ForEach(parts) { part in partBox(part) }
            }
            if let failure { Text(failure).font(TF.body(12)).foregroundStyle(TF.danger) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: detail.project.takes.map(\.id)) { refreshed = nil }
        .sheet(item: $viewing) { req in viewer(req) }
        .confirmationDialog("¿Eliminar la toma?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Eliminar \(deleting?.label ?? "toma")", role: .destructive) { if let d = deleting { delete(d.id) }; deleting = nil }
            Button("Cancelar", role: .cancel) { deleting = nil }
        } message: {
            Text("Se borra su carpeta (audio y vídeo). No se puede deshacer.")
        }
    }

    // MARK: Filas

    private func partBox(_ part: RecordingPart) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(part.name).font(TF.body(14, .semibold))
            ForEach(Array(part.takeIDs.enumerated()), id: \.element) { i, id in
                if let take = project.takes.first(where: { $0.id == id }) { row(take, number: i + 1, part: part) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.fieldLine))
    }

    private func row(_ take: Take, number: Int, part: RecordingPart) -> some View {
        let best = part.bestTakeID == take.id
        let label = Self.label(number: number, part: part)
        return HStack(spacing: 12) {
            Text("Toma \(number)").font(TF.body(13, .semibold)).foregroundStyle(best ? TF.ok : TF.text2).frame(width: 64, alignment: .leading)
            if best { Text("★").foregroundStyle(TF.ok).accessibilityLabel("Mejor toma") }
            Text(take.createdAt.formatted(date: .abbreviated, time: .shortened)).font(TF.body(12)).foregroundStyle(TF.muted)
            Text(Self.durationText(take, layout: layout)).font(TF.body(12)).monospacedDigit().foregroundStyle(TF.muted)
            Text(Self.hasVideo(take) ? "Con vídeo" : "Sin vídeo").font(TF.body(12)).foregroundStyle(TF.muted)
            if let n = take.punches?.count, n > 0 { Text(n == 1 ? "1 punch" : "\(n) punches").font(TF.body(12)).foregroundStyle(TF.muted) }
            Spacer()
            Button { viewing = TakeViewRequest(takeID: take.id, title: label) } label: {
                Label("Ver toma", systemImage: "play.fill").font(TF.body(12, .semibold))
            }
            .buttonStyle(SecondaryButton(height: 32)).disabled(take.processedFile == nil || take.songStart == nil)
            Button("Eliminar") { deleting = DeleteRequest(id: take.id, label: label) }.buttonStyle(SecondaryButton(height: 32))
        }
    }

    static func label(number: Int, part: RecordingPart) -> String { "Toma \(number) · \(part.name)" }

    static func hasVideo(_ t: Take) -> Bool { t.videoFile != nil || (t.punches ?? []).contains { $0.videoFile != nil } }

    static func durationText(_ t: Take, layout: ProjectLayout) -> String {
        guard let rel = t.processedFile, let d = TakeViewPlanning.duration(of: layout.url(relative: rel)) else { return "–" }
        return Fmt.clock(d)
    }

    // MARK: Visor y acciones

    @ViewBuilder private func viewer(_ req: TakeViewRequest) -> some View {
        let best = project.recording?.part(containingTake: req.takeID)?.bestTakeID == req.takeID
        TakeViewer(project: project, layout: layout, takeID: req.takeID, title: req.title, isBest: best,
                   onMarkBest: { markBest(req.takeID) },
                   onDelete: { viewing = nil; delete(req.takeID) },
                   onClose: { viewing = nil })
    }

    private func markBest(_ takeID: UUID) {
        guard let library = model.library, var rec = project.recording, rec.part(containingTake: takeID) != nil else { return }
        for i in rec.parts.indices where rec.parts[i].takeIDs.contains(takeID) { rec.parts[i].setBest(takeID) }
        let id = detail.id
        Task {
            do {
                try await library.saveRecording(id: id, rec)
                reload()
            } catch { failure = "No se pudo marcar la toma como mejor (\(error))." }
        }
    }

    private func delete(_ takeID: UUID) {
        guard let library = model.library else { return }
        let id = detail.id
        Task {
            do {
                try await library.deleteTake(projectID: id, takeID: takeID)
                failure = nil
                reload()
            } catch { failure = "No se pudo eliminar la toma (\(error))." }
        }
    }

    /// Relee `project.json` y avisa al estudio abierto (si lo hay) del cambio.
    private func reload() {
        if let p = try? ProjectFile.load(folder: detail.folder) { refreshed = p }
        if model.study?.projectID == detail.id { model.study?.reload() }
    }
}
