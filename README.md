# Guild Core

Guild Core is a Retail World of Warcraft addon for guild roster intelligence, recruitment, officer workflows, communication, and member history tracking.

Current addon version: `1.5.9`

## Current Module Structure

- `Core/`
  Bootstrap, API wrappers, event flow, migrations, permissions, and shared helpers.
- `Services/DataStore.lua`
  Safe access layer over `GuildCoreDB`.
- `Services/GuildService.lua`
  UI-facing roster, stats, prompt, and lookup helpers.
- `Modules/Roster/`
  Snapshot capture, diffing, history application, and saved scan summaries.
- `Modules/Bank/`
  Guild bank item and money log capture when the guild bank is opened, plus deduped persistence into activity history.
- `Modules/Alts/`
  Main/alt/unknown classification, validation, linking, unlinking, and prompt dismissal.
- `Modules/Points/`
  Point balance and transaction logging.
- `Modules/Messages/`
  Native message-library module, reusable chunking service, saved categories/templates, and safe guild-message output helpers.
- `Modules/Invite/`
  Recruitment scanning, invite candidate filtering, direct user-triggered guild invites, invite history, recent-decline tracking, and invite UI state.
- `Modules/WelcomeBatch/`
  Batched post-join guild welcome messages using system-message detection plus guild roster comparison.
- `Modules/Operations/`
  Officer macro helpers and MOTD support.
- `Modules/Purge/`
  Review-first guild removal queue, inactivity candidate scan, safe-tag protection, `/gremove` macro generation, and post-execution verification.
- `Modules/Sync/`
  Stub for future outbound sync work.
- `UI/`
  Main frame, roster/dashboard/purge/log/settings panels, player detail controls, compact first-seen prompt card, dashboard officer-insight views, minimap access button, Community/Guild UI access tab, and shared layering helpers.

## UI Access Points

- Minimap button:
  GuildCore creates a draggable minimap button using `Interface/AddOns/GuildCore/Assets/icons/GC_Gold.tga`.
  Left-click toggles the main Guild Core window open or closed.
  The tooltip title is `Guild Core` and the body reads `Left Click: Open/Close Guild Core`.
- Minimap persistence:
  The button angle around the minimap is stored in `GuildCoreDB.ui.minimapButtonAngle`.
  Existing saved variables are preserved because defaults are merged only for missing keys.
- Community/Guild tab:
  When Blizzard's Guild/Community interface is available, GuildCore adds a transparent right-side icon button near the bottom-right edge of the Guild/Communities frame.
  Clicking it toggles the Guild Core main window.
  The integration waits for `Blizzard_Communities` / related UI to load and retries defensively, so the tab may appear only after the J-key interface has been opened or Blizzard finishes loading that UI.
  The hover state uses a subtle golden glow, while the icon itself remains visually close to Blizzard's side-tab stack.
- Icon asset:
  Both access points use `Interface/AddOns/GuildCore/Assets/icons/GC_Gold.tga`.

## Frame Layering

- The main Guild Core window uses the `DIALOG` frame strata with an elevated frame level so it appears above normal addon windows and loose external addon icons.
- The outer shadow sits one frame level behind the main window on the same strata.
- GuildCore popups such as the roster context menu and Dashboard export overlay use `DIALOG` with levels above the main frame.
- GameTooltip remains Blizzard-managed on tooltip strata; GuildCore does not promote every child frame to `TOOLTIP`.
- Esc closing, dragging, resizing, tabs, and panel behavior continue to use the existing frame scripts and lazy main-frame creation flow.

## Roster Scan Behavior

- GuildCore uses a two-phase roster flow.
  It requests fresh guild data first, then waits for `GUILD_ROSTER_UPDATE` before reading the roster.
- Login scan:
  Requested shortly after `PLAYER_LOGIN`, with `PLAYER_GUILD_UPDATE` as a backup if guild info arrives late.
- Automatic scan:
  Runs every 60 minutes by default and respects the configurable setting in Settings.
- Manual scan:
  Available from `/gc scan`, the sidebar `Scan Now` button, and the roster `Refresh` button.
- Offline guild members are requested explicitly before capture so the scan includes online and offline tracked members.
- Safe no-guild behavior:
  Manual and automatic scans exit quietly when the character is not in a guild.

## Tracked Ranks

Phase 1 roster intelligence only tracks these guild ranks:

- `Member`
- `Initiate`

Members outside those ranks are excluded from the active tracked roster and marked `untracked` if they were previously being watched.

## Officer Note Parsing Format

GuildCore parses officer notes opportunistically. It does not require one exact template, but these patterns are recognized best:

