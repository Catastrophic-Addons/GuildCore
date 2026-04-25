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
- [x] Dashboard Guild Insights cards and Needs Attention list
- [x] Simple dashboard export for copy-paste officer review
- [x] Guild bank item and money log capture on guild bank open
- [x] Activity tab support for captured bank events
- [x] Native Messages module with saved templates, categories, chunk preview, and safe queue/send helpers
- [x] Minimap access button using `Assets/icons/GC_Gold.tga`
- [x] Guild/Community UI access tab with load-on-demand safety
- [x] Main-frame and popup layering helpers for Guild Core UI
- [x] Message placeholders, Auto Mode queue automation, direct-send row actions, and drag reorder for Messages

## Messaging System Roadmap

### Current Messaging Implementation

- [x] Messaging module is registered and can be enabled/disabled from settings
- [x] Per-guild SavedVariables storage exists for `messages`, `categories`, `messageOrderByCategory`, and `messageQueue`
- [x] Safe default General category is created and migrated without wiping existing saved messages
- [x] Message templates support `id`, `title`, `categoryId`, `body`, `notes`, timestamps, and `lastUsedAt`
- [x] Category create, rename, delete-with-message-move, selection, and basic ordering exist
- [x] Message create, edit, delete, move between categories, and reorder exist
- [x] Chunk preview and queueing exist through `Modules/Messages/Chunker.lua`
- [x] Manual Send Next, Load Chunk, Clear Queue, Auto Mode opt-in, Stop Auto, and direct row Send exist
- [x] Basic placeholders exist for `@player.name`, `@guild.name`, `@realm.name`, `@target.name`, `@new.member`, and `@time.left`
- [x] Guild join system messages are captured into `lastJoinedName` for `@new.member`

### Partially Implemented

- [x] Template schema supports non-destructive expansion for `tags`, `targetChannel`, `usageCount`, `createdBy`, `updatedBy`, `favorite`, and `archived`
- [x] Placeholder preview uses friendly fallback text for known missing values and warns on unknown tokens
- [x] Chunker supports limits, numbering, clean breaks, and the 255 hard max option
- [x] Auto Mode has stronger large-send confirmations, channel warnings, improved status, and loop prevention
- [x] Direct Send still means "queue template, auto-start only if Auto Mode is enabled"; template rows now also have duplicate, archive, favorite, and confirmed delete flows
- [x] Target channel support is service-capable and wired into preview queueing, direct send, send-next, auto-send, and load-to-chat
- [x] Drag reorder exists for messages, and category reorder/collapse/archive is implemented
- [ ] Permission helpers exist globally, but Messaging does not yet check separate messaging permissions

### Missing From Spec

- [x] Default category seed set: General, Recruitment, Welcome / Onboarding, Discord Verification, Raid, Mythic+, Events, Officer Notes, Guild Rules, Follow-Ups
- [x] Search/filter UI for templates
- [x] Template tags, favorites, archive visibility, duplicate flow, and soft-delete/archive behavior
- [x] Template default target channel plus per-send override for Guild, Officer, Whisper, Say, Yell, Party, Raid, and Instance
- [x] Whisper recipient handling
- [x] Message usage history capped per guild, including sender, target, recipient, timestamp, template id, and chunk count
- [ ] Rich placeholder groups for onboarding, event, Mythic+, raid, and recruitment values
- [x] Rank, date, and current time placeholders
- [x] Placeholder picker and insert-helper buttons
- [ ] Onboarding flags, suggested message prompts, checklist icons, and welcome/reminder workflows
- [x] Manual Discord/web export-import bridge foundation and shared template concepts
- [ ] Campaign-style multi-step workflow engine

### Phase 1 - Safe Schema and Channel Foundation

