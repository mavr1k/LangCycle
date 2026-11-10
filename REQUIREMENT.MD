# LangCycle — Requirements

A tiny macOS menu bar app that switches keyboard layouts the way Windows does (fixed order, always forward) and shows a large, obvious indicator of the language you just picked.

## 1. Problem

The macOS input-source switcher is unsatisfactory:
- With 3+ layouts, pressing the hotkey, releasing it, and pressing again goes back to the previous layout instead of moving to the next one (macOS counts layouts passed through while cycling).
- The on-screen indicator is sometimes fullscreen/disruptive, and it does not clearly show which language was chosen.
- Existing open-source apps (Input Source Pro, IMESwitch) don't fix this: they use most-recently-used ordering and/or a small popup.

## 2. Goals

1. Every hotkey press moves to the **next enabled layout in a fixed order** (A → B → C → A). The result never depends on press timing, on whether the modifier was released, or on history.
2. After each switch, show a **large HUD** with the language name, so the choice is obvious at a glance.
3. The HUD must be **non-intrusive**: never steals focus, never blocks clicks, fades out quickly, and also appears over fullscreen apps.
4. Small, dependency-free, local-build, fully open source.

## 3. Non-goals (for now)

- No text correction/transliteration (that is what AURA Switcher does).
- No per-app language memory.
- No Windows/Linux support.
- No support for CJK input methods that use candidate windows (plain keyboard layouts only; they may work but are untested).
- No analytics or telemetry for now. This may change later: if analytics are ever added they must be opt-in, described in NFR-3 and the README before they ship, and kept separate from the update check (5.6).
- Network access is limited to the update check and the update download (5.6). Nothing else talks to the network.

## 4. Target platform

- macOS 13+ (Apple Silicon + Intel, universal build).
- Swift, AppKit (+ Carbon for hotkeys and Text Input Sources). No third-party dependencies.
- Menu bar agent: `LSUIElement = true` (no Dock icon).
- Build with `swiftc` via a `build.sh` or a SwiftPM package; must not require a full Xcode project. Output: `LangCycle.app` installed to `/Applications` (ad-hoc signed is fine).

## 5. Functional requirements

### 5.1 Switching
- **FR-1** Default hotkey **⌃Space** → select next layout. **⌃⇧Space** → select previous layout.
- **FR-2** The layout list is the set of **enabled, selectable keyboard layouts/input sources** from `TISCreateInputSourceList` (filter: `kTISPropertyInputSourceIsSelectCapable == true` and category `kTISCategoryKeyboardInputSource`). Order follows the order returned by the system (same as System Settings → Keyboard → Input Sources), unless the user has set their own order (FR-28). The list is re-read on every press so adding/removing layouts is picked up immediately; also listen for `kTISNotifyEnabledKeyboardInputSourcesChanged`.
- **FR-3** Switching uses `TISSelectInputSource`.
- **FR-4 (core)** Next layout is computed from the **last layout this app selected**, if that was within the last ~800 ms. Otherwise it is computed from the **currently active** layout (`TISCopyCurrentKeyboardInputSource`). This avoids races where the system hasn't yet reported the new layout during fast repeated presses, and still handles layout changes made by other means (menu, mouse, another shortcut).
  - Acceptance: from layout A, pressing the hotkey 3 times quickly yields B, C, A. Pressing, waiting 2 s, pressing again yields B, C. Never goes "back" on a forward press.
- **FR-5** Holding the key (auto-repeat) must not cause repeated switching; one keydown = one switch (ignore repeats).
- **FR-6** If only one layout is enabled, do nothing (show HUD with that layout is acceptable).

### 5.2 Hotkey registration
- **FR-7** Prefer Carbon `RegisterEventHotKey` (does not need Accessibility permission, consumes the key event so it is not passed to apps). Fall back to an active `CGEventTap` only if needed.
- **FR-8** Hotkey is configurable in the menu (preset list is enough for v1: ⌃Space, ⌥Space, ⇧⌃Space is reserved for reverse; plus "Record shortcut…" if simple). Persist in `UserDefaults`.
- **FR-9** Detect registration failure (shortcut already taken) and show it in the menu ("Shortcut unavailable — disable the system one").
- **FR-10** First-run help window/menu item explaining that the system shortcut must be disabled: System Settings → Keyboard → Keyboard Shortcuts → Input Sources → untick "Select the previous input source" and "Select next source in Input menu" (and Spotlight if it uses the same keys).

