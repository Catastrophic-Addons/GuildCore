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

- [ ] Template schema needs non-destructive expansion for `tags`, `targetChannel`, `usageCount`, `createdBy`, `updatedBy`, `favorite`, and `archived`
- [ ] Placeholder preview exists, but unresolved placeholders are left as raw tokens instead of friendly fallback text
- [ ] Chunker supports limits, numbering, and clean breaks, but does not expose all spec options or enforce a 255 hard max option
- [ ] Auto Mode exists, but needs stronger large-send confirmations, channel warnings, better status, and throttling aligned with WoW chat behavior
- [ ] Direct Send currently means "queue template, auto-start only if Auto Mode is enabled"; additional row actions still need Edit, Preview, Duplicate, Archive, Delete, and Load to Chat
- [ ] Target channel support is service-capable but UI currently hardcodes Guild for preview queueing and load-to-chat
- [ ] Drag reorder exists for messages, but category reorder/collapse/archive is not implemented
- [ ] Permission helpers exist globally, but Messaging does not yet check separate messaging permissions

### Missing From Spec

- [ ] Default category seed set: General, Recruitment, Welcome / Onboarding, Discord Verification, Raid, Mythic+, Events, Officer Notes, Guild Rules, Follow-Ups
- [ ] Search/filter UI for templates
- [ ] Template tags, favorites, archive visibility, duplicate flow, and soft-delete/archive behavior
- [ ] Template default target channel plus per-send override for Guild, Officer, Whisper, Say, Yell, Party, Raid, and Instance
- [ ] Whisper recipient handling
- [ ] Message usage history capped per guild, including sender, target, recipient, timestamp, template id, and chunk count
- [ ] Rich placeholder groups for onboarding, event, Mythic+, raid, recruitment, rank, date, and current time values
- [ ] Placeholder picker and insert-helper buttons
- [ ] Onboarding flags, suggested message prompts, checklist icons, and welcome/reminder workflows
- [ ] Discord/web export-import bridge and shared template concepts
- [ ] Campaign-style multi-step workflow engine

### Phase 1 - Safe Schema and Channel Foundation

- [ ] Add a migration-only schema expansion that preserves all existing `guild.messages.messages` rows and only fills missing fields
- [ ] Add template fields: `targetChannel`, `tags`, `usageCount`, `createdBy`, `updatedBy`, `favorite`, `archived`
- [ ] Add category fields: `archived`, `collapsed`, optional `color`, optional `icon`, and stable ordering metadata if needed
- [ ] Add message history storage under the current guild, capped to 250 entries, without changing existing logs
- [ ] Add service-level channel validation and supported-channel metadata before changing UI controls
- [ ] Keep Manual Mode as the default and keep current queue/send behavior intact

### Phase 2 - Messaging Safety and Target UI

- [ ] Add a channel selector and per-template default target channel in `UI/MessagingPanel.lua`
- [ ] Add whisper recipient input and validation before queue/send/load-to-chat
- [ ] Route Queue Preview, Direct Send, Send Next, and Load Chunk through validated channel options instead of hardcoded Guild
- [ ] Add confirmations for more than 3 chunks and for higher-risk channels such as Officer, Yell, Raid, and Instance
- [ ] Add a 255-character hard max option while keeping 240 as the default preview/send limit
- [ ] Improve auto-send status, cooldown messaging, and Stop Auto visibility without enabling Auto Mode by default

### Phase 3 - Template Library Quality

- [ ] Add duplicate, archive/unarchive, favorite, delete confirmation, and archived-template filtering
- [ ] Add category reorder, collapse/expand, archive, and default category seed creation that does not overwrite user categories
- [ ] Add template search over title, notes, body, and tags
- [ ] Add usage tracking updates on successful send and append capped message history entries
- [ ] Add a small history view or history section in the Messaging panel

### Phase 4 - Placeholder Expansion

- [ ] Expand core placeholders with `@rank.name`, `@date.today`, and `@time.now`
- [ ] Add roster-aware target lookup so placeholders can resolve member data when a target is selected
- [ ] Add onboarding placeholders only after member onboarding state exists
- [ ] Add event, raid, Mythic+, and recruitment placeholders as their source data modules become available
- [ ] Add friendly fallback values for unresolved placeholders and expose unresolved-token warnings in preview
- [ ] Add placeholder picker and insert-helper buttons near the editor

### Phase 5 - Onboarding Integration

- [ ] Define per-member onboarding flags in player records with migration-safe defaults
- [ ] Connect guild join detection to a non-sending officer prompt for welcome/Discord/main-alt/rules actions
- [ ] Add suggested-template filtering based on missing onboarding flags
- [ ] Add checklist indicators to roster/player UI without changing existing roster scan behavior
- [ ] Mark onboarding tasks complete only after officer action succeeds

### Phase 6 - External Bridge and Campaigns

- [ ] Add manual export/import for templates before any network or bot integration
- [ ] Align placeholder names with future Discord bot and website account/profile concepts
- [ ] Add campaign data structures only after template history and onboarding flags are stable
- [ ] Keep Discord bot, website API, and triggered campaign sending out of the core send path until explicitly implemented and reviewed

### Messaging File Impact List

- [ ] `Modules/Messages/Service.lua` - schema validation, template/category operations, channel validation, history, usage tracking, and send safety
- [ ] `Modules/Messages/Chunker.lua` - hard max behavior, option handling, and preview metadata
- [ ] `Modules/Messages/Placeholders.lua` - expanded resolver, fallback text, roster/onboarding context, and unresolved-token reporting
- [ ] `Modules/Messages/Module.lua` - module metadata only if new settings or permissions require it
- [ ] `UI/MessagingPanel.lua` - target controls, row actions, search, history, placeholder picker, warnings, and safer confirmations
- [ ] `Core/Migrations.lua` - non-destructive SavedVariables migrations for new message/category/history/onboarding fields
- [ ] `Core/Database.lua` and `Data/Defaults.lua` - defaults for new guild message state without overwriting existing guild data
- [ ] `Core/Permissions.lua` - messaging-specific permission checks using existing guild-rank helpers
- [ ] `Core/Events.lua` - future onboarding prompts from guild join events, kept non-sending by default
- [ ] `UI/RosterPanel.lua` and `UI/PlayerPanel.lua` - later onboarding checklist indicators and suggested-message entry points
- [ ] `GuildCore.toc` - only if new Messaging helper files are split out
- [ ] `README.md` - document Messaging SavedVariables behavior and safety rules after implementation phases land

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

## Next Priority

- [ ] Start Messaging Phase 1 with schema-safe template/category field expansion and service-level channel metadata
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
