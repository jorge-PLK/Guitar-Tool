# NativeDSP: de vDSP a la fachada

`import NativeDSP` en vez de `import Accelerate`. `DSP` es el motor del sistema: en el Mac,
`DSPAccelerate` (cada función llama tal cual a vDSP, cero cambio de comportamiento); en Windows,
`DSPPortable` (Swift + pocketfft). Los dos motores tienen las mismas firmas (las obliga el protocolo
interno `DSPEngine`) y los tests los comparan operación por operación (`Tests/NativeKitTests/DSPEngineTests.swift`).

Regla general: **`vDSP_xxx(` → `DSP.xxx(`**, mismos argumentos, en el mismo orden (incluido el orden
invertido de `vsub`/`vdiv`), mismos pasos (también negativos), escalares por puntero (`&k`) y operación
en el sitio. Tipos:

| Accelerate | Fachada |
|---|---|
| `vDSP_Length(n)` | `DSPLength(n)` (es `UInt`, igual que antes) |
| `vDSP_Stride(s)` | `DSPStride(s)` (`Int`) |
| `DSPSplitComplex(realp:imagp:)` | `SplitComplex(realp:imagp:)` |
| `DSPComplex` (`bindMemory(to:)`, `withMemoryRebound(to:)`) | `InterleavedComplex` (misma disposición) |
| `vImage_Buffer(data:height:width:rowBytes:)` | `ImageBuffer(data:height:width:rowBytes:)` |
| `vImagePixelCount(x)` | `PixelCount(x)` |
| `kvImageNoError` | `imageNoError` |

## Operaciones (las 46 que usan AudioKit, StemKit, StudyKit y TabKit)

| vDSP / vForce / vImage | Fachada |
|---|---|
| `vDSP_vadd`, `vDSP_vaddD` | `DSP.vadd`, `DSP.vaddD` |
| `vDSP_vsub` (c = a − b, primero el sustraendo) | `DSP.vsub` |
| `vDSP_vmul` | `DSP.vmul` |
| `vDSP_vdiv` (c = a / b, primero el divisor) | `DSP.vdiv` |
| `vDSP_vma` (d = a·b + c) | `DSP.vma` |
| `vDSP_vsma` (d = a·k + c) | `DSP.vsma` |
| `vDSP_vsmsa` (d = a·k + s) | `DSP.vsmsa` |
| `vDSP_vsmul`, `vDSP_vsmulD` | `DSP.vsmul`, `DSP.vsmulD` |
| `vDSP_vsadd` | `DSP.vsadd` |
| `vDSP_vfill`, `vDSP_vclr` | `DSP.vfill`, `DSP.vclr` |
| `vDSP_vrvrs` | `DSP.vrvrs` |
| `vDSP_vabs`, `vDSP_vabsD` | `DSP.vabs`, `DSP.vabsD` |
| `vDSP_vmax`, `vDSP_vmaxD` | `DSP.vmax`, `DSP.vmaxD` |
| `vDSP_vthres` | `DSP.vthres` |
| `vDSP_vspdp` (Float → Double) | `DSP.vspdp` |
| `vDSP_sve`, `vDSP_svesq` | `DSP.sve`, `DSP.svesq` |
| `vDSP_meanv`, `vDSP_measqv`, `vDSP_rmsqv` | `DSP.meanv`, `DSP.measqv`, `DSP.rmsqv` |
| `vDSP_maxmgv`, `vDSP_maxvD` | `DSP.maxmgv`, `DSP.maxvD` |
| `vDSP_dotpr`, `vDSP_dotprD` | `DSP.dotpr`, `DSP.dotprD` |
| `vDSP.maximum(x)` (Float o Double) | `DSP.maximum(x)` |
| `vDSP.convertElements(of:to:)` (Float ↔ Double) | `DSP.convertElements(of:to:)` |
| `vDSP_conv`, `vDSP_convD` | `DSP.conv`, `DSP.convD` |
| `vDSP_desamp` | `DSP.desamp` |
| `vDSP_mmul` | `DSP.mmul` |
| `vDSP_zvabs`, `vDSP_zvmul`, `vDSP_zvmov` (`&split`) | `DSP.zvabs`, `DSP.zvmul`, `DSP.zvmov` (`&split` de `SplitComplex`) |
| `vDSP_ctoz`, `vDSP_ztoc` (paso de `C` en `Float`, 2 = contiguo) | `DSP.ctoz`, `DSP.ztoc` |
| `vvlogf`, `vvlog1pf`, `vvlog10f` (`&count` Int32) | `DSP.vvlogf`, `DSP.vvlog1pf`, `DSP.vvlog10f` |
| `vImageConvert_Planar16FtoPlanarF(&src, &dst, vImage_Flags(kvImageNoFlags))` | `DSP.convertPlanar16FtoPlanarF(&src, &dst)` (sin flags; devuelve `Int`, 0 bien) |

## Setups (clases; se destruyen solas en `deinit`)

| Accelerate | Fachada |
|---|---|
| `vDSP_DFT_zrop_CreateSetup(prev, n, .FORWARD / .INVERSE)` → `vDSP_DFT_Setup?` | `DSP.RealDFT(count: n, direction: .forward / .inverse)` → opcional |
| `vDSP_DFT_zop_CreateSetup(prev, n, dir)` | `DSP.ComplexDFT(count: n, direction: dir)` |
| `vDSP_DFT_zop_CreateSetupD(prev, n, dir)` → `vDSP_DFT_SetupD?` | `DSP.ComplexDFTD(count: n, direction: dir)` |
| `vDSP_DFT_Execute(s, ir, ii, or, oi)`, `vDSP_DFT_ExecuteD(...)` | `s.execute(ir, ii, or, oi)` |
| `vDSP_DFT_DestroySetup(s)`, `vDSP_DFT_DestroySetupD(s)` | nada (quitar el `defer`/`deinit`) |
| `vDSP_biquad_CreateSetup(coeffs, secciones)` | `DSP.Biquad(coefficients: coeffs, sections: secciones)` |
| `vDSP_biquad(s, &delay, x, ix, &y, iy, n)` | `s.execute(&delay, x, ix, &y, iy, n)` |
| `vDSP_biquad_DestroySetup(s)` | nada |

El argumento `prev` (compartir tablas) desaparece. Las convenciones son las de vDSP:

- `RealDFT` adelante: entrada par/impar (`vDSP_ctoz` de la señal con paso 2), salida `or[0] = 2·X[0]`,
  `oi[0] = 2·X[n/2]`, `or[k] + i·oi[k] = 2·X[k]`. Inversa: la misma disposición, sin normalizar (ida y
  vuelta = 2n·x).
- `ComplexDFT[D]`: adelante e^{-i}, inversa e^{+i}, sin normalizar.
- `Biquad`: coeficientes `[b0, b1, b2, a1, a2]` por sección; `delay` de 2·secciones + 2 `Float`, del más
  antiguo al más reciente: `[x[n-2], x[n-1], y1[n-2], y1[n-1], …]`.
- Los setups son `Sendable` y se pueden ejecutar desde varios hilos a la vez (como los de vDSP).

## Si falta una operación

NativeKit está congelada durante la ola 2 (plan, «Fase 7c», paso 6): la parte que la necesite la añade en
un fichero suyo, `Sources/NativeDSP/Extra<Paquete>.swift`, como extensión de `DSPPortable` y (dentro de
`#if canImport(Accelerate)`) de `DSPAccelerate` con la misma firma, con su caso en los tests, y lo dice en
su informe.
