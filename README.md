# PluginSpector Beta Audit App

Small native macOS SwiftUI app that scans standard macOS audio plugin locations, including Pro Tools AAX folders, and gives you a trust-first audit browser for installed plugin bundles.

## Run

```bash
swift run
```

## Package A One-Click App

```bash
./scripts/package-app.sh
```

That creates shareable artifacts in `dist/`.

## Beta Scope

- Plugin name
- Format (`AU`, `VST2`, `VST3`, `AAX` when present)
- Normalized manufacturer name
- Version
- Package size
- Folder/location
- Modified date
- Basic compatibility / legacy verdict
- Bundle details in the inspector pane
- Sidebar section search and list sorting
- Reveal in Finder
- CSV export report
- Cached startup state with background refresh

## Notes

- The app scans recursively inside `/Library/Audio/Plug-Ins` and `/Library/Application Support/Avid/Audio/Plug-Ins`.
- The app restores the last saved library snapshot on launch so the window can load immediately, then refreshes plugin data in the background.
- The beta is intentionally an audit-first browser, not a mover, cleanup tool, or recovery workflow.
- Destructive actions, uninstall flows, backup flows, and hardware/license-dependent recovery features are out of scope for this beta.
