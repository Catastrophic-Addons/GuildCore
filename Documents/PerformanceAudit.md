# Guild Core Performance Audit Notes

## 2026-05-20 roster and sync stabilization

Findings:
- The shared list component was rendering one row frame per roster item. Large guilds could create hundreds or thousands of button frames and font strings after roster filtering/grouping.
- Roster search applied filters on every keystroke and allocated fresh result/group tables repeatedly.
- Grouped alt display cloned roster rows for indentation instead of reusing display records.
- Sync sessions retained chunk buffers until the whole session was dropped, and the outbox used front-removal behavior that could churn tables during large transfers.

Fixes:
- `GC.UI.List` now renders a capped visible row pool and reuses row scripts/frames while scrolling.
- Roster search filtering is debounced, scratch tables are reused, and grouped alt rows no longer clone whole member records.
- `GC.Perf` adds gated memory snapshots plus `/gc mem` and `/gc gc` diagnostics.
- Sync now clears dataset chunk buffers as soon as each dataset is merged, wipes failed/timed-out sessions, and uses a head/tail outbox queue.

How to test:
1. Run `/gc mem` after login for a baseline.
2. Open the roster, search repeatedly, toggle Online Only and Group Alts, use A-Z filters, and scroll for 30 seconds.
3. Run `/gc mem` again, then `/gc gc`, then `/gc mem`.
4. Run Sync Now with another compatible officer online and repeat the memory check.

Remaining risks:
- WoW may keep frame memory reserved after creating the visible row pool, but row frame count should now stabilize instead of growing with roster size.
- Sync still allocates serialized payload strings during an active transfer; they are intentionally short-lived and cleared after send/merge.
