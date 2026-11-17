/// Corrección de los golpes de ADTOF después del modelo y de los picos (Fase 5b, «Platos de ADTOF confundidos con
/// charles», ADR-016): la columna de platos (49, crash y ride juntos) se lleva el charles abierto. ADTOF no tiene
/// clase de charles abierto, y en sus golpes de platos la activación de charles es casi nula (El roce de tu cuerpo:
/// mediana 0,015 frente a 0,80 de platos), así que un margen entre columnas no sirve; lo que los separa es el ritmo.
///
/// Regla: los golpes de platos seguidos a ≤ `seriesMaxGap` forman una serie; en las series de `minSeriesLength` o
/// más golpes, todos pasan a charles abierto (GM 46) salvo el primero si cae con bombo, que sigue siendo crash
/// (el acento de entrada de frase). Los golpes sueltos y las series cortas no se tocan.
///
/// Medido en El roce de tu cuerpo (171 BPM, `Probes/P5b-guitarra/drums/series.py`): 427 golpes de platos, 410 en
/// series con separación de negra (≈ 350 ms) o corchea (≈ 180 ms); entre series, huecos de ≈ 700 ms y ninguna
/// separación entre 0,4 y 0,6 s. Los 17 sueltos caen en cabeza de compás (82 %) con bombo (94 %), como un crash.
/// En la banda > 5 kHz del stem, los golpes del interior de las series bajan 12,9 dB a 150 ms (charles: 15,6;
/// sueltos: 8,4) y son 3–4 dB más flojos que el primero de su serie, que decae como los sueltos (8,7 dB).
public enum DrumCymbalSeries {
    /// Nota GM del charles abierto (la pista de batería la pinta y la exporta como `DrumPiece.openHiHat`).
    public static let openHiHatMIDI = 46
    static let cymbalMIDI = 49
    static let kickMIDI = 35
    /// Separación máxima entre golpes de una serie, en segundos: en el hueco vacío entre 0,4 y 0,6 s medido en El roce
    /// (con 0,4 o 0,5 el resultado es el mismo; con 0,6 se unen cuatro sueltos a series). Por debajo de ~120 BPM una
    /// serie de negras queda fuera y se conserva como crash.
    static let seriesMaxGap = 0.5
    /// Golpes mínimos de una serie para pasarla a charles abierto. En El roce las series tienen 1 golpe (17), 2 (6:
    /// crash en la cabeza y otro un pulso después) o 5 y más (24); ninguna de 3 o 4.
    static let minSeriesLength = 4
    /// Ventana para «cae con bombo», en segundos (los golpes de ADTOF van a tramas de 10 ms).
    static let kickWindow = 0.03

    /// Mismos golpes, mismo orden (tiempo, nota): solo cambia la nota de los platos que la regla pasa a charles abierto.
    /// `hits` debe venir ordenado por tiempo, como lo devuelve `DrumTranscriber.transcribe`.
    public static func refine(_ hits: [TranscribedDrumHit]) -> [TranscribedDrumHit] {
        let cymbals = hits.indices.filter { hits[$0].midi == cymbalMIDI }
        let kicks = hits.filter { $0.midi == kickMIDI }.map(\.time)
        var out = hits
        var series = [Int]()
        func close() {
            defer { series = [] }
            guard series.count >= minSeriesLength else { return }
            for (k, i) in series.enumerated() {
                if k == 0, hasKick(near: hits[i].time, kicks: kicks) { continue }
                out[i].midi = openHiHatMIDI
            }
        }
        for i in cymbals {
            if let last = series.last, hits[i].time - hits[last].time > seriesMaxGap + 1e-9 { close() }
            series.append(i)
        }
        close()
        out.sort { ($0.time, $0.midi) < ($1.time, $1.midi) }
        return out
    }

    /// Hay bombo a ≤ `kickWindow` de `t` (`kicks` ordenado).
    static func hasKick(near t: Double, kicks: [Double]) -> Bool {
        var lo = 0, hi = kicks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if kicks[mid] < t - kickWindow - 1e-9 { lo = mid + 1 } else { hi = mid }
        }
        return lo < kicks.count && kicks[lo] <= t + kickWindow + 1e-9
    }
}
