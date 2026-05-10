# GuildCore Invite Compliance Review

Last reviewed: 2026-05-10

This document explains how GuildCore's invite functionality works and why the
current implementation is designed to stay within Blizzard's addon and gameplay
automation expectations. It is not a legal opinion; Blizzard has final authority
over World of Warcraft policy interpretation and can disable addon behavior at
its discretion.

## Blizzard Policy Touchpoints

GuildCore's invite design is based on these public Blizzard policy points:

- Blizzard's End User License Agreement prohibits bots and unauthorized software
  that allows automated control of a game, part of a game, or platform feature.
  Source: [Blizzard EULA](https://www.blizzard.com/en-us/legal/08b946df-660a-40e4-a072-1fbde65173b1/blizzard-end-user-license-agreement)
- Blizzard's UI Add-On Development Policy requires addons to be free, visible,
  non-obfuscated, non-advertising, non-disruptive, and compliant with the WoW
  Terms of Use and EULA. Source:
  [WoW UI Add-On Development Policy](https://eu.forums.blizzard.com/en/wow/t/wow-user-interface-add-on-development-policy/1642)
- Blizzard support documentation describes normal guild invitation methods,
  including `/ginvite CharacterName`, guild recruitment/applicants, and the
  Guild/Community invite UI. Source:
  [Unable to Invite to Guild](https://us.support.blizzard.com/en/article/10462)

## Compliance Summary

GuildCore is a normal Lua addon that runs inside Blizzard's supported addon
environment. It does not ship external executables, memory tools, injection
tools, background bot software, or hidden/obfuscated code.

For guild invites specifically:

- The addon discovers possible invite candidates using Blizzard's in-game WHO
  query path.
- The addon filters candidates locally so officers can review them.
- The current public live invite action sends exactly one guild invite per user
  click or configured keybind through `INVITE NEXT`.
- The addon checks guild invite permission before attempting an invite.
- The addon records recent invite/decline state to avoid repeatedly inviting the
  same characters.
- The visible `Invite Selected` button is intentionally a disabled/stub workflow
  that only warns the user to use `Invite Next`.
- The slash command queue path supports adding candidates and dry-run processing
  only; it does not expose a live batch invite command.

## What The Invite Module Does Not Do

- It does not run while the player is away from the keyboard.
- It does not repeatedly invite players without a user action for each live
  invite in the current public UI.
- It does not bypass Blizzard's guild invite APIs.
- It does not automate character movement, combat, targeting, gathering, or any
  gameplay loop.
- It does not modify the WoW client, inspect memory, inject code, or connect to
  Blizzard services outside the in-game API.
- It does not sell, advertise, solicit donations, or include premium features.
- It does not send chat spam as part of invite scanning.

## Live Invite Call Site

The only wrapper that calls Blizzard's guild invite function is:

- `Core/API.lua`
  - `GC.API.GuildInvite(name)`
  - Normalizes the target name.
  - Calls `C_GuildInfo.Invite` when present, otherwise `GuildInvite`.
  - Wraps the call in `pcall` and returns success/failure.

Current public UI live invite path:

1. User selects one eligible candidate in the Invite tab.
2. User clicks `INVITE NEXT` or presses the configured `Invite Next` keybind.
3. `UI/InvitePanel.lua` calls `IP:_inviteNow()`.
4. `IP:_inviteNow()` picks the first selected eligible candidate.
5. `Modules/Invite/Queue.lua` calls `Queue:InviteNow(candidate)`.
6. `Queue:InviteNow()` validates permission, guild status, realm eligibility,
   and candidate eligibility.
7. `Queue:InviteNow()` calls `GC.API.GuildInvite(target)` once.

### Invite UI

- `Invite` tab:
  Opens the review surface for candidate scanning and one-at-a-time invites.
- `Scan` / `Scan Next`:
  Sends WHO query requests for candidate discovery.
- `Select All`:
  Selects currently visible eligible rows for review and dry-run queue use.
- `Clear Selection`:
  Clears candidate selections.
- `Refresh Status`:
  Re-applies recent invite/decline state.
- `Invite Selected`:
  Warning-only placeholder. It does not start live batch invites.
- `INVITE NEXT`:
  Sends one guild invite for one selected eligible candidate.

### Settings

- `Invite Next hotkey`:
  Defaults to `CTRL-SHIFT-I`. Bound to the same one-candidate `INVITE NEXT`
  button path.
- `Invite Scan hotkey`:
  Defaults to `CTRL-SHIFT-S`. Starts or advances scan behavior only.
- `Dry Run`:
  Simulates queue processing and logs "would invite" results without calling
  the guild invite API.

### Slash Commands

- `/gc invite`
  Opens the Invite tab.
- `/gc invitescan`
  Starts candidate discovery from the detected guild realm.
- `/gc invitescan next`
  Sends the next pending WHO query if a scan pauses.
- `/gc invitescan stop`
  Stops the current scan.
- `/gc invitescan clear`
  Stops the scan and clears candidates.
- `/gc invitescan status`
  Prints current scan state.
- `/gc invitescan realm`
  Prints realm detection diagnostics.
- `/gc invitescan testrealm`
  Starts manual realm query format testing.
- `/gc invitefilters`
  Prints invite filter settings.
- `/gc invitefilters reset`
  Resets safe recruitment defaults.
- `/gc invitefilters set guildlessOnly true|false`
  Changes whether guilded candidates are filtered.
- `/gc invitequeue addeligible`
  Adds eligible scanned candidates to the internal queue.
- `/gc invitequeue list`
  Prints queued candidates.
- `/gc invitequeue dryrun`
  Processes queued candidates as simulation only. This path does not call the
  guild invite API.
- `/gc invitequeue pause|resume|cancel|clear`
  Controls the dry-run queue state.

There is intentionally no `/gc invitequeue live`, `/gc invite selected`, or
equivalent slash command that starts unattended live guild invites.

## Safeguards

- Permission gate:
  `Core/Permissions.lua` uses `CanGuildInvite()` when available and reports a
  clear failure if the player is not in a guild or lacks invite permission.
- Eligibility gate:
  `Modules/Invite/Queue.lua` blocks candidates already in a guild, outside the
  allowed realm set, or marked ineligible by filters.
- Candidate filtering:
  `Modules/Invite/Filters.lua` supports guildless-only filtering, recent
  invite/decline exclusion, ignored names, class filters, level range filters,
  and zone include/exclude filters.
- Recent-invite protection:
  `Modules/Invite/Service.lua` and `Modules/Invite/History.lua` store local
  recent invite and decline state so the UI can avoid repeat invites.
- Dry-run separation:
  `Queue:StartDryRun()` and `_processDryRunNext()` are explicitly simulation
  paths and include comments stating that they never call the real invite API.
- User-action surface:
  The current visible live workflow is one invite per click/keybind through
  `INVITE NEXT`.

## Reviewer Notes

The service file contains live queue helper functions (`StartLiveRun()` and
`_processLiveNext()`) from earlier development. The current UI does not wire
`Invite Selected` to those functions, and the slash-command queue surface exposes
dry-run only. If the review goal is to remove even dormant live batch code, those
helpers can be deleted or hard-disabled before distribution.

Blizzard remains the authority on whether a specific addon behavior is allowed.
If Blizzard reviewers ask for stricter behavior, the safest next hardening step
is to remove dormant live queue functions and keep only `InviteNow(candidate)`.

## Review Checklist

- [ ] Confirm addon source is plain Lua/XML/assets and not obfuscated.
- [ ] Confirm there are no bundled executables or external automation tools.
- [ ] Confirm `GC.API.GuildInvite` is the only wrapper around the guild invite
      API.
- [ ] Confirm visible live invite UI calls only `Queue:InviteNow(candidate)`.
- [ ] Confirm `Invite Selected` is warning-only.
- [ ] Confirm `/gc invitequeue` exposes dry-run only and no live queue command.
- [ ] Confirm candidate discovery uses Blizzard WHO APIs and local filtering.
- [ ] Confirm no behavior continues sending live invites while the player is
      away from the keyboard.
