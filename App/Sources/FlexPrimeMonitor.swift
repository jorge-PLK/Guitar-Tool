import AudioKit
import Observation

/// Estado USB de la Flex Prime: se relee la lista de salidas cuando CoreAudio avisa de un cambio (sin sondeo).
@MainActor @Observable
final class FlexPrimeMonitor {
    private(set) var isConnected = false
    @ObservationIgnored private let provider = CoreAudioDeviceProvider()

    init() {
        refresh()
        provider.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        isConnected = provider.outputDevices().contains { OutputRouting.isFlexPrime($0) }
    }
}
