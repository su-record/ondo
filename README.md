# ondo

English · [한국어](README.ko.md)

A menu bar app that keeps a MacBook awake with the lid closed. While it does, ondo watches CPU and battery temperature and power, and when the Mac overheats or the charger is unplugged it stops keeping the Mac awake and puts it to sleep. That overheat protection is what sets it apart from Amphetamine and KeepingYouAwake.

A free, open-source app from Tory Labs, under the MIT License. Product page: https://torylabs.dev/ondo

- Apple silicon Macs with macOS 13 or later (Intel builds are produced but have not been tested on hardware)

## Install

**Homebrew**

```sh
brew install --cask su-record/tap/ondo
```

This also installs the `ondo` terminal command.

**DMG**: download it from [GitHub Releases](https://github.com/su-record/ondo/releases) and drag ondo into Applications. The app is notarized by Apple.

### First run

1. Open ondo. A closed laptop with a thermometer appears in the menu bar.
2. The first time you turn on "Stay Awake, Lid Closed", System Settings › General › Login Items opens. Turn on ondo under "Allow in the Background". You approve once; after that ondo never asks for your password.
3. If a full menu bar or a menu bar organizer hides the icon, open ondo again from Spotlight to get the same menu in a window.

## Use

- **Stay awake with the lid closed**: the switch in the menu.
- **End time**: no end, a duration to the minute such as 1 h 30 min, or a clock time such as 07:30. At the end ondo stops keeping the Mac awake and, with the lid closed, puts it to sleep.
- **Temperature**: the menu bar thermometer shows CPU temperature. It is blue up to 40°C and moves through green, yellow and orange to red at the overheat limit (85°C by default). The mercury rises with it.
- **Turn off display**: the display goes dark; work continues.
- **Wake and resume**: wake the Mac at a set time and keep it awake again.

## Overheat protection

While keeping the Mac awake, ondo reads temperatures every 2 seconds.

1. **Warn**: when the CPU stays above its limit (85°C by default) or the battery above its limit (45°C by default) for 60 seconds, ondo sends an alert and lists the three processes using the most CPU.
2. **Stop**: after 60 more seconds above the limit it stops keeping the Mac awake. With the lid closed the Mac sleeps right away; with the lid open you get an alert.
3. The warning clears once the reading falls 3°C under the limit. Between the limit and that point the count pauses, so a reading at the edge does not warn again and again.

With "Wake the Mac and resume once cooled" turned on, ondo wakes the Mac a set time (30 minutes by default) after an overheat stop. If both temperatures are 10°C under their limits it resumes; otherwise the Mac sleeps again. It checks up to three times.

On a Mac whose sensors cannot be read, the menu says so and everything else keeps working.

## Power protection

- Unplugging the charger while awake stops it (can be turned off in Settings).
- On battery, falling below the floor (20% by default) stops it.
- Turning on is refused while the Mac is too hot or the battery is low.

## How it works

Staying awake with the lid closed needs `pmset -a disablesleep 1`, which requires administrator rights. ondo does not edit sudoers; it hands the call to a small helper (a LaunchDaemon registered with `SMAppService`).

- The helper only sets `disablesleep 1/0` and schedules or cancels wakes. It accepts no command text, so there is no way to make it run anything else.
- It accepts connections only from ondo.app signed with the same developer certificate.
- Temperatures come from IOHID sensors and SMC keys, which Apple does not document. No administrator rights are needed for that.

How ondo makes sure the Mac is never left unable to sleep:

| When | What restores sleep |
|---|---|
| You quit ondo | The app asks the helper for `disablesleep 0` before it exits. |
| ondo crashes or is force-quit | The helper sees the app's connection drop and sets `0`. |
| The helper is stopped, or the Mac restarts | The helper sets `0` when it exits and again when it starts at boot. |

## External and AI control

```sh
ondo status            # state, time left, temperatures, power
ondo on --for 1h30m
ondo on --until 07:30
ondo off
ondo temp
ondo display-off
ondo wake --in 30m     # wake later and keep the Mac awake again (--at 07:00, --cancel)
ondo sensors           # every sensor value (debug)
```

Add `--json` for JSON. Exit codes: 0 ok, 1 error, 2 ondo app not reachable, 3 refused by protection.

- **MCP**: `claude mcp add ondo -- ondo mcp` lets Claude Code, Claude desktop, Codex and other AI apps use the same functions as tools.
- **Links**: `ondo://on?for=1h30m`, `ondo://off`, `ondo://display-off`, `ondo://wake?in=30m`, for Shortcuts, Raycast or Alfred.

External callers can turn staying awake on and off, read status, turn off the display and schedule wakes. Overheat and power limits change only in ondo's settings, so an AI agent cannot switch the protection off.

## Caveats

- Don't use ondo together with apps that change the same `disablesleep` setting, such as Amphetamine's Closed-Display Mode; they overwrite each other.
- A closed MacBook sheds heat less easily. Keep it somewhere with airflow.
- The default 85°C limit can be reached during heavy work such as builds. Change it in Settings (60–105°C).

## Uninstall

1. In ondo's Settings › General, click "Remove helper".
2. Quit ondo and delete it from Applications, or `brew uninstall --cask ondo`.

## Build from source

Requires Xcode (Swift 6). No third-party dependencies.

```sh
swift test                                  # unit tests
scripts/build-app.sh                        # dist/ondo.app, Developer ID signed
NOTARY_PROFILE=<profile> scripts/make-dmg.sh   # notarized DMG (or the APPLE_API_KEY* variables)
```

Design and decisions: [SPEC.md](SPEC.md). Manual test checklists: [docs/manual-tests.md](docs/manual-tests.md).

## License

MIT. Made by [Tory Labs](https://torylabs.dev).
