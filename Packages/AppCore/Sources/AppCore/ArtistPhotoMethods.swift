import Foundation
import SourceKit

/// Foto de un artista (`ArtistPhotoService`: caché en `<support dir>/artists/` o Spotify). Protocolo para inyectar una
/// simulada en los tests; sin red ni credenciales el servicio real devuelve `nil` (iniciales), como el Mac.
protocol ArtistPhotoProviding: Sendable {
    func photo(for name: String) async -> URL?
}

extension ArtistPhotoService: ArtistPhotoProviding {}

struct ArtistPhotoParams: Codable, Sendable { var name: String }

/// `photo` es una URL `data:` con la imagen (la caché está en la carpeta de soporte, fuera de la que sirve el anfitrión);
/// `nil` si no hay foto (la página pinta las iniciales).
struct ArtistPhotoResult: Codable, Sendable {
    var photo: String?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(photo, forKey: .photo)
    }
}

extension Bridge {
    /// Tope de una foto servida por el puente (las de Spotify rondan 20-100 KB).
    static let maxArtistPhotoBytes = 2_000_000

    func registerArtistPhotoMethods(options: LaunchOptions) {
        let provider: any ArtistPhotoProviding = artistPhotos ?? {
            let defaultDir = SourceKit.HelperLocator.defaultSupportDirectory.deletingLastPathComponent()
            return ArtistPhotoService.live(supportDir: options.supportDir ?? defaultDir, defaultSupportDir: defaultDir)
        }()
        router.register("library.artistPhoto") { (p: ArtistPhotoParams) -> ArtistPhotoResult in
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return ArtistPhotoResult(photo: nil) }
            guard let url = await provider.photo(for: name), let data = try? Data(contentsOf: url),
                  !data.isEmpty, data.count <= Bridge.maxArtistPhotoBytes else { return ArtistPhotoResult(photo: nil) }
            return ArtistPhotoResult(photo: "data:\(Bridge.imageMime(data));base64,\(data.base64EncodedString())")
        }
    }

    /// Tipo de la imagen por sus primeros bytes (la caché guarda `.img` sin extensión).
    static func imageMime(_ d: Data) -> String {
        if d.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if d.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "image/webp" }
        return "image/jpeg"
    }
}
