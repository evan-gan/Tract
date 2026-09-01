# Tract

An infinite-canvas handwriting app for iPad, built for maths homework.

You write with the Apple Pencil on a dotted paper canvas; fingers only pan and zoom.
A **problem wheel** in the top bar tags each stroke with a problem number (`1.b.ii`),
so a whole page of scratch work can be **exported as a PDF laid out as a clean problem
table** — or as PNG/SVG. Every stroke keeps its full pencil telemetry (position,
pressure, tilt, timing) for future local ML features.

Three tools, nothing else: **pen**, **eraser**, **lasso**. iPadOS 26+, SwiftUI, Swift 6.2.

## Setup

```bash
brew install xcodegen
cp Local.xcconfig.example Local.xcconfig   # fill in DEVELOPMENT_TEAM
```

Signing needs an Apple ID with a paid Developer Program membership added in
Xcode → Settings → Accounts. `xcode-select -p` must point at your Xcode install.

## Develop

**Xcode never needs to be opened** — everything runs from the shell.

```bash
./scripts/build.sh                        # compile / type-check (unsigned) — the inner loop
./scripts/test.sh                         # unit + UI tests on an iPad simulator
./scripts/screenshot.sh both              # → build/screenshots/*.png, to actually see a UI change
./scripts/deploy-device.sh                # signed build onto a connected, unlocked iPad
xcodegen generate                         # only after editing project.yml
```

`Tract.xcodeproj` is generated and gitignored — never edit it. Sources are collected
by folder, so a new `.swift` file in an existing folder needs no config change; a new
top-level folder goes in `project.yml`.

Because the canvas takes pencil input only, a simulator can't draw on it — hand-test on
a real iPad, and use `screenshot.sh` (canvas / library / exportmenu / problempicker) to
look at chrome changes. Xcode runs are slow, so bundle build + tests + screenshots into
one invocation rather than running them one at a time.

## Where things live

`Canvas/` drawing engine and `CanvasViewModel` (the single source of truth) ·
`Stroke/` pure data types · `Document/` model, persistence and the home screen ·
`ToolDock/` the floating tool bar · `Toolbar/` the top glass pill ·
`ProblemPicker/` the tagging wheel · `Export/` PDF/PNG/SVG · `Tests/`, `UITests/`.

**[`project_context.md`](project_context.md) is the full map** — every file, the
architectural rules, and a "where to make common changes" table. Read it before
changing anything; keep it current after.