### 5.3 HUD (indicator)
- **FR-11** Shown after each switch, centered on the screen that contains the mouse cursor (fallback: main screen).
- **FR-12** Content: language **name** large (e.g. "Українська", "English", "Deutsch") plus short code (`EN`, `УК`) and, if available, the layout icon (`kTISPropertyIconImageURL`). A secondary row shows all layouts as a compact list with the active one highlighted (so the user sees the position in the cycle).
- **FR-13** Size: card ≈ 320×180 pt minimum, primary text ≥ 48 pt. Size adjustable in menu: Small / Medium / Large.
- **FR-14** Style: rounded rect (corner radius ~24), `NSVisualEffectView` material `.hudWindow`, light/dark aware.
- **FR-15** Timing: appears instantly (≤ 50 ms after keypress), stays visible while any key of the hotkey combination just used is held (its modifier, Space, and ⇧ for the reverse hotkey), hides 1 s after **all** of them are released, and fades out over 0.2 s. A new switch while visible updates content and restarts the wait (no flicker, no stacked windows).
- **FR-16** Window behavior (critical):
  - `NSPanel`, styleMask `.borderless + .nonactivatingPanel`; `canBecomeKey/Main = false`; `ignoresMouseEvents = true`.
  - Level ≥ `.statusBar` (use `CGShadowingWindowLevel`-style high level if needed to cover fullscreen apps).
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
  - Must not activate the app, steal keyboard focus, or change the active text field.
  - Must appear over fullscreen apps and on all Spaces.
- **FR-17** HUD can be disabled in the menu (menu bar label only).

### 5.4 Menu bar item
- **FR-18** Status item shows the current layout's short code (`EN`, `УК`, `DE`…), updated on `kTISNotifySelectedKeyboardInputSourceChanged` (so it stays correct when switched by any means).
- **FR-19** Menu: list of enabled layouts (click to select, checkmark on current); Hotkey; HUD size; Show HUD (toggle); Launch at login (toggle, via `SMAppService.mainApp`); Setup help…; Quit.
- **FR-20** Optional: "Skip layouts…" submenu to exclude layouts from the cycle while keeping them enabled.
- **FR-28** "Layout Order" submenu: the user sets the cycle order. Each layout has ▲ ▼ buttons that move it one place up or down (the first wraps to the end, the last to the start). The buttons are views inside the menu items, so the menu stays open while the user reorders. "Reset to System Order" clears the custom order. The order is stored as a list of input source IDs (`layoutOrder`). It applies to the hotkey cycle, the menu layout list and the HUD's layout row. Layouts without a stored place (newly enabled) go at the end in system order. IDs of layouts that are currently disabled stay in the stored list, so re-enabling one puts it back in its old place.

### 5.5 Lifecycle
- **FR-21** Single instance (second launch quits immediately).
- **FR-22** Settings persisted in `UserDefaults` (suite `com.local.langcycle`).

### 5.6 Updates
- **FR-23** Update check: shortly after launch and then at most once every 24 h, the app asks GitHub for the latest stable release of this project (`GET https://api.github.com/repos/mavr1k/LangCycle/releases/latest`). The menu has **Check for Updates Automatically** (on by default, can be turned off) and **Check for Updates Now** (always available).
- **FR-24** Ask first: when a newer version exists, the menu shows **Update Available: X.Y.Z — Install and Restart…** at the top and the menu bar title gets a ↑ marker. Automatic checks never open windows, and nothing is downloaded or changed until the user chooses to install.
- **FR-25** Install: the app downloads the release zip over https from this project's GitHub releases, checks its SHA-256 against the digest GitHub publishes for the asset, unpacks it, and requires exactly one `LangCycle.app` with the same bundle identifier, the announced version and a valid code signature. Only then does it replace the running app (atomic swap) and relaunch. If any step fails, the current app is left untouched and the user is told why, with a link to the release page.
- **FR-26** Safety limits: it never installs a version that is not newer than the running one, never installs drafts or pre-releases, and never downloads from anywhere except `github.com/mavr1k/LangCycle/releases/download/…`. If the app cannot replace itself (not in a writable `.app`, e.g. run from a build folder or from a quarantined download), it offers the release page instead.
- **FR-27** Privacy: a check sends only the standard HTTPS request (`User-Agent: LangCycle/<version>`) and the IP address GitHub sees. No identifiers, no usage data. Failed automatic checks are silent; failures of a check the user started are reported.
- **Known limit:** the digest comes from the same GitHub release as the zip, so this protects against corrupted or swapped downloads but not against someone who controls the GitHub repository. Signing releases with a separate key could be added later.

