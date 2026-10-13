# F99 Mood

F99 Mood is a Mac menu bar app for the **EPOMAKER x AULA F99** keyboard. AULA's
own software for the F99 only runs on Windows. This app lets you control the
keyboard's lighting from a Mac.

- **Moods.** Each mood is a lighting setup with a name and an emoji. Pick one
  from the menu bar or with a shortcut, and the keyboard changes to match.
- **Macros.** Shortcuts that type text for you or open an app or a link. A
  macro can work all the time or only in one mood.
- **Dance to music.** The keys light up in time with whatever is playing on
  your Mac.

This is an unofficial app. It is not made by, supported by or connected to AULA
or EPOMAKER.

> **Status:** Tested on a real F99 (original model, wired): moods, live
> streaming, music mode and the light strip's colours and styles work. The automated tests
> pass. See [Testing it on your keyboard for the first time](#testing-it-on-your-keyboard-for-the-first-time).

A new install starts clean: the built-in moods, no macros, no start-up mood,
and a short welcome screen to pick how it starts. Your choices are saved only
on your Mac (`~/Library/Application Support/F99 Mood/`), never in the app.

---

## Contents

- [What you need](#what-you-need)
- [Install](#install)
- [Testing it on your keyboard for the first time](#testing-it-on-your-keyboard-for-the-first-time)
- [Using the app](#using-the-app)
- [Permissions](#permissions)
- [How it works](#how-it-works)
- [Safety](#safety)
- [If something goes wrong](#if-something-goes-wrong)
- [Limits](#limits)
- [Project layout](#project-layout)
- [Credits](#credits)

---

## What you need

- A Mac running **macOS 14.2 or later**
- **Apple's Command Line Tools.** Full Xcode is not needed. If you don't have
  them, run `xcode-select --install`.
- An **AULA F99** (also sold as the EPOMAKER x AULA F99)
- A **USB-C data cable.** Some USB-C cables only carry power. Those won't work.

## Install

In Terminal, go to the project folder and run:

```
./build.sh
open "build/F99 Mood.app"
```

`build.sh` runs the tests first and then builds `build/F99 Mood.app`. The app
icon is drawn by `Tools/make_icon.swift` (a minimal keyboard on black, every key
lit from cyan to magenta with a wave of light running through it) and saved in
`Resources/`. A keyboard icon appears in the menu bar, and the app is in the
Dock too (turn that off in **Settings**).

To keep the app, drag `F99 Mood.app` into your Applications folder. To start it
when you log in, turn on **Settings → Open at login**.

**Keep permissions across rebuilds.** macOS ties permissions (Input
Monitoring, Accessibility, audio) to the app's signature. Run this once to make
your own local signing certificate, and `build.sh` uses it from then on:

```
Tools/make_signing_identity.sh
```

Without it, the app is signed ad hoc and you have to allow it again after each
build. To sign with a different certificate (say, a Developer ID), set
`SIGN_IDENTITY="Your certificate name"` when running `build.sh`.

## Testing it on your keyboard for the first time

On a new setup, try it in this order:

1. **Plug the keyboard in with the USB-C cable** and set it to wired mode.
2. **Run a read-only check.** This only reads from the keyboard and changes
   nothing:

   ```
   "build/F99 Mood.app/Contents/MacOS/F99Mood" --info
   ```

   If it works, it prints the model (`AULA F99`), the current lighting and the
   raw settings.
3. **Try a mood** from the menu bar. Check that the lighting changes the way you
   expect.
4. **Try Dance to music** with a song playing. This is the most experimental
   part of the app.

If any step fails, keep the message the app shows. It tells you what went
wrong.

## Using the app

### Moods

Click the menu bar icon and choose a mood. The current mood is highlighted.

Most moods use the keyboard's own animated effects, the ones **Fn + \\** cycles
through.

| Mood | Keyboard effect | Shortcut |
|---|---|---|
| 🎯 Focus | Fixed on, soft white | ⌃⌥1 |
| 🎮 Gaming | Reaction (keys light as you press them), red | ⌃⌥G |
| ✨ Starry Night | Stars twinkle, white | ⌃⌥3 |
| 🌊 Ocean Waves | Sine wave, cyan | ⌃⌥4 |
| 🌈 Rainbow Wheel | Rainbow wheel | ⌃⌥6 |
| 🌙 Lights out | Lights off | ⌃⌥0 |

There's one mood for each kind of movement, so the list stays short. The
keyboard's other effects look like one of these, but you can still reach them
on the keyboard with **Fn + \\**.

### Live effects

Your F99's firmware only has its 18 effects, so F99 Mood also draws **live
effects** itself and streams them to the keys, the same way music mode does.
They're modelled on popular effects from other brands, and run while F99 Mood is
open. In the mood list they have a pink **LIVE** badge.

| Mood | Live effect | Inspired by |
|---|---|---|
| 🌠 Neon Cascade ★ | Electric and Neon colours flowing across every key, always bright; pressed keys flash near-white with a halo | Razer "Wave", Corsair "Rainbow Wave" |
| ⚡️ Electric Ripples | Soft rings of dark blue and violet spreading across the keys | Razer "Ripple" |
| 🟩 Matrix | Green code raining down | QMK "Digital Rain", Razer Chroma |
| 🔥 Campfire | Flames rising from the bottom row | Razer Chroma "Fire", HyperX |
| 🌌 Aurora | Slow curtains of colour | HyperX "Aurora", Wooting |
| 🌡️ Typing Heatmap | Keys you use most glow hotter | QMK "Typing Heatmap" |
| 🎮 WASD | Your own painted keys: WASD and the arrows bright on dim violet | Razer Synapse, Wooting, VIA |

**Start-up mood** (★): pick one on the welcome screen or in **Settings**, and
F99 Mood switches to it whenever it opens. There's none until you choose. If the keyboard is replugged, the app
carries on with whatever mood you're using.

**Keep every key lit** (in **Settings**, off until you turn it on) keeps every
key at least half lit in live effects and music, so you can read the letters.

Any mood can use a live effect: in the **Moods** pane, pick it from the
**Effect** menu under "Live effects". Brightness, speed and colour work the same;
**Colourful** uses the effect's own colours. The typing effects need
**Accessibility** permission to see which keys you press; they use only the key's
position, only while the effect is on, and store nothing. Live effects follow
the same limits as music mode: brightness at 80% or less and no harsh flashing.

If you used an earlier version, moods you made or changed are kept; the old
built-in ones you never changed are replaced by this set.

⌃ is Control and ⌥ is Option.

To change a mood or add one, open the **Moods** pane. For each mood
you can set:

- **Effect:** one of the keyboard's own effects (Fixed on, Breathing, Rainbow
  wheel, Stars twinkle, Reaction, Sine wave) or a live effect.
- **Brightness:** 0 to 4. 0 turns the lights off.
- **Speed:** 0 to 4.
- **Colour:** red, green, blue, yellow, magenta, cyan, white, or "colourful"
  (the keyboard cycles through colours). Some effects choose their own colours,
  so this control is greyed out for them.
- **Shortcut:** any combination of ⌃ ⌥ ⇧ ⌘ with a letter, number or F-key.

Click **Use this mood now** to try it on the keyboard.

### Macros

Open the **Macros** pane. A macro does one of two things:

- **Type text:** types a block of text, such as an email signature or a common
  reply. It can be more than one line.
- **Open app or link:** opens an app (for example `Spotify`), a website
  (`https://…`) or a file (`/Users/you/…`).

Under **Active in**, choose **Every mood** or a single mood. For example, a
"Focus music" macro can be set to work only in the Focus mood. Switching moods
switches which macros are active.

The app comes with two example macros. ⌃⌥S types an email signature. ⌃⌥M opens
focus music, but only in the Focus mood. Edit or delete them as you like.

If another app already uses a shortcut, the app says so. Pick a different one.

### Dance to music

Click **Dance to music** in the menu, or press **⌃⌥D**. Choose a style:

- **Spectrum:** the keyboard works like an equaliser. Bass is on the left and
  treble is on the right. The louder each part of the music is, the higher its
  column lights, running through your colour theme from bottom to top.
- **Pulse:** the whole keyboard breathes with the bass and sparks on big beats.
- **Ripples:** every beat sends a soft ring of colour out from a random key.
  Harder hits make bigger, faster rings.
- **Wave:** colour flows outward from the middle of the keyboard, in time with
  the music.
- **Fireworks:** keys pop and fade on the beat, and the treble adds small
  sparkles.

The **light strip** between Backspace and Num Lock follows what's on the keys:
steady in the main colour of the mood or music theme (Electric blue, Fire red,
Neon Cascade cyan), off for Lights out, and the keyboard's rainbow gradient only
for rainbow moods and the Rainbow theme. Its gradient is always the full
rainbow (its other two settings are brightness and speed), so it can't show a
theme's own colours together. It can't flash with each beat: unlike the keys, the strip has no
live colour channel, only a saved setting, and saving many times a second would
wear out the keyboard's memory. Turn this off with **Strip matches colours**;
then **Fn + Shift** on the keyboard picks the strip's style yourself.

Pick a **colour theme**: Electric (deep blue, violet, cyan, with magenta for big
moments), Neon, Fire, Ocean, Sunset, Classic or Rainbow, or **Custom** to choose
2 to 5 colours of your own.

By default the app listens to whatever your Mac is playing, such as Spotify,
Apple Music, YouTube or a game. To react to music in the room instead, go to
the **Music** pane and choose **Microphone**.

**Moods while dancing.** Click a mood while the music plays and the music keeps
going in that mood's colours and brightness: Calm dances in shades of cyan,
Cozy dances dim and warm, Party in rainbow. Lights out turns the lights off.
Picking a colour theme switches back. When you stop the music, the last mood
you picked stays on.

The window shows the music's **tempo** (BPM) once it has locked on. If the app
hears only silence for a few seconds, it shows a warning with a button to open
the right privacy setting.

When you click **Stop dancing** or quit the app, your previous lighting comes
back.

### The window

The sidebar has five places: **Home** (the keyboard picture, your moods and a
play button for music), **Moods** (edit, add and share moods), **Macros**,
**Music** (style, colours, where to listen) and **Settings**. The menu bar
panel has your moods, the music button and Open/Quit.

### Settings

One page with everything else:

- **Lights:** keep every key lit, light up keys you press, the strip matching
  your colours, dimming when you're away (off, or after 1–30 minutes) and
  lights off while the Mac is locked.
- **Schedule:** switch to a mood at set times on chosen days.
- **Alerts:** flash the keyboard before calendar events and when new mail
  arrives, and show song progress beside the strip. An alert also blinks the
  strip until it's over or you clear it on Home.
- **Typing sounds:** Tactile, Clicky, Soft or your own file, and the volume.
- **General:** open at login, start-up mood, appearance (light, dark or match
  the Mac) and the Dock icon.
- **Keyboard:** connection status, Reconnect, and **Restore original
  lighting**, which puts back the lighting the keyboard had the first time F99
  Mood connected to it.
- **Permissions**, with a **Fix** button for a switch that looks on in System
  Settings but belongs to an older build.
- **Reset all settings**.

### Moods that switch on by themselves

In a mood's settings, **Switch on automatically → Add an app…**. While that app
is in front, the mood is on; switching away goes back to the mood you had. For
example Gaming for Steam, Focus for your code editor, Lights out for Zoom.

### Organising and sharing moods

- **Duplicate**, **Export**, **Import** and **Restore built-in moods** are in the
  **⋯** menu under the mood list. Exported files leave out your shortcuts and
  apps, and imported moods never take over a shortcut.
- Turn off **Show in the mood grid and menu bar** to keep a mood out of the way.
- Live moods can use any **colour theme** (Electric, Neon, Fire, your custom
  colours…) instead of a single colour.
- Shortcuts that clash with another mood, macro or the music shortcut are shown
  in red, and a new shortcut always starts on a free one.

### Comfort and flashing

Music mode never flashes the keyboard more than three times a second (the
WCAG accessibility limit), keeps brightness at 80% or less, and limits how far
the whole board's brightness can jump from one frame to the next. White flashes
only happen on strong hits during a drop. Turn on **Reduced flashing** for
softer beats, no white flashes and slower changes.

### Terminal commands

| Command | What it does |
|---|---|
| `F99Mood --info` | Connects to the keyboard, reads it and prints the model and lighting. Changes nothing. |
| `F99Mood --listen` | Shows a text equaliser of what music mode hears, for 10 seconds. Doesn't touch the keyboard. |
| `open -n --stdout /dev/stdout "build/F99 Mood.app" --args --permissions` | Shows whether macOS allows Input Monitoring and Accessibility for this copy of the app. |

The full path is `"build/F99 Mood.app/Contents/MacOS/F99Mood"`.

## Permissions

macOS asks for these the first time each feature is used:

| Permission | Needed for | Where to change it |
|---|---|---|
| **Input Monitoring** | Talking to the keyboard. macOS treats any program that opens a keyboard as possibly reading keystrokes. F99 Mood only uses the lighting connection and never reads what you type. | Privacy & Security → Input Monitoring |
| **Accessibility** | Macros that type text for you | Privacy & Security → Accessibility |
| **Audio recording** | Dance to music, listening to the Mac's sound | Privacy & Security → Screen & System Audio Recording |
| **Microphone** | Dance to music, microphone option only | Privacy & Security → Microphone |

In music mode, the sound is measured as it plays and then thrown away. Nothing
is recorded, saved or sent anywhere.

Your moods and macros are saved in
`~/Library/Application Support/F99 Mood/settings.json`.

---

## How it works

### The big picture

```
   ┌──────────────── F99 Mood (menu bar app) ────────────────┐
   │                                                          │
   │  Moods ──────► change the keyboard's saved lighting      │
   │                                                          │
   │  Music ──────► analyse the sound, then stream colours    │
   │                ~20 times a second                        │
   │                                                          │
   │  Macros ─────► type text / open apps (on the Mac only)   │
   │                                                          │
   └───────────────────────────┬──────────────────────────────┘
                               │  USB-C cable
                               │  HID "feature reports"
                               ▼
                    ┌─────────────────────┐
                    │      AULA F99       │
                    │  lighting settings  │
                    │  live key colours   │
                    └─────────────────────┘
```

Moods and music talk to the keyboard. Macros don't involve the keyboard at
all. They run on the Mac and work with any keyboard.

### How the Mac talks to the keyboard

The F99 plugs in as an ordinary USB keyboard, so typing works with no software.
Next to the typing connection, it has a second, hidden connection that AULA's
Windows software uses for settings. This app uses that hidden connection.

Messages on that connection are **HID feature reports**. HID is the standard
USB system for keyboards and mice, and feature reports are its way of sending
settings. macOS can send these without any driver. Each message is 520 bytes:

```
byte 0     report number (always 6)
byte 1     command: what to do
byte 2     extra parameter
byte 4-5   which part of a longer message this is
byte 6-7   how many bytes of data follow
byte 8…    the data
```

The app uses only four commands:

| Command | Meaning |
|---|---|
| `0x82` | "What model are you?" The F99 answers `03 00 00 00 00 a4`. |
| `0x84` | "Send me your lighting settings." |
| `0x04` | "Save these lighting settings." |
| `0x08` | "Show these colours right now." Used by music mode. |

AULA makes several keyboards that all appear to the Mac as the same USB device.
The app tells them apart with the `0x82` answer. It only makes changes on a
keyboard that answers as an F99.

### How moods work

The keyboard keeps its lighting in a **128-byte settings page**. The parts the
app uses are:

```
byte 10        which effect is on (1 = Fixed on, 2 = Breathing, …)
bytes 58-125   one 2-byte slot per effect:
                 first byte  = brightness
                 second byte = speed (top half) + colour (bottom half)
bytes 126-127  5A A5, the end marker
```

The keyboard remembers brightness, speed and colour separately for every
effect. That's why the table has one slot per effect.

When you pick a mood, the app:

1. **reads** the settings page from the keyboard;
2. **checks** that it ends with `5A A5`. A busy keyboard sometimes sends back a
   broken, mostly empty page, and writing that back would wipe its settings;
3. **changes only** the effect byte and that effect's 2-byte slot. Everything
   else stays exactly as the keyboard sent it, including settings the app
   doesn't understand, such as the sleep timer;
4. **writes** the page back;
5. waits 0.4 seconds, **reads it again** and checks that the change stuck. If
   it didn't, the app writes the original page back and shows an error.

Moods are saved on the keyboard. The lighting stays even after you unplug it or
quit the app.

### How music mode works

Music mode doesn't change saved settings 20 times a second. That would wear out
the keyboard's memory. Instead:

1. **Switch to custom colours, once.** The app sets three bytes of the settings
   page that put the keyboard into per-key mode, where it shows colours sent
   from the computer. This uses the same read, change, write and check steps as
   moods. The app also keeps a copy of the page from before.
2. **Listen.** macOS 14.2 added a way for apps to get a copy of the Mac's sound
   output, called a Core Audio "process tap". Your music keeps playing normally.
   The app keeps only the last fraction of a second of sound in memory.
3. **Analyse, 20 times a second.** These choices follow WLED, LedFx and the
   audio-reactive-led-strip project, plus research on beat detection:
   - It splits the sound into **16 frequency bands**, from 40 Hz (deep bass) to
     12 kHz (cymbals), using a fast Fourier transform (FFT). Higher bands get a
     boost of 3 dB per octave, because music has much less energy up there and
     the treble would otherwise stay dark.
   - It **adjusts the volume automatically**, so quiet and loud songs both work.
     The boost is capped, so quiet passages still look quiet.
   - A **noise gate** treats very low sound as silence. In silence the keys
     fade to a dim, slowly breathing glow, and the automatic volume stops
     adjusting, so background hiss isn't turned up.
   - It **detects beats** with "spectral flux": how suddenly the sound jumps
     from one moment to the next, mostly in the bass. This catches claps,
     snares and softer hits, not only loud kicks. A beat must stand out from
     the last 1.5 seconds and come at least 0.22 seconds after the previous one.
   - Beat detection actually runs about 80 times a second, separately from the
     20 light updates, so beats land within about 12 ms.
   - It **tracks the tempo** from the gaps between beats, and keeps a beat
     clock running in time between them. Motion rolls once per beat, and
     colour takes a bigger step at the start of each four-beat bar.
   - It compares the last half second with the last 10 seconds, to tell a
     **quiet passage** from a **drop**. Quiet passages are calmer, and white
     flashes only happen at drops.
4. **Paint a frame.** The app knows where each of the F99's 99 keys sits on the
   board. It took those positions from AULA's own F99 layout file. For each key
   it picks a colour from your theme based on the style. Colours are blended
   in **Oklab**, a colour model built so blends look even to the eye. Simple
   RGB blending gives muddy middles, and blue-to-white drifts purple.
   Flashes fade in about a tenth of a second, while brightness and colour
   change more slowly, over about half a second. Colours sent to the real
   keyboard are adjusted for how LEDs look (a 2.2 gamma curve), so it matches
   the picture on screen. You can turn this off in the Music tab. Then the safety limits from
   [Comfort and flashing](#comfort-and-flashing) are applied.
5. **Send the frame** with command `0x08`. These colours go into the keyboard's
   working memory, not its saved settings. If nothing changed since the last
   frame, the app skips sending it, but it resends every 2 seconds in case the
   keyboard repainted by itself.
6. **Restore when you stop.** The app writes back the lighting part of the page
   it saved in step 1.

**Why 20 frames a second?** AULA's own software never sends colours faster
than one frame every 46 ms, about 21 a second. The people who reverse-engineered
these keyboards found that faster updates take time away from the keyboard
reading your keys. At first it starts missing or doubling keypresses, and then
it stops responding. The app waits 50 ms between frames.

### How macros work

Macros don't touch the keyboard.

- **Shortcuts** are registered with macOS as global hotkeys. They work in any
  app, and listening for them needs no special permission.
- **Typing text** works by sending the text to macOS as if it were typed, which
  needs Accessibility permission. The app waits a quarter of a second first, so
  you've let go of the shortcut keys.
- **Opening things** uses the standard macOS "open" behaviour, the same as
  double-clicking.

When you switch moods, the app re-registers the shortcuts. Only the macros for
the current mood (plus "every mood" macros) are active.

### Where the protocol knowledge came from

AULA doesn't publish how its keyboards communicate. Two open-source projects
worked it out by studying AULA's Windows software and recording USB traffic:

- [AulaSofwareLinux](https://github.com/leisiji/AulaSofwareLinux): the command
  format, the settings page layout, the F99's model ID, and AULA's own F99
  configuration file (effects, brightness and speed ranges, key positions).
- [keylux](https://github.com/SibteProf/keylux): per-key mode, colour
  streaming, the timing limits, and the dangers of the 2.4 GHz receiver.

Both projects tested their findings on an AULA F75, which uses the same
firmware family as the F99.

---

## Safety

The app is careful because it writes to the keyboard's memory:

- **USB cable only.** Over the 2.4 GHz receiver the keyboard uses a different
  protocol. Writing settings that way stopped an F75 from typing, and fixing it
  needed a firmware reflash. The app refuses to change anything unless the
  cable is connected.
- **F99 only.** Other AULA models are shown as read-only.
- **Never builds settings from scratch.** It always reads, changes the few
  lighting bytes, writes and checks again, and undoes the change if the check
  fails.
- **Rejects broken reads.** A settings page without the `5A A5` end marker is
  never written back.
- **Keeps a backup.** The first time it connects, the app saves the keyboard's
  original settings to `~/Library/Application Support/F99 Mood/original-settings.bin`.
- **Never sends firmware commands,** and never tries unknown commands.
- **Respects the speed limit** in music mode: 50 ms between frames.

## If something goes wrong

| Problem | What to do |
|---|---|
| "No F99 found" | Use the USB-C cable, not Bluetooth or the receiver. Try another cable, since some only carry power. Plug directly into the Mac, not a hub. Then click **Reconnect** in **Settings**. |
| "macOS blocked access" | Turn on F99 Mood under Privacy & Security → Input Monitoring, then quit and reopen the app. |
| "Unrecognised keyboard" | The keyboard reported a different model. The app won't change it. Send the output of `F99Mood --info`. |
| A mood doesn't change the lighting | Run `--info` and check what the keyboard reports. The app shows an error if the change didn't stick. |
| Music mode: keys stay dark or flicker | Click **Stop dancing**. If the lighting doesn't come back, use **Keyboard → Restore original lighting**. |
| The keyboard stays dark after a crash, Force Quit or unplugging mid-song | Open F99 Mood with the cable in: it notices the keyboard was left in per-key mode and puts your lighting back by itself. |
| Typing effects don't light the keys I press | Turn on F99 Mood under Privacy & Security → Accessibility. The orange banner in the app has a button for it. |
| Music stops reacting after switching to AirPods or another output | It should follow the new device by itself within a second. If not, stop and start the music. |
| Settings look reset | If the settings file couldn't be read, it's kept as `settings-unreadable-….json` next to the new one (in `~/Library/Application Support/F99 Mood/`). |
| Music mode doesn't react | Run `--listen` while music plays. If the bars don't move, check Screen & System Audio Recording permission, or switch to Microphone. |
| Keypresses get missed or doubled in music mode | Stop music mode and report it. This is what too many updates look like. |
| A macro doesn't type anything | Turn on F99 Mood under Privacy & Security → Accessibility. |
| Anything else strange with the keyboard | Hold **Fn + Esc** for a few seconds to factory-reset it. |

## Limits

- **Not yet tested on an F99.** Everything comes from AULA's F99 configuration
  file and from testing on the F75. Music mode is the least certain part.
- **The light strip only changes when you pick a mood or start music.** It
  isn't part of the live colour channel, so it can't move with the beat.
  (Found by testing: settings byte 0x1c is the strip's style, which Fn + Shift
  steps through: 0 off, 1 and 2 rainbow gradients, 3 steady, 4 blinking; 5
  and up show steady red. Byte 0x1d is its colour, 0x1e its brightness (0 is
  off) and 0x1f its speed. AULA's own
  Windows app doesn't control the strip at all.)
- **Keyboard effects use the keyboard's colours.** The keyboard's own 18 effects
  only take its 7 colours plus "colourful". Live effects and music use any
  colour.
- **Macros live on the Mac.** They work only while the app is running. The
  format for storing macros on the keyboard itself hasn't been worked out yet.
- **Key remapping isn't included.** For that, macOS's own **Keyboard → Modifier
  Keys** setting or the free app Karabiner-Elements works with any keyboard.
- **Wired only** for lighting changes, as explained above.

---

## Project layout

```
build.sh                 runs the tests, then builds "build/F99 Mood.app"
Info.plist               app name, minimum macOS version, permission messages
Sources/
  Main.swift             app entry point and the --info / --listen commands
  F99.swift              F99 facts: USB IDs, model IDs, effects, colours
  F99Layout.swift        position and light number of all 99 keys
  ConfigPage.swift       the 128-byte settings page: read, check, change
  Keyboard.swift         finding the keyboard and sending it commands
  AudioSource.swift      listening to the Mac's sound or the microphone
  Music.swift            frequency bands, beat detection, the three styles
  Hotkeys.swift          global shortcuts, typing text, opening apps
  Settings.swift         moods, macros and saving them to disk
  AppModel.swift         app state, connects everything together
  Views.swift            the menu bar panel and the settings window
  SettingsViews.swift    the Settings pane, permissions, the welcome screen
  MainWindow.swift       the main window and the on-screen keyboard
  LiveEffects.swift      the live effects and the key-press glow
Tools/
  make_icon.swift        draws the app icon
  make_signing_identity.sh  a local signing certificate, so permissions stick
Tests/
  main.swift             tests for settings changes, music analysis and the key layout
```

The tests use a real settings page read from an F75. They check, for example,
that changing a mood only touches the expected bytes, that broken reads are
rejected, that a 60 Hz tone counts as bass, and that a pulsing bass line is
detected as beats.

## Credits

- App and app icon: Papiha Joharapurkar. The icon is drawn by
  `Tools/make_icon.swift`.
- Music design: [WLED sound reactive](https://github.com/wled/WLED),
  [LedFx](https://github.com/LedFx/LedFx),
  [audio-reactive-led-strip](https://github.com/scottlawsonbc/audio-reactive-led-strip),
  Nanoleaf Rhythm, [Oklab](https://bottosson.github.io/posts/oklab/) and
  [WCAG 2.3.1](https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold).
- Protocol research: [AulaSofwareLinux](https://github.com/leisiji/AulaSofwareLinux)
  (MIT) and [keylux](https://github.com/SibteProf/keylux) (MIT / Apache-2.0).
- Effect names, key positions and value ranges come from AULA's own F99
  configuration file.
- Typing sounds: real keystroke recordings, all CC0, by
  [StavSounds](https://freesound.org/people/StavSounds/packs/42151/) (Tactile,
  Clicky) and [unicaegames](https://opengameart.org/content/keyboard-soundpack-1-typing-and-single-keystrokes)
  (Soft). See `Resources/Sounds/CREDITS.md`.

AULA and EPOMAKER are trademarks of their owners. This project is not
affiliated with or endorsed by either company. Use it at your own risk, on
hardware you own.
