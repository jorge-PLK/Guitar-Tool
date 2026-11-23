import Foundation

/// Listas de ediciones (`edts/elst`) en un MP4 ya cerrado (plan, «Fase 7c», paso 7, parte 7.2). Media Foundation no
/// escribe ninguna: con ellas el MP4 de Windows dice, como el de `AVAssetWriter`, dónde empieza cada pista en el tiempo
/// de la película (tramo vacío delante de una toma que empieza a mitad de tema). El audio no lleva lista ni cebado
/// declarado (ver `AACPriming`).
///
/// Solo reescribe la caja `moov` y exige que sea la última del fichero (la deja así `IMFSinkWriter`): los
/// desplazamientos de los trozos (`stco`/`co64`) apuntan a `mdat`, que va delante, y no cambian. Puro (sin Media
/// Foundation): se prueba también en el Mac.
enum MP4EditList {
    /// Un tramo de la lista: `segmentDuration` en la escala de la película; `mediaTime` en la de la pista (-1: tramo
    /// vacío, sin muestras).
    struct Edit: Equatable, Sendable {
        var segmentDuration: UInt64
        var mediaTime: Int64

        static func empty(_ duration: UInt64) -> Edit { Edit(segmentDuration: duration, mediaTime: -1) }
    }

    /// Lo que se sabe de una pista al decidir sus ediciones.
    struct Track: Equatable, Sendable {
        /// `vide`, `soun`…
        var handler: String
        var movieTimescale: UInt32
        var mediaTimescale: UInt32
        /// Duración de los medios (`mdhd`), en la escala de la pista. Media Foundation pone aquí la marca absoluta del
        /// final (con una toma que empieza en 12,3 s, 12,3 s de más): para los tramos vale `sampleDuration`.
        var mediaDuration: UInt64
        /// Suma de las duraciones de las muestras (`stts`), en la escala de la pista.
        var sampleDuration: UInt64
        /// Ediciones que ya tenía (vacío si ninguna).
        var edits: [Edit]
        /// Tipo de la primera entrada de `stsd` (`hvc1`, `hev1`, `avc1`…); nil sin `stsd` (conversión HEVC → H.264 de
        /// Windows, `TakeVideoProbe`).
        var sampleEntry: String? = nil
        /// Tamaño de la entrada visual de `stsd` (0 si la pista no es de vídeo).
        var width: Int = 0
        var height: Int = 0
        /// Muestras según `stts`.
        var sampleCount: Int = 0
        /// Menor instante de composición (DTS de `stts` + desfase de `ctts`), en la escala de la pista: el primer
        /// fotograma que se muestra.
        var firstCompositionTime: Int64 = 0
    }

    enum Failure: Error, Equatable {
        case malformed(String)
        case moovNotLast
    }

    // MARK: Fichero

    /// Pistas del fichero con sus ediciones. Solo lee: admite la caja `moov` delante o detrás de `mdat` (un MP4 con
    /// `+faststart` también), a diferencia de `rewrite`.
    static func tracks(in url: URL) throws -> [Track] {
        let (moov, _) = try readMoov(url, requireLast: false)
        return try tracks(moov: moov)
    }

    /// Cambia las ediciones de las pistas para las que `edits` devuelve una lista (`nil`: la pista no se toca; `[]`: se
    /// quita). Actualiza la duración de la pista (`tkhd`) y la de la película (`mvhd`).
    static func rewrite(_ url: URL, edits: (Track) -> [Edit]?) throws {
        let (moov, offset) = try readMoov(url)
        let patched = try patch(moov: moov, edits: edits)
        let fh = try FileHandle(forUpdating: url)
        defer { try? fh.close() }
        try fh.seek(toOffset: offset)
        try fh.write(contentsOf: patched)
        try fh.truncate(atOffset: offset + UInt64(patched.count))
    }

    /// Lee la caja `moov`. Con `requireLast` (lo que necesita `rewrite`) debe ser la última de primer nivel (salvo
    /// `free`/`skip` detrás); sin él vale en cualquier sitio.
    static func readMoov(_ url: URL, requireLast: Bool = true) throws -> (Data, UInt64) {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let end = try fh.seekToEnd()
        var off: UInt64 = 0
        var moov: (UInt64, UInt64)?
        while off + 8 <= end {
            try fh.seek(toOffset: off)
            let h = try fh.read(upToCount: 16) ?? Data()
            guard h.count >= 8 else { break }
            var size = UInt64(be32(h, 0))
            let type = String(decoding: h[h.startIndex + 4..<h.startIndex + 8], as: UTF8.self)
            if size == 1, h.count >= 16 { size = be64(h, 8) } else if size == 0 { size = end - off }
            guard size >= 8 else { throw Failure.malformed("caja \(type) de \(size) bytes en \(off)") }
            if type == "moov" {
                moov = (off, size)
                if !requireLast { break }
            } else if moov != nil, type != "free", type != "skip" {
                throw Failure.moovNotLast
            }
            off += size
        }
        guard let (mo, ms) = moov else { throw Failure.malformed("sin moov") }
        try fh.seek(toOffset: mo)
        guard let data = try fh.read(upToCount: Int(ms)), data.count == Int(ms) else { throw Failure.malformed("moov truncado") }
        return (data, mo)
    }