- Join date:
  `2026-04-24`, `2026/04/24`, `04/24/2026`
- Discord verification:
  `discord verified`, `verified discord`, `discord=yes`, `discord=true`
- Discord negative flag:
  `discord=no`, `discord=false`, `discord unverified`
- Discord name:
  `Discord: Name#1234`, `discord=Name`, `DC: Name`, `@name`

Parsed note fields are stored under each player record as officer-data fields and refreshed on every tracked scan.

## SavedVariables Structure

```lua
GuildCoreDB = {
  meta = {
    dbVersion = 18,
  },
  settings = {
    autoScanIntervalMinutes = 60,
    enableRosterModule = true,
    enableGuildBankModule = true,
    enableMessagingModule = true,
    enableInviteModule = true,
    includeConnectedRealms = true,
    allowHomeRealmFallback = true,
    neverScanAllRealms = true,
    enablePointsModule = true,
    enableSyncModule = false,
    enableClassificationPrompts = true,
    officerRankThreshold = 4,
    debugMode = false,
    themePreset = "guildcore",
    fontTheme = "wowDefault",
    inviteHotkey = "CTRL-SHIFT-I",
    inviteScanHotkey = "CTRL-SHIFT-S",
    enableWelcomeBatch = true,
    welcomeBatchWindowSeconds = 180,
    welcomeMessageTemplate = "Welcome to the guild, {names}! Glad to have you aboard!",
  },
  ui = {
    lastPanel = "dashboard",
    windowX = nil,
    windowY = nil,
    windowWidth = nil,
    windowHeight = nil,
    minimapButtonAngle = 225,
  },
  guilds = {
    ["GuildName-Realm"] = {
      players = {
        ["Player-Realm"] = {
          key = "Player-Realm",
          name = "Player",
          realm = "Realm",
          rankName = "Member",
          rankIndex = 5,
          class = "WARRIOR",
          classDisplayName = "Warrior",
          level = 80,
          status = "active", -- active | left | untracked
          firstSeenAt = 0,
          joinedAt = nil,
          joinedAtSource = nil, -- officerNote | manual | nil
          lastRosterSeenAt = 0,
          lastSeenAt = nil,
          classification = "unknown", -- main | alt | unknown
          main = nil,
          alts = {},
          promptState = {
            dismissedAt = nil,
            completedAt = nil,
            bootstrapSuppressed = nil,
          },
          officerData = {
            joinDate = nil,
            discordVerified = nil,
            discordName = nil,
            noteLastParsedAt = nil,
          },
          notes = {
            custom = "",
            tags = {},
          },
          points = {
            balance = 0,
            lifetime = 0,
            transactions = {},
          },
        },
      },
      logs = {},
      bank = {
        entries = {},
        seenKeys = {},
        lastCapturedAt = nil,
      },
      snapshots = {
        latest = {},
      },
      scans = {
        history = {},
      },
      prompts = {},
      purge = {
        queue = {},
        candidates = {},
        protected = {},
        log = {},
        meta = {
          daysOffline = 30,
          safeTags = { "PROTECTED", "LEAVE", "OFFICER ALT", "DO NOT KICK" },
          includeRanks = { "Initiate", "Member" },
          includeAllRanks = true,
          exemptLinkedCharacters = true,
        },
      },
      messageQueue = {},
      messageHistory = {},
      messagingCampaigns = {
        meta = {
          nextCampaignId = 1,
          nextStepId = 1,
        },
        campaigns = {},
        steps = {},
      },
      messages = {
        meta = {
          nextMessageId = 1,
          nextCategoryId = 1,
          selectedCategoryId = "general",
          selectedMessageId = nil,
          automationEnabled = false,
          autoSendDelaySeconds = 2,
          maxQueueSize = 25,
          previewTargetName = "",
          dailyTargetHour = 18,
          dailyTargetMinute = 0,
          lastJoinedName = nil,
        },
        categories = {
          general = {
            id = "general",
            name = "General",
            createdAt = 0,
            updatedAt = 0,
            archived = false,
            collapsed = false,
            color = nil,
            icon = nil,
          },
        },
        categoryOrder = { "general" },
        messages = {
          ["msg-1"] = {
            id = "msg-1",
            title = "Raid Reminder",
            categoryId = "general",
            body = "Raid starts at 8 PM server.",
            notes = "Officer reminder template",
            targetChannel = "GUILD",
            tags = {},
            usageCount = 0,
            createdBy = "OfficerName",
            updatedBy = "OfficerName",
            favorite = false,
            archived = false,
            createdAt = 0,
            updatedAt = 0,
            lastUsedAt = nil,
          },
        },
        messageOrderByCategory = {
          general = { "msg-1" },
        },
      },
      invite = {
        settings = {
          enabled = false,
          dryRun = false,
          guildlessOnly = true,
          requireOnline = true,
          inviteDelaySeconds = 3,
          inviteResponseTimeoutSeconds = 20,
          maxPerSession = 25,
          showGuildedCandidates = false,
          showRecentlyInvitedCandidates = false,
          showRecentlyDeclinedCandidates = false,
        },
        recentInvites = {},
        recentDeclines = {},
        cooldowns = {},
        history = {},
      },
      welcomeBatch = {
        recentWelcomed = {},
        lastSentAt = nil,
      },
      sync = {
        outboundQueue = {},
      },
    },
  },
}
```

