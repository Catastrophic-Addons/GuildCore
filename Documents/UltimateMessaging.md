Here’s the Ultimate GuildCore Messaging System Spec, designed as a command deck for guild communication, onboarding, recruitment, Discord nudges, reminders, and officer workflows. 🏴‍☠️

GuildCore Messaging System Spec
1. Core Purpose

GuildCore Messaging should become the central communication hub for the addon.

It should handle:

Saved message templates
Categories and folders
Smart placeholders
Message chunking
Manual and automatic sending
Onboarding reminders
Recruitment replies
Discord verification prompts
Guild rank progression messaging
Officer task prompts
Future integration with Discord bot/web tools

The goal is not just “send messages.”
The goal is: make guild communication repeatable, trackable, and officer-friendly.

2. Main Concepts
Message Templates

Each saved message should support:

{
  id = "msg-1",
  title = "Welcome New Member",
  categoryId = "onboarding",
  body = "Welcome @target.name to @guild.name!",
  notes = "Use when someone joins the guild.",
  tags = { "welcome", "onboarding", "discord" },
  targetChannel = "GUILD",
  createdAt = 123456789,
  updatedAt = 123456789,
  lastUsedAt = nil,
  usageCount = 0,
}

Recommended fields:

title
body
notes
categoryId
tags
targetChannel
lastUsedAt
usageCount
createdBy
updatedBy
favorite
archived
3. Categories

Default categories:

General
Recruitment
Welcome / Onboarding
Discord Verification
Raid
Mythic+
Events
Officer Notes
Guild Rules
Follow-Ups

Category features:

Create
Rename
Delete
Reorder
Collapse/expand
Archive
Move messages between categories
Optional category color/icon
4. Placeholder System

This is the spellbook. Make templates dynamic.

Core placeholders
@player.name
@guild.name
@realm.name
@target.name
@new.member
@rank.name
@date.today
@time.now
@time.left
Onboarding placeholders
@main.name
@alt.name
@discord.name
@discord.status
@join.date
@days.in.guild
@onboarding.status
@missing.steps
Event placeholders
@event.name
@event.date
@event.time
@event.location
@event.leader
Mythic+ placeholders
@team.name
@team.day
@team.time
@team.role
@captain.name
Raid placeholders
@raid.name
@raid.date
@raid.time
@raid.requirements
Guild recruitment placeholders
@recruit.name
@class.name
@spec.name
@role.name
5. Placeholder Preview

The editor should include a Resolved Preview panel.

Example:

Template body:

Welcome @target.name to @guild.name! Please join Discord: @discord.invite

Preview:

Welcome Blackbeard to Blackwake Armada! Please join Discord: discord.gg/bw-armada

If a placeholder cannot resolve:

@discord.name → Unknown Discord

Do not error. Never let one missing field sink the ship.

6. Message Chunking

Chunking should be reusable across all GuildCore modules.

Requirements
Configurable character limit
Default 240 chars
Hard max option: 255
Prefer clean breaks:
Paragraph breaks
Sentence endings
Line breaks
Word boundaries
Hard split
Optional numbering:
(1/3) Message text
(2/3) Message text
Preview chunk count and character count
Useful options
{
  limit = 240,
  includeNumbers = true,
  preserveParagraphs = true,
  trimWhitespace = true,
}
7. Sending Modes
Manual Mode

Default and safest.

Flow:

Preview → Queue → Send Next

Best for:

Guild-wide announcements
Officer messages
Anything sensitive
Auto Mode

Optional power-user mode.

Flow:

Preview → Queue → Start Auto Send

Rules:

Delay between chunks, default 2 seconds
Stop button
Queue cap
Visible warning/status
Never enabled by default
Load-to-Chat Mode

Safest possible option.

Flow:

Load Chunk → Officer presses Enter manually

This is perfect for avoiding accidental spam.

8. Target Channels

Supported now:

Guild
Officer
Whisper
Say
Yell
Party
Raid
Instance

Future targets:

In-game mail
Guild applicant reply
Discord webhook/bot
Website notification

Each template should have a default target channel, but the officer can override it before sending.

9. Direct Send Shortcuts

Each saved template row should have quick actions:

Edit
Preview
Queue
Send / Auto Send
Load to Chat
Duplicate
Archive
Delete

In Manual Mode:

“Send” should queue only
Officer still clicks Send Next

In Auto Mode:

“Send” queues and starts auto-send
10. Onboarding Integration

This is where the system becomes a proper guild goblin-engine. ⚙️

Each guild member can have onboarding flags:

{
  hasDiscord = true,
  discordName = "CaptainCrunch",
  hasMainSelected = true,
  hasAltLinked = false,
  hasReadRules = true,
  hasIntroMessageSent = true,
  promotedToMember = false,
}

Messaging can then power:

Welcome Flow

When someone joins:

Detect guild join
Set @new.member
Show officer prompt:
Send Welcome Message?
Ask about Discord?
Ask if this is main or alt?
Mark task complete once sent
Missing Step Reminders

