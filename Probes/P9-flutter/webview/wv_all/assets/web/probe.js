// P9.4: utilidades de medida que llama Dart (probe.*).
(function (root) {
  function post(o) { try { root.webkit.messageHandlers.tf.postMessage(o); } catch (e) {} }
  root.__post = post;
  root.__keys = [];
  var recvList = [];

  var probe = {
    echo: function (n) { post({ event: 'echo', n: n }); },
    burst: function (k) {
      for (var i = 1; i <= k; i++) post({ event: 'b', n: i });
      post({ event: 'bdone', k: k });
    },
    recv: function (n) { recvList.push(n); },
    recvReport: function () {
      var seen = {}, dup = 0, ooo = 0, max = 0;
      for (var i = 0; i < recvList.length; i++) {
        var n = recvList[i];
        if (seen[n]) dup++; seen[n] = true;
        if (n < max) ooo++; else max = n;
      }
      var uniq = Object.keys(seen).length;
      var expected = 1000;
      post({ event: 'rdone', count: recvList.length, missing: expected - uniq, duplicates: dup, outOfOrder: ooo });
      recvList = [];
    },
    diag: function () {
      var fonts = [], loaded = false;
      try {
        document.fonts.forEach(function (f) {
          fonts.push({ family: f.family, status: f.status });
          if (/bravura|alphatab/i.test(f.family) && f.status === 'loaded') loaded = true;
        });
      } catch (e) {}
      return JSON.stringify({
        bravuraLoaded: loaded, fonts: fonts, shimOk: root.__shimOk, shimErr: root.__shimErr || null,
        href: String(location.href), alphaTab: typeof root.alphaTab, ua: navigator.userAgent
      });
    },
    resources: function () {
      var targets = ['font/Bravura.woff2', 'soundfont/sonivox.sf2'];
      var results = [];
      var pending = targets.length * 2 + 1;
      try {
        new FontFace('probeBravura', 'url(font/Bravura.woff2)').load()
          .then(function () { results.push({ url: 'font/Bravura.woff2', via: 'FontFace', ok: true }); done(); })
          .catch(function (e) { results.push({ url: 'font/Bravura.woff2', via: 'FontFace', ok: false, error: String(e) }); done(); });
      } catch (e) { results.push({ via: 'FontFace', ok: false, error: String(e) }); done(); }
      function done() { if (--pending === 0) post({ event: 'res', results: results }); }
      targets.forEach(function (t) {
        fetch(t).then(function (r) { return r.arrayBuffer().then(function (b) {
          results.push({ url: t, via: 'fetch', ok: true, status: r.status, bytes: b.byteLength }); done();
        }); }).catch(function (e) { results.push({ url: t, via: 'fetch', ok: false, error: String(e) }); done(); });
        try {
          var x = new XMLHttpRequest();
          x.open('GET', t); x.responseType = 'arraybuffer';
          x.onload = function () { results.push({ url: t, via: 'xhr', ok: true, status: x.status, bytes: x.response ? x.response.byteLength : 0 }); done(); };
          x.onerror = function () { results.push({ url: t, via: 'xhr', ok: false, error: 'onerror' }); done(); };
          x.send();
        } catch (e) { results.push({ url: t, via: 'xhr', ok: false, error: String(e) }); done(); }
      });
    },
    state: function () {
      var svg = document.querySelector('#alphaTab svg');
      var surf = document.querySelector('#alphaTab > div') || document.getElementById('alphaTab');
      return JSON.stringify({
        iw: root.innerWidth, ih: root.innerHeight,
        surfaceW: surf ? surf.getBoundingClientRect().width : 0,
        svg: document.querySelectorAll('#alphaTab svg').length + (svg ? 0 : 0),
        vis: document.visibilityState
      });
    },
    startCount: function (secs) {
      var raf = 0, ticks = 0, sec = 0, t0 = Date.now();
      function loop() { raf++; root.requestAnimationFrame(loop); }
      root.requestAnimationFrame(loop);
      setInterval(function () { ticks++; }, 100);
      var iv = setInterval(function () {
        sec++;
        post({ event: 'occ', sec: sec, raf: raf, ticks: ticks, vis: document.visibilityState, t: Date.now() - t0 });
        if (sec >= secs) clearInterval(iv);
      }, 1000);
    }
  };
  root.probe = probe;

  ['keydown', 'keyup'].forEach(function (type) {
    root.addEventListener(type, function (e) {
      var o = { event: 'key', type: type, key: e.key, code: e.code, meta: e.metaKey, ctrl: e.ctrlKey, shift: e.shiftKey, alt: e.altKey, repeat: e.repeat, ts: Date.now() };
      if (root.__keys.length < 5000) root.__keys.push(o);
      post(o);
    }, true);
  });
})(window);
