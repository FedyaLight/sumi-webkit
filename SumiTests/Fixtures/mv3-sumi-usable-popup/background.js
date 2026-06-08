chrome.runtime.onInstalled.addListener(function () {});

chrome.runtime.onMessage.addListener(function (message, sender, sendResponse) {
  if (message && message.type === "sumi-usable-ping") {
    sendResponse({ type: "sumi-usable-pong" });
    return true;
  }
});

chrome.runtime.onConnect.addListener(function (port) {
  if (port.name !== "sumi-usable-port") {
    return;
  }
  port.onMessage.addListener(function (message) {
    if (message && message.type === "sumi-usable-ping") {
      port.postMessage({ type: "sumi-usable-pong" });
    }
  });
});