## Dashboard Guild Insights

The Dashboard now uses a `Guild Insights` section instead of repeating the raw activity feed already available in the `Activity` tab.

Insight cards:

- `Initiates Needing Review`
  Active characters currently at the `Initiate` rank.
- `Missing Discord Verification`
  Active characters whose parsed officer-note data does not currently confirm Discord verification.
- `Unlinked / Unknown`
  Active characters still marked with unknown main/alt status.
- `Inactive 7+ Days`
  Active characters not seen online in at least 7 days.

Needs Attention prioritization:

1. Unknown main/alt status
2. Missing Discord verification
3. Initiates needing review
4. Inactive members

The `Needs Attention` list is intentionally capped to keep the Dashboard actionable instead of turning into a second full activity log.

Dashboard actions:

- `Activity Log`
  Opens the dedicated Activity tab.
- `Export`
  Opens a simple copy-paste-friendly text export of the current `Needs Attention` list.

Current data gaps:

- “Possible unlinked alt” currently maps to the existing `Unknown` main/alt classification state.
- Discord status depends on parsed officer-note data and may be incomplete if notes use custom formats GuildCore does not yet recognize.

## Guild Bank Log Capture

- GuildCore captures guild bank logs when the guild bank frame is opened and the bank log data is visible to the current character.
- Both item logs and money logs are queried, normalized, deduped, and persisted.
- New bank entries are mirrored into the Activity tab under the `Bank` filter.
- Supported money events:
  `deposit`, `withdrawal`, `repair`
- Supported item events:
  `deposit`, `withdraw`, `move`

Saved bank entry fields include:

- `kind`
  `item` or `money`
- `transactionType`
- `playerName`
- `playerKey`
- `itemLink` / `itemName` / `count` for item logs
- `amount` for money logs
- `tab`, `fromTab`, `toTab`, and tab-name fields when relevant
- `occurredAt`
  best-effort timestamp bucket derived from Blizzard’s relative log age values
- `capturedAt`
- `signature`
  used for deduplication

Known limitations:

- Guild bank logs are only captured while the guild bank is open and accessible.
- The addon can only capture logs the current character is allowed to see.
- Blizzard bank logs are limited and rolling, so older entries may already be gone before GuildCore sees them.
- Blizzard’s guild bank logs have had known reliability issues in recent Retail periods, so missing historical entries may be a game-side limitation rather than an addon failure.
- The Guild/Community tab depends on Blizzard's load-on-demand Community UI. If that UI is not loaded at login, GuildCore waits and creates/repositions the tab after Blizzard loads or shows the frame.

## Main / Alt Tracking

- Every tracked character can be marked as `Main`, `Alt`, or `Unknown`.
- Alts store their parent in `player.main`.
- Mains store child links in `player.alts`.
- Validation blocks:
  self-links, circular chains, linking to unknown characters, linking to inactive/untracked characters, and using an alt as a main target.
- Changing a character to `Unknown` is blocked if that character still owns linked alts.
- The roster list shows a compact badge:
  `[M]`, `[A]`, or `[?]`
- Player detail controls allow:
  mark main, mark unknown, enter a main name/key, link as alt, and remove an alt link.

## First-Seen Prompt Behavior

- Newly detected tracked members default to `Unknown`.
- A compact prompt card appears inside the main window when prompts are enabled and a tracked member still needs classification.
- Prompt actions:
  `Main`, `Alt` with typed main name/key, `View`, and `Dismiss`.
- Dismissed prompts stay dismissed so the same character is not repeatedly prompted.
- Bootstrap safety:
  the first full scan suppresses automatic prompt spam for pre-existing members already in the guild when the addon is first used.

## Manual Scan Instructions

- Slash command:
  `/gc scan`
- Sidebar:
  `Scan Now`
- Roster panel:
  `Refresh`

## Recruitment Invites

