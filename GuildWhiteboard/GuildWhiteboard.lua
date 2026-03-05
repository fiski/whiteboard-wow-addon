-- GuildWhiteboard.lua
-- Entry point: UI creation, input handling, SavedVariables, slash commands.
-- Depends on Serialize.lua, Network.lua, Drawing.lua (loaded after this file,
-- but all calls happen inside event handlers which fire after all files load).

GuildWhiteboardData = GuildWhiteboardData or { strokes = {} }

-- ─── Brush state ─────────────────────────────────────────────────────────────

local GWB = {
    color           = { r = 255, g = 255, b = 255 },
    brushSize       = 3,
    isDrawing       = false,
    lastX           = nil,
    lastY           = nil,
    currentStrokeID = nil,
    strokeHistory   = {},  -- ordered list of own strokeIDs, newest last
}

local strokeCounter = 0
local function NewStrokeID()
    strokeCounter = strokeCounter + 1
    return UnitName("player") .. "_" .. strokeCounter
end

-- ─── Palette / sizes ─────────────────────────────────────────────────────────

local COLORS = {
    { r = 255, g = 255, b = 255, name = "White"  },
    { r = 255, g = 80,  b = 80,  name = "Red"    },
    { r = 80,  g = 220, b = 80,  name = "Green"  },
    { r = 80,  g = 140, b = 255, name = "Blue"   },
    { r = 255, g = 220, b = 60,  name = "Yellow" },
    { r = 220, g = 80,  b = 220, name = "Purple" },
    { r = 255, g = 160, b = 40,  name = "Orange" },
    { r = 60,  g = 220, b = 220, name = "Cyan"   },
}

local BRUSH_SIZES = { 2, 4, 7, 12 }

-- ─── UI helpers ──────────────────────────────────────────────────────────────

local function MakeButton(parent, label, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, h)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function MakeTooltip(btn, text)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ─── Main frame ──────────────────────────────────────────────────────────────

local function CreateMainFrame()
    local frame = CreateFrame("Frame", "GuildWhiteboardFrame", UIParent,
                              "BackdropTemplate")
    frame:SetSize(660, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -12)
    title:SetText("Guild Whiteboard")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    return frame
end

-- ─── Toolbar ─────────────────────────────────────────────────────────────────

local function CreateToolbar(parent, canvas)
    local toolbar = CreateFrame("Frame", nil, parent)
    toolbar:SetSize(640, 42)
    toolbar:SetPoint("BOTTOM", canvas, "TOP", 0, 6)

    local x = 4

    -- Color swatches
    local selectedBorder
    for i, col in ipairs(COLORS) do
        local btn = CreateFrame("Button", nil, toolbar)
        btn:SetSize(28, 28)
        btn:SetPoint("LEFT", toolbar, "LEFT", x, 0)
        x = x + 32

        local fill = btn:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(btn)
        fill:SetColorTexture(col.r / 255, col.g / 255, col.b / 255, 1)

        -- White highlight ring shown on the active swatch
        local ring = btn:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2, 2)
        ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        ring:SetColorTexture(1, 1, 1, 0)

        if i == 1 then
            ring:SetColorTexture(1, 1, 1, 0.8)
            selectedBorder = ring
        end

        btn:SetScript("OnClick", function()
            GWB.color = { r = col.r, g = col.g, b = col.b }
            if selectedBorder then selectedBorder:SetColorTexture(1, 1, 1, 0) end
            ring:SetColorTexture(1, 1, 1, 0.8)
            selectedBorder = ring
        end)
        MakeTooltip(btn, col.name)
    end

    x = x + 8

    -- Brush-size dots
    local sizeLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("LEFT", toolbar, "LEFT", x, 0)
    sizeLabel:SetText("Size:")
    x = x + 34

    local selectedSizeRing
    for j, sz in ipairs(BRUSH_SIZES) do
        local btn = CreateFrame("Button", nil, toolbar)
        btn:SetSize(26, 26)
        btn:SetPoint("LEFT", toolbar, "LEFT", x, 0)
        x = x + 30

        local dot = btn:CreateTexture(nil, "BACKGROUND")
        local ds = math.max(sz, 4)
        dot:SetSize(ds, ds)
        dot:SetPoint("CENTER")
        dot:SetColorTexture(1, 1, 1, 1)

        local ring = btn:CreateTexture(nil, "OVERLAY")
        ring:SetAllPoints(btn)
        ring:SetColorTexture(1, 1, 1, 0)

        if j == 1 then
            ring:SetColorTexture(1, 1, 1, 0.4)
            selectedSizeRing = ring
        end

        btn:SetScript("OnClick", function()
            GWB.brushSize = sz
            if selectedSizeRing then selectedSizeRing:SetColorTexture(1, 1, 1, 0) end
            ring:SetColorTexture(1, 1, 1, 0.4)
            selectedSizeRing = ring
        end)
        MakeTooltip(btn, "Brush size: " .. sz)
    end

    x = x + 8

    local undoBtn = MakeButton(toolbar, "Undo", 52, 26,
        function() GWB.LocalUndo() end)
    undoBtn:SetPoint("LEFT", toolbar, "LEFT", x, 0)
    x = x + 58

    local clearBtn = MakeButton(toolbar, "Clear", 52, 26,
        function() GWB.LocalClear(true) end)
    clearBtn:SetPoint("LEFT", toolbar, "LEFT", x, 0)
    x = x + 58

    local syncBtn = MakeButton(toolbar, "Sync", 52, 26, function()
        GWBNetwork.QueueMessage(GWBSerialize.EncodeSyncRequest())
        print("|cff00ff00GuildWhiteboard:|r Sync request sent.")
    end)
    syncBtn:SetPoint("LEFT", toolbar, "LEFT", x, 0)
    MakeTooltip(syncBtn, "Request current board state from a peer")
