(function () {
  if (window.__sumiAutofillFillProbeInstalled) {
    return;
  }
  window.__sumiAutofillFillProbeInstalled = true;

  const state = {
    inputEvents: 0,
    changeEvents: 0,
    lastInputAt: null,
    lastChangeAt: null,
  };

  function attachProbe(root) {
    root.querySelectorAll("input, textarea, select").forEach((field) => {
      if (field.dataset.sumiProbeAttached === "1") {
        return;
      }
      field.dataset.sumiProbeAttached = "1";
      field.addEventListener("input", () => {
        state.inputEvents += 1;
        state.lastInputAt = Date.now();
      });
      field.addEventListener("change", () => {
        state.changeEvents += 1;
        state.lastChangeAt = Date.now();
      });
    });
  }

  function scan() {
    attachProbe(document);
    document.querySelectorAll("iframe").forEach((frame) => {
      try {
        if (frame.contentDocument) {
          attachProbe(frame.contentDocument);
        }
      } catch (_) {
        // Cross-origin iframe — parent cannot observe DOM events.
      }
    });
  }

  window.__sumiAutofillFillProbe = {
    snapshot() {
      scan();
      return { ...state };
    },
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", scan, { once: true });
  } else {
    scan();
  }

  window.addEventListener("sumi:spa-form-ready", scan);
  const observer = new MutationObserver(scan);
  observer.observe(document.documentElement, { childList: true, subtree: true });
})();