- [x] Add a migration-only schema expansion that preserves all existing `guild.messages.messages` rows and only fills missing fields
- [x] Add template fields: `targetChannel`, `tags`, `usageCount`, `createdBy`, `updatedBy`, `favorite`, `archived`
- [x] Add category fields: `archived`, `collapsed`, optional `color`, optional `icon`, and stable ordering metadata if needed
- [x] Add message history storage under the current guild, capped to 250 entries, without changing existing logs
- [x] Add service-level channel validation and supported-channel metadata before changing UI controls
- [x] Keep Manual Mode as the default and keep current queue/send behavior intact

### Phase 1 Notes

- [x] Changed `Modules/Messages/Service.lua` for repeat-safe schema validation, message history helpers, and channel metadata helpers only
- [x] Changed `Core/Migrations.lua`, `Core/Database.lua`, and `Data/Defaults.lua` for non-destructive dbVersion 7 defaults/migration support
- [x] Changed `README.md` briefly because Messaging SavedVariables internals are already documented there
- [ ] Follow-up risk: Phase 2 must wire channel metadata into UI/send paths carefully; Phase 1 intentionally leaves Queue Preview, Direct Send, Send Next, and Load Chunk behavior unchanged
- [ ] Follow-up risk: future history writes should only happen after a successful send or officer-confirmed action, not during preview or queue-only flows

### Phase 2 - Messaging Safety and Target UI

- [x] Add a channel selector and per-template default target channel in `UI/MessagingPanel.lua`
- [x] Add whisper recipient input and validation before queue/send/load-to-chat
- [x] Route Queue Preview, Direct Send, Send Next, and Load Chunk through validated channel options instead of hardcoded Guild
- [x] Add confirmations for more than 3 chunks and for higher-risk channels such as Officer, Yell, Raid, and Instance
- [x] Add a 255-character hard max option while keeping 240 as the default preview/send limit
- [x] Improve auto-send status, cooldown messaging, and Stop Auto visibility without enabling Auto Mode by default

### Phase 2 Notes

- [x] Changed `UI/MessagingPanel.lua` for the channel selector, whisper recipient field, confirmation prompts, and output routing
- [x] Changed `Modules/Messages/Service.lua` so queue entries preserve target/recipient options and send/load paths validate them before output
- [x] Changed `Modules/Messages/Chunker.lua` to clamp chunk limits to the 20-255 safe range
- [x] Deferred Phase 3 row actions, archive/favorite filters, search, history view, and category movement work have been implemented
- [ ] Follow-up risk: the channel selector is a compact cycle button for Phase 2; a dropdown/picker may be more discoverable later if a shared UI component is added

### Phase 3 - Template Library Quality

- [x] Add duplicate, archive/unarchive, favorite, delete confirmation, and archived-template filtering
- [x] Add category reorder, collapse/expand, archive, and default category seed creation that does not overwrite user categories
- [x] Add template search over title, notes, body, and tags
- [x] Add usage tracking updates on successful send and append capped message history entries
- [x] Add a small history view or history section in the Messaging panel

### Phase 3 Notes

- [x] Changed `Modules/Messages/Service.lua` for default category seeding, template duplicate/archive/favorite helpers, category reorder/collapse/archive helpers, filters/search, usage tracking, and history listing
- [x] Changed `UI/MessagingPanel.lua` for template search, Show Archived/Favs filters, duplicate/favorite/archive/delete actions, category movement/collapse/archive buttons, and compact read-only history
- [x] Changed `README.md` briefly because Messaging internals and panel behavior are documented there
- [x] Deferred Phase 4 placeholder expansion, picker/insert helpers, fallback warnings, and roster-aware lookup have been implemented
- [ ] Follow-up risk: usage/history is recorded after `SendChatMessage` is invoked for the first chunk in a queued batch; WoW can still throttle or block delivery after the addon call returns

### Phase 4 - Placeholder Expansion

- [x] Expand core placeholders with `@rank.name`, `@date.today`, and `@time.now`
- [x] Add roster-aware target lookup so placeholders can resolve member data when a target is selected
- [x] Keep onboarding placeholders deferred until member onboarding state exists
- [x] Keep event, raid, Mythic+, and recruitment placeholders deferred until source data modules exist
- [x] Add friendly fallback values for unresolved placeholders and expose unresolved-token warnings in preview
- [x] Add placeholder picker and insert-helper buttons near the editor

