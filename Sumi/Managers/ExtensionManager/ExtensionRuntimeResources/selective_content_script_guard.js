(() => {
  const markerAttribute = __SUMI_MARKER_ATTRIBUTE_STRING__;
  const root = document.documentElement;
  if (root && root.getAttribute(markerAttribute) === "1") {
    return;
  }
  if (root) {
    root.setAttribute(markerAttribute, "1");
  }

  const originalScripts = __SUMI_ORIGINAL_SCRIPT_FILENAMES_JSON__;
  const runtimeAPI = globalThis.browser?.runtime || globalThis.chrome?.runtime;
  const resolveURL = (relativePath) => {
    if (runtimeAPI && typeof runtimeAPI.getURL === "function") {
      return runtimeAPI.getURL(relativePath);
    }
    return relativePath;
  };

  for (const relativePath of originalScripts) {
    const scriptURL = resolveURL(relativePath);
    const request = new XMLHttpRequest();
    request.open("GET", scriptURL, false);
    request.send(null);

    if (!((request.status >= 200 && request.status < 400) || request.status === 0)) {
      throw new Error("Sumi content-script guard failed to load " + relativePath);
    }

    (0, eval)(request.responseText + "\n//# sourceURL=" + scriptURL.replace(/\n/g, ""));
  }
})();