    // MARK: Caja moov (puro)

    struct Box {
        var type: String
        var start: Int      // índice del principio de la caja en el Data
        var header: Int
        var size: Int
        var body: Range<Int> { (start + header)..<(start + size) }
    }

    static func children(_ d: Data, _ range: Range<Int>) throws -> [Box] {
        var out: [Box] = []
        var off = range.lowerBound
        while off + 8 <= range.upperBound {
            var size = Int(be32(d, off - d.startIndex))
            var header = 8
            if size == 1 {
                guard off + 16 <= range.upperBound else { throw Failure.malformed("caja de 64 bits truncada") }
                size = Int(be64(d, off - d.startIndex + 8))
                header = 16
            } else if size == 0 {
                size = range.upperBound - off
            }
            guard size >= header, off + size <= range.upperBound else { throw Failure.malformed("tamaño de caja \(size) en \(off)") }
            out.append(Box(type: String(decoding: d[(off + 4)..<(off + 8)], as: UTF8.self), start: off, header: header, size: size))
            off += size
        }
        return out
    }

    static func tracks(moov: Data) throws -> [Track] {
        let d = Data(moov)
        let top = try children(d, d.startIndex..<d.endIndex)
        guard let root = top.first, root.type == "moov" else { throw Failure.malformed("no es moov") }
        let kids = try children(d, root.body)
        guard let mvhd = kids.first(where: { $0.type == "mvhd" }) else { throw Failure.malformed("sin mvhd") }
        let movieTS = mvhdTimescale(d, mvhd)
        return try kids.filter { $0.type == "trak" }.map { try describe(d, $0, movieTimescale: movieTS) }
    }

    static func patch(moov: Data, edits: (Track) -> [Edit]?) throws -> Data {
        var d = Data(moov)
        let top = try children(d, d.startIndex..<d.endIndex)
        guard let root = top.first, root.type == "moov", root.header == 8 else { throw Failure.malformed("no es moov") }
        let kids = try children(d, root.body)
        guard let mvhd = kids.first(where: { $0.type == "mvhd" }) else { throw Failure.malformed("sin mvhd") }
        let movieTS = mvhdTimescale(d, mvhd)
        // Primera pasada: ediciones nuevas y, en las pistas que cambian, `mdhd` con la duración de sus muestras (campo
        // de tamaño fijo: se corrige en su sitio).
        var plan: [Int: (Track, [Edit]?)] = [:]
        for k in kids where k.type == "trak" {
            var track = try describe(d, k, movieTimescale: movieTS)
            let e = edits(track)
            if e != nil, track.mediaDuration != track.sampleDuration {
                try setMdhdDuration(&d, trak: k, track.sampleDuration)
                track.mediaDuration = track.sampleDuration
            }
            plan[k.start] = (track, e)
        }
        var body = Data()
        var movieDuration: UInt64 = 0
        var mvhdAt: Int?
        for k in kids {
            guard k.type == "trak", let (track, newEdits) = plan[k.start] else {
                if k.type == "mvhd" { mvhdAt = body.count }
                body.append(d[k.start..<(k.start + k.size)])
                continue
            }
            let trakKids = try children(d, k.body)
            var t = Data()
            var tkhdAt: Int?
            for c in trakKids where !(c.type == "edts" && newEdits != nil) {
                if c.type == "tkhd" { tkhdAt = t.count }
                t.append(d[c.start..<(c.start + c.size)])
                if c.type == "tkhd", let e = newEdits, !e.isEmpty { t.append(edtsBox(e)) }
            }
            let effective = newEdits ?? track.edits
            let duration = effective.isEmpty
                ? track.sampleDuration * UInt64(movieTS) / UInt64(max(1, track.mediaTimescale))
                : effective.reduce(0) { $0 + $1.segmentDuration }
            if newEdits != nil, let at = tkhdAt { setTkhdDuration(&t, at: at, duration) }
            movieDuration = max(movieDuration, duration)
            body.append(box("trak", t))
        }
        if let at = mvhdAt { setMvhdDuration(&body, at: at, movieDuration) }
        return box("moov", body)
    }

    // MARK: Cajas sueltas