### Phase 4 Notes

- [x] Changed `Modules/Messages/Placeholders.lua` into a defensive placeholder registry/resolver with `Resolve`, `GetAvailablePlaceholders`, `FindUnknownPlaceholders`, and `BuildContext`
- [x] Changed `Modules/Messages/Service.lua` to expose placeholder metadata/unknown-token helpers and attach warning metadata to preview payloads without mutating saved message bodies
- [x] Changed `UI/MessagingPanel.lua` for a compact placeholder picker, insert button, and preview warning display
- [x] Changed `README.md` because Messaging placeholder behavior is documented there
- [ ] Deferred to Phase 5+: onboarding flags, suggested onboarding prompts, and checklist state
- [ ] Deferred until backing modules exist: event, raid, Mythic+, recruitment, and campaign placeholders
- [ ] Follow-up risk: roster-aware values depend on the latest locally scanned roster data and may fall back when the target is not found or data is stale

### Phase 5 - Onboarding Integration

- [ ] Define per-member onboarding flags in player records with migration-safe defaults
- [ ] Connect guild join detection to a non-sending officer prompt for welcome/Discord/main-alt/rules actions
- [ ] Add suggested-template filtering based on missing onboarding flags
- [ ] Add checklist indicators to roster/player UI without changing existing roster scan behavior
- [ ] Mark onboarding tasks complete only after officer action succeeds

### Phase 6 - External Bridge and Campaigns

- [x] Add manual export/import for templates before any network or bot integration
- [x] Align placeholder names with future Discord bot and website account/profile concepts
- [x] Add campaign data structures only after template history and onboarding flags are stable
- [x] Keep Discord bot, website API, and triggered campaign sending out of the core send path until explicitly implemented and reviewed

### Phase 6 Notes

- [x] Changed `Modules/Messages/Service.lua` for repeat-safe `messagingCampaigns` storage access; template export/import now lives in `Modules/Messages/TemplateBridge.lua`
- [x] Changed `Modules/Messages/TemplateBridge.lua` for deterministic copy/paste template export, safe import validation, missing-category creation, and duplicate-as-copy imports
- [x] Changed `UI/MessagingPanel.lua` for selected/all template export and a validate-before-import dialog that delegates encode/decode work to `MessageTemplateBridge`; no automatic network sending was added
- [x] Changed `Modules/Messages/Placeholders.lua` to recognize shared-safe Discord/web placeholders while keeping future event placeholders defensive until backing data exists
- [x] Changed `Core/Migrations.lua`, `Core/Database.lua`, and `Data/Defaults.lua` for dbVersion 8 campaign storage scaffolding without touching existing message/template/queue data
- [x] Changed `README.md` because Messaging internals already document placeholders and SavedVariables structures
- [ ] Deferred to later phases: overwrite-on-import choices, export bundles for non-template state, campaign workflow execution, Discord bot/web API sync, and triggered campaign sending

### Messaging Stabilization Refactor Notes

- [x] Split manual template export/import encoding and decoding out of `UI/MessagingPanel.lua` and `Modules/Messages/Service.lua` into `Modules/Messages/TemplateBridge.lua`
- [x] Registered `MessageTemplateBridge` as a dedicated service and loaded it from `GuildCore.toc`
- [x] Added `ValidateQueueEntry`, `ValidateQueue`, and `RepairQueue` service helpers so malformed queue entries can be reported without normal send paths silently deleting them
- [x] Updated Send Next to preserve a malformed first queue entry and return a clear repair/clear status instead of removing it
- [x] Added a compact queue invalid-count status hook in the Messaging panel without adding a repair UI
- [ ] Future task: consider splitting `UI/MessagingPanel.lua` further into smaller list/editor/preview/history components
- [ ] Remaining risk: queue repair is service-level only; officers still recover through Clear Queue unless a later debug/admin repair control is added

