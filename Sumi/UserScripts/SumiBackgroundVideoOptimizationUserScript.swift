import Foundation
import WebKit

@MainActor
final class SumiBackgroundVideoOptimizationUserScript: NSObject, SumiUserScript {
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let messageNames: [String] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}

    let source = """
    (() => {
        const apiName = "__sumiBackgroundVideoOptimizer";
        if (window[apiName]) {
            return;
        }

        const commandType = "__sumiBackgroundVideoOptimizationCommand";
        const states = new WeakMap();
        let nativeMode = "visible";
        let nativeGraceMs = 10000;
        let hiddenSince = { value: 0 };
        let timer = { value: 0 };

        function nextCommandId() {
            return `${Date.now()}:${Math.random()}`;
        }

        function stateFor(video) {
            let state = states.get(video);
            if (!state) {
                state = {
                    disabledTracks: [],
                    pausedBySumi: false
                };
                states.set(video, state);
            }
            return state;
        }

        function mediaElements() {
            return Array.from(document.querySelectorAll("video"));
        }

        function isPlaying(video) {
            return !video.paused && !video.ended && video.readyState > 0;
        }

        function hasDefinitelyNoAudibleTrack(video) {
            if (video.muted || video.volume <= 0) {
                return true;
            }
            if (video.audioTracks && video.audioTracks.length === 0) {
                return true;
            }
            return false;
        }

        function disableSelectedVideoTracks(video) {
            const tracks = video.videoTracks;
            if (!tracks || !tracks.length) {
                return false;
            }

            const selectedTracks = [];
            for (let index = 0; index < tracks.length; index += 1) {
                const track = tracks[index];
                if (track && track.selected) {
                    selectedTracks.push({ id: track.id || "", index });
                }
            }

            if (!selectedTracks.length && tracks.selectedIndex >= 0) {
                const index = tracks.selectedIndex;
                const track = tracks[index];
                if (track) {
                    selectedTracks.push({ id: track.id || "", index });
                }
            }

            if (!selectedTracks.length) {
                return false;
            }

            const state = stateFor(video);
            if (!state.disabledTracks.length) {
                state.disabledTracks = selectedTracks;
            }

            for (const selected of selectedTracks) {
                const track = tracks[selected.index];
                if (track) {
                    track.selected = false;
                }
            }
            return true;
        }

        function restoreVideoTracks(video) {
            const state = states.get(video);
            if (!state || !state.disabledTracks.length) {
                return;
            }

            const tracks = video.videoTracks;
            if (tracks && tracks.length) {
                for (const saved of state.disabledTracks) {
                    let restored = false;
                    if (saved.id) {
                        for (let index = 0; index < tracks.length; index += 1) {
                            const track = tracks[index];
                            if (track && track.id === saved.id) {
                                track.selected = true;
                                restored = true;
                                break;
                            }
                        }
                    }
                    if (!restored && tracks[saved.index]) {
                        tracks[saved.index].selected = true;
                    }
                }
            }

            state.disabledTracks = [];
        }

        function restorePausedPlayback(video) {
            const state = states.get(video);
            if (!state || !state.pausedBySumi) {
                return;
            }
            state.pausedBySumi = false;
            video.play().catch(() => {});
        }

        function applyVisible() {
            clearTimeout(timer.value);
            timer.value = 0;
            for (const video of mediaElements()) {
                restoreVideoTracks(video);
                restorePausedPlayback(video);
            }
        }

        function applyHiddenNow() {
            for (const video of mediaElements()) {
                if (!isPlaying(video)) {
                    continue;
                }

                if (nativeMode === "hiddenPreserveAudio") {
                    disableSelectedVideoTracks(video);
                    continue;
                }

                if (nativeMode === "hiddenPauseSilentVideo" && hasDefinitelyNoAudibleTrack(video)) {
                    const state = stateFor(video);
                    state.pausedBySumi = true;
                    video.pause();
                }
            }
        }

        function scheduleHiddenApply() {
            clearTimeout(timer.value);
            const elapsed = hiddenSince.value ? Date.now() - hiddenSince.value : 0;
            const delay = Math.max(0, nativeGraceMs - elapsed);
            timer.value = setTimeout(applyHiddenNow, delay);
        }

        function effectiveMode() {
            if (nativeMode !== "visible") {
                return nativeMode;
            }
            return document.hidden ? "hiddenPauseSilentVideo" : "visible";
        }

        function applyEffectiveMode() {
            const mode = effectiveMode();
            if (mode === "visible") {
                applyVisible();
            } else {
                scheduleHiddenApply();
            }
        }

        function setMode(mode, graceMs, shouldBroadcast, commandId = null) {
            if (
                mode !== "visible"
                && mode !== "hiddenPreserveAudio"
                && mode !== "hiddenPauseSilentVideo"
            ) {
                return;
            }

            nativeMode = mode;
            nativeGraceMs = Number.isFinite(graceMs) ? Math.max(0, graceMs) : 10000;
            if (nativeMode === "visible") {
                hiddenSince.value = 0;
            } else if (!hiddenSince.value) {
                hiddenSince.value = Date.now();
            }

            applyEffectiveMode();

            if (shouldBroadcast) {
                broadcastToChildFrames(mode, nativeGraceMs, commandId || nextCommandId());
            }
        }

        function broadcastToChildFrames(mode, graceMs, commandId) {
            for (let index = 0; index < window.frames.length; index += 1) {
                try {
                    window.frames[index].postMessage({ commandType, mode, graceMs, commandId }, "*");
                } catch {}
            }
        }

        window.addEventListener("message", (event) => {
            const data = event.data;
            if (!data || data.commandType !== commandType) {
                return;
            }
            setMode(
                data.mode,
                Number(data.graceMs),
                true,
                typeof data.commandId === "string" ? data.commandId : nextCommandId()
            );
        });

        document.addEventListener("visibilitychange", () => {
            applyEffectiveMode();
        }, true);

        document.addEventListener("play", (event) => {
            if (event.target instanceof HTMLVideoElement && effectiveMode() !== "visible") {
                scheduleHiddenApply();
            }
        }, true);

        new MutationObserver(() => {
            if (effectiveMode() !== "visible") {
                scheduleHiddenApply();
            }
        }).observe(document.documentElement || document, {
            childList: true,
            subtree: true
        });

        window[apiName] = {
            setNativeVisibility(mode, graceMs) {
                setMode(mode, Number(graceMs), true, nextCommandId());
            }
        };

        applyEffectiveMode();
    })();
    """
}