    static func describe(_ d: Data, _ trak: Box, movieTimescale: UInt32) throws -> Track {
        let kids = try children(d, trak.body)
        guard let mdia = kids.first(where: { $0.type == "mdia" }) else { throw Failure.malformed("trak sin mdia") }
        let mk = try children(d, mdia.body)
        guard let mdhd = mk.first(where: { $0.type == "mdhd" }), let hdlr = mk.first(where: { $0.type == "hdlr" }) else {
            throw Failure.malformed("mdia sin mdhd o hdlr")
        }
        let b = mdhd.body.lowerBound - d.startIndex
        let v1 = d[mdhd.body.lowerBound] == 1
        let ts = be32(d, b + (v1 ? 20 : 12))
        let dur = v1 ? be64(d, b + 24) : UInt64(be32(d, b + 16))
        let h = hdlr.body.lowerBound + 8
        let handler = String(decoding: d[h..<(h + 4)], as: UTF8.self)
        var samples: UInt64 = 0
        var entry: (type: String, width: Int, height: Int)?
        var sampleCount = 0
        var firstCT: Int64 = 0
        let stblKids: [Box]
        if let minf = mk.first(where: { $0.type == "minf" }), let stbl = try children(d, minf.body).first(where: { $0.type == "stbl" }) {
            stblKids = try children(d, stbl.body)
        } else {
            stblKids = []
        }
        if let stsd = stblKids.first(where: { $0.type == "stsd" }), stsd.body.count >= 8,
           let first = try children(d, (stsd.body.lowerBound + 8)..<stsd.body.upperBound).first {
            // Entrada visual: cabecera (8) + 6 reservados + índice (2) + 16 de relleno, luego ancho y alto (16 bits).
            let o = first.start - d.startIndex
            let visual = handler == "vide" && first.size >= 36
            entry = (first.type, visual ? Int(be16(d, o + 32)) : 0, visual ? Int(be16(d, o + 34)) : 0)
        }
        if let stts = stblKids.first(where: { $0.type == "stts" }) {
            let s = stts.body.lowerBound - d.startIndex
            let n = Int(be32(d, s + 4))
            guard stts.body.count >= 8 + 8 * n else { throw Failure.malformed("stts truncado") }
            var runs: [(count: Int, delta: UInt64)] = []
            for i in 0..<n {
                let count = Int(be32(d, s + 8 + 8 * i)), delta = UInt64(be32(d, s + 12 + 8 * i))
                samples += UInt64(count) * delta
                sampleCount += count
                runs.append((count, delta))
            }
            firstCT = try firstCompositionTime(d, runs: runs, ctts: stblKids.first { $0.type == "ctts" })
        } else {
            samples = dur
        }
        var edits: [Edit] = []
        if let edts = kids.first(where: { $0.type == "edts" }), let elst = try children(d, edts.body).first(where: { $0.type == "elst" }) {
            let e = elst.body.lowerBound - d.startIndex
            let ev1 = d[elst.body.lowerBound] == 1
            let n = Int(be32(d, e + 4))
            var o = e + 8
            for _ in 0..<n {
                if ev1 {
                    edits.append(Edit(segmentDuration: be64(d, o), mediaTime: Int64(bitPattern: be64(d, o + 8))))
                    o += 20
                } else {
                    edits.append(Edit(segmentDuration: UInt64(be32(d, o)), mediaTime: Int64(Int32(bitPattern: be32(d, o + 4)))))
                    o += 12
                }
            }
        }
        return Track(handler: handler, movieTimescale: movieTimescale, mediaTimescale: ts, mediaDuration: dur, sampleDuration: samples,
                     edits: edits, sampleEntry: entry?.type, width: entry?.width ?? 0, height: entry?.height ?? 0,
                     sampleCount: sampleCount, firstCompositionTime: firstCT)
    }

    /// Menor DTS + desfase de composición (`ctts` de versión 0 sin signo o 1 con signo; sin `ctts`, el primer DTS = 0).
    static func firstCompositionTime(_ d: Data, runs: [(count: Int, delta: UInt64)], ctts: Box?) throws -> Int64 {
        guard let ctts else { return 0 }
        let c = ctts.body.lowerBound - d.startIndex
        let signed = d[ctts.body.lowerBound] == 1
        let n = Int(be32(d, c + 4))
        guard ctts.body.count >= 8 + 8 * n else { throw Failure.malformed("ctts truncado") }
        var offsets: [(count: Int, offset: Int64)] = []
        for i in 0..<n {
            let raw = be32(d, c + 12 + 8 * i)
            // Versión 0: sin signo en la norma, pero hay muxers que escriben negativos; un valor > 2^31 solo puede ser eso.
            let offset = signed || raw > UInt32(Int32.max) ? Int64(Int32(bitPattern: raw)) : Int64(raw)
            offsets.append((Int(be32(d, c + 8 + 8 * i)), offset))
        }
        var best = Int64.max
        var dts: Int64 = 0
        var k = 0, left = offsets.first?.count ?? 0
        for r in runs {
            for _ in 0..<r.count {
                while left == 0, k + 1 < offsets.count { k += 1; left = offsets[k].count }
                let off = k < offsets.count && left > 0 ? offsets[k].offset : 0
                best = min(best, dts + off)
                if left > 0 { left -= 1 }
                dts += Int64(r.delta)
            }
        }
        return best == .max ? 0 : best
    }

