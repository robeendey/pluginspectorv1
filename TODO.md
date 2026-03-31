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

## Plugin Compatibility Cleanup Plan

### Summary

- Build a host-aware compatibility layer that classifies each plugin family as `Native`, `Requires Rosetta` (Apple Silicon only), `Legacy 32-bit / Not runnable`, or `Unknown`.
- Collapse AU/VST/VST3/AAX variants into a single family row with a clear compatibility badge and a plain-language reason in the details pane.
- Treat compatibility as a per-machine verdict so the same scan can be accurate on Apple Silicon and Intel hosts.

### Key Changes

- Extend the scan/model layer to inspect executable slices, minimum macOS requirements, and any mixed or missing binary cases.
- Cache compatibility results by bundle modification date so the browser stays fast during rescans.
- Add a compatibility verdict object to each plugin record and family row, including the exact reason string and any variant-level conflicts.
- Add a dedicated `Compatibility` section in the left sidebar with filters for `Native`, `Rosetta`, `Legacy 32-bit`, `Incompatible`, and `Unknown`.
- Update the main list to surface compatibility badges alongside the existing tags, using explicit copy like `Intel-only`, `Universal`, `Arm64 native`, or `Not runnable on current macOS`.
- Reuse the existing safe file-action and workflow-preference scaffolding for cleanup, defaulting to quarantine/archive with dry-run preview and verified copy-before-remove behavior.
- Add a restore path for quarantined plugins so cleanup is reversible and action history stays clear.

### Test Plan

- Create synthetic fixtures for `arm64-only`, `x86_64-only`, `universal`, `32-bit`, malformed/no-Mach-O, and minimum-OS-too-new bundles.
- Verify each fixture maps to the correct verdict on Apple Silicon, and confirm Intel hosts do not incorrectly mention Rosetta.
- Verify family collapse behavior when one plugin exists in multiple formats and at least one variant is Rosetta-only or incompatible.
- Test the sidebar filters, counts, and main-list badges against mixed families and `Unknown` cases.
- Smoke-test cleanup flows with dry-run first, then quarantine, then restore.

### Assumptions

- The app targets modern macOS on Apple Silicon, but verdicts remain host-relative so the same scan works on Intel too.
- `Legacy 32-bit` means not runnable on current macOS, not a Rosetta candidate.
- Quarantine/archive is the default remediation action; hard delete stays opt-in.
- No heuristic guessing from plugin names or extensions alone; verdicts must come from binary slice inspection plus explicit metadata.

## Notes

- `swift build` passes.
- `swift test` is still blocked by the local `xcrun` / macOS SDK path issue on this machine.
