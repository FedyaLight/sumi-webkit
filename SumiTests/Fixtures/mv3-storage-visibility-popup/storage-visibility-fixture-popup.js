(function () {
  const status = document.getElementById("status");
  const markerKey = "mv3StartupStorageMarker";
  let onChangedCount = 0;

  function fail(reason) {
    status.textContent = reason;
    status.dataset.outcome = "fail";
  }

  function succeed() {
    status.textContent = "Storage Visibility OK";
    status.dataset.outcome = "ok";
  }

  chrome.storage.onChanged.addListener(function (changes, areaName) {
    if (areaName === "local" && changes && changes[markerKey]) {
      onChangedCount += 1;
    }
  });

  const port = chrome.runtime.connect({ name: "mv3-storage-visibility" });
  port.onMessage.addListener(function () {
    chrome.storage.local.get(markerKey, function (items) {
      if (!items || items[markerKey] !== "startup") {
        fail("storage-read-fail");
        port.disconnect();
        return;
      }
      if (onChangedCount < 1) {
        fail("storage-onchanged-fail");
        port.disconnect();
        return;
      }
      port.disconnect();
      succeed();
    });
  });

})();
