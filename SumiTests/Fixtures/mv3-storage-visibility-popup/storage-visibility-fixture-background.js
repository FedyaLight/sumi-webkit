chrome.runtime.onInstalled.addListener(function () {
  chrome.storage.local.set({ mv3InstallStorageMarker: "install" });
});

chrome.runtime.onConnect.addListener(function (port) {
  if (port.name !== "mv3-storage-visibility") {
    return;
  }
  chrome.storage.local.set({ mv3StartupStorageMarker: "startup" });
  port.postMessage({ type: "storage-written" });
});
