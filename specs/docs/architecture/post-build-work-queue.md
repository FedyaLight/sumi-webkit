# Post-build work queue

This queue is the first concrete execution order after the baseline Helium app
 launches successfully.

## 1. Prove the baseline app

- launch the built Helium app
- verify normal browser window creation
- verify vertical tabs are enabled in the upstream baseline used by Aura

## 2. Mount Aura shell ownership

- add the first `BrowserView` integration hook for `AuraChromeController`
- add the first `VerticalTabStripRegionView` host for the Aura sidebar
- ensure no duplicate toolbar, sidebar, or media runtime is created

## 3. Replace the browser chrome

- replace the visible sidebar path with Aura's spaces/folders/essentials shell
- replace the visible address bar path with Aura's canonical URL bar and hub
- keep Helium as the owner of tabs, profiles, navigation, extensions, and media

## 4. Bind product state

- load `AuraProfileState`
- load `AuraWindowState`
- bind `AuraProfileRouter`
- bind `AuraThemeService`
- bind `AuraMediaSessionService`

## 5. Reach first useful Aura window

Success for this phase means:

- app opens as a real native Helium window
- sidebar is Aura-owned
- address bar is Aura-owned
- media section is Aura-owned but Helium-backed
- spaces and profile routing are live

This is the first milestone where the app stops being "baseline Helium" and
starts being recognizably Aura.
