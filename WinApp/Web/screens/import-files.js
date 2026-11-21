import { signal } from '@preact/signals';
import { html } from '../html.js';
import { call, on } from '../bridge.js';
import { loadLibrary, notify, openProject } from '../state.js';
import { DuplicateDialog } from './library-dialogs.js';

// Importar ficheros (L-F4 y L-F5): selector con selección múltiple y arrastrar y soltar sobre la ventana.
// Mac: AppModel.pickAndImport / importFiles (un tema tras otro; lo que no es wav, flac o mp3 se ignora; el último repetido
// abre el aviso «Este tema ya está en la biblioteca»; un fallo avisa y sigue con el siguiente).

/// Extensiones admitidas (spec; las mismas que `JobEngine.importExtensions` del núcleo).
export const IMPORT_EXTENSIONS = ['wav', 'flac', 'mp3'];
const PICK_TIMEOUT_MS = 10 * 60 * 1000;
const IMPORT_TIMEOUT_MS = 60 * 60 * 1000;

const duplicateId = signal(null);

const baseName = p => String(p).split(/[\\/]/).pop();
export const isImportable = p => IMPORT_EXTENSIONS.includes((baseName(p).split('.').pop() ?? '').toLowerCase());

/// `importFiles` del Mac: importa en orden los ficheros admitidos (`import.file`, que espera a que acabe cada uno).
export async function importPaths(paths) {
  const files = (paths ?? []).filter(isImportable);
  if (!files.length) return;
  for (const path of files) {
    try {
      const res = await call('import.file', { path }, { timeout: IMPORT_TIMEOUT_MS });
      if (res.duplicate) duplicateId.value = res.id;
    } catch (e) {
      notify('error', `No se pudo importar ${baseName(path)}: ${e.message}`);
    }
  }
  await loadLibrary();
}

/// «Importar fichero…»: selector nativo con selección múltiple (`host.pickAudioFiles`).
export async function pickAndImport() {
  try {
    const picked = await call('host.pickAudioFiles', {}, { timeout: PICK_TIMEOUT_MS });
    if (picked.paths?.length) await importPaths(picked.paths);
  } catch (e) {
    notify('error', `No se pudo importar el tema: ${e.message}`);
  }
}

/// Aviso de tema repetido, a nivel de ventana como el `alert` del Mac.
export function ImportDuplicate() {
  const id = duplicateId.value;
  if (!id) return null;
  return html`<${DuplicateDialog} id=${id} onOpen=${openProject} onClose=${() => { duplicateId.value = null; }} />`;
}

/// Soltar ficheros sobre la ventana. WebView2 no da rutas a la página: la página avisa al anfitrión con
/// `postMessageWithAdditionalObjects` (los ficheros van como objetos adicionales) y el anfitrión contesta con el evento
/// `host.filesDropped {paths:[...]}` (contrato 8.3d). Sin anfitrión (mock, Mac de desarrollo) el arrastre se ignora.
export function installFileDrop() {
  const hasFiles = e => [...(e.dataTransfer?.types ?? [])].includes('Files');
  window.addEventListener('dragover', e => { if (hasFiles(e)) { e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; } });
  window.addEventListener('drop', e => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    const files = e.dataTransfer.files;
    const wv = window.chrome?.webview;
    if (wv?.postMessageWithAdditionalObjects && files?.length) {
      wv.postMessageWithAdditionalObjects(JSON.stringify({ method: 'host.dropFiles', params: { names: [...files].map(f => f.name) } }), files);
    }
  });
  on('host.filesDropped', p => importPaths(p?.paths ?? []));
}
