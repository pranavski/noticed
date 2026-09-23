# App Store screenshots — iPhone 6.9" (1320 × 2868)

Re-shot 2026-09-19 after the rename, on the iPhone 16 Pro Max simulator in
`SOMA_PREVIEW` mode (sample feed, light appearance, status bar at 9:41).
App Store Connect derives the 6.5" set from these.

- `01…06-*.png` — the upload set: captioned frames on the paper background,
  caption in Fraunces italic with the persimmon period, plate numeral in
  Plex Mono. Captions are the ones in `docs/app-store-connect-copy.md`.
- `raw/` — the bare simulator captures the frames are built from.

Regenerate after any visual change:

```sh
DesignAssets/screenshots/capture.sh   # build, install, capture into raw/
python3 DesignAssets/screenshots/compose.py   # raw/ -> captioned frames
```

The HealthKit sheet shot from the plan still isn't here. It needs a tap,
and on a simulator it shows "not connected" anyway. The kitchen (export /
delete) takes slot 6 in its place.