### Messaging File Impact List

- [x] `Modules/Messages/Service.lua` - schema validation, channel metadata, history storage helpers, queue diagnostics, and send-path queue validation
- [x] `Modules/Messages/TemplateBridge.lua` - manual template export/import encode, decode, validation, and copy-on-import helpers
- [x] `Modules/Messages/Chunker.lua` - hard max behavior, option handling, and preview metadata
- [x] `Modules/Messages/Placeholders.lua` - expanded resolver, fallback text, defensive roster context, and unresolved-token reporting
- [ ] `Modules/Messages/Module.lua` - module metadata only if new settings or permissions require it
- [x] `UI/MessagingPanel.lua` - target controls, row actions, search, history, warnings, and safer confirmations
- [x] `Core/Migrations.lua` - non-destructive SavedVariables migration for new message/category/history fields and Phase 6 campaign storage scaffolding
- [x] `Core/Database.lua` and `Data/Defaults.lua` - defaults for new guild message history and campaign state without overwriting existing guild data
- [ ] `Core/Permissions.lua` - messaging-specific permission checks using existing guild-rank helpers
- [ ] `Core/Events.lua` - future onboarding prompts from guild join events, kept non-sending by default
- [ ] `UI/RosterPanel.lua` and `UI/PlayerPanel.lua` - later onboarding checklist indicators and suggested-message entry points
- [x] `GuildCore.toc` - loads the split-out Messaging template bridge helper
- [x] `README.md` - document Messaging SavedVariables behavior and safety rules after implementation phases land

### Messaging Risk List

- [ ] SavedVariables: migrations must only add missing fields, never rebuild `guild.messages.messages`, `messageOrderByCategory`, or `messageQueue`
- [ ] SavedVariables: archive should be a soft state first; avoid destructive deletes except through existing explicit delete flows
- [ ] Backward compatibility: existing templates without `targetChannel`, `tags`, or `usageCount` must continue to preview, queue, and send
- [ ] WoW chat throttling: current 1.2 second cooldown is basic; Auto Mode should remain conservative and respect channel-specific throttling/spam risks
- [ ] WoW chat throttling: never send empty chunks, and confirm larger multi-chunk sends before queueing or auto-starting
- [ ] UI taint: keep Messaging UI as normal addon frames; avoid protected action/button behavior and avoid hooking protected Blizzard chat/guild UI paths unnecessarily
- [ ] UI taint: Load-to-Chat should continue using chat edit APIs as the safest user-confirmed path
- [ ] Permissions: Officer/Yell/Raid/Instance actions should be gated or warned before sending, using existing rank helper patterns
- [ ] Compatibility: external Discord/web/campaign features should use export/import or separate integration layers, not block or rewrite the in-game messaging module
- [ ] Compatibility: Phase 6 import intentionally creates local copies by default; a future overwrite mode needs a stronger preview and explicit officer choice before touching existing templates
- [ ] Maintainability: `UI/MessagingPanel.lua` is still large after the bridge split and should be decomposed gradually without changing behavior

## Next Priority

- [x] Start Messaging Phase 1 with schema-safe template/category field expansion and service-level channel metadata
- [ ] Add a dedicated guild bank history view with tab and transaction-type filters
- [ ] Add bank-capture summaries or status text in the UI after a successful guild bank import
- [ ] Add optional export helpers for guild bank history
- [ ] Add a searchable picker for choosing a main character in UI prompts
- [ ] Add explicit rejoin handling for tracked characters who leave and return
- [ ] Improve visibility for `untracked` transitions caused by rank changes
- [ ] Add grouped roster views by main character
- [ ] Expand export helpers beyond the current simple Dashboard copy-paste flow

## Later

- [ ] Sync roster intelligence safely between officer clients
- [ ] Add audit tools for officer-note formatting consistency
- [ ] Add richer inactivity / retention dashboards
- [ ] Add messaging templates that pull tracked roster intelligence into placeholders or targeted output flows