## 6. Non-functional requirements

- **NFR-1 Latency:** layout actually changes ≤ 30 ms after keydown; HUD visible ≤ 50 ms.
- **NFR-2 Resources:** idle CPU ~0%, memory < 40 MB.
- **NFR-3 Privacy/Security:** the only network access is the update check and download (5.6); no analytics or telemetry for now (if added later: opt-in and documented first); no logging of keystrokes, no keystroke monitoring beyond the registered hotkey. Code is open source (MIT or GPL-3.0 — choose in repo).
- **NFR-4 Robustness:** never freezes input; if the hotkey can't be registered, the app still runs and tells the user why.

## 7. Edge cases to handle

- Layout changed externally between presses (menu, mouse, other shortcut): next press continues from the real current layout (FR-4, >800 ms case).
- Layout added/removed while running.
- Secure input fields (password, secure terminal): Carbon hotkeys generally still fire; verify and document behavior.
- Multiple displays / fullscreen app on one display: HUD appears on the display with the cursor.
- Duplicate-named layouts (e.g. two "ABC"-like English layouts): disambiguate by input source ID.
- Names from `kTISPropertyLocalizedName`; code abbreviations derived from `kTISPropertyInputSourceLanguages` (first language, uppercased 2 letters; Cyrillic scripts shown in native script: `УК`) with a small override table.

## 8. Acceptance tests (manual)

1. Enable 3 layouts (EN, UK, DE). Press ⌃Space 6 times quickly → EN→UK→DE→EN→UK→DE, never repeating the previous layout.
2. Press ⌃Space, release everything, wait 1 s, press again → advances once more (not back).
3. ⌃⇧Space reverses the order.
4. In a fullscreen app (e.g. Safari fullscreen) the HUD appears centered, does not exit fullscreen, and does not take focus (typing continues uninterrupted).
5. Switching via the system menu bar input menu updates the menu bar code; the next ⌃Space continues from the new layout.
6. The HUD stays while you hold the hotkey's modifier (or Space) and disappears ~1 s after you release all of them; rapid presses don't stack windows.
7. Quit and relaunch: settings preserved; Launch at login works.
8. With **Check for Updates Automatically** off and no manual check, the app makes zero network connections (verify with Little Snitch / `nettop`). With it on, the only connection is to `api.github.com`, plus `github.com` while an update is being installed.
9. With a newer release published: the menu shows the update item and the ↑ marker without any window popping up; **Install and Restart…** downloads, replaces the app and relaunches the new version; the settings are kept. With the newest version installed, **Check for Updates Now** says it is up to date. With the network off, a manual check reports the problem and an automatic one stays silent.

## 9. Deliverables

- Source in a git repo: `Sources/`, `build.sh`, `README.md` (build, permissions, disabling the system shortcut, uninstall), `LICENSE`.
- Unit tests for the next/previous selection logic (pure function: `(layouts, lastSelected, lastSelectedTime, current, now) -> target`), covering FR-4.
- Unit tests for the update logic: version comparison, release parsing and validation, the check schedule, and the installer (wrong fingerprint, wrong app, wrong version, successful replace).
- `build.sh` produces a universal `LangCycle.app` and installs to `/Applications`.

## 10. Suggested implementation notes for Claude Code

- Put selection logic in a pure, testable function; keep TIS/Carbon calls in a thin wrapper.
- TIS calls should run on the main thread.
- `TISSelectInputSource` may not be reflected immediately by `TISCopyCurrentKeyboardInputSource` — this is why FR-4 tracks the last selection by time.
- Start with the HUD and switching working end-to-end, then add the menu options.
- Ask me before adding features beyond this document.