end

-- ─── Drawing actions ─────────────────────────────────────────────────────────

-- Convert a screen pixel coordinate to canvas-local normalized [0,1].
local function ScreenToNorm(canvas, sx, sy)
    local left   = canvas:GetLeft()
    local bottom = canvas:GetBottom()
    local w      = canvas:GetWidth()
    local h      = canvas:GetHeight()
    local nx = (sx - left) / w
    local ny = (sy - bottom) / h
    return math.max(0, math.min(1, nx)),
           math.max(0, math.min(1, ny))
end

local function RecordSegment(x1, y1, x2, y2)
    local sid  = GWB.currentStrokeID
    local r, g, b = GWB.color.r, GWB.color.g, GWB.color.b
    local sz   = GWB.brushSize

    GWBDraw.DrawSegment(sid, x1, y1, x2, y2, r, g, b, sz)

    local seg = { strokeID = sid,
                  x1 = x1, y1 = y1, x2 = x2, y2 = y2,
                  r = r, g = g, b = b, size = sz }
    table.insert(GuildWhiteboardData.strokes, seg)

    local msg = GWBSerialize.EncodeDrawSegment(sid, x1, y1, x2, y2, r, g, b, sz)
    if #msg <= 255 then
        GWBNetwork.QueueMessage(msg)
    end
end

function GWB.LocalClear(broadcast)
    GWBDraw.ClearCanvas()
    GuildWhiteboardData.strokes = {}
    GWB.strokeHistory = {}
    if broadcast then
        GWBNetwork.QueueMessage(GWBSerialize.EncodeClear())
    end
end

function GWB.LocalUndo()
    if #GWB.strokeHistory == 0 then return end
    local sid = table.remove(GWB.strokeHistory)
    GWBDraw.UndoStroke(sid)

    local kept = {}
    for _, seg in ipairs(GuildWhiteboardData.strokes) do
        if seg.strokeID ~= sid then
            table.insert(kept, seg)
        end
    end
    GuildWhiteboardData.strokes = kept

    GWBNetwork.QueueMessage(GWBSerialize.EncodeUndo(sid))
end

-- ─── Canvas input ────────────────────────────────────────────────────────────

local function SetupCanvasInput(canvas)
    canvas:EnableMouse(true)

    canvas:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        GWB.isDrawing       = true
        GWB.currentStrokeID = NewStrokeID()
        table.insert(GWB.strokeHistory, GWB.currentStrokeID)

        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        GWB.lastX, GWB.lastY = ScreenToNorm(canvas, cx / scale, cy / scale)
    end)

    canvas:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        GWB.isDrawing = false
        GWB.lastX     = nil
        GWB.lastY     = nil
    end)
end

-- ─── Network callbacks ───────────────────────────────────────────────────────

