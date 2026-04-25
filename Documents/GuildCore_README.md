# Guild Core
Modular guild management suite for World of Warcraft.

## Purpose
Guild Core is intended to become a clean, scalable leadership platform for WoW guilds. It is meant to reduce officer busywork, centralize key workflows, and provide strong historical insight without becoming a tangled monolith.

## Product Direction
Guild Core should combine:
- the strategic depth and practical officer workflows of mature guild management addons
- the modularity and maintainability of a modern addon architecture
- the polish and communication tooling of focused UI/message addons

## Core Pillars
1. Roster intelligence
2. Historical tracking
3. Alt and main relationship management
4. Points and contribution systems
5. Officer operations tools
6. Messages and templates
7. Controlled synchronization
8. Clean, extensible UI

## Phase 1 Scope
- Core framework
- SavedVariables database with migrations
- Roster snapshot and diff engine
- Join/leave/rank-change logging
- Join date tracking
- Alt linking
- Points ledger foundation
- Officer message templates
- Settings and permissions
- Main dashboard shell

## Out of Scope for Initial Build
- Full guild calendar system
- Recruitment/application tooling
- Profession overlays
- Web integration
- Advanced plugin marketplace
- Niche game-mode support

## Top Lessons From Prior Addons
- Keep scan/diff logic separate from UI
- Use timestamp-based conflict resolution for sync
- Build around macro-assisted protected actions
- Make exports and audits first-class
- Do not let globals and UI-first design sprawl everywhere

## Proposed Folder Structure
```text
GuildCore/
├── GuildCore.toc
├── GuildCore.lua
├── Core/
│   ├── Init.lua
│   ├── Events.lua
│   ├── Database.lua
│   ├── Migrations.lua
│   ├── Permissions.lua
│   ├── Utils.lua
│   └── Registry.lua
├── Modules/
│   ├── Roster/
│   │   ├── Service.lua
│   │   ├── Scan.lua
│   │   ├── Diff.lua
│   │   └── History.lua
│   ├── Alts/
│   │   └── Service.lua
│   ├── Points/
│   │   └── Service.lua
│   ├── Messages/
│   │   └── Service.lua
│   ├── Operations/
│   │   └── Service.lua
│   └── Sync/
│       └── Service.lua
├── UI/
│   ├── MainFrame.lua
│   ├── Dashboard.lua
│   ├── RosterPanel.lua
│   ├── PlayerPanel.lua
│   ├── LogPanel.lua
│   ├── SettingsPanel.lua
│   └── Theme.lua
└── Data/
    └── Defaults.lua
```

## Proposed Data Shape
```lua
GuildCoreDB = {
  meta = {
    dbVersion = 1,
  },
  guilds = {
    ["GuildName-Realm"] = {
      settings = {},
      players = {},
      logs = {},
      snapshots = {},
      sync = {},
    }
  }
}
```

## Guiding Principle
Guild Core should feel like a command deck, not a pile of disconnected tools.

---

## WoW API Modernization Notes

> WoW API changes frequently. Prefer `C_*` namespaces and avoid legacy globals when possible. If a `C_*` replacement is available, call it. If you must support multiple client versions, route calls through `Core/API.lua`.

### Deprecated APIs Found in This Addon

| File | Deprecated Call | Replacement | Status |
|---|---|---|---|
| `Modules/Roster/Service.lua` | `GuildRoster()` | `C_GuildInfo.GuildRoster()` | ✅ Fixed — routed through `GC.API.GuildRoster()` |
| `Modules/Roster/Scan.lua` | `GetGuildRosterInfo(index)` | `C_GuildInfo.GetGuildRosterInfo(index)` | ✅ Fixed — routed through `GC.API.GetGuildRosterInfo(index)` |
| `Core/Events.lua` | Direct `GUILD_ROSTER_UPDATE` scan | Debounced via `C_Timer.After` | ✅ Fixed — prevents event flood loop |
| `Core/API.lua` *(file itself)* | `local addonName, GuildCore = ...` | `local addonName, ns = ...` / `local GC = ns.GuildCore` | ✅ Fixed — wrong namespace, disconnected from `ns.GuildCore` |
| `Core/API.lua` *(file itself)* | Not registered in `.toc` | Added to `GuildCore.toc` after `Core\Init.lua` | ✅ Fixed — file never loaded |

