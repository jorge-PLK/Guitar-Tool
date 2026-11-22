import AudioKit
import Observation
import Store
import SwiftUI

/// Lista de dispositivos de los selectores; se relee cuando el proveedor avisa de un cambio (sin sondeo).
@MainActor @Observable
final class AudioDeviceList {
    private(set) var inputs: [AudioDevice] = []
    private(set) var outputs: [AudioDevice] = []
    private(set) var systemDefault: AudioDevice?
    /// Nombres vistos en esta sesión, para seguir nombrando un dispositivo elegido que ya no está conectado.
    private(set) var names: [String: String] = [:]
    @ObservationIgnored private let provider: AudioDeviceProviding
    /// Lo llama `refresh()` tras cambiar la lista (el controlador de audio rehace la sesión).
    @ObservationIgnored var onChange: (() -> Void)?

    init(provider: AudioDeviceProviding) {
        self.provider = provider
        refresh()
        provider.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(notify: Bool = true) {
        inputs = provider.inputDevices()
        outputs = provider.outputDevices()
        systemDefault = provider.defaultOutputDevice()
        for d in inputs + outputs { names[d.uid] = d.name }
        if notify { onChange?() }
    }
}

extension ChannelPair: @retroactive Hashable {
    public func hash(into h: inout Hasher) { h.combine(left); h.combine(right) }
}

/// Opción de canales de un selector: etiqueta y valor.
struct ChannelChoice<Value: Hashable>: Hashable {
    var label: String
    var value: Value
}

/// Combinaciones de canales ofrecidas; solo las que pasan `AudioSettings.validate()`.
enum ChannelChoices {
    static func backing(channels: Int, current: AudioSettings) -> [ChannelChoice<ChannelPair>] {
        var pairs = stride(from: 1, to: max(channels, 2), by: 2).map { ChannelPair(left: $0, right: $0 + 1) }
        if !pairs.contains(current.backingOut) { pairs.append(current.backingOut) }
        return pairs.filter { p in var a = current; a.backingOut = p; return a.isValid }
            .map { ChannelChoice(label: "Salidas \($0.left) y \($0.right) · estéreo", value: $0) }
    }

    static func guitar(channels: Int, current: AudioSettings) -> [ChannelChoice<[Int]?>] {
        var options: [[Int]] = (1...max(channels, 1)).map { [$0] }
        options += stride(from: 1, to: max(channels, 2), by: 2).map { [$0, $0 + 1] }
        if let g = current.guitarIn, !options.contains(g) { options.append(g) }
        let valid = options.filter { g in var a = current; a.guitarIn = g; return a.isValid }
        return [ChannelChoice<[Int]?>(label: "Sin asignar", value: nil)]
            + valid.map { ChannelChoice<[Int]?>(label: $0.count == 1 ? "Entrada \($0[0])" : "Entradas \($0[0]) y \($0[1])", value: $0) }
    }
}

/// Medidores de entrada por canal (mini-spec Fase 3, «Ajustes · Audio»). `levels` = nivel 0...1 por canal;
/// con nil no pinta nada (sin sesión abierta). Lo alimenta `AudioController.inputLevels`.
struct InputMeters: View {
    var levels: [Float]?

    var body: some View {
        if let levels {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, l in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(TF.field)
                        RoundedRectangle(cornerRadius: 2).fill(TF.ok).frame(height: 28 * CGFloat(min(max(l, 0), 1)))
                    }
                    .frame(width: 8, height: 28)
                }
            }
        }
    }
}

