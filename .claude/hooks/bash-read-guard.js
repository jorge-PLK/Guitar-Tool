#!/usr/bin/env node
// bash-read-guard — PreToolUse hook on Bash (ToneForge, main thread and subagents)
//
// Measured 14-22 Nov 2026 over 58 sessions and 376 subagents: subagents were 68 %
// of the weighted spend, and their single largest injector was Bash used as a
// file reader — `cd <dir> && grep/cat/sed …`: 3,123 calls, 2.7M tokens, 875 per
// call, plus ~1M more from unbounded `grep -r`. Every injected token is re-read
// on each remaining request of that agent (median 26-62), so the cost multiplies.
// `read-amplify` only watches the Read tool, so `cat` of a whole file slipped past
// it, and a written rule (tf-docs already forbade `cd … &&`) was not followed.
//
// Denies, with the alternative in the reason:
//   1. `cd <dir>` followed by a reading command (cwd is already the project root).
//   2. `cat` of files over CAT_MAX_BYTES (or of a glob) with no bounding pipe.
//   3. `sed -n 'A,Bp'` printing more than SED_MAX_LINES lines.
//   4. `head`/`tail -n N` of a file with N > HEAD_MAX_LINES.
//   5. recursive grep/rg with no bound (-l, -c, -q, -m, or | head/tail/wc).
// Anything it cannot parse is allowed: never stand between the model and a build.

const fs = require('fs');
const path = require('path');

const CAT_MAX_BYTES = 3000;   // ~800 tokens
const SED_MAX_LINES = 80;
const HEAD_MAX_LINES = 150;
const READ_VERBS = /^(cat|grep|egrep|fgrep|rg|sed|head|tail|ls|find|wc|awk|less|more|nl|tree)$/;
const BOUNDS = /^(head|tail|wc)$/;

// Split a command into pipelines of stages, respecting quotes.
function parse(cmd) {
  const pipelines = [[]];
  let cur = '', q = null;
  const pushStage = () => { pipelines[pipelines.length - 1].push(cur.trim()); cur = ''; };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i], n = cmd[i + 1];
    if (q) { if (c === q) q = null; else if (c === '\\' && q === '"') { cur += c + (n || ''); i++; continue; } cur += c; continue; }
    if (c === "'" || c === '"') { q = c; cur += c; continue; }
    if (c === '\\') { cur += c + (n || ''); i++; continue; }
    if ((c === '&' && n === '&') || (c === '|' && n === '|')) { pushStage(); pipelines.push([]); i++; continue; }
    if (c === ';' || c === '\n') { pushStage(); pipelines.push([]); continue; }
    if (c === '|') { pushStage(); continue; }
    cur += c;
  }
  pushStage();
  return pipelines.map(p => p.filter(Boolean)).filter(p => p.length);
}

function words(stage) {
  const out = []; let cur = '', q = null, has = false;
  for (let i = 0; i < stage.length; i++) {
    const c = stage[i];
    if (q) { if (c === q) q = null; else cur += c; continue; }
    if (c === "'" || c === '"') { q = c; has = true; continue; }
    if (/\s/.test(c)) { if (cur || has) out.push(cur); cur = ''; has = false; continue; }
    cur += c;
  }
  if (cur || has) out.push(cur);
  // drop env assignments and wrappers
  while (out.length && (/^\w+=/.test(out[0]) || /^(sudo|time|command|nice)$/.test(out[0]))) out.shift();
  return out;
}

function fileArgs(w) {
  const files = [];
  for (let i = 1; i < w.length; i++) {
    const a = w[i];
    if (a.startsWith('-')) continue;
    if (a === '>' || a === '>>' || a === '2>' || a === '<') { i++; continue; }
    if (/^\d?>/.test(a)) continue;
    files.push(a);
  }
  return files;
}

function size(f, base) {
  try {
    const p = path.isAbsolute(f) ? f : path.join(base, f.replace(/^~(?=\/)/, process.env.HOME || '~'));
    const st = fs.statSync(p);
    return st.isFile() ? st.size : 0;
  } catch (e) { return 0; }
}

