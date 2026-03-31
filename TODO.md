# PluginSpector TODO

This file tracks what has been completed, what is partially in place, and what still remains from the roadmap and recent code review.

## Done

### Phase 1: Low Difficulty
- Done: Single Click Reveal
- Done: Mini Search Bar
- Done: Sort Options
- Done: AAX Format Inclusion

### Phase 2: Medium Difficulty
- Done: Plugin File Size Indicator

### Phase 3: High Difficulty
- Done: Deep Background Scan

### Other Done Work
- Done: `swift run` now activates the app window on launch
- Done: Main performance refactor with cached dashboard state

## In Progress / Scaffolded

### Phase 2: Medium Difficulty
- In progress: Workflow Notification & Settings
  - Persistent JSON storage exists in `Sources/WorkflowPreferences.swift`
  - The first-start UI flow is not wired yet
- In progress: Collapse Versions (VST/AU/AAX)
  - Grouping helpers exist in `Sources/PluginGrouping.swift`
  - The browser is still flat
- In progress: Batch Delete
  - Safe file-action primitives exist in `Sources/PluginFileActions.swift`
  - No user-facing batch delete flow yet
- In progress: Off-Drive Backup
  - Copy/verify/remove primitives exist in `Sources/PluginFileActions.swift`
  - The full external-drive workflow is not exposed in the UI

## Outstanding

### Phase 1: Low Difficulty
- Outstanding: Search Bar Input Fix
  - Search is smoother via debounce, but it still uses standard SwiftUI text binding rather than low-level keyboard input handling
- Outstanding: Search normalization parity
  - Cached search is faster, but it needs accent-insensitive / locale-aware matching parity with the old behavior

### Phase 2: Medium Difficulty
- Outstanding: Non-Use Notifications
- Outstanding: Legacy File Identification

### Phase 3: High Difficulty
- Outstanding: Scraping for Plugin Photos
- Outstanding: In-App Agent / Housekeeping
- Outstanding: UAD Active Scan
- Outstanding: Undo/Deleted File Tracking

### Phase 4: Expert / Critical Difficulty
- Outstanding: DAW Recovery Mode
- Outstanding: Plugin Alliance Uninstaller

## Review Follow-Ups

- P2: Search normalization lost accent-insensitive matching in `Sources/DashboardSnapshot.swift`
- P2: Selection changes still rebuild the full dashboard snapshot in `Sources/DashboardSnapshot.swift`
  - Current snapshot rebuild still re-walks aggregate counts when selection changes

## Notes

- `swift build` passes.
- `swift test` is still blocked by the local `xcrun` / macOS SDK path issue on this machine.