Example:

@target.name still needs:
- Discord verification
- Main character selection
- Rules acknowledgment

Officer can click:

Send Discord Reminder
Send Alt/Main Prompt
Send Rules Reminder
11. Officer Checklist Integration

Messaging should connect to your future onboarding checklist.

Example member row icons:

✅ Discord verified
⚠️ Missing main character
⚠️ No join date
📨 Welcome sent
📨 Reminder pending

Clicking a warning opens suggested templates.

Example:

Missing Discord → show Discord Verification templates
Missing Main → show Main/Alt templates
New Initiate → show Welcome templates

This makes the addon feel alive instead of just being a spreadsheet in armor.

12. Discord Bot Integration

Eventually, GuildCore and the Discord bot should share message concepts.

Shared template ideas

Discord bot could use similar placeholders:

@discord.name
@character.name
@team.name
@role.name
@event.time
Future sync options

Possible future paths:

Option A: Manual export/import

GuildCore exports templates as JSON-ish text.

Discord bot imports them.

Option B: Website/API bridge

Guild website stores templates centrally.

GuildCore and Discord bot both read from the website API.

Option C: Discord bot owns external messaging

GuildCore sends in-game messages.
Discord bot sends Discord messages.
Website ties identities together.

Best long-term design:

GuildCore = in-game officer cockpit
Discord Bot = Discord workflow engine
Website = persistent account/profile hub
13. Recommended UI Layout
Messaging Main Panel
+---------------------------------------------------------------+
| Messaging                                                     |
| [Mode: Manual/Auto] [Target: Guild] [Limit: 240] [Search...]  |
+------------------+----------------------+---------------------+
| Categories       | Templates            | Editor              |
|                  |                      | Title               |
| General          | Welcome New Member   | Notes               |
| Recruitment      | Discord Reminder     | Body                |
| Onboarding       | Raid Reminder        |                     |
| Raid             |                      | [Save] [Preview]    |
+------------------+----------------------+---------------------+
| Preview / Queue / Output                                      |
| Chunk 1/3 | 232 chars                                          |
| Chunk 2/3 | 198 chars                                          |
| [Queue] [Load Chunk] [Send Next] [Start Auto] [Stop Auto]      |
+---------------------------------------------------------------+
14. Template Builder Helpers

Add helper buttons beside the editor:

Insert Placeholder
Insert Discord Link
Insert Guild Name
Insert Target Name
Insert Event Time
Insert Rule Reminder

Placeholder picker:

Player
Guild
Member
Onboarding
Event
Raid
Mythic+

This prevents officers needing to memorize every @thing.name.

15. Message History

Track usage.

Each sent template can log:

{
  templateId = "msg-1",
  title = "Welcome New Member",
  target = "GUILD",
  recipient = "Sagewyn",
  sentBy = "OfficerName",
  sentAt = 123456789,
  chunkCount = 3,
}

Useful for:

“Did we already message this person?”
“When was the Discord reminder sent?”
“Who sent the welcome message?”

Keep this capped, such as latest 250 entries per guild.

16. Permissions

Suggested permission levels:

View templates
Create/edit templates
Delete templates
Send guild messages
Send officer messages
Use Auto Mode
Manage categories
View history

Use existing GuildCore permissions when possible.

17. Safety Rules

Hard rules:

Manual Mode default
Auto Mode opt-in
Stop button always visible during auto-send
Never send empty chunks
Never silently send unresolved dangerous text
Queue cap
Cooldown
Confirmation for large sends
Confirmation for sending more than 3 chunks
Confirmation for Officer/Yell/Raid if desired
18. Future “Campaigns”

This is the big-brain version.

A campaign is a multi-step message workflow.

Example: New Member Onboarding Campaign

Step 1: Welcome message
Step 2: Discord reminder
Step 3: Main/alt question
Step 4: Rules reminder
Step 5: Promotion-ready notice

Each step has:

{
  id = "step-1",
  templateId = "msg-welcome",
  trigger = "member_joined",
  delay = nil,
  required = true,
  completionFlag = "welcomeSent",
}

That turns GuildCore into a real guild operations engine.

19. Best Build Order
Phase 1: Messaging Foundation
Templates
Categories
Chunking
Queue
Manual send
Direct send
Phase 2: Power Features
Placeholders
Auto Mode
Drag-and-drop
Usage history
Phase 3: Onboarding Tie-In
Member flags
Suggested messages
Checklist icons
Welcome flow prompts
Phase 4: Discord/Web Bridge
Export/import templates
Shared placeholder names
Discord bot message templates
Website account/profile linkage
Phase 5: Campaign System
Multi-step workflows
Triggered reminders
Officer task queue
20. Best Final Vision

GuildCore Messaging should eventually become:

A reusable communication engine for every officer workflow.

Not just messages.
Not just templates.
A little brass-and-shadow machine that turns guild chaos into clean, repeatable action.