import XCTest
@testable import AudioKit

/// Tipos portátiles de la E/S WASAPI: periodos (con los números de P8 en la VM), latencia declarada, avisos y regla de
/// frecuencia. Corren en el Mac y en Windows.
final class WASAPITypesTests: XCTestCase {
    /// P8, «Altavoces» (48 kHz): IAudioClient3 motor por defecto 480, paso 32, mínimo 128, máximo 480.
    static let speakers = WASAPIEnginePeriods(defaultFrames: 480, fundamentalFrames: 32, minimumFrames: 128, maximumFrames: 480)
    /// P8, «Línea de entrada» (44,1 kHz): mínimo 128, máximo 448.
    static let lineIn = WASAPIEnginePeriods(defaultFrames: 448, fundamentalFrames: 32, minimumFrames: 128, maximumFrames: 448)

    func testSharedEnginePeriodMatchesShimRounding() {
        let s = Self.speakers
        XCTAssertEqual(s.granted(requested: 0), 128, "0 = el mínimo")
        XCTAssertEqual(s.granted(requested: 100), 128, "por debajo del mínimo → mínimo")
        XCTAssertEqual(s.granted(requested: 128), 128)
        XCTAssertEqual(s.granted(requested: 129), 160, "al siguiente múltiplo del paso contado desde el mínimo")
        XCTAssertEqual(s.granted(requested: 256), 256)
        XCTAssertEqual(s.granted(requested: 512), 480, "AudioSetup.bufferFrames por encima del máximo → máximo")
        XCTAssertEqual(Self.lineIn.granted(requested: 512), 448)
        XCTAssertEqual(Self.lineIn.granted(requested: 440), 448)
    }

    func testPeriodConversionsRoundLikeTheShim() {
        // P8: GetDevicePeriod 10,0/2,667 ms (48 kHz) y 10,159/2,902 ms (44,1 kHz).
        XCTAssertEqual(WASAPIPeriod.frames(hundredNanoseconds: 100_000, sampleRate: 48_000), 480)
        XCTAssertEqual(WASAPIPeriod.frames(hundredNanoseconds: 26_667, sampleRate: 48_000), 128)
        XCTAssertEqual(WASAPIPeriod.frames(hundredNanoseconds: 101_587, sampleRate: 44_100), 448)
        XCTAssertEqual(WASAPIPeriod.frames(hundredNanoseconds: 29_025, sampleRate: 44_100), 128)
        XCTAssertEqual(WASAPIPeriod.hundredNanoseconds(frames: 128, sampleRate: 48_000), 26_667)
        XCTAssertEqual(WASAPIPeriod.hundredNanoseconds(frames: 512, sampleRate: 48_000), 106_667)
        XCTAssertEqual(WASAPIPeriod.milliseconds(frames: 128, sampleRate: 48_000), 2.6667, accuracy: 1e-4)
    }

    func testDeviceInfoMinimumPeriods() {
        let mix = WASAPIFormat(sampleRate: 48_000, channels: 2, bits: 32, validBits: 32, isFloat: true)
        var d = WASAPIDeviceInfo(id: "{0.0.0.00000000}.{a}", name: "Altavoces (High Definition Audio Device)", flow: .render,
                                 isDefault: true, mix: mix, defaultPeriod100ns: 100_000, minimumPeriod100ns: 26_667,
                                 engine: Self.speakers, exclusiveFloat: false)
        XCTAssertEqual(d.sharedPath, .client3Shared)
        XCTAssertEqual(d.minimumSharedPeriodFrames, 128)
        XCTAssertEqual(d.minimumExclusivePeriodFrames, 128)
        XCTAssertEqual(d.sharedPeriodFrames(requested: 512), 480)
        d.engine = nil   // sin IAudioClient3: compartido al periodo por defecto
        XCTAssertEqual(d.sharedPath, .clientShared)
        XCTAssertEqual(d.minimumSharedPeriodFrames, 480)
        XCTAssertEqual(d.sharedPeriodFrames(requested: 128), 480)
        XCTAssertEqual(mix.label, "48000 Hz · 2 ch · float32")
        XCTAssertEqual(WASAPIFormat(sampleRate: 44_100, channels: 2, bits: 32, validBits: 24, isFloat: false).label,
                       "44100 Hz · 2 ch · int24/32")
    }

