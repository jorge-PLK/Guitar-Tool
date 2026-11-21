// Gancho de QA (solo con `?demo=` en la URL; tf-webdev lo pasa con `--query demo=...`): deja la pantalla en un estado
// concreto para las capturas, usando las mismas acciones de la interfaz. No afecta al uso normal.
import { setRate, setLoop, seek, play, setTranspose, setCapo, transport, chordsExpanded } from './store.js';

const wait = ms => new Promise(r => setTimeout(r, ms));

export async function runDemo(name) {
  if (!name) return;
  const loop = (start, end, n) => setLoop(start, end, n);
  if (name === 'loop70') {
    await setRate(0.7);
    await loop(48.5, 80.5, 'Estribillo 1');
    await seek(52.2);
    await play();
  } else if (name === 'grid') {
    chordsExpanded.value = true;
    await setRate(0.7);
    await loop(48.5, 64.5, 'compases');
    await seek(53);
    await play();
  } else if (name === 'capo') {
    await setCapo(3);
    await setTranspose(-2);
    await seek(20);
  }
  await wait(0);
  return transport.value;
}
