# F99 Mood

A Mac menu bar app for the **EPOMAKER x AULA F99** keyboard. AULA's own
software only runs on Windows. This app lets you control the lighting from a
Mac.

- **Moods:** lighting presets you switch from the menu bar or with ⌃⌥
  shortcuts. Some use the keyboard's built-in effects. Others are live effects
  the app draws itself, like Aurora, Matrix, Campfire and a typing heatmap.
- **Music:** the keys move with whatever is playing on your Mac, or with sound
  from the microphone.
- **Macros:** shortcuts that type text or open an app or a link.
- **Extras:** a schedule, calendar and mail alerts, and typing sounds.

Unofficial. Not made by or connected to AULA or EPOMAKER.

## What you need

- macOS 13 Ventura or later. Music from the Mac's own sound needs 14.2; older
  versions use the microphone.
- Apple's Command Line Tools (`xcode-select --install`). Xcode isn't needed.
- A USB-C **data** cable. Some cables only charge.

## Build and run

```
./build.sh
open "build/F99 Mood.app"
```

`build.sh` runs the tests, then builds the app. Drag it into Applications to
keep it.

macOS ties permissions to the app's signature. To keep them across rebuilds,
run `Tools/make_signing_identity.sh` once before building.

## Permissions

| Permission | Why |
|---|---|
| Input Monitoring | To talk to the keyboard over USB. The app doesn't read what you type. |
| Accessibility | Typing effects (to light the key you press) and macros that type text. |
| Audio recording or Microphone | Music mode. Sound is analysed live and never saved. |

If a switch is on in System Settings but the app still asks, press **Fix** in
**Settings → Permissions**.

## Safety

The app writes to the keyboard's memory, so it is careful:

- It only makes changes over the USB-C cable, never the 2.4 GHz receiver.
- It only changes a keyboard that identifies as an F99.
- It reads the settings, changes only the lighting bytes, writes them back and
  checks they stuck. If they didn't, it undoes the change.
- It saves your keyboard's original lighting the first time it connects.
  **Settings → Restore original lighting** puts it back.

## If something goes wrong

- **No F99 found:** use the USB-C cable, try another cable, plug straight into
  the Mac and press **Reconnect** in Settings.
- **Keys stay dark after music or a crash:** open the app with the cable in, or
  use **Restore original lighting**.
- **Anything else odd with the keyboard:** hold **Fn + Esc** for a few seconds
  to reset it.

## Credits

Made by Papiha Joharapurkar.

How the keyboard talks over USB comes from two open-source projects:
[AulaSofwareLinux](https://github.com/leisiji/AulaSofwareLinux) and
[keylux](https://github.com/SibteProf/keylux). Typing sounds are CC0 (see
`Resources/Sounds/CREDITS.md`).

AULA and EPOMAKER are trademarks of their owners. Use at your own risk, on
hardware you own.
