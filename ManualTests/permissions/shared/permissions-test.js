(function () {
  "use strict";

  function nowStamp() {
    return new Date().toISOString();
  }

  function formatError(error) {
    if (!error) {
      return { message: "Unknown error" };
    }
    return {
      name: error.name || error.constructor?.name || "Error",
      message: error.message || String(error),
      code: error.code,
    };
  }

  function safeJson(value) {
    try {
      return JSON.stringify(value, null, 2);
    } catch (error) {
      return String(value);
    }
  }

  function appendLog(message, detail) {
    const target = document.querySelector("[data-log]");
    if (!target) {
      return;
    }
    const suffix = detail === undefined ? "" : "\n" + safeJson(detail);
    target.textContent = `[${nowStamp()}] ${message}${suffix}\n\n${target.textContent}`;
  }

  function clearLog() {
    const target = document.querySelector("[data-log]");
    if (target) {
      target.textContent = "";
    }
  }

  function setStatus(message, kind) {
    const target = document.querySelector("[data-status]");
    if (!target) {
      return;
    }
    target.textContent = message;
    target.classList.remove("result-ok", "result-warn", "result-error");
    if (kind) {
      target.classList.add(`result-${kind}`);
    }
  }

  function runtimeRows() {
    let origin = "(opaque or unavailable)";
    try {
      origin = window.location.origin || origin;
    } catch (error) {
      origin = "(origin read failed)";
    }
    return [
      ["Current URL", window.location.href],
      ["Origin", origin],
      ["Secure context", String(window.isSecureContext)],
      ["User agent", navigator.userAgent],
      ["Timestamp", nowStamp()],
    ];
  }

  function renderRuntimeInfo() {
    document.querySelectorAll("[data-runtime-info]").forEach((target) => {
      target.classList.add("runtime-info");
      target.innerHTML = runtimeRows()
        .map(([label, value]) => `<div><strong>${label}</strong><br>${escapeHtml(value)}</div>`)
        .join("");
    });
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function safeClick(selector, handler) {
    const node = document.querySelector(selector);
    if (!node) {
      appendLog(`Missing control ${selector}`);
      return;
    }
    node.addEventListener("click", async (event) => {
      try {
        await handler(event);
      } catch (error) {
        appendLog(`${selector} failed`, formatError(error));
        setStatus(`${selector} failed: ${formatError(error).message}`, "error");
      }
    });
  }

  async function queryPermission(name, descriptor) {
    if (!navigator.permissions?.query) {
      appendLog(`navigator.permissions.query unavailable for ${name}`);
      return null;
    }
    try {
      const status = await navigator.permissions.query(descriptor || { name });
      appendLog(`${name} permission state`, { state: status.state });
      status.onchange = () => appendLog(`${name} permission changed`, { state: status.state });
      return status;
    } catch (error) {
      appendLog(`${name} permission query failed`, formatError(error));
      return null;
    }
  }

  async function queryPermissions(names) {
    const results = {};
    for (const name of names) {
      const status = await queryPermission(name);
      results[name] = status ? status.state : "unavailable";
    }
    return results;
  }

  function describeTrack(track) {
    return {
      kind: track.kind,
      label: track.label || "(no label)",
      readyState: track.readyState,
      enabled: track.enabled,
      muted: track.muted,
    };
  }

  function attachTrackLogging(stream, label) {
    stream.getTracks().forEach((track) => {
      appendLog(`${label} track added`, describeTrack(track));
      track.addEventListener("ended", () => appendLog(`${label} track ended`, describeTrack(track)));
      track.addEventListener("mute", () => appendLog(`${label} track mute`, describeTrack(track)));
      track.addEventListener("unmute", () => appendLog(`${label} track unmute`, describeTrack(track)));
    });
  }

  function renderTracks(stream, selector) {
    const target = document.querySelector(selector);
    if (!target) {
      return;
    }
    if (!stream) {
      target.textContent = "No active tracks.";
      return;
    }
    target.textContent = safeJson(stream.getTracks().map(describeTrack));
  }

  function fileSummary(fileList) {
    const files = Array.from(fileList || []);
    return {
      count: files.length,
      names: files.map((file) => file.name),
      types: files.map((file) => file.type || "(unknown)"),
      sizes: files.map((file) => file.size),
    };
  }

  function positionSummary(position) {
    const coords = position.coords;
    return {
      latitude: Number(coords.latitude.toFixed(6)),
      longitude: Number(coords.longitude.toFixed(6)),
      accuracyMeters: coords.accuracy,
      altitude: coords.altitude,
      altitudeAccuracy: coords.altitudeAccuracy,
      heading: coords.heading,
      speed: coords.speed,
      timestamp: new Date(position.timestamp).toISOString(),
    };
  }

  function installPage() {
    renderRuntimeInfo();
    document.querySelectorAll("[data-clear-log]").forEach((button) => {
      button.addEventListener("click", clearLog);
    });
  }

  window.SumiPermissionsTest = {
    appendLog,
    clearLog,
    formatError,
    setStatus,
    renderRuntimeInfo,
    safeClick,
    queryPermission,
    queryPermissions,
    describeTrack,
    attachTrackLogging,
    renderTracks,
    fileSummary,
    positionSummary,
    installPage,
  };

  document.addEventListener("DOMContentLoaded", installPage);
})();