local function SetupNetworkCallbacks()
    GWBNetwork.OnDrawReceived = function(sender, seg)
        GWBDraw.DrawSegment(seg.strokeID, seg.x1, seg.y1, seg.x2, seg.y2,
                            seg.r, seg.g, seg.b, seg.size)
        table.insert(GuildWhiteboardData.strokes, seg)
    end

    GWBNetwork.OnClearReceived = function(sender)
        GWB.LocalClear(false)
    end

    GWBNetwork.OnUndoReceived = function(sender, strokeID)
        GWBDraw.UndoStroke(strokeID)
        local kept = {}
        for _, seg in ipairs(GuildWhiteboardData.strokes) do
            if seg.strokeID ~= strokeID then
                table.insert(kept, seg)
            end
        end
        GuildWhiteboardData.strokes = kept
    end

    -- Respond to a sync request by whispering our full stroke list to the sender.
    GWBNetwork.OnSyncRequest = function(sender)
        local chunks = GWBSerialize.EncodeSyncChunks(GuildWhiteboardData.strokes)
        for _, chunk in ipairs(chunks) do
            GWBNetwork.SendWhisper(chunk, sender)
        end
    end

    -- Merge incoming sync strokes into the local canvas.
    GWBNetwork.OnSyncData = function(sender, segments)
        -- Build a lookup set of already-known strokeIDs to avoid duplicates.
        local known = {}
        for _, seg in ipairs(GuildWhiteboardData.strokes) do
            known[seg.strokeID] = true
        end
        for _, seg in ipairs(segments) do
            if not known[seg.strokeID] then
                GWBDraw.DrawSegment(seg.strokeID,
                    seg.x1, seg.y1, seg.x2, seg.y2,
                    seg.r, seg.g, seg.b, seg.size)
                table.insert(GuildWhiteboardData.strokes, seg)
                known[seg.strokeID] = true
            end
        end
    end

    GWBNetwork.OnSyncEnd = function(sender) end
end

-- ─── Initialization ──────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
local mainFrame
local sampleElapsed = 0
local SAMPLE_INTERVAL = 0.05  -- draw point sample rate (20 Hz)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "GuildWhiteboard" then
            GuildWhiteboardData = GuildWhiteboardData or { strokes = {} }
            GWBNetwork.Initialize()
        end

    elseif event == "PLAYER_LOGIN" then
        mainFrame = CreateMainFrame()
        local canvas = GWBDraw.CreateCanvas(mainFrame)
        CreateToolbar(mainFrame, canvas)
        SetupCanvasInput(canvas)
        SetupNetworkCallbacks()

        if GuildWhiteboardData and GuildWhiteboardData.strokes then
            GWBDraw.RestoreStrokes(GuildWhiteboardData.strokes)
        end

        -- OnUpdate: flush network queue + sample cursor while drawing
        mainFrame:SetScript("OnUpdate", function(self, elapsed)
            pcall(GWBNetwork.FlushQueue, elapsed)

            if not GWB.isDrawing then return end

            sampleElapsed = sampleElapsed + elapsed
            if sampleElapsed < SAMPLE_INTERVAL then return end
            sampleElapsed = 0

            local ok = pcall(function()
                local scale = UIParent:GetEffectiveScale()
                local cx, cy = GetCursorPosition()
                local nx, ny = ScreenToNorm(canvas, cx / scale, cy / scale)
                if GWB.lastX and (nx ~= GWB.lastX or ny ~= GWB.lastY) then
                    RecordSegment(GWB.lastX, GWB.lastY, nx, ny)
                end
                GWB.lastX, GWB.lastY = nx, ny
            end)

            if not ok then
                GWB.isDrawing = false
            end
        end)

    elseif event == "CHAT_MSG_ADDON" then
        pcall(GWBNetwork.HandleMessage, ...)
    end
end)

-- ─── Slash commands ──────────────────────────────────────────────────────────

SLASH_GWB1 = "/gwb"
SlashCmdList["GWB"] = function(msg)
    msg = strtrim(msg or "")
    if msg == "clear" then
        GWB.LocalClear(true)
        print("|cff00ff00GuildWhiteboard:|r Canvas cleared.")
    elseif msg == "sync" then
        GWBNetwork.QueueMessage(GWBSerialize.EncodeSyncRequest())
        print("|cff00ff00GuildWhiteboard:|r Sync request sent.")
    else
        if mainFrame then
            if mainFrame:IsShown() then
                mainFrame:Hide()
            else
                mainFrame:Show()
            end
        end
    end
end
