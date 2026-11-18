// tf-separate (StemKit) para con DispatchSource.makeSignalSource(SIGTERM): ¿existe en Windows?
import Dispatch
import Foundation

signal(SIGTERM, SIG_IGN)
let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
src.setEventHandler { print("SIGTERM recibido"); exit(0) }
src.resume()
print("OK makeSignalSource(SIGTERM) creado")
