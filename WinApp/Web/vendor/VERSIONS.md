# Dependencias vendorizadas (sin build, sin npm en el repo)

Bajadas con curl de jsDelivr (espejo de npm) y fijadas por versión. Se resuelven con el import map de `index.html`.
Todas MIT salvo htm (Apache-2.0) y las fuentes (SIL OFL 1.1, textos en `../fonts/LICENSE-*.txt`).

| Fichero | Paquete | Versión | URL | SHA-256 |
|---|---|---|---|---|
| preact.module.js | preact (MIT) | 10.29.8 | https://cdn.jsdelivr.net/npm/preact@10.29.8/dist/preact.module.js | c30e721ebfdc6e2ad4c18c14d2dfb82667829c8aec27de1207774e3fc16858a8 |
| hooks.module.js | preact/hooks (MIT) | 10.29.8 | https://cdn.jsdelivr.net/npm/preact@10.29.8/hooks/dist/hooks.module.js | a6ee626f2d01570592dd569a792e3f050154aa02890eead8c223fa3ed5aa3d5a |
| htm.module.js | htm (Apache-2.0, no MIT) | 3.1.1 | https://cdn.jsdelivr.net/npm/htm@3.1.1/dist/htm.module.js | ab33dd3f38059b9be4d5f5350128eefb2356639c4e0bbe9d9e8b3ba75847e9e4 |
| signals.module.js | @preact/signals (MIT) | 2.11.4 | https://cdn.jsdelivr.net/npm/@preact/signals@2.11.4/dist/signals.module.js | 89074d9db96b7f8e1be47f93913355b8cef829fb939f18a3a3ee320854ceebf8 |
| signals-core.module.js | @preact/signals-core (MIT) | 1.14.5 | https://cdn.jsdelivr.net/npm/@preact/signals-core@1.14.5/dist/signals-core.module.js | 45c263e519aaf3b6ef9b0a12a8b63dc06cdfcbd35bffc8203ec68c6117e6fcd7 |


## Fuentes (`../fonts/`, subconjunto latin, woff2)

| Fichero | Paquete | Versión | SHA-256 |
|---|---|---|---|
| inter-latin-{400,500,600}.woff2 | @fontsource/inter (OFL 1.1) | 5.3.0 | ver `shasum -a 256` |
| space-grotesk-latin-{500,700}.woff2 | @fontsource/space-grotesk (OFL 1.1) | 5.3.0 | ver `shasum -a 256` |

URL: `https://cdn.jsdelivr.net/npm/@fontsource/<familia>@5.3.0/files/<familia>-latin-<peso>-normal.woff2`
- fonts/inter-latin-400.woff2 8909904ab6c872eb994093482a88a28eca2cd95912d7b6fecd72103b0dc07edc
- fonts/inter-latin-500.woff2 f3779f1efccc4bdcdf9c0a02ab95bf6bd092ed09c48c08cedc725889edd1d19f
- fonts/inter-latin-600.woff2 f9a06e79cd3a2a20951c0f0e28f66dd0e6d3fda73911d640a2125c8fcb78f21a
- fonts/space-grotesk-latin-500.woff2 1b1a8131d9edf975d9decee81e2f2bf504812f7a4f498e5500f28a613e22e64c
- fonts/space-grotesk-latin-700.woff2 35f8aec56cfd5cbfdb03cc68733a54a0b05bb3617ffcd5fd332badc0b045ca55
