import Foundation

let usage = """
p2 · prueba de audio USB de la Flex Prime (canales 1-based; --out por defecto: out)

  p2 list [--out dir]
  p2 record --device <nombre|uid> --seconds N --out <dir> [--buffer N]
  p2 analyze <dir>
  p2 backing-test --device <d> --out-ch a,b [--out dir] [--buffer N]
  p2 latency --device <d> --out-ch a --in-ch b [--reps 10] [--out dir] [--buffer N]
  p2 reamp --device <d> --di <wav> --out-ch a[,b] --out <dir> [--latency-ms X] [--buffer N]
  p2 soak --device <d> --minutes 5 --out <dir> [--keep-wav] [--buffer N]
  p2 selftest [--out dir]       (sin hardware: señales sintéticas)
"""

let argv = Array(CommandLine.arguments.dropFirst())
guard let cmd = argv.first else { print(usage); exit(2) }
let args = Args(Array(argv.dropFirst()))

do {
    switch cmd {
    case "list": try Commands.list(args)
    case "record": try Commands.record(args)
    case "analyze": try Commands.analyze(args)
    case "backing-test": try Commands.backingTest(args)
    case "latency": try Commands.latency(args)
    case "reamp": try Commands.reamp(args)
    case "soak": try Commands.soak(args)
    case "selftest": try Commands.selftest(args)
    default: print(usage); exit(2)
    }
} catch {
    Log.say("ERROR: \(error)")
    exit(1)
}
