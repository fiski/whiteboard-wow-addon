-- Network.lua
-- Sends and receives addon messages for GuildWhiteboard.
-- Outgoing messages are queued and flushed at most once per SEND_INTERVAL
-- to stay within WoW's ~18 messages/second rate limit.

GWBNetwork = {
    PREFIX        = "GWB",
    sendQueue     = {},
    lastSend      = 0,
    SEND_INTERVAL = 0.06,
}

-- Callbacks assigned by the main module
GWBNetwork.OnDrawReceived = nil  -- function(sender, segData)
GWBNetwork.OnClearReceived = nil -- function(sender)
GWBNetwork.OnUndoReceived = nil  -- function(sender, strokeID)
GWBNetwork.OnSyncRequest = nil   -- function(sender)
GWBNetwork.OnSyncData = nil      -- function(sender, segments)
GWBNetwork.OnSyncEnd = nil       -- function(sender)

local function GetChannel()
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    else
        return "GUILD"
    end
end

-- Add a message to the outgoing queue using the current group channel.
function GWBNetwork.QueueMessage(msg)
    table.insert(GWBNetwork.sendQueue, { msg = msg, channel = GetChannel() })
end

-- Send to a specific player (used for sync replies to avoid flooding the channel).
function GWBNetwork.SendWhisper(msg, target)
    SendAddonMessage(GWBNetwork.PREFIX, msg, "WHISPER", target)
end

-- Called from the main frame's OnUpdate. Drains one message per interval.
function GWBNetwork.FlushQueue(elapsed)
    GWBNetwork.lastSend = GWBNetwork.lastSend + elapsed
    if GWBNetwork.lastSend < GWBNetwork.SEND_INTERVAL then return end
    if #GWBNetwork.sendQueue == 0 then return end
    GWBNetwork.lastSend = 0
    local item = table.remove(GWBNetwork.sendQueue, 1)
    SendAddonMessage(GWBNetwork.PREFIX, item.msg, item.channel)
end

-- Handle an incoming CHAT_MSG_ADDON event.
-- Ignores messages from the local player (they are already applied locally).
function GWBNetwork.HandleMessage(prefix, message, _, sender)
    if prefix ~= GWBNetwork.PREFIX then return end

    -- Strip realm suffix for same-realm comparison
    local senderName = strsplit("-", sender)
    if senderName == UnitName("player") then return end

    local msgType = strsplit("|", message)

    if msgType == "DRAW" then
        if GWBNetwork.OnDrawReceived then
            local seg = GWBSerialize.DecodeDrawSegment(message)
            if seg then GWBNetwork.OnDrawReceived(sender, seg) end
        end

    elseif message == "CLEAR" then
        if GWBNetwork.OnClearReceived then
            GWBNetwork.OnClearReceived(sender)
        end

    elseif msgType == "UNDO" then
        if GWBNetwork.OnUndoReceived then
            local strokeID = GWBSerialize.DecodeUndo(message)
            if strokeID then GWBNetwork.OnUndoReceived(sender, strokeID) end
        end

    elseif message == "SYNC_REQ" then
        if GWBNetwork.OnSyncRequest then
            GWBNetwork.OnSyncRequest(sender)
        end

    elseif msgType == "SYNC_DATA" then
        if GWBNetwork.OnSyncData then
            local segments = GWBSerialize.DecodeSyncChunk(message)
            GWBNetwork.OnSyncData(sender, segments)
        end

    elseif message == "SYNC_END" then
        if GWBNetwork.OnSyncEnd then
            GWBNetwork.OnSyncEnd(sender)
        end
    end
end

function GWBNetwork.Initialize()
    RegisterAddonMessagePrefix(GWBNetwork.PREFIX)
end
