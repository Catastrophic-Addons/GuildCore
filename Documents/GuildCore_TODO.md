# Guild Core TODO

## Current State

- [x] Service-based addon structure
- [x] Two-phase roster scan flow
- [x] Auto-scan ticker
- [x] Manual scan from UI and slash command
- [x] Saved roster snapshots and scan summaries
- [x] Officer note parsing for join date and Discord fields
- [x] Main / Alt / Unknown relationship model
- [x] Validation against self-links, circular links, and unknown targets
- [x] Compact first-seen classification prompt
- [x] Settings toggle for prompts
- [x] Updated README for scan and SavedVariables behavior

## Next Priority

- [ ] Add a searchable picker for choosing a main character in UI prompts
- [ ] Add explicit rejoin handling for tracked characters who leave and return
- [ ] Improve visibility for `untracked` transitions caused by rank changes
- [ ] Add grouped roster views by main character
- [ ] Add export helpers for tracked roster intelligence

## Later

- [ ] Sync roster intelligence safely between officer clients
- [ ] Add audit tools for officer-note formatting consistency
- [ ] Add richer inactivity / retention dashboards
- [ ] Add messaging templates that use tracked roster intelligence