    func testDeclaredLatencyIsBothStreamLatenciesInSamples() {
        // P8 exclusivo: latencia de flujo 2,667 ms salida + 3,333 ms entrada = 6 ms = 288 muestras a 48 kHz.
        let i = WASAPIStreamInfo(mode: .exclusive, renderPath: .exclusive, capturePath: .exclusive, renderFormat: nil,
                                 captureFormat: nil, renderBufferFrames: 128, captureBufferFrames: 160, renderPeriodFrames: 128,
                                 capturePeriodFrames: 160, renderLatency100ns: 26_667, captureLatency100ns: 33_333,
                                 captureDeviceRate: 48_000, renderName: "", captureName: "")
        XCTAssertEqual(i.declaredLatencySamples(sampleRate: 48_000), 288, accuracy: 0.01)
    }

    func testEventActions() {
        let input = "{0.0.1.00000000}.{in}", output = "{0.0.0.00000000}.{out}"
        func act(_ e: WASAPIEvent, flow: Int32 = 0, id: String? = nil, input: String = input) -> WASAPIEvent.Action {
            WASAPIEvent.action(kind: e.rawValue, flow: flow, deviceID: id, inputUID: input, outputUID: output)
        }
        XCTAssertEqual(act(.deviceRemoved, id: output), .interrupt(.disconnected(output)))
        XCTAssertEqual(act(.deviceRemoved, flow: 1, id: input), .interrupt(.disconnected(input)))
        XCTAssertEqual(act(.deviceRemoved, id: "{otro}"), .ignore, "otro endpoint: nada")
        XCTAssertEqual(act(.deviceRemoved, id: nil), .ignore)
        XCTAssertEqual(act(.deviceInvalidated, flow: 0), .interrupt(.disconnected(output)))
        XCTAssertEqual(act(.streamError, flow: 1), .interrupt(.disconnected(input)))
        XCTAssertEqual(act(.stalled, flow: -1), .interrupt(.disconnected(output)))
        XCTAssertEqual(act(.formatChanged, id: output), .checkRate(uid: output, flow: .render))
        XCTAssertEqual(act(.formatChanged, id: input), .checkRate(uid: input, flow: .capture))
        XCTAssertEqual(act(.formatChanged, id: "{otro}"), .ignore)
        XCTAssertEqual(act(.defaultChanged, id: "{otro}"), .ignore, "la sesión sigue con los endpoints que abrió")
        XCTAssertEqual(WASAPIEvent.action(kind: 99, flow: 0, deviceID: output, inputUID: input, outputUID: output), .ignore)
        // Solo salida (reproductor): sin entrada, un endpoint vacío no casa con nada.
        XCTAssertEqual(act(.deviceRemoved, id: "", input: ""), .ignore)
        XCTAssertEqual(act(.streamError, flow: 1, input: ""), .interrupt(.disconnected(output)))
    }

    func testSharedRenderMustRunAtWorkingRate() {
        XCTAssertEqual(WASAPIRateRule.mismatch(mode: .shared, renderMixRate: 44_100, working: 48_000), 44_100)
        XCTAssertNil(WASAPIRateRule.mismatch(mode: .shared, renderMixRate: 48_000, working: 48_000))
        XCTAssertNil(WASAPIRateRule.mismatch(mode: .exclusive, renderMixRate: 44_100, working: 48_000),
                     "en exclusivo el flujo abre a la frecuencia pedida o falla al abrir")
    }

    /// Parte 7.10b: la entrada también estricta en compartido (el caso de la VM: entrada 44,1 kHz, salida 48 kHz), salvo
    /// la opción de tests y diagnóstico.
    func testSharedInputMustRunAtWorkingRateUnlessResamplingAllowed() {
        XCTAssertEqual(WASAPIRateRule.inputMismatch(mode: .shared, captureMixRate: 44_100, working: 48_000, allowResampling: false),
                       44_100)
        XCTAssertNil(WASAPIRateRule.inputMismatch(mode: .shared, captureMixRate: 48_000, working: 48_000, allowResampling: false))
        XCTAssertNil(WASAPIRateRule.inputMismatch(mode: .shared, captureMixRate: 44_100, working: 48_000, allowResampling: true))
        XCTAssertNil(WASAPIRateRule.inputMismatch(mode: .exclusive, captureMixRate: 44_100, working: 48_000, allowResampling: false))
    }

    func testDriverKind() {
        XCTAssertEqual(WASAPIDriverInfo(service: "usbaudio2", provider: "Microsoft", infPath: "usbaudio2.inf").kind, .usbAudio2Generic)
        XCTAssertEqual(WASAPIDriverInfo(service: "USBAUDIO", provider: "Microsoft").kind, .usbAudio1Generic)
        XCTAssertEqual(WASAPIDriverInfo(service: "HdAudAddService", provider: "Microsoft").kind, .microsoft)
        XCTAssertEqual(WASAPIDriverInfo(service: "flexprime_wdm", provider: "HeadRush", infPath: "oem42.inf").kind, .vendor)
        XCTAssertEqual(WASAPIDriverInfo().kind, .unknown)
    }
}