    /// `edts` con un `elst` de versión 1 (64 bits) y velocidad 1.
    static func edtsBox(_ edits: [Edit]) -> Data {
        var e = Data([1, 0, 0, 0])
        e.append(u32(UInt32(edits.count)))
        for x in edits {
            e.append(u64(x.segmentDuration))
            e.append(u64(UInt64(bitPattern: x.mediaTime)))
            e.append(u32(0x0001_0000))
        }
        return box("edts", box("elst", e))
    }

    static func setMdhdDuration(_ d: inout Data, trak: Box, _ v: UInt64) throws {
        guard let mdia = try children(d, trak.body).first(where: { $0.type == "mdia" }),
              let mdhd = try children(d, mdia.body).first(where: { $0.type == "mdhd" }) else { return }
        let b = mdhd.body.lowerBound
        if d[b] == 1 { put64(&d, b + 24, v) } else { put32(&d, b + 16, UInt32(min(v, UInt64(UInt32.max)))) }
    }

    // MARK: Cebado del AAC (iTunSMPB)

    // Decisión de Jorge (19/11/2026): el AAC de Windows va sin compensar, así que ya no se escribe iTunSMPB (ver
    // `AACPriming`). Queda el lector para comprobar que no lo lleva.

    /// Texto de iTunSMPB del fichero, si lo tiene (para comprobarlo).
    static func gaplessInfo(moov: Data) -> String? {
        guard let r = moov.range(of: Data("iTunSMPB".utf8)), let dr = moov.range(of: Data("data".utf8), in: r.upperBound..<moov.endIndex) else { return nil }
        let size = Int(be32(moov, dr.lowerBound - 4 - moov.startIndex))
        let start = dr.upperBound + 8, end = dr.lowerBound - 4 + size
        guard start <= end, end <= moov.endIndex else { return nil }
        return String(decoding: moov[start..<end], as: UTF8.self)
    }

    static func mvhdTimescale(_ d: Data, _ mvhd: Box) -> UInt32 {
        let b = mvhd.body.lowerBound - d.startIndex
        return be32(d, b + (d[mvhd.body.lowerBound] == 1 ? 20 : 12))
    }

    /// `tkhd` empieza en `at` (con cabecera de 8 bytes).
    static func setTkhdDuration(_ t: inout Data, at: Int, _ v: UInt64) {
        let b = t.startIndex + at + 8
        if t[b] == 1 { put64(&t, b + 28, v) } else { put32(&t, b + 20, UInt32(min(v, UInt64(UInt32.max)))) }
    }

    static func setMvhdDuration(_ m: inout Data, at: Int, _ v: UInt64) {
        let b = m.startIndex + at + 8
        if m[b] == 1 { put64(&m, b + 24, v) } else { put32(&m, b + 16, UInt32(min(v, UInt64(UInt32.max)))) }
    }

    static func box(_ type: String, _ body: Data) -> Data {
        var d = u32(UInt32(8 + body.count))
        d.append(contentsOf: Array(type.utf8))
        d.append(body)
        return d
    }

    // Enteros big-endian; `o` es relativo al principio del Data.
    static func be32(_ d: Data, _ o: Int) -> UInt32 {
        let i = d.startIndex + o
        return UInt32(d[i]) << 24 | UInt32(d[i + 1]) << 16 | UInt32(d[i + 2]) << 8 | UInt32(d[i + 3])
    }

    static func be64(_ d: Data, _ o: Int) -> UInt64 { UInt64(be32(d, o)) << 32 | UInt64(be32(d, o + 4)) }
    static func be16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[d.startIndex + o]) << 8 | UInt16(d[d.startIndex + o + 1]) }
    static func u32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]) }
    static func u64(_ v: UInt64) -> Data { u32(UInt32(v >> 32)) + u32(UInt32(v & 0xffff_ffff)) }

    static func put32(_ d: inout Data, _ i: Int, _ v: UInt32) {
        d[i] = UInt8(v >> 24); d[i + 1] = UInt8((v >> 16) & 0xff); d[i + 2] = UInt8((v >> 8) & 0xff); d[i + 3] = UInt8(v & 0xff)
    }

    static func put64(_ d: inout Data, _ i: Int, _ v: UInt64) {
        put32(&d, i, UInt32(v >> 32))
        put32(&d, i + 4, UInt32(v & 0xffff_ffff))
    }
}
