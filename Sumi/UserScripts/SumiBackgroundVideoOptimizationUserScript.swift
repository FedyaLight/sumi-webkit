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
        // Lazily installed only while an optimization mode is active. When the
        // tab is visible (the common case) this stays null so dynamic pages
        // don't pay for a whole-document MutationObserver on every DOM change.
        let addedVideoObserver = null;
        // Viewport optimization runs only inside an active tab. It disables
        // the video track of offscreen videos so the decoder stops producing
        // frames while audio keeps playing. Never pauses playback.
        let viewportOptimizerInstalled = false;
        let viewportObserver = null;
        // Minimum share of a video that must be offscreen before we touch its
        // tracks, to avoid thrash around the viewport edge during scroll.
        const offscreenThreshold = 0.02;
        // Minimum area in CSS px^2; tiny decorative previews are ignored.
        const minVisibleArea = 48 * 48;

        function nextCommandId() {
            return `${Date.now()}:${Math.random()}`;
        }

        function stateFor(video) {
            let state = states.get(video);
            if (!state) {
                state = {
                    disabledTracks: [],
                    pausedBySumi: false,
                    viewportDisabled: false
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
            uninstallAddedVideoObserver();
            // Viewport optimization stays active in a visible tab.
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
            installAddedVideoObserver();
            clearTimeout(timer.value);
            const elapsed = hiddenSince.value ? Date.now() - hiddenSince.value : 0;
            const delay = Math.max(0, nativeGraceMs - elapsed);
            timer.value = setTimeout(applyHiddenNow, delay);
        }

        // Lazily observes newly added <video> elements only while an
        // optimization mode is active. Idle in the common visible-tab case so
        // dynamic pages don't pay for a whole-document MutationObserver.
        function installAddedVideoObserver() {
            if (addedVideoObserver) { return; }
            const target = document.documentElement || document;
            if (!target || typeof MutationObserver !== "function") { return; }
            addedVideoObserver = new MutationObserver(() => {
                if (effectiveMode() !== "visible") {
                    scheduleHiddenApply();
                }
            });
            addedVideoObserver.observe(target, {
                childList: true,
                subtree: true
            });
        }

        function uninstallAddedVideoObserver() {
            if (!addedVideoObserver) { return; }
            addedVideoObserver.disconnect();
            addedVideoObserver = null;
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

        // MARK: - Viewport optimization (active tab)

        // Returns true only when the active tab is a safe place to apply
        // viewport-based track disabling: the document is the foreground tab
        // and nothing on the page is currently in element fullscreen / PiP.
        function viewportOptimizationAllowed() {
            if (document.hidden) { return false; }
            if (document.fullscreenElement) { return false; }
            if (document.pictureInPictureElement) { return false; }
            return true;
        }

        function videoArea(entry) {
            const rect = entry && entry.boundingClientRect;
            if (!rect) { return 0; }
            return Math.max(0, rect.width) * Math.max(0, rect.height);
        }

        function disableVideoForViewport(video) {
            const state = stateFor(video);
            if (state.viewportDisabled) { return; }
            // Reuse the existing track-disabling path. Audio keeps playing.
            if (disableSelectedVideoTracks(video)) {
                state.viewportDisabled = true;
            }
        }

        function restoreVideoForViewport(video) {
            const state = states.get(video);
            if (!state || !state.viewportDisabled) { return; }
            state.viewportDisabled = false;
            restoreVideoTracks(video);
        }

        function reevaluateViewportVideos() {
            if (!viewportOptimizationAllowed()) {
                // Tab/background changed under us: hand control back to the
                // native reconcile path so the right mode is re-applied.
                for (const video of mediaElements()) {
                    restoreVideoForViewport(video);
                }
                return;
            }

            for (const video of mediaElements()) {
                if (!isPlaying(video)) { continue; }
                // We never pause playback in the viewport path: muted, silent,
                // and audible videos alike only get their video track disabled
                // while offscreen so the decoder stops producing frames.
                if (!video.videoTracks || !video.videoTracks.length) { continue; }

                const rect = video.getBoundingClientRect();
                const area = Math.max(0, rect.width) * Math.max(0, rect.height);
                if (area < minVisibleArea) { continue; }

                // Compute the on-screen share without a second layout query.
                const vw = document.documentElement.clientWidth || window.innerWidth || 0;
                const vh = document.documentElement.clientHeight || window.innerHeight || 0;
                const left = Math.max(rect.left, 0);
                const right = Math.min(rect.right, vw);
                const top = Math.max(rect.top, 0);
                const bottom = Math.min(rect.bottom, vh);
                const visibleArea = Math.max(0, right - left) * Math.max(0, bottom - top);
                const visibleShare = area > 0 ? visibleArea / area : 0;

                if (visibleShare <= (1 - offscreenThreshold)) {
                    disableVideoForViewport(video);
                } else {
                    restoreVideoForViewport(video);
                }
            }
        }

        function observeVideoForViewport(video) {
            if (!viewportObserver || video.__sumiViewportObserved) { return; }
            video.__sumiViewportObserved = true;
            viewportObserver.observe(video);
        }

        function observeAllVideosForViewport() {
            if (!viewportObserver) { return; }
            for (const video of mediaElements()) {
                observeVideoForViewport(video);
            }
        }

        function installViewportOptimizer() {
            if (viewportOptimizerInstalled) { return; }
            if (typeof IntersectionObserver !== "function") { return; }
            viewportObserver = new IntersectionObserver((entries) => {
                for (const entry of entries) {
                    if (entry.target instanceof HTMLVideoElement) {
                        // Track the latest area so reevaluateViewportVideos
                        // can decide without querying layout again.
                        entry.target.__sumiLastRect = entry.boundingClientRect;
                    }
                }
                scheduleViewportReevaluate();
            }, {
                root: null,
                threshold: [0, 0.1, 0.25, 0.5, 0.75, 1]
            });
            viewportOptimizerInstalled = true;
            observeAllVideosForViewport();
            scheduleViewportReevaluate();
        }

        function uninstallViewportOptimizer() {
            if (!viewportOptimizerInstalled) { return; }
            if (viewportObserver) {
                viewportObserver.disconnect();
                viewportObserver = null;
            }
            viewportOptimizerInstalled = false;
            for (const video of mediaElements()) {
                restoreVideoForViewport(video);
            }
        }

        let viewportReevaluateScheduled = false;
        function scheduleViewportReevaluate() {
            if (viewportReevaluateScheduled) { return; }
            viewportReevaluateScheduled = true;
            setTimeout(() => {
                viewportReevaluateScheduled = false;
                reevaluateViewportVideos();
            }, 120);
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
            scheduleViewportReevaluate();
        }, true);

        document.addEventListener("play", (event) => {
            if (event.target instanceof HTMLVideoElement) {
                observeVideoForViewport(event.target);
                if (effectiveMode() !== "visible") {
                    scheduleHiddenApply();
                } else {
                    scheduleViewportReevaluate();
                }
            }
        }, true);

        // Catch videos that enter/leave element fullscreen or PiP on the page
        // so we never disable tracks while the user is actively watching.
        const fullScreenEvents = ["fullscreenchange", "webkitfullscreenchange"];
        for (const evt of fullScreenEvents) {
            document.addEventListener(evt, () => {
                if (!viewportOptimizationAllowed()) {
                    for (const video of mediaElements()) {
                        restoreVideoForViewport(video);
                    }
                } else {
                    scheduleViewportReevaluate();
                }
            }, true);
        }
        document.addEventListener("enterpictureinpicture", () => {
            if (!viewportOptimizationAllowed()) {
                for (const video of mediaElements()) {
                    restoreVideoForViewport(video);
                }
            }
        }, true);
        document.addEventListener("leavepictureinpicture", () => {
            scheduleViewportReevaluate();
        }, true);

        window[apiName] = {
            setNativeVisibility(mode, graceMs) {
                setMode(mode, Number(graceMs), true, nextCommandId());
            }
        };

        applyEffectiveMode();
        // Viewport optimization is always safe to install in the foreground
        // tab; it disables video tracks only while it is permitted by
        // viewportOptimizationAllowed().
        installViewportOptimizer();
    })();
    """
}
