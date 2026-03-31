# PluginSpector Beta Scope

This file is now the beta execution guardrail. The March 31, 2026 scope freeze cuts PluginSpector down to a trust-first audit release.

## Beta Thesis

- PluginSpector beta is a local-first macOS plugin audit tool that shows what is installed, helps users find it quickly, and highlights obvious risk without touching the system.

## Frozen Scope

### P0
- Core scan across `AU`, `VST`, `VST3`, and `AAX`
- Responsive search
- Accent-insensitive / normalized search matching
- Sidebar search and manufacturer filtering
- Detail panel
- Reveal in Finder
- CSV export report
- Manufacturer normalization
- Basic compatibility and legacy identification for obvious supported cases

### P1
- Family / duplicate / version collapse only if already close and low-risk
- Minimal visual polish only when it improves readability without destabilizing core work

## Explicitly Cut

- Workflow notifications/settings
- Batch delete
- Off-drive backup
- Undo/deleted file tracking
- UAD active scan
- DAW Recovery Mode
- Plugin Alliance uninstaller
- Deep background scan as a launch feature
- Plugin photo scraping / thumbnails
- Notification suite / non-use notifications
- Broad opaque “agent” behavior

## Immediate Execution Order

1. Scanner correctness and compatibility signals
2. Search responsiveness and normalized matching
3. Sidebar filtering and summary integrity
4. Detail, reveal, and export flows
5. Manufacturer normalization
6. Optional family collapse only if it does not threaten launch confidence

## Hard Success Criteria

- Real plugin folders scan successfully.
- Search feels responsive on large libraries.
- Search and sidebar filtering behave predictably.
- Details, reveal, and export work end-to-end.
- Manufacturer naming looks consistent.
- Compatibility labels are conservative and credible.
- No destructive workflow is exposed as beta-ready.

## Not Promised In Beta

- Deletion, quarantine, backup, restore, or rollback
- DAW crash recovery automation
- Vendor-specific uninstallers
- Full UAD authorization truth
- Notifications, thumbnails, or background intelligence
- A full plugin management suite

## Notes

- `Sources/WorkflowPreferences.swift` and `Sources/PluginFileActions.swift` remain scaffolding only and are not part of beta scope.
- `Sources/PluginGrouping.swift` remains optional P1 work.