- The Invite tab scans for recruitment candidates through WoW's `/who` data path and stores candidates per guild.
- Invite compliance documentation for guild/officer review lives in `Documents/Invite_Compliance_Review.md`.
- Filters include guilded, recently invited, recently declined, level bands, class filters, zone filters, realm handling, and online requirements.
- `Dry Run` defaults to `false`.
  When enabled manually, the invite path records/logs intent without sending live guild invites.
- `Invite Next` is the primary live invite action.
  It sends one selected eligible invite directly from the user's click or configured hotkey.
- `Invite Selected` is intentionally disabled/muted in the UI and labeled as in progress to avoid implying unattended bulk invites are supported.
- `Select All`, `Clear Selection`, and `Refresh Status` manage candidate selection and update local invite/decline state.
- Invite hotkeys are configurable in Settings:
  `Invite Next hotkey` defaults to `CTRL-SHIFT-I`, and `Invite Scan hotkey` defaults to `CTRL-SHIFT-S`.
  Click the hotkey field, press the desired key combination, or use `Escape`, `Backspace`, or `Delete` to clear it.
- WoW's protected-action model still applies:
  unattended automated guild invites are not reliable or appropriate, so GuildCore favors explicit user-triggered invite actions.

## Batched Welcome Messages

- `Modules/WelcomeBatch/Service.lua` watches for new guild joins using two signals:
  localized `CHAT_MSG_SYSTEM` join text when available, and debounced `GUILD_ROSTER_UPDATE` roster comparison as the reliable fallback.
- Existing roster members become the baseline on login or `/reload`, which prevents welcoming the whole guild after startup.
- New joins are collected into a queue and sent as one guild chat message after the configured batch window.
  The default window is `180` seconds and the Settings UI enforces a minimum of `15` seconds.
- The default template is:
  `Welcome to the guild, {names}! Glad to have you aboard!`
- `{names}` is replaced with a natural list:
  `Allisock`, `Allisock and Steve`, or `Allisock, Steve, and Danktotemz`.
  If `{names}` is missing from the template, GuildCore appends the names safely.
- Duplicate protection uses normalized character keys plus `guild.welcomeBatch.recentWelcomed`, so reloads or repeated roster events do not resend the same welcome.
- Sending is skipped when:
  the feature is disabled, the Messaging module is disabled, the queue is empty, the character is not in a guild, guild chat permission is unavailable, or combat lockdown is active.
  Combat skips are retried after a short delay.
- Welcome messages are capped to a guild-chat-safe length; very large batches collapse to an `and others` form rather than producing an oversized chat line.
- Debug mode logs detection, queueing, timer start, sending, and skipped-send reasons.

## Messages Module

- The `Messages` sidebar panel stores reusable templates per guild in `GuildCoreDB.guilds[guildKey].messages`.
- Templates support:
  category assignment, title, notes, message body, saved order inside each category, target channel metadata, tags, usage counters, creator/updater names, soft favorite/archive flags, created/updated timestamps, and optional `lastUsedAt`.
- Categories always include `General`.
  Missing default categories are seeded without renaming existing user categories.
  Deleting a non-default category safely reassigns its messages back to `General`.
- Message history is stored per guild in `messageHistory` and capped to the latest 250 entries.
- Supported placeholders:
  `@player.name`, `@guild.name`, `@realm.name`, `@target.name`, `@new.member`, `@rank.name`, `@discord.name`, `@character.name`, `@main.name`, `@team.name`, `@role.name`, `@date.today`, `@time.now`, and `@time.left`.
  Future event placeholders such as `@event.name`, `@event.date`, and `@event.time` are recognized defensively but are not shown in the picker until backing event data exists.
- Placeholder resolution happens at preview/send time, not when templates are saved.
  Missing known values fall back safely, such as `member`, `new member`, `unknown rank`, `your guild`, or `your realm`.
  Unknown placeholder tokens remain visible and produce a concise preview warning.
- The editor includes a compact placeholder picker and insert button.
  When local roster data is available, target-aware placeholders can use existing member rank and officer-data fields defensively.
- `@new.member` is fed by `CHAT_MSG_SYSTEM` join detection and remembers the most recent guild join seen by the addon.
- Long messages are previewed through `GC.Services.MessageChunker`, which:
  prefers paragraph breaks, then sentence boundaries, then word boundaries, and only hard-splits when needed.
- Chunk preview uses a configurable character limit and automatically adds numbering like `(1/3)` when multiple chunks are produced.
- Manual Mode remains the default.
  In Manual Mode, direct-send buttons queue resolved chunks without sending them immediately.
