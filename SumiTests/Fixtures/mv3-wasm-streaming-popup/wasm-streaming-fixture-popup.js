(function () {
  const status = document.getElementById("wasm-status");

  function finish(outcome, detail) {
    status.dataset.outcome = outcome;
    if (detail) {
      status.dataset.detail = detail;
    }
  }

  if (
    !globalThis.WebAssembly
    || typeof WebAssembly.instantiateStreaming !== "function"
  ) {
    finish("unsupported");
    return;
  }

  WebAssembly.instantiateStreaming(fetch("./assets/test.wasm"))
    .then(function (result) {
      if (result && result.instance) {
        finish("ok");
        return;
      }
      finish("fail", "missing-instance");
    })
    .catch(function (error) {
      const message = String(error && error.message || error || "unknown");
      finish("fail", message.slice(0, 120));
    });
})();
