import AudioKit
import Observation

/// Estado del dispositivo de salida elegido en el perfil (`audio.outputDeviceUID`): se relee la lista de
/// CoreAudio cuando avisa de un cambio (sin sondeo). Sin nada elegido, la barra lateral dice «Salida del sistema».
@MainActor @Observable
final class AudioDeviceMonitor {
    /// UID elegido en el perfil; nil = salida por defecto del sistema.
    private(set) var chosenUID: String?
    /// Nombre del dispositivo elegido (el último visto si ahora no está conectado).
    private(set) var chosenName: String?
    private(set) var isConnected = false
    @ObservationIgnored private let provider: AudioDeviceProviding

    /// `observeChanges: false` para un proveedor compartido (solo admite un manejador de cambios) o simulado.
    init(provider: AudioDeviceProviding = CoreAudioDeviceProvider(), observeChanges: Bool = true) {
        self.provider = provider
        refresh()
        guard observeChanges else { return }
        provider.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Lo llama la app al cambiar el perfil.
    func choose(uid: String?) {
        let uid = (uid?.isEmpty ?? true) ? nil : uid
        guard uid != chosenUID else { return }
        chosenUID = uid
        chosenName = nil
        refresh()
    }

    var title: String { chosenUID == nil ? "Salida del sistema" : (chosenName ?? "Dispositivo elegido") }

    var subtitle: String {
        guard chosenUID != nil else { return "Por defecto" }
        return isConnected ? "Conectado" : "Sin conectar"
    }

    private func refresh() {
        guard let uid = chosenUID else { isConnected = false; return }
        if let d = provider.outputDevices().first(where: { $0.uid == uid }) {
            chosenName = d.name
            isConnected = true
        } else {
            isConnected = false
        }
    }
}
