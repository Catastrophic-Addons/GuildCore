# Guild Core TODO

Canonical working list: `../TODO.md`

This document snapshot is intentionally short so exported docs do not drift from
the root todo. Update `TODO.md` first when planning or closing work.

## Current Priority Snapshot

- [ ] Add a dedicated guild bank history view with tab and transaction-type filters
- [ ] Add bank-capture summaries or status text in the UI after a successful guild bank import
- [ ] Add optional export helpers for guild bank history
- [ ] Add a searchable picker for choosing a main character in UI prompts
- [ ] Add explicit rejoin handling for tracked characters who leave and return
- [ ] Improve visibility for `untracked` transitions caused by rank changes
- [ ] Add grouped roster views by main character
- [ ] Expand export helpers beyond the current simple Dashboard copy-paste flow
- [ ] Finish the multi-select invite workflow once a safe user-action model is settled
- [ ] Add richer invite session reporting around pending/no-response outcomes
- [ ] Add welcome-message preview/testing controls in Settings or the Messages panel
- [ ] Design sync payloads for relationship and officer-note intelligence before enabling client-to-client reconciliation

## Recently Completed

- [x] Messaging phases 1-6 foundation, placeholder expansion, template import/export, and queue stabilization
- [x] Invite tab foundation with WHO scanning, candidate filters, history, hotkeys, dry run, and explicit `Invite Next`
- [x] Purge tab foundation with review-first macro workflow
- [x] Batched welcome messages for new guild joins
- [x] Configurable UI font themes
