import SwiftUI
import AppKit
import Store
import SourceKit

/// Recuadro de un artista: foto de Spotify (o iniciales sobre un color estable), nombre y «N temas» (spec Fase 7b, 6c).
struct ArtistTile: View {
    @Environment(AppModel.self) private var model
    let name: String?
    let count: Int
    let action: () -> Void
    @State private var photo: NSImage?
    @State private var hovering = false

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { cover }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(hovering ? TF.accent.opacity(0.6) : TF.line))
                Text(name ?? "Sin artista").font(TF.body(14, .semibold)).lineLimit(1).truncationMode(.tail)
                Text(count == 1 ? "1 tema" : "\(count) temas").font(TF.body(12)).foregroundStyle(TF.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(name ?? "Sin artista"), \(count) temas")
        // Solo los recuadros visibles piden foto: la tarea se cancela al salir de pantalla (LazyVGrid).
        .task(id: name) { await loadPhoto() }
    }

    @ViewBuilder private var cover: some View {
        if let photo {
            Image(nsImage: photo).resizable().aspectRatio(contentMode: .fill)
        } else if let name {
            ZStack {
                Self.color(for: name)
                Text(Self.initials(name)).font(TF.display(34)).foregroundStyle(.white.opacity(0.9))
            }
        } else {
            ZStack {
                TF.field
                Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(TF.muted)
            }
        }
    }

    private func loadPhoto() async {
        photo = nil
        guard let name else { return }
        let key = LibraryFilter.fold(name) as NSString
        if let hit = Self.cache.object(forKey: key) { photo = hit; return }
        guard let url = await model.artistPhotoProvider(name), !Task.isCancelled,
              let image = NSImage(contentsOf: url) else { return }
        Self.cache.setObject(image, forKey: key)
        photo = image
    }

    /// Hasta dos letras: las iniciales de las dos primeras palabras.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let s = words.compactMap { $0.first.map { String($0) } }.joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    /// Color estable derivado del nombre plegado (FNV-1a; `hashValue` cambia en cada arranque).
    static func color(for name: String) -> Color {
        var h: UInt64 = 0xcbf29ce484222325
        for b in LibraryFilter.fold(name).utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Color(hue: Double(h % 360) / 360, saturation: 0.45, brightness: 0.5)
    }
}

/// Campos «Título» y «Artista» con el botón de intercambiar; los comparten la hoja de la lista y la página del tema.
struct SongInfoFields: View {
    @Binding var title: String
    @Binding var artist: String
    var focus: FocusState<Bool>.Binding?
    let onSubmit: () -> Void

    private func field(_ label: String, text: Binding<String>, focused: FocusState<Bool>.Binding? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(TF.body(13)).foregroundStyle(TF.muted)
            TextField(label, text: text).textFieldStyle(.plain)
                .padding(.horizontal, 12).frame(height: 40)
                .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
                .modifier(OptionalFocus(focus: focused))
                .onSubmit(onSubmit)
        }
    }

    private struct OptionalFocus: ViewModifier {
        let focus: FocusState<Bool>.Binding?
        @ViewBuilder func body(content: Content) -> some View {
            if let focus { content.focused(focus) } else { content }
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                field("Título", text: $title, focused: focus)
                field("Artista", text: $artist)
            }
            Button {
                swap(&title, &artist)
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 14))
                    .foregroundStyle(TF.muted)
                    .frame(width: 36, height: 36)
                    .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
            }
            .buttonStyle(.plain)
            .help("Intercambiar título y artista").accessibilityLabel("Intercambiar título y artista")
        }
    }
}

/// Tema que se está corrigiendo desde la lista (spec Fase 7b, 6b).
struct SongEditTarget: Identifiable {
    let id: UUID
    let title: String
    let artist: String
}

/// Hoja de corrección de título y artista de una fila de Biblioteca (spec Fase 7b, 6b).
struct SongInfoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: SongEditTarget
    @State private var title = ""
    @State private var artist = ""
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    private func save() {
        guard canSave else { return }
        saving = true
        Task {
            if await model.updateSongInfo(id: target.id, title: title, artist: artist) { dismiss() }
            saving = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Corregir título y artista").font(TF.display(22))
            SongInfoFields(title: $title, artist: $artist, focus: $titleFocused, onSubmit: save)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButton(height: 36)).keyboardShortcut(.cancelAction)
                Button("Guardar", action: save).buttonStyle(PrimaryButton()).disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 520)
        .onAppear { title = target.title; artist = target.artist; titleFocused = true }
    }
}
