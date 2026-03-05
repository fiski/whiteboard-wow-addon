-- Serialize.lua
-- Encode/decode stroke data for network transmission.
-- All messages are kept within WoW's 255-byte addon message limit.

GWBSerialize = {}

-- Encode a single draw segment.
-- Format: "DRAW|strokeID|x1,y1,x2,y2|r,g,b|size"
function GWBSerialize.EncodeDrawSegment(strokeID, x1, y1, x2, y2, r, g, b, size)
    return string.format("DRAW|%s|%.4f,%.4f,%.4f,%.4f|%d,%d,%d|%d",
        strokeID, x1, y1, x2, y2, r, g, b, size)
end

function GWBSerialize.DecodeDrawSegment(msg)
    local _, strokeID, coords, color, size = strsplit("|", msg)
    if not (strokeID and coords and color and size) then return nil end
    local x1, y1, x2, y2 = strsplit(",", coords)
    local r, g, b = strsplit(",", color)
    return {
        strokeID = strokeID,
        x1 = tonumber(x1), y1 = tonumber(y1),
        x2 = tonumber(x2), y2 = tonumber(y2),
        r = tonumber(r), g = tonumber(g), b = tonumber(b),
        size = tonumber(size),
    }
end

function GWBSerialize.EncodeClear()
    return "CLEAR"
end

-- Format: "UNDO|strokeID"
function GWBSerialize.EncodeUndo(strokeID)
    return "UNDO|" .. strokeID
end

function GWBSerialize.DecodeUndo(msg)
    local _, strokeID = strsplit("|", msg)
    return strokeID
end

function GWBSerialize.EncodeSyncRequest()
    return "SYNC_REQ"
end

-- Encode the full stroke list into one or more SYNC_DATA messages, each <=255 bytes.
-- Each entry: "strokeID:x1,y1,x2,y2:r,g,b:size"
-- Entries within a message are separated by ";"
-- A final "SYNC_END" message signals completion.
function GWBSerialize.EncodeSyncChunks(strokes)
    local chunks = {}
    local batch = {}
    local batchLen = 0
    local header = "SYNC_DATA|"
    local maxPayload = 240 - #header

    for _, seg in ipairs(strokes) do
        local entry = string.format("%s:%.4f,%.4f,%.4f,%.4f:%d,%d,%d:%d",
            seg.strokeID, seg.x1, seg.y1, seg.x2, seg.y2,
            seg.r, seg.g, seg.b, seg.size)
        -- +1 accounts for the ";" separator
        if batchLen + #entry + 1 > maxPayload and #batch > 0 then
            table.insert(chunks, header .. table.concat(batch, ";"))
            batch = {}
            batchLen = 0
        end
        table.insert(batch, entry)
        batchLen = batchLen + #entry + 1
    end

    if #batch > 0 then
        table.insert(chunks, header .. table.concat(batch, ";"))
    end
    table.insert(chunks, "SYNC_END")
    return chunks
end

-- Format: "SYNC_DATA|entry1;entry2;..."
function GWBSerialize.DecodeSyncChunk(msg)
    local _, data = strsplit("|", msg)
    if not data then return {} end
    local segments = {}
    for entry in string.gmatch(data, "[^;]+") do
        local strokeID, coords, color, size = strsplit(":", entry)
        if strokeID and coords and color and size then
            local x1, y1, x2, y2 = strsplit(",", coords)
            local r, g, b = strsplit(",", color)
            table.insert(segments, {
                strokeID = strokeID,
                x1 = tonumber(x1), y1 = tonumber(y1),
                x2 = tonumber(x2), y2 = tonumber(y2),
                r = tonumber(r), g = tonumber(g), b = tonumber(b),
                size = tonumber(size),
            })
        end
    end
    return segments
end