- Auto Mode is optional and clearly labeled in the UI.
  When enabled, queued chunks can be sent automatically with a configurable delay and a visible stop control.
- Queue safety rules:
  the module rejects empty chunks, enforces a max queue size, reports malformed queue entries without silently deleting them, avoids duplicate auto-send loops, and stops auto-send if the messaging module is disabled.
- Saved templates now support direct-send buttons and drag-and-drop reorder within the selected category.
  Up/Down buttons remain available as a fallback, and templates can be searched, duplicated, favorited, archived, unarchived, or deleted after confirmation.
- Archived templates and categories are hidden by default and can be shown with the Messaging panel filters.
- Category collapse, archive state, and ordering persist in SavedVariables.
- Successful output records template usage and appends a compact read-only history entry with target, recipient, timestamp, and chunk count.
- Templates can be manually exported/imported through copyable text.
  Imports are handled by the `MessageTemplateBridge` service, validate first, create missing categories safely, and create local template copies without importing usage history.
- Future campaign storage lives under `messagingCampaigns`, but no triggered campaign sending or network bridge is active.
- Output safety:
  loading a selected chunk into chat is the safest flow, while direct sending uses the queue plus a light pacing guard to reduce spam risk.
- The Messaging panel includes a target channel selector for `GUILD`, `OFFICER`, `WHISPER`, `SAY`, `YELL`, `PARTY`, `RAID`, and `INSTANCE_CHAT`.
  Whisper output requires a recipient before queueing, sending, or loading a chunk into chat.
- Riskier channels and outputs longer than three chunks ask for confirmation before queueing or starting Auto Mode.
  Manual Mode remains the default.

## Purge Safety

- GuildCore never calls `GuildRemove()` or `GuildUninvite()` directly for purge actions.
  Guild removal is prepared as `/gremove PlayerName` lines inside the account-wide `GuildCore_Action` macro because Blizzard requires the final guild removal command to be user executed.
- Manual purge from the roster/player UI only adds an entry to the purge queue.
  The officer must review the queue, build the macro, then click or place the `GuildCore_Action` macro.
- Rule scans start conservatively with `Initiate` and `Member` ranks, an offline-days threshold, and safe tag checks against public notes, officer notes, and local custom notes.
  Safe tags are case-insensitive and include `PROTECTED`, `LEAVE`, `OFFICER ALT`, and `DO NOT KICK` by default.
- Purge actions are permission-gated with `CanGuildRemove()` and rank comparison.
  Guild Masters and equal or higher-ranked members are never queued.
- Macro batches respect WoW's 255-character macro limit.
  If the queue is larger than one macro can hold, rebuild the macro after the first batch is clicked and verified.
- GuildCore does not mark a purge as complete when the macro is built or clicked.
  It waits for a matching system message or a roster refresh showing that the queued member is no longer active, then logs the verified removal locally.

## Debug Output

- Debug chat output only appears when `Debug mode` is enabled in Settings.
- Each completed scan logs a compact summary in debug mode:
  tracked members, online tracked members, excluded members, change count, and pending prompt count.
- Invite and welcome systems add debug lines for scan/invite status, join detection, welcome queueing, batch timers, send attempts, and skipped-send reasons.

## Known Limitations

- Officer note parsing is pattern-based.
  Very custom note formats may not be recognized automatically.
- Tracked roster intelligence is currently limited to `Member` and `Initiate`.
- Bootstrap suppresses automatic prompts for already-existing members to avoid flooding the user on first install.
- Sync remains a stub and does not yet reconcile roster intelligence between clients.
- The prompt UI supports typed main selection, not a full searchable dropdown yet.
- WoW addons cannot copy text to the OS clipboard directly.
  The Messages panel therefore focuses on previewing chunks, loading them into chat input safely, and queueing direct sends carefully.
- Blizzard chat throttling and server-side anti-spam protections still apply.
  Auto Mode uses a paced loop, but addons still cannot guarantee delivery timing if Blizzard throttles or blocks outgoing chat.
- Guild invites require an explicit user-triggered action.
  GuildCore supports `Invite Next` and an invite hotkey, but does not provide unattended bulk guild invites.
- Batched welcome messages use the best join signals available to addons.
  Roster comparison is the fallback when localized system text is missing or inconsistent.

## Next Roadmap Items

- Searchable main selector for prompt and player-detail alt linking.
- Better promotion/demotion history around transitions into and out of tracked ranks.
- Optional exports for tracked roster and relationship data.
- Sync payload design for relationship and officer-note intelligence.
- Additional roster intelligence for inactivity review and officer dashboards.
- Finish the multi-select invite workflow once a safe user-action model is settled.
