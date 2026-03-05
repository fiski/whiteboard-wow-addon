# GuildWhiteboard – WoW Addon

## Project Overview

A World of Warcraft addon that provides a shared collaborative whiteboard. Players in the same group/raid/guild who have the addon installed can draw on a shared canvas in real time. Drawing strokes are broadcast via WoW's addon messaging API and rendered on all connected clients.

Target client: **WoW: The Burning Crusade Classic**

---

## File Structure

```
GuildWhiteboard/
├── CLAUDE.md
├── GuildWhiteboard.toc       -- Addon manifest
├── GuildWhiteboard.lua       -- Core logic: UI, drawing, networking
├── Drawing.lua               -- Drawing engine (lines, textures, canvas)
├── Network.lua               -- Addon message send/receive layer
├── Serialize.lua             -- Encode/decode stroke data to/from strings
└── media/
    └── white.tga             -- 1x1 white texture used for drawing lines
```

---

## Architecture

### Rendering
- The whiteboard is a **WoW Frame** (`CreateFrame("Frame", ...)`) overlaid with a dark background texture.
- Drawing is done using **Line objects** (`frame:CreateLine()`) or by placing small tiled textures along the stroke path.
- Coordinates are stored and transmitted in **normalized form (0.0–1.0)** relative to the canvas size, then scaled to local pixel coordinates on render. This ensures strokes look correct across different resolutions.

### Input
- Mouse events on the canvas frame: `OnMouseDown`, `OnMouseUp`, `OnUpdate` (drag detection).
- Stroke points are sampled during drag at a fixed interval to limit message volume.

### Networking
- Uses `SendAddonMessage(prefix, message, channel)` to broadcast strokes.
- Prefix: `"GWB"` (registered with `RegisterAddonMessagePrefix("GWB")`).
- Channel: `"PARTY"` in a group, `"RAID"` in a raid, `"GUILD"` as fallback.
- Received via `CHAT_MSG_ADDON` event.

### Message Format
Messages are pipe-delimited plain strings to stay within WoW's 255-byte message limit.

```
-- Stroke segment:
DRAW|x1,y1,x2,y2|r,g,b|size

-- Clear canvas:
CLEAR

-- Undo last stroke by sender:
UNDO|strokeID
```

Coordinates use 4-decimal float precision. Color channels are 0–255 integers. Stroke size is an integer (1–10).

### Throttling
- WoW enforces ~18 addon messages/second. The network layer queues outgoing messages and flushes on `OnUpdate` with a minimum interval of `0.06s` between sends.
- Long strokes are chunked: if a drag produces more points than can be sent in one message, they are split across sequential messages with the same `strokeID`.

### State
- Active canvas state (all strokes) is stored in `GuildWhiteboardData` (`SavedVariables`) so the board persists across sessions.
- On login, the local board is restored from `SavedVariables`. Remote peers do **not** auto-sync on join — a manual "Request Sync" button sends a `SYNC_REQ` message; the first responder replies with the full stroke list serialized in chunks.

---

## Key WoW API Used

| API | Purpose |
|---|---|
| `CreateFrame` | Main window and canvas frame |
| `frame:CreateLine()` | Draw stroke segments |
| `frame:CreateTexture()` | Background and brush dot fallback |
| `RegisterAddonMessagePrefix` | Register `"GWB"` prefix |
| `SendAddonMessage` | Broadcast strokes to group/raid/guild |
| `CHAT_MSG_ADDON` event | Receive strokes from other players |
| `IsInGroup` / `IsInRaid` | Determine correct channel |
| `UnitName("player")` | Tag strokes with sender name |
| `SavedVariables` | Persist canvas between sessions |

---

## TBC Classic Compatibility Notes

- `frame:CreateLine()` is available in TBC Classic (introduced in 8.x retail but backported). If unavailable, fall back to placing tiled 1x1 white textures along the stroke vector.
- Do **not** use `C_Timer.After` for throttling — use `OnUpdate` with elapsed tracking instead, as `C_Timer` may have limited availability in TBC Classic.
- `SendAddonMessage` in TBC Classic has a **255 character limit** per message. Serialize accordingly.
- Use `GetAddOnMetadata` sparingly; `.toc` fields are the source of truth.

---

## TOC File

```toc
## Interface: 20504
## Title: GuildWhiteboard
## Notes: Shared collaborative drawing canvas for your group or guild.
## Author: YourName
## Version: 1.0.0
## SavedVariables: GuildWhiteboardData

GuildWhiteboard.lua
Serialize.lua
Network.lua
Drawing.lua
```

---

## Development Notes

- **No external libraries** — keep the addon self-contained with zero dependencies.
- **Error handling:** Wrap `OnUpdate` and `CHAT_MSG_ADDON` handlers in `pcall` to prevent one bad message from breaking the frame loop.
- **Slash command:** `/gwb` toggles the whiteboard window. `/gwb clear` clears the local canvas and broadcasts `CLEAR` to the group.
- **UI:** Keep it minimal — a toolbar with color swatches (6–8 colors), brush size selector, clear button, undo button, and a close button. Use WoW's built-in `GameFontNormal` and standard backdrop textures to match the game's UI style.
- All frame strata should be `"HIGH"` so the board renders above the world but below system dialogs.
