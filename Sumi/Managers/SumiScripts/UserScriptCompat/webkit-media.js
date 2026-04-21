/**
 * Sumi userscript compat: webkit-media
 *
 * Opt-in via `// @aura-compat webkit-media` or
 * `@require aura-internal://userscript-compat/webkit-media.js`
 *
 * WebKit can glitch when user media code calls AudioContext.prototype.suspend()
 * together with pausing HTMLMediaElement (common in translation / dubbing scripts).
 * This replaces suspend with a resolved no-op so audio graph state stays consistent
 * for typical userscript lifecycles. Opt-in only — affects contexts created after load.
 */
(function () {
  'use strict';
  if (globalThis.__auraWebkitMediaCompatInstalled) return;
  globalThis.__auraWebkitMediaCompatInstalled = true;
  var Ctor = globalThis.AudioContext || globalThis.webkitAudioContext;
  if (!Ctor || !Ctor.prototype) return;
  var proto = Ctor.prototype;
  if (typeof proto.suspend !== 'function') return;
  proto.suspend = function auraCompatSuspendNoOp() {
    return Promise.resolve();
  };
})();
