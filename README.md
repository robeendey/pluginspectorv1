# PluginSpector Prototype

Small native macOS SwiftUI prototype that scans `/Library/Audio/Plug-Ins` and gives you a searchable browser for installed plugin bundles.

## Run

```bash
swift run
```

## Package A One-Click App

```bash
./scripts/package-app.sh
```

That creates shareable artifacts in `dist/`.

## What It Shows

- Plugin name
- Format (`AU`, `VST2`, `VST3`, `AAX` when present)
- Vendor guess
- Version
- Package size
- Folder/location
- Modified date
- Bundle details in the inspector pane
- Sidebar section search and list sorting

## Notes

- The app scans recursively inside `/Library/Audio/Plug-Ins`.
- It is intentionally a browser prototype, not a mover/cleanup tool yet.
- If you want the next step, we can add favorites, hide/archive rules, duplicate detection, or safe move-to-quarantine flows.
