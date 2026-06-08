(function () {
  const status = document.getElementById("baseline-status");
  const button = document.getElementById("baseline-button");

  function fail(reason) {
    status.textContent = reason;
    status.dataset.outcome = "fail";
  }

  function succeed() {
    status.textContent = "Sumi Usable Popup OK";
    status.dataset.outcome = "ok";
  }

  button.addEventListener("click", function () {
    if (status.dataset.outcome === "ok") {
      status.textContent = "clicked";
    }
  });

  const manifest = chrome.runtime.getManifest();
  if (!manifest || manifest.manifest_version !== 3) {
    fail("manifest-fail");
    return;
  }

  chrome.storage.local.set({ sumiUsableFixture: "ok" }, function () {
    chrome.storage.local.get("sumiUsableFixture", function (items) {
      if (!items || items.sumiUsableFixture !== "ok") {
        fail("storage-fail");
        return;
      }

      chrome.runtime.sendMessage({ type: "sumi-usable-ping" }, function (response) {
        if (!response || response.type !== "sumi-usable-pong") {
          fail("sendMessage-fail");
          return;
        }

        const port = chrome.runtime.connect({ name: "sumi-usable-port" });
        port.onMessage.addListener(function (message) {
          if (!message || message.type !== "sumi-usable-pong") {
            fail("connect-fail");
            port.disconnect();
            return;
          }
          port.disconnect();

          chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
            if (!Array.isArray(tabs) || tabs.length === 0) {
              fail("tabs-fail");
              return;
            }

            chrome.permissions.contains(
              { permissions: ["activeTab"] },
              function (hasActiveTab) {
                chrome.permissions.getAll(function (all) {
                  if (
                    !hasActiveTab
                    || !all
                    || !Array.isArray(all.permissions)
                  ) {
                    fail("permissions-fail");
                    return;
                  }
                  succeed();
                });
              }
            );
          });
        });
        port.postMessage({ type: "sumi-usable-ping" });
      });
    });
  });
})();