function check(cmd, cwd) {
  // Heredoc bodies are data (scripts, commit messages): analyse only up to the marker line.
  const hd = cmd.search(/<<-?\s*['"]?\w+/);
  if (hd >= 0) { const nl = cmd.indexOf('\n', hd); if (nl >= 0) cmd = cmd.slice(0, nl); }

  const pipes = parse(cmd);
  let base = cwd;

  for (let pi = 0; pi < pipes.length; pi++) {
    const stages = pipes[pi].map(words);
    const head = stages[0];
    if (!head.length) continue;
    const verb = path.basename(head[0]);
    const bounded = stages.slice(1).some(w => w.length && BOUNDS.test(path.basename(w[0])));

    // 1. cd followed by a reading command
    if (verb === 'cd' && stages.length === 1) {
      const later = pipes.slice(pi + 1).some(p => { const w = words(p[0]); return w.length && READ_VERBS.test(path.basename(w[0])); });
      if (later) return `\`cd …\` seguido de un comando de lectura. El directorio de trabajo ya es la raíz del proyecto: quita el \`cd\` y usa rutas relativas (o absolutas), y para leer usa Read, para buscar Grep con head_limit.`;
      if (head[1]) base = path.isAbsolute(head[1]) ? head[1] : path.join(base, head[1]);
      continue;
    }

    // 2. cat of large files
    if (verb === 'cat' && !bounded) {
      if (head.some(a => a.startsWith('<<'))) continue;
      if (head.includes('>') || head.includes('>>')) continue;  // writing, not reading
      const files = fileArgs(head);
      if (!files.length) continue;
      if (files.some(f => /[*?[]/.test(f))) return `\`cat\` de un glob vuelca varios ficheros enteros al contexto. Lee con Read solo el fichero que necesites, o busca con Grep.`;
      const total = files.reduce((s, f) => s + size(f, base), 0);
      if (total > CAT_MAX_BYTES) return `\`cat\` de ${files.join(', ')} (${Math.round(total / 1024)} KB) vuelca el fichero entero al contexto y se salta read-amplify. Usa Read (entero si vas a editarlo; offset/limit si no), o Grep para buscar.`;
      continue;
    }

    // 3. sed -n with a long range
    if (verb === 'sed' && head.includes('-n') && !bounded) {
      const script = head.find((a, i) => i > 0 && !a.startsWith('-')) || '';
      let lines = 0;
      for (const m of script.matchAll(/(\d+|\$)\s*,\s*(\d+|\$)\s*p/g)) {
        const a = m[1] === '$' ? 1e9 : +m[1], b = m[2] === '$' ? 1e9 : +m[2];
        lines += Math.max(0, b - a + 1);
      }
      if (lines > SED_MAX_LINES) return `\`sed -n\` de ${lines >= 1e8 ? 'hasta el final' : lines + ' líneas'}: es una lectura. Usa Read con offset/limit (entra en el control de relecturas) o Grep para lo que buscas.`;
      continue;
    }

    // 4. head/tail -n N of a file
    if ((verb === 'head' || verb === 'tail') && !bounded) {
      let n = 10;
      for (let i = 1; i < head.length; i++) {
        const a = head[i];
        if (a === '-n' && head[i + 1]) n = parseInt(head[i + 1], 10) || n;
        else if (/^-n\d+$/.test(a)) n = parseInt(a.slice(2), 10);
        else if (/^-\d+$/.test(a)) n = parseInt(a.slice(1), 10);
      }
      const files = fileArgs(head).filter(f => !/^\d+$/.test(f));
      if (files.length && n > HEAD_MAX_LINES) return `\`${verb}\` de ${n} líneas de un fichero es una lectura. Usa Read con offset/limit, o baja a ${HEAD_MAX_LINES} líneas.`;
      continue;
    }

    // 5. unbounded recursive search
    const isGrep = /^(grep|egrep|fgrep)$/.test(verb) || (verb === 'git' && head[1] === 'grep');
    const isRg = verb === 'rg';
    if ((isGrep || isRg) && !bounded) {
      const flags = head.filter(a => a.startsWith('-') && !a.startsWith('--')).join('');
      const long = head.filter(a => a.startsWith('--'));
      const recursive = isRg || verb === 'git' || /r|R/.test(flags) || long.includes('--recursive');
      const limited = /[lLcq]/.test(flags) || /m/.test(flags) ||
        long.some(a => /^--(files-with-matches|files-without-match|count|quiet|max-count|files)/.test(a));
      if (recursive && !limited) return `Búsqueda recursiva sin límite: puede devolver cientos de líneas. Acótala con \`| head -40\`, \`-l\` (solo ficheros) o \`-m N\`, o usa la herramienta Grep con head_limit.`;
    }
  }
  return null;
}

module.exports = { check, parse, words };

if (require.main === module) {
  let input = '';
  const guard = setTimeout(() => process.exit(0), 5000);
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', c => input += c);
  process.stdin.on('end', () => {
    clearTimeout(guard);
    try {
      const data = JSON.parse(input);
      if (data.tool_name !== 'Bash') process.exit(0);
      const cmd = String((data.tool_input || {}).command || '');
      const reason = check(cmd, data.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd());
      if (!reason) process.exit(0);
      process.stdout.write(JSON.stringify({
        systemMessage: 'bash-read-guard — lectura por Bash bloqueada.',
        hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason }
      }));
    } catch (e) { process.exit(0); }
  });
}
