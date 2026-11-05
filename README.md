<p align="center">
  <img src="Resources/AppIcon.png" width="160" alt="LangCycle app icon">
</p>

<h1 align="center">LangCycle</h1>

A tiny macOS menu bar app that switches keyboard layouts the way Windows does: every press of the hotkey moves to the **next layout in a fixed order** (A → B → C → A). It then shows a **large HUD** with the language you picked, so you can see it at a glance.

- **⌃Space** selects the next layout and **⌃⇧Space** the previous one. You can choose ⌥Space or ⌘Space instead.
- The result never depends on how fast you press or whether you let go of the modifier. Pressing, releasing and pressing again always moves forward.
- The HUD never takes focus or blocks clicks. It fades out about 1 s after the last press and also appears over fullscreen apps and on every Space.
- The menu bar shows the current layout's code (`EN`, `УК`, `РУ`…), even when you switch some other way.
- No dependencies, no network access, no analytics, and no permissions to grant.

## Requirements

- macOS 13 or later, on Apple Silicon or Intel (the app is a universal build).
- To build from source only: Apple's Command Line Tools (`xcode-select --install`). Xcode is not needed.

## Install

LangCycle is not notarized by Apple (that needs a paid Apple Developer account); it is only ad-hoc signed. So macOS treats a downloaded copy as coming from an unidentified developer. Both ways below deal with that.

### Homebrew

```sh
brew install --cask mavr1k/tap/langcycle
```

The cask removes the download quarantine flag after installing, so macOS shows no warning.

### Download

1. Download `LangCycle-<version>.zip` from the [Releases page](https://github.com/mavr1k/LangCycle/releases) and unzip it.
2. Drag `LangCycle.app` into `/Applications`.
3. Open it. macOS refuses the first time with a message that Apple could not verify it. Click **Done**, then open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to "LangCycle was blocked". Confirm with your password. You only do this once.

   On macOS 13 and 14 you can instead right-click the app and choose **Open**. Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/LangCycle.app`.

After installing, follow [First run](#first-run-turn-off-the-macos-shortcut-required) below.

### Build from source

```sh
./build.sh               # build a universal LangCycle.app, install it to /Applications and launch it
./build.sh --no-install  # build only: build/LangCycle.app
./test.sh                # run the unit tests
```

`build.sh` builds arm64 and x86_64 separately with SwiftPM, merges them with `lipo`, and ad-hoc signs the bundle.

`test.sh` runs `swift test`. With only the Command Line Tools installed, SwiftPM can't find the Swift Testing macro plugin by itself, so the script passes its location. With Xcode installed, plain `swift test` works.

## First run: turn off the macOS shortcut (required)

macOS uses ⌃Space for its own input switcher. While that shortcut is on, macOS handles the key first and LangCycle never sees it. Turn it off once:

1. Open **System Settings → Keyboard → Keyboard Shortcuts… → Input Sources**.
2. Untick **Select the previous input source** and **Select next source in Input menu**.
3. If you choose ⌘Space as the hotkey, also untick **Spotlight → Show Spotlight search**.

LangCycle shows these steps on first launch, and later under **Setup Help…** in its menu. While a macOS shortcut still conflicts with the chosen hotkey, the menu shows **⚠︎ Shortcut unavailable — disable the system one**. The same warning appears if another app has already taken the key combination.

## Menu

| Item | What it does |
|---|---|
| Layout list | Click to select a layout. The current one has a checkmark. |
| Hotkey | Choose ⌃Space, ⌥Space or ⌘Space. Adding ⇧ always goes backwards. |
| HUD Size | Small, Medium or Large. |
| Show HUD | Turn the HUD off to keep only the menu bar code. |
| Skip Layouts | Leave layouts out of the cycle while keeping them enabled in macOS. |
| HUD Labels | Rename the big name the HUD shows for a layout (see below). |
| Launch at Login | Uses `SMAppService`. macOS may ask you to approve it in System Settings → General → Login Items. |
| Setup Help… | The steps for turning off the macOS shortcut. |
| About LangCycle | Version, author and a short bio. The text is in `Sources/LangCycle/About.swift`. |

Settings are stored in the `com.local.langcycle` defaults domain.

### Renaming HUD labels

By default the HUD shows each language's own name as the headline ("English", "Українська", "Русский") and the macOS layout name ("ABC", "Ukrainian", "Russian – PC") underneath it. To use your own wording:

1. Open **HUD Labels** in the menu and click a layout. A checkmark marks layouts that already have a custom label.
2. Type the new label and press **Save**. Labels are limited to 30 characters.
3. To go back to the automatic name, press **Reset to Default**, or save an empty label.

Labels are saved per layout (by its macOS input source ID), so they survive restarts and reordering. They only change the big name in the HUD. The short codes (`EN`, `УК`…) and the names in the menu stay as they are.

## How the next layout is chosen

The layout list comes from macOS: the enabled keyboard layouts, in the order shown in System Settings → Keyboard → Input Sources. It is read again on every press, so adding or removing a layout takes effect immediately.

Right after LangCycle selects a layout, macOS can still report the old one for a short time. So a press within **0.8 s** of LangCycle's last switch continues from the layout LangCycle just picked. Any later press continues from the layout that is actually active, including one you picked with the mouse or another shortcut.

This logic is a pure function, `nextLayout(...)` in `Sources/LangCycleCore/Cycle.swift`, and is covered by the unit tests.

## Permissions and privacy

- **No permissions are needed.** The hotkey uses Carbon's `RegisterEventHotKey`, which does not need Accessibility or Input Monitoring access and keeps the key from reaching the app you are typing in.
- **Keystrokes:** only the registered hotkey reaches the app. Nothing is logged.
- **Network:** the app contains no network code. You can confirm with `lsof -i -a -p $(pgrep -x LangCycle)` or `nettop`.
- **Secure input** (password fields, Terminal → Secure Keyboard Entry): Carbon hotkeys usually keep working while secure input is on. **This has not been verified for this build yet.** To check, turn on Terminal → Secure Keyboard Entry, focus Terminal and press the hotkey.

## Project layout

```
Sources/LangCycleCore/Cycle.swift     pure logic: next/previous layout, short codes, native language names
Sources/LangCycle/main.swift          app delegate, menu bar item and menu, settings, single instance
Sources/LangCycle/Hotkey.swift        Carbon hotkeys, presets, detection of conflicting macOS shortcuts
Sources/LangCycle/InputSources.swift  thin wrapper over Text Input Sources (TIS)
Sources/LangCycle/HUD.swift           the indicator panel
Sources/LangCycle/About.swift         the text of the About window
Tests/LangCycleCoreTests/             unit tests (Swift Testing)
Resources/Info.plist                  LSUIElement agent app, bundle id com.local.langcycle
```

## Uninstall

1. Turn off **Launch at Login** in the menu, then choose **Quit LangCycle**.
2. Run:
   ```sh
   rm -rf /Applications/LangCycle.app
   defaults delete com.local.langcycle
   ```
   If you installed with Homebrew, run `brew uninstall --cask --zap langcycle` instead. It removes the app and the saved settings.
3. If you want macOS's own shortcut back, tick it again in System Settings → Keyboard → Keyboard Shortcuts… → Input Sources.

## About

Made by **mavr1k**. The same details are shown in the app, under **About LangCycle** in the menu.

- GitHub: [github.com/mavr1k](https://github.com/mavr1k)
- LinkedIn: [linkedin.com/in/mavrosaus](https://www.linkedin.com/in/mavrosaus/)
- Email: [hard359@gmail.com](mailto:hard359@gmail.com)

## License

MIT. See [LICENSE](LICENSE).
