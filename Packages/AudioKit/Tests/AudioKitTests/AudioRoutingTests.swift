import XCTest
@testable import AudioKit

/// Regla de salida del backing (mini-spec Fase 3, «Dispositivo y canales»).
final class AudioRoutingTests: XCTestCase {
    let builtIn = AudioDevice(id: 1, uid: "BuiltIn", name: "Altavoces", outputChannels: 2, sampleRates: [44100, 48000])
    let pedal = AudioDevice(id: 7, uid: "Pedal", name: "Pedalera", inputChannels: 4, outputChannels: 4, sampleRates: [48000])
    let micOnly = AudioDevice(id: 9, uid: "Mic", name: "Micro", inputChannels: 1)

    private func route(_ sim: SimulatedDeviceProvider, _ sel: OutputSelection) -> OutputRoute? {
        AudioRouting.route(selection: sel, devices: sim.outputDevices(), defaultDevice: sim.defaultOutputDevice())
    }

    func testChosenAndConnectedUsesDeviceAndPair() {
        let sim = SimulatedDeviceProvider(devices: [builtIn, pedal], defaultID: 1)
        let r = route(sim, OutputSelection(deviceUID: "Pedal", left: 1, right: 2))
        XCTAssertEqual(r, OutputRoute(device: pedal, channelMap: [0, 1, -1, -1]))
        let r2 = route(sim, OutputSelection(deviceUID: "Pedal", left: 4, right: 3))
        XCTAssertEqual(r2?.channelMap, [-1, -1, 1, 0])
        XCTAssertFalse(r2?.isSystemDefault ?? true)
    }

    func testChosenButDisconnectedFallsBackToSystemDefault() {
        let sim = SimulatedDeviceProvider(devices: [builtIn], defaultID: 1)
        let r = route(sim, OutputSelection(deviceUID: "Pedal", left: 3, right: 4))
        XCTAssertEqual(r, OutputRoute(device: builtIn, channelMap: nil, isSystemDefault: true))
    }

    func testNothingChosenUsesSystemDefaultEvenIfAPedalIsConnected() {
        let sim = SimulatedDeviceProvider(devices: [builtIn, pedal], defaultID: 1)
        XCTAssertEqual(route(sim, OutputSelection()), OutputRoute(device: builtIn, channelMap: nil, isSystemDefault: true))
        XCTAssertEqual(route(sim, OutputSelection(deviceUID: "")), route(sim, OutputSelection()))
        XCTAssertNil(route(SimulatedDeviceProvider(devices: [], defaultID: nil), OutputSelection()))
    }

    /// M-3d: backing mono en una salida de un canal: ruta al dispositivo, sin mapa y sin caer al de por defecto.
    func testMonoBackingOnOneChannelOutputKeepsDevice() {
        let mono = AudioDevice(id: 5, uid: "Mono", name: "Mono", outputChannels: 1)
        let sim = SimulatedDeviceProvider(devices: [builtIn, mono], defaultID: 1)
        let r = route(sim, OutputSelection(deviceUID: "Mono", left: 1, right: 1))
        XCTAssertEqual(r, OutputRoute(device: mono, channelMap: nil))
    }

    /// M-3d: el mezclador mono suma L y R × 0,5.
    func testBackingMonoMixerSignal() {
        let l: [Float] = [1, 1, 0, -1], r: [Float] = [0, 1, 0, -1]
        var out = [Float](repeating: 9, count: 4)
        BackingMono.mix(left: l, right: r, into: &out, count: 4)
        XCTAssertEqual(out, [0.5, 1.0, 0, -1.0])
    }

    func testPairOutOfRangeFallsBackToSystemDefault() {
        let sim = SimulatedDeviceProvider(devices: [builtIn, pedal], defaultID: 1)
        XCTAssertTrue(route(sim, OutputSelection(deviceUID: "Pedal", left: 5, right: 6))?.isSystemDefault ?? false)
        XCTAssertTrue(route(sim, OutputSelection(deviceUID: "Pedal", left: 2, right: 2))?.isSystemDefault ?? false)
    }

    func testInputOnlyDeviceIsNotAnOutput() {
        let sim = SimulatedDeviceProvider(devices: [builtIn, micOnly], defaultID: 1)
        XCTAssertEqual(sim.inputDevices(), [micOnly])
        XCTAssertEqual(sim.outputDevices(), [builtIn])
        XCTAssertTrue(route(sim, OutputSelection(deviceUID: "Mic"))?.isSystemDefault ?? false)
    }

    func testNameDoesNotMatter() {
        let flexNamed = AudioDevice(id: 5, uid: "Other", name: "HeadRush Flex Prime", outputChannels: 4)
        let sim = SimulatedDeviceProvider(devices: [builtIn, flexNamed], defaultID: 1)
        XCTAssertTrue(route(sim, OutputSelection())?.isSystemDefault ?? false)
    }

    func testSampleRateSupport() {
        XCTAssertTrue(pedal.supports(sampleRate: 48000))
        XCTAssertFalse(pedal.supports(sampleRate: 44100))
        XCTAssertTrue(micOnly.supports(sampleRate: 44100))
    }

    @MainActor
    func testReconnectionRestoresChosenDevice() async {
        let sim = SimulatedDeviceProvider(devices: [builtIn], defaultID: 1)
        let c = OutputController(provider: sim, selection: OutputSelection(deviceUID: "Pedal", left: 3, right: 4))
        XCTAssertEqual(c.route?.device, builtIn)
        var changes: [OutputRoute?] = []
        c.onRouteChange = { changes.append($0) }
        sim.plug(pedal)
        for _ in 0..<100 where changes.isEmpty { await Task.yield() }
        XCTAssertEqual(c.route, OutputRoute(device: pedal, channelMap: [-1, -1, 0, 1]))
        sim.unplug(id: 7)
        for _ in 0..<100 where changes.count < 2 { await Task.yield() }
        XCTAssertEqual(c.route?.device, builtIn)
        sim.plug(pedal)
        for _ in 0..<100 where changes.count < 3 { await Task.yield() }
        XCTAssertEqual(c.route?.device, pedal)
    }
}
