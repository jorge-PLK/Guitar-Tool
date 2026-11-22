// Texto de `tf-audio` para WASAPI (parte 7.10b): listado de dispositivos con driver y periodos mínimos, lo que quedó
// abierto y los contadores del hilo de audio. Portátil (tipos de AudioKit sin Windows) para probarlo en el Mac; lo usa
// la rama `#if os(Windows)` de `Commands` y `Rig`.
import AudioKit
import Foundation

enum WASAPIListing {
    /// Como `AudioDevice`, para buscar `--in`/`--out` con `Parse.device` (id exacto o trozo del nombre). `index` hace de
    /// `id` numérico (WASAPI no tiene).
    static func audioDevice(_ d: WASAPIDeviceInfo, index: Int) -> AudioDevice {
        AudioDevice(id: UInt32(index), uid: d.id, name: d.name,
                    inputChannels: d.flow == .capture ? d.mix.channels : 0,
                    outputChannels: d.flow == .render ? d.mix.channels : 0,
                    sampleRates: [], nominalSampleRate: d.mix.sampleRate > 0 ? d.mix.sampleRate : nil)
    }

    static func hex(_ hr: Int32) -> String { "0x" + String(UInt32(bitPattern: hr), radix: 16, uppercase: true) }

    static func ms(_ frames: Int, _ fs: Double) -> String { WASAPIPeriod.milliseconds(frames: frames, sampleRate: fs).fixed(3) }

    static func kindText(_ k: WASAPIDriverInfo.Kind) -> String {
        switch k {
        case .usbAudio2Generic: return "USB Audio 2.0 genérico de Windows"
        case .usbAudio1Generic: return "USB Audio 1.0 genérico de Windows"
        case .microsoft: return "de Microsoft"
        case .vendor: return "propio del fabricante"
        case .unknown: return "desconocido"
        }
    }

    /// «USB Audio 2.0 genérico de Windows · servicio usbaudio2 · Microsoft · versión 10.0.22621.1 · usbaudio2.inf».
    static func driverText(_ d: WASAPIDriverInfo) -> String {
        var parts = [kindText(d.kind)]
        if !d.service.isEmpty { parts.append("servicio \(d.service)") }
        if !d.provider.isEmpty { parts.append(d.provider) }
        if !d.version.isEmpty { parts.append("versión \(d.version)") }
        if !d.infPath.isEmpty { parts.append(d.infPath) }
        if !d.description.isEmpty { parts.append("«\(d.description)»") }
        if d.hresult != 0 { parts.append("consulta fallida \(hex(d.hresult))") }
        return parts.joined(separator: " · ")
    }

    /// Periodos en compartido: los del motor con IAudioClient3; sin él, el fijo por defecto. Con lo que concedería al
    /// pedir `requested` (0 = el mínimo).
    static func sharedText(_ d: WASAPIDeviceInfo, requested: Int) -> String {
        let fs = d.mix.sampleRate
        let granted = d.sharedPeriodFrames(requested: requested)
        let asked = requested > 0 ? "con \(requested) pedidas" : "pidiendo el mínimo"
        if let e = d.engine {
            return "IAudioClient3, mínimo \(e.minimumFrames) muestras (\(ms(e.minimumFrames, fs)) ms), paso \(e.fundamentalFrames), "
                + "máximo \(e.maximumFrames); \(asked): \(granted) (\(ms(granted, fs)) ms)"
        }
        return "IAudioClient, periodo fijo \(granted) muestras (\(ms(granted, fs)) ms)"
    }

    static func exclusiveText(_ d: WASAPIDeviceInfo) -> String {
        let n = d.minimumExclusivePeriodFrames
        return "mínimo \(n) muestras (\(ms(n, d.mix.sampleRate)) ms); float32 en exclusivo: \(d.exclusiveFloat ? "sí" : "no (el shim prueba enteros)")"
    }

