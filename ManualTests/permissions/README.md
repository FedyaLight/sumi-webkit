# Sumi Permission Manual Tests

These pages validate Sumi's implemented normal-tab permission system. Serve them from localhost; do not open them with `file://`, because most permission APIs require a secure context and Sumi's policy treats `localhost`, `127.0.0.1`, and `[::1]` as trusted local development origins.

## Serve The Suite

```sh
cd ManualTests/permissions
python3 -m http.server 8000
```

Open `http://localhost:8000/index.html` in a normal Sumi tab.

## Storage Access Two-Origin Setup

Storage Access API validation needs an embedded third-party origin. Use two localhost ports:

```sh
cd ManualTests/permissions
python3 -m http.server 8000
```

In another terminal:

```sh
cd ManualTests/permissions
python3 -m http.server 8001
```

Open `http://localhost:8000/storage-access-embedder.html`. The embedder page loads `storage-access-frame.html` from `http://127.0.0.1:8001/` by default. The embedder is the top-level origin; the frame is the requesting embedded origin.

## macOS Permissions

Some tests require macOS system permission in addition to Sumi site permission:

- Camera
- Microphone
- Location Services
- Notifications
- Screen Recording

Reset them manually in System Settings -> Privacy & Security. For TCC-backed permissions, `tccutil reset Camera com.sumi.browser`, `tccutil reset Microphone com.sumi.browser`, `tccutil reset Location com.sumi.browser`, and `tccutil reset ScreenCapture com.sumi.browser` can help when testing a signed build with the default bundle identifier.

## Reset Sumi Site Permissions

- URL hub -> Permissions -> Reset permissions for this site
- Privacy Settings -> Site Settings -> Site detail -> Reset permissions

These resets should clear saved permission decisions for the exact site/profile scope without deleting cookies, website data, tracking-protection overrides, zoom, HTTP auth, or extension permissions.

## One-Time Behavior

Use pages such as `media.html`, `geolocation.html`, and `screen-capture.html`:

- Choose `Allow this time`.
- Repeat the same request on the same page visit; it may reuse the current page grant.
- Reload; Sumi should prompt again.
- Navigate away and back; Sumi should prompt again.
- Close the tab; Sumi should prompt again in a new tab.

## Anti-Abuse Behavior

Repeatedly dismiss the same prompt for the same site/profile/permission key. Sumi should enter cooldown/embargo without storing a site Block. Manual Allow or Reset for the exact key should clear suppression; explicit stored Block remains a normal site decision.

## Automatic Cleanup

Use Privacy Settings -> Site Settings -> Automatic permission cleanup to toggle cleanup. Do not wait 90 days manually; stale-date behavior is validated with injected clocks in unit tests. Manual validation should confirm the toggle/status text, auto-revoked recent activity after a test-triggered cleanup path, and that cleanup removes only stale saved Allow decisions.
