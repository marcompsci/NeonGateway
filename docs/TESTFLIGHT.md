# Neon Getaway: TestFlight

## Ship a build

1. Leave `tools/check_watch.command` running on the Mac (or double-click `tools/check.command` after the next step).
2. Put `testflight` in `Logs/check_mode` and create `Logs/check_request`.
3. The check runs the GameCore tests and a Simulator build first; only if both pass does it archive a Release build and upload it. The build number comes from `tools/build_number.txt` (last one used) and goes up by one each upload. Results: `Logs/check.txt`, `Logs/archive.log`, `Logs/upload.log`.
4. App Store Connect processes the build (usually 5–30 minutes), then it appears under TestFlight.

## App Store Connect record

- Name: Neon Getaway · Bundle ID: com.phoronomicstudios.neongetaway · SKU: neongetaway · Primary language: English (U.S.)
- Team: X6LZQ3FS36 · Apple ID (app): 6821629274 · App ID registered 2026-10-11
- Internal TestFlight group: "Neon Getaway team" (automatic distribution on), tester Omari Bell
- External TestFlight group: "Public testers", public link https://testflight.apple.com/join/D5zuDQmg (up to 1,000 testers). Feedback email hello@phoronomicstudios.com.
- Uploads sign with an App Store Connect API key (Admin). The .p8 lives outside the repo in `../.appstoreconnect/`; `tools/check.command` finds it there.
- Export compliance: answered in the build (`ITSAppUsesNonExemptEncryption = NO`), so no prompt per build.
- Privacy: since 0.11 the app uses a Game Center player ID and player-made designs (iCloud) for online play; the App Privacy answers in App Store Connect still need updating to match.

## Builds

| Version | Build | Uploaded | State |
| --- | --- | --- | --- |
| 0.6.0 | 2 | 2026-10-11 06:59 PDT | Valid, in internal testing |
| 0.11.0 | 3 | 2026-10-12 12:05 PDT | Valid; internal testing; added to "Public testers", waiting on Beta App Review |

## What to Test (paste into TestFlight)

Neon Getaway 0.6: an original top-down arcade driving game set in Port Aurora. Three jobs on the map plus free drive.

Please try:
1. Cold Crate: deliver from Pier 9 to Lantern Alley in 35 seconds. Too easy, fair, or too hard?
2. Tide Line Run: start hot in the Customs Yard, lose the patrols, then reach Pier 4. How long did it take to shake them?
3. Lantern Sweep: grab three lanterns, then get home in 60 seconds.
4. Steering and drift: does the car feel good? Is the steering strip the right size?
5. Patrols: fair, too aggressive, or too easy to lose?
6. Sound: engine, siren and blips (the silent switch mutes them).

Tell us anything that felt off, with the job name and roughly what happened.