### APIs Checked — Still Valid Globals in The War Within

These were audited against the deprecation list and confirmed still functional as global calls in TWW. No migration required yet, but monitor each patch cycle.

| Call | Used In | Notes |
|---|---|---|
| `GetGuildInfo("player")` | `Core/Database.lua`, `Core/Permissions.lua` | Valid global; `C_GuildInfo.GetGuildInfo` also exists as an alias |
| `GetNumGuildMembers()` | `Modules/Roster/Scan.lua` | Still valid; returns `numTotal, numOnline, numOnlineAndMobile` |
| `GetRealmName()` | `Core/Utils.lua`, `Core/Database.lua`, `Modules/Roster/Scan.lua` | Still valid; strip spaces before use (already done) |
| `IsInGuild()` | `Core/Events.lua`, `Modules/Roster/Service.lua` | Still valid global |
| `GuildSetMOTD(message)` | `Modules/Operations/Service.lua` | Still valid protected API for officers |
| `SendChatMessage(msg, "GUILD")` | `Modules/Messages/Service.lua` | Still valid |

### APIs Wrapped in `GC.API` — Not Yet Used by This Addon

These wrappers exist in `Core/API.lua` for future use. Each checks for the modern `C_*` form first and falls back to the legacy global.

| `GC.API` Wrapper | Modern Call | Legacy Fallback |
|---|---|---|
| `GC.API.SetGuildRosterShowOffline(enabled)` | `C_GuildInfo.SetGuildRosterShowOffline` | `SetGuildRosterShowOffline` |
| `GC.API.GetItemInfo(item)` | `C_Item.GetItemInfo` | `GetItemInfo` |
| `GC.API.GetItemCount(item, ...)` | `C_Item.GetItemCount` | `GetItemCount` |
| `GC.API.GetContainerNumSlots(bagID)` | `C_Container.GetContainerNumSlots` | `GetContainerNumSlots` |
| `GC.API.GetContainerItemInfo(bagID, slot)` | `C_Container.GetContainerItemInfo` | `GetContainerItemInfo` |
| `GC.API.PickupContainerItem(bagID, slot)` | `C_Container.PickupContainerItem` | `PickupContainerItem` |
| `GC.API.GetSpellInfo(spellID)` | `C_Spell.GetSpellInfo` | `GetSpellInfo` |
| `GC.API.IsSpellKnown(spellID, isPet)` | `C_Spell.IsSpellKnown` | `IsSpellKnown` |

### Common WoW API Migrations Reference

| Deprecated | Replacement | Namespace |
|---|---|---|
| `GuildRoster()` | `C_GuildInfo.GuildRoster()` | Guild |
| `GetGuildRosterInfo(index)` | `C_GuildInfo.GetGuildRosterInfo(index)` | Guild |
| `SetGuildRosterShowOffline(enabled)` | `C_GuildInfo.SetGuildRosterShowOffline(enabled)` | Guild |
| `GetItemInfo(item)` | `C_Item.GetItemInfo(item)` | Item |
| `GetItemCount(item, ...)` | `C_Item.GetItemCount(item, ...)` | Item |
| `GetContainerItemInfo(bag, slot)` | `C_Container.GetContainerItemInfo(bag, slot)` | Container |
| `GetContainerNumSlots(bag)` | `C_Container.GetContainerNumSlots(bag)` | Container |
| `PickupContainerItem(bag, slot)` | `C_Container.PickupContainerItem(bag, slot)` | Container |
| `GetSpellInfo(spellID)` | `C_Spell.GetSpellInfo(spellID)` | Spell |
| `IsSpellKnown(spellID, isPet)` | `C_Spell.IsSpellKnown(spellID, isPet)` | Spell |