struct AudioSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let devices = model.audio.devices
        VStack(alignment: .leading, spacing: 20) {
            deviceGroup(devices)
            channelsGroup(devices)
            calibrationGroup
        }
        // Los medidores y la sesión sin guitarra asignada solo corren con esta pestaña a la vista.
        .onAppear { model.audio.metersVisible = true }
        .onDisappear { model.audio.metersVisible = false }
        .sheet(isPresented: $model.showCalibrationSheet) { CalibrationSheet() }
    }

    // MARK: Perfil

    private var audio: AudioSettings { model.profile.audio ?? AudioSettings() }

    private func update(_ change: (inout AudioSettings) -> Void) {
        var a = audio
        change(&a)
        model.profile.audio = a
        model.saveProfile()
    }

    // MARK: Dispositivo

    private func deviceGroup(_ list: AudioDeviceList) -> some View {
        SettingsGroup(title: "Dispositivo", note: "Por dónde suena el backing y por dónde entra tu guitarra.") {
            InfoRow(label: "Dispositivo de salida") {
                Picker("Dispositivo de salida", selection: Binding(
                    get: { audio.outputDeviceUID }, set: { uid in update { $0.chooseOutput(uid) } })) {
                    Text("Salida del sistema").tag(String?.none)
                    ForEach(options(list.outputs, chosen: audio.outputDeviceUID, list: list, channels: \.outputChannels), id: \.uid) {
                        Text($0.label).tag(String?.some($0.uid))
                    }
                }
                .labelsHidden().frame(maxWidth: 320, alignment: .trailing)
            }
            InfoRow(label: "Dispositivo de entrada") {
                Picker("Dispositivo de entrada", selection: Binding(
                    get: { audio.inputDeviceUID }, set: { uid in update { $0.chooseInput(uid) } })) {
                    Text("Ninguna").tag(String?.none)
                    ForEach(options(list.inputs, chosen: audio.inputDeviceUID, list: list, channels: \.inputChannels), id: \.uid) {
                        Text($0.label).tag(String?.some($0.uid))
                    }
                }
                .labelsHidden().frame(maxWidth: 320, alignment: .trailing)
            }
            InfoRow(label: "Frecuencia de trabajo") {
                Picker("Frecuencia de trabajo", selection: Binding(
                    get: { model.profile.workingSampleRate }, set: { model.setSampleRate($0) })) {
                    ForEach(EquipmentProfile.allowedSampleRates, id: \.self) { Text(Fmt.rate($0)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220, alignment: .trailing)
            }
            if let mismatch = rateMismatch(list) { rateWarning(mismatch) }
        }
    }

    private struct DeviceOption { var uid: String; var label: String }

    /// Dispositivos conectados con su nº de canales; el elegido que no esté conectado se mantiene como «desconectado».
    private func options(_ connected: [AudioDevice], chosen: String?, list: AudioDeviceList,
                         channels: KeyPath<AudioDevice, Int>) -> [DeviceOption] {
        var result = connected.map { DeviceOption(uid: $0.uid, label: "\($0.name) · \($0[keyPath: channels]) can.") }
        if let chosen, !connected.contains(where: { $0.uid == chosen }) {
            result.append(DeviceOption(uid: chosen, label: "\(list.names[chosen] ?? "Dispositivo elegido") · desconectado"))
        }
        return result
    }

    /// Frecuencia ACTUAL (`nominalSampleRate`) de un dispositivo elegido que no está a la de trabajo.
    private func rateMismatch(_ list: AudioDeviceList) -> (rate: Double, working: Double)? {
        model.audio.mismatchedRate.map { ($0, model.profile.workingSampleRate) }
    }

    @ViewBuilder private func rateWarning(_ m: (rate: Double, working: Double)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("El dispositivo está a \(Fmt.rate(m.rate)) y la frecuencia de trabajo es \(Fmt.rate(m.working))")
                .font(TF.body(13)).foregroundStyle(TF.accent).fixedSize(horizontal: false, vertical: true)
            Text("Grabar y calibrar quedan bloqueados; el backing suena igual.")
                .font(TF.body(12)).foregroundStyle(TF.muted)
            if EquipmentProfile.allowedSampleRates.contains(m.rate) {
                Button("Usar \(Fmt.rate(m.rate)) como frecuencia de trabajo") { model.setSampleRate(m.rate) }
                    .buttonStyle(SecondaryButton())
            }
        }
    }

    // MARK: Canales

    private func channelsGroup(_ list: AudioDeviceList) -> some View {
        let outDevice = audio.outputDeviceUID.map { uid in list.outputs.first { $0.uid == uid } } ?? list.systemDefault
        let inDevice = audio.inputDeviceUID.flatMap { uid in list.inputs.first { $0.uid == uid } }
        let backing = ChannelChoices.backing(channels: outDevice?.outputChannels ?? 2, current: audio)
        let guitar = ChannelChoices.guitar(channels: inDevice?.inputChannels ?? 2, current: audio)
        return SettingsGroup(title: "Canales", note: "Qué entra y qué sale por cada canal del dispositivo.") {
            InfoRow(label: "Salida del backing") {
                Picker("Salida del backing", selection: Binding(
                    get: { audio.backingOut }, set: { p in update { $0.backingOut = p } })) {
                    ForEach(backing, id: \.value) { Text($0.label).tag($0.value) }
                }
                .labelsHidden().frame(maxWidth: 280, alignment: .trailing)
            }
            InfoRow(label: "Entrada de guitarra") {
                InputMeters(levels: model.audio.inputLevels)
                Picker("Entrada de guitarra", selection: Binding(
                    get: { audio.guitarIn }, set: { g in update { $0.guitarIn = g } })) {
                    ForEach(guitar, id: \.value) { Text($0.label).tag($0.value) }
                }
                .labelsHidden().frame(maxWidth: 280, alignment: .trailing)
                .disabled(audio.inputDeviceUID == nil)
            }
        }
    }

    // MARK: Calibración

    private var calibrationGroup: some View {
        let block = model.audio.deviceBlock
        return SettingsGroup(title: "Calibración",
                             note: "Un pulso de prueba mide el retardo de ida y vuelta del dispositivo.") {
            InfoRow(label: "Latencia") { latencyStatus }
            Button("Calibrar latencia") { model.showCalibrationSheet = true }
                .buttonStyle(SecondaryButton())
                .disabled(block != nil)
            if let block {
                Text(block.message).font(TF.body(12)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var latencyStatus: some View {
        let rate = model.profile.workingSampleRate
        if let l = audio.validLatency(sampleRate: rate) {
            let ms = (l.latencySamples / rate * 1000).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "es")))
            Text("Calibrada · \(ms) ms · \(l.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es"))))")
                .fontWeight(.semibold).foregroundStyle(TF.ok)
        } else {
            Text("Sin calibrar").fontWeight(.semibold).foregroundStyle(TF.accent)
        }
    }
}