    /// El listado de `tf-audio devices` en Windows: salidas y luego entradas, por nombre.
    static func lines(_ list: [WASAPIDeviceInfo], requestedPeriod: Int) -> [String] {
        var out = ["Modo por defecto: compartido; periodo pedido por defecto: \(requestedPeriod) muestras (cámbialos con --mode y --period)"]
        let sorted = list.sorted {
            $0.flow != $1.flow ? $0.flow == .render : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if sorted.isEmpty { out.append("No hay dispositivos de audio.") }
        for d in sorted {
            let side = d.flow == .render ? "salida" : "entrada"
            out.append("Dispositivo: \(d.name) · \(side)\(d.isDefault ? " (por defecto)" : "")")
            out.append("  UID: \(d.id)")
            // W2-E2: `PKEY_Device_ContainerId`, para ver en un PC si la entrada y la salida de la HeadRush comparten aparato.
            out.append("  Contenedor: \(d.containerID ?? "no lo da Windows")")
            out.append("  Formato de mezcla: \(d.mix.label)")
            out.append("  Driver: \(driverText(d.driver))")
            if !d.driver.adapterInstance.isEmpty {
                out.append("  Adaptador: \(d.driver.adapterName.isEmpty ? "" : d.driver.adapterName + " · ")\(d.driver.adapterInstance)")
            }
            out.append("  Compartido: \(sharedText(d, requested: requestedPeriod))")
            out.append("  Exclusivo: \(exclusiveText(d))")
            if d.hresult != 0 { out.append("  Error al consultar el endpoint: \(hex(d.hresult))") }
        }
        return out
    }

    /// Entrada y salida en el mismo aparato (mismo nodo PnP del adaptador); `nil` si no se sabe. En Windows tienen ids
    /// distintos: `tf-audio` asume que son el mismo aparato (un reloj) y solo avisa si consta que no.
    static func sameAdapter(_ input: WASAPIDeviceInfo, _ output: WASAPIDeviceInfo) -> Bool? {
        let a = input.driver.adapterInstance, b = output.driver.adapterInstance
        guard !a.isEmpty, !b.isEmpty else { return nil }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// Lo que quedó abierto, para el informe de `latency` y `verify`.
    static func streamLines(_ i: WASAPIStreamInfo) -> [String] {
        func side(_ name: String, _ path: WASAPIStreamPath, _ f: WASAPIFormat?, period: Int, buffer: Int, lat: Int64) -> String {
            let fs = f?.sampleRate ?? 0
            let latMs = (Double(lat) / 1e4).fixed(3)
            return "  \(name): \(path.label) · \(f?.label ?? "-") · periodo \(period) (\(ms(period, fs)) ms) · búfer \(buffer) · "
                + "latencia de flujo \(latMs) ms"
        }
        var out = ["WASAPI: modo \(i.mode == .exclusive ? "exclusivo" : "compartido")"]
        out.append(side("Salida", i.renderPath, i.renderFormat, period: i.renderPeriodFrames, buffer: i.renderBufferFrames,
                        lat: i.renderLatency100ns))
        if i.capturePath != .none {
            out.append(side("Entrada", i.capturePath, i.captureFormat, period: i.capturePeriodFrames, buffer: i.captureBufferFrames,
                            lat: i.captureLatency100ns))
            if i.capturePath == .autoconvert {
                out.append("  AVISO: entrada remuestreada por Windows desde \(Int(i.captureDeviceRate)) Hz (retardo sin medir)")
            }
        }
        return out
    }

    /// Contadores del hilo de audio del shim.
    static func statusLine(_ s: WASAPIStreamStatus) -> String {
        var t = "WASAPI: MMCSS \(s.mmcss ? "sí" : "NO") · \(s.renderBuffers) búferes de salida · \(s.renderStarved) sin hueco · "
            + "\(s.capturePackets) paquetes de entrada · \(s.clockFailures) fallos de IAudioClock"
        if s.stopReason != 0 { t += " · parado solo (motivo \(s.stopReason), \(hex(s.lastHResult)))" }
        if let d = s.driftPPM { t += " · deriva \(d.fixed(1)) ppm" }
        return t
    }
}
