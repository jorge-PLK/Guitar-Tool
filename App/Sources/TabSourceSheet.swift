import AppKit
import SourceKit
import SwiftUI
import TabKit

/// Hoja «Tablatura de Songsterr» (mini-spec Fase 5b, «Recorrido» 1 a 4): resultado marcado con sus pistas, otros resultados,
/// enlace pegado y, tras «Usar esta», la lista de emparejamiento con la confianza de cada pareja y los avisos.
struct TabSourceSheet: View {
    let tab: TabController

    /// «Vista previa» abierta: la hoja se ensancha y la página de la versión marcada va a la derecha de la lista.
    @State private var previewOpen = false

    static let listWidth: CGFloat = 612
    static let previewWidth: CGFloat = 640
    static let sheetHeight: CGFloat = 640

    private var previewURL: URL? {
        guard previewOpen, tab.importStage == .choosing, let id = tab.lookup?.selectedID else { return nil }
        return SongsterrReader.songURL(songId: id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tablatura de Songsterr").font(TF.display(22))
                switch tab.importStage {
                case .choosing: choosing
                case .working(let text): working(text)
                case .pairing: pairing
                case .failed(let issue): failed(issue)
                }
            }
            .frame(width: Self.listWidth, alignment: .topLeading)
            if let url = previewURL { previewPane(url) }
        }
        .font(TF.body(13)).foregroundStyle(TF.text2)
        .padding(24)
        .frame(width: previewURL == nil ? 660 : 660 + 20 + Self.previewWidth, height: Self.sheetHeight, alignment: .topLeading)
        .background(TF.bg)
    }

    /// Página de la versión marcada (navegable), con «Usar esta» al lado.
    private func previewPane(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Vista previa").font(TF.body(14, .semibold)).foregroundStyle(TF.text)
                Spacer()
                Button("Usar esta") { tab.useSelectedSong() }
                    .buttonStyle(PrimaryButton()).disabled(tab.lookup?.selectedSong == nil)
                Button("Cerrar") { previewOpen = false }.buttonStyle(SecondaryButton(height: 32))
            }
            SongsterrPreview(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
        }
        .frame(width: Self.previewWidth)
    }


    // MARK: Búsqueda

    @ViewBuilder private var choosing: some View {
        if let lookup = tab.lookup {
            let song = tab.session.project.song
            Text("Búsqueda: \([song.artist, song.title].compactMap { $0 }.joined(separator: " · "))").foregroundStyle(TF.muted)
            switch lookup.phase {
            case .idle, .searching:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Buscando en Songsterr…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .failed(let issue):
                issueBox(issue, retry: { tab.retrySearch() })
                Spacer(minLength: 0)
            case .results:
                results(lookup)
            }
            linkField(lookup)
            HStack {
                Button("Cancelar") { tab.closeSourceSheet() }.buttonStyle(SecondaryButton(height: 36))
                Spacer()
                if !previewOpen {
                    Button("Vista previa") { previewOpen = true }
                        .buttonStyle(SecondaryButton(height: 36)).disabled(lookup.selectedID == nil)
                }
                Button("Transcribir automáticamente") { tab.chooseAutomatic() }.buttonStyle(SecondaryButton(height: 36))
                Button("Usar esta") { tab.useSelectedSong() }
                    .buttonStyle(PrimaryButton()).disabled(lookup.selectedSong == nil)
            }
        }
    }

    private func results(_ lookup: SongsterrLookup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let song = lookup.selectedSong {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(song.artist) · \(song.title)").font(TF.body(14, .semibold)).foregroundStyle(TF.text)
                    ForEach(song.tracks) { t in
                        HStack(spacing: 10) {
                            Text(t.name).frame(width: 190, alignment: .leading).lineLimit(1)
                            Text(t.instrument).foregroundStyle(TF.muted).frame(width: 170, alignment: .leading).lineLimit(1)
                            Text(Self.tuningText(t.tuning)).foregroundStyle(TF.muted).monospacedDigit()
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
            } else if lookup.loadingID != nil {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Leyendo las pistas…") }
            } else if let issue = lookup.detailIssue {
                issueBox(issue, retry: { tab.retrySearch() })
            }
            Text("Otros resultados").foregroundStyle(TF.muted)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(lookup.results) { r in
                        let on = r.songId == lookup.selectedID
                        HStack(spacing: 8) {
                            Button { tab.select(songId: r.songId); previewOpen = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(on ? TF.accent : TF.muted)
                                    Text("\(r.artist) · \(r.title)").foregroundStyle(on ? TF.text : TF.text2).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? TF.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func linkField(_ lookup: SongsterrLookup) -> some View {
        @Bindable var lookup = lookup
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("O pega un enlace de Songsterr", text: $lookup.link)
                    .textFieldStyle(.plain).padding(.horizontal, 10).frame(height: 32)
                    .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
                    .onSubmit { tab.submitLink() }
                Button("Usar enlace") { tab.submitLink() }
                    .buttonStyle(SecondaryButton(height: 32))
                    .disabled(lookup.link.trimmingCharacters(in: .whitespaces).isEmpty || lookup.isBusy)
            }
            if let issue = lookup.linkIssue { Text(issue.message).foregroundStyle(TF.danger) }
        }
    }

    private func issueBox(_ issue: SongsterrIssue, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(issue.message).foregroundStyle(TF.text)
            if issue.suggestsAutomatic, issue == .noResults || !issue.canRetry {
                Text("Puedes transcribir el tema automáticamente.").foregroundStyle(TF.muted)
            }
            if issue.canRetry { Button("Reintentar", action: retry).buttonStyle(SecondaryButton(height: 32)) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(TF.dangerBg, in: RoundedRectangle(cornerRadius: 10))
    }

    /// «E A D G B E» de la cuerda más grave a la más aguda; vacío en batería.
    static func tuningText(_ tuning: [Int]?) -> String {
        guard let tuning, !tuning.isEmpty else { return "-" }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return tuning.reversed().map { names[(($0 % 12) + 12) % 12] }.joined(separator: " ")
    }

    // MARK: Descarga y alineación

    private func working(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
            AccentBar(value: nil).frame(width: 260)
            Spacer()
            HStack {
                Button("Cancelar") { tab.backToResults() }.buttonStyle(SecondaryButton(height: 36))
                Spacer()
            }
        }
    }

    private func failed(_ issue: SongsterrIssue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            issueBox(issue, retry: { tab.retryImport() })
            Spacer()
            HStack {
                Button("Volver") { tab.backToResults() }.buttonStyle(SecondaryButton(height: 36))
                Spacer()
                Button("Transcribir automáticamente") { tab.chooseAutomatic() }.buttonStyle(SecondaryButton(height: 36))
            }
        }
    }

    // MARK: Emparejamiento

    @ViewBuilder private var pairing: some View {
        if let plan = tab.plan {
            Text("Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio.")
                .foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(plan.slots, id: \.id) { slot in
                    pairRow(plan, slot)
                    if slot.id != plan.slots.last?.id { Divider().overlay(TF.line) }
                }
            }
            .padding(.horizontal, 12)
            .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
            if !plan.extraTracks.isEmpty {
                let names = plan.extraTracks.map { plan.tracks[$0].name }.joined(separator: ", ")
                Text("Pistas extra, sin stem: \(names). Entran en la tablatura y en el .gp y solo suenan con «Oír transcripción».")
                    .foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            }
            let warnings = plan.warnings
            if !warnings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(TF.accent)
                                Text(w).foregroundStyle(TF.text2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12).frame(maxHeight: 140)
                .background(TF.accentBg, in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
            HStack {
                Button("Atrás") { tab.backToResults() }.buttonStyle(SecondaryButton(height: 36))
                Button("Todo automático") { tab.setAllAutomatic() }.buttonStyle(SecondaryButton(height: 36))
                Spacer()
                Button("Cancelar") { tab.closeSourceSheet() }.buttonStyle(SecondaryButton(height: 36))
                Button("Aceptar") { tab.acceptPairing() }.buttonStyle(PrimaryButton())
            }
        }
    }

    @ViewBuilder private func pairRow(_ plan: SongsterrImportPlan, _ slot: SongsterrStemSlot) -> some View {
        if slot.role == .guitarLead {
            leadRows(plan, slot)
        } else {
            trackRow(plan, slot)
        }
    }

    /// Solista: una fila por sección de solo, «Solo n (m:ss) ← pista (confianza)»; sin secciones, automática.
    @ViewBuilder private func leadRows(_ plan: SongsterrImportPlan, _ slot: SongsterrStemSlot) -> some View {
        let solos = plan.assignment(for: slot.id)?.solos ?? []
        if solos.isEmpty {
            HStack(spacing: 12) {
                Text(slot.name).foregroundStyle(TF.text).frame(width: 150, alignment: .leading)
                Image(systemName: "arrow.right").foregroundStyle(TF.muted)
                Text("Transcripción automática (el tema no tiene secciones de solo)").foregroundStyle(TF.muted)
                Spacer(minLength: 0)
            }
            .frame(height: 44)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(solos.enumerated()), id: \.offset) { k, s in
                    let selection = Binding<Int?>(get: { plan.assignment(for: slot.id)?.solos[k].track },
                                                  set: { tab.setSoloPairing(stemID: slot.id, solo: k, track: $0) })
                    HStack(spacing: 12) {
                        Text(k == 0 ? slot.name : "").foregroundStyle(TF.text).frame(width: 150, alignment: .leading)
                        Text("Solo \(k + 1) (\(SongsterrImportPlan.clockText(s.span.lowerBound)))")
                            .foregroundStyle(TF.text2).monospacedDigit()
                        Image(systemName: "arrow.left").foregroundStyle(TF.muted)
                        Picker("Solo \(k + 1)", selection: selection) {
                            Text("Ninguna").tag(Int?.none)
                            ForEach(plan.soloChoices(for: slot.id, solo: k), id: \.track) { c in
                                Text(c.name + (c.similarity.map { " (\(Self.percent($0)))" } ?? "")).tag(Int?.some(c.track))
                            }
                        }
                        .labelsHidden().frame(width: 200)
                        Spacer(minLength: 0)
                        if s.track != nil {
                            Text(s.confidence.map { Self.percent($0) } ?? "sin medir")
                                .foregroundStyle(Self.confidenceColor(s.confidence)).monospacedDigit()
                        }
                    }
                    .frame(height: 44)
                }
            }
        }
    }

    private func trackRow(_ plan: SongsterrImportPlan, _ slot: SongsterrStemSlot) -> some View {
        let a = plan.assignment(for: slot.id)
        let selection = Binding<Int?>(get: { plan.assignment(for: slot.id)?.track },
                                      set: { tab.setPairing(stemID: slot.id, track: $0) })
        return HStack(spacing: 12) {
            Text(slot.name).foregroundStyle(TF.text).frame(width: 150, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(TF.muted)
            Picker(slot.name, selection: selection) {
                Text("Transcripción automática").tag(Int?.none)
                ForEach(plan.choices(for: slot.id), id: \.track) { c in
                    Text(c.name + (c.similarity.map { " (\(Self.percent($0)))" } ?? "")).tag(Int?.some(c.track))
                }
            }
            .labelsHidden().frame(width: 260)
            Spacer(minLength: 0)
            if a?.track != nil {
                Text(a?.confidence.map { Self.percent($0) } ?? "sin medir")
                    .foregroundStyle(Self.confidenceColor(a?.confidence)).monospacedDigit()
            }
        }
        .frame(height: 44)
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    /// Solo color orientativo de la lista (no son umbrales de la spec): verde de 0,6 en adelante, ámbar desde 0,35.
    static let goodConfidence = 0.6
    static let fairConfidence = 0.35

    static func confidenceColor(_ v: Double?) -> Color {
        guard let v else { return TF.muted }
        return v >= goodConfidence ? TF.ok : (v >= fairConfidence ? TF.accent : TF.danger)
    }
}
