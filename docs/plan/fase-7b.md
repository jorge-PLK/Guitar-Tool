# Fase 7b · Retoques de interfaz (rama desde `fase-7`)

Lista de Jorge del 17/11/2026, tras usar la app. La mini-spec se escribe al empezar; las dudas abiertas van al final.

*Decisión de Jorge, 22/11/2026: la 7b se hará sobre la interfaz en Flutter (ver «Condición de cierre de la 7c»), no sobre SwiftUI ni sobre la página de WebView2.*

***Descartada (Jorge, 22/11/2026, ADR-021):** la Fase 7b no se hace. La Fase 7f porta la interfaz 1:1 a Flutter y, terminado el port, los cambios de UX se decidirán sobre lo portado en una fase nueva. La lista de abajo queda como historia y como punto de partida de esa fase.*

Biblioteca:

- [ ] Quitar la cabecera de contadores (temas, tomas grabadas, vídeos exportados): no aporta
- [ ] Buscador de temas (título y artista)
- [ ] «Importar tema» abre un popup con un campo para el enlace y un botón «Importar fichero»
- [ ] Ese campo hace también de buscador de Spotify: si lo escrito no es un enlace, al pulsar «Importar» se buscan 10 resultados en Spotify, cada uno con un botón que lo reproduce en Spotify para oírlo antes de elegir
- [ ] Dos vistas: por tema (la actual) y por artista
- [ ] «Abrir» pasa a ser «Seleccionar», con otro botón para mostrar en Finder. El tema seleccionado aparece entre Ajustes y el dispositivo (título y artista, empujándolos); si no cabe se trunca y al pasar el ratón el texto se desplaza para verse entero. Al pulsarlo lleva a su página de información, con Mostrar en Finder, Eliminar y las grabaciones guardadas del tema

- [ ] Corregir título y artista desde la lista: icono de lápiz en cada fila (añadido el 18/11/2026)
- [ ] Vista Artistas en recuadros con foto (de Spotify) y nombre; al pulsar uno, sus temas con flecha para volver; al volver de Temas, siempre la cuadrícula completa (añadido el 18/11/2026)

Backing track:

- [ ] Alargar o encoger una sección en el modo expandido sigue fallando
- [ ] No se puede crear una sección dentro de otra. Al empujar una sección contra otra, la segunda se encoge; el solo nunca se encoge de forma indirecta, solo se modifica directamente

Grabar:

- [ ] Reproducir las tomas hechas, para verlas y volver a evaluarlas por si hay que mejorarlas

Ajustes:

- [ ] El apartado «Biblioteca y equipo» pasa a ser solo «Biblioteca», sin las guitarras del perfil de equipo

Condición de paso: los diez puntos comprobados por Jorge en la app.

Decidido con Jorge (17/11/2026):

- Búsqueda en Spotify con clave propia: app de desarrollador gratuita, Web API, flujo client credentials (sin usuario). Client ID y secret en un `.env` que no se versiona (`.env.example` sí, con los nombres de las variables); nunca en el repositorio ni dentro del bundle. La app (lanzada desde Finder no ve el entorno de la shell) lee `<support dir>/.env`, si no existe el del directorio de soporte por defecto (`~/Library/Application Support/ToneForge/.env`, chmod 600), y las variables de entorno con el mismo nombre mandan sobre ambos. Jorge crea la app guiado por el orquestador. Es una excepción a «sin credenciales» de ADR-008 solo para buscar: los metadatos y el audio siguen igual. Reproducir en Spotify = abrir `spotify:track:<id>` en su app. Token: client credentials no da refresh token (los 180 días del panel son del flujo con usuario); el access token dura 1 h, se guarda en memoria y se pide otro al caducar o con un 401. Jorge tiene Premium «por ahora»: si la cuenta o la clave dejan de valer (401/403, sin clave), el campo avisa y sigue aceptando enlaces e «Importar fichero»; la búsqueda no puede ser imprescindible.
- Solo: si se empuja otra sección contra él, el arrastre se para en su borde.
- Tema seleccionado en la barra lateral: ocupa el hueco encima del bloque del dispositivo y empuja «Ajustes» hacia arriba. Sin tema seleccionado (al abrir la app, la selección no se recuerda), «Ajustes» queda donde está ahora.
- Perfil de equipo: las guitarras salen de la interfaz y del modelo de datos (con migración de los proyectos existentes); lo que guarda de audio (dispositivos, canales, latencia) se conserva.
