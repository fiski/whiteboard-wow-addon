-- Drawing.lua
-- Canvas creation and stroke rendering.
-- Coordinates are stored and drawn in normalized [0,1] space so they look
-- correct regardless of the player's resolution or UI scale.

GWBDraw = {
    canvas      = nil,
    strokeLines = {},  -- strokeID -> { line, line, ... }  (for undo / clear)
}

local CANVAS_W = 600
local CANVAS_H = 450

-- Built-in solid-white texture available in all WoW clients; used as a
-- fallback when CreateLine() is unavailable and for brush dot placement.
local WHITE_TEX = "Interface\\ChatFrame\\ChatFrameBackground"

-- Convert normalized [0,1] coords to canvas-local pixel coords.
-- Y-axis: 0 = bottom, 1 = top (matches WoW's coordinate system).
local function Norm2Canvas(nx, ny)
    return nx * CANVAS_W, ny * CANVAS_H
end

-- Create and attach the drawing canvas to the given parent frame.
function GWBDraw.CreateCanvas(parent)
    local canvas = CreateFrame("Frame", "GWBCanvas", parent)
    canvas:SetSize(CANVAS_W, CANVAS_H)
    canvas:SetPoint("CENTER", parent, "CENTER", 0, -18)

    local bg = canvas:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(canvas)
    bg:SetColorTexture(0.04, 0.04, 0.07, 1)

    -- Thin border around the canvas
    local border = canvas:CreateTexture(nil, "BORDER")
    border:SetAllPoints(canvas)
    border:SetColorTexture(0.3, 0.3, 0.35, 0.6)

    GWBDraw.canvas = canvas
    return canvas
end

-- Draw a single segment between two normalized points.
-- Attempts CreateLine(); falls back to a texture dot if unavailable.
function GWBDraw.DrawSegment(strokeID, x1, y1, x2, y2, r, g, b, size)
    local canvas = GWBDraw.canvas
    if not canvas then return end

    local px1, py1 = Norm2Canvas(x1, y1)
    local px2, py2 = Norm2Canvas(x2, y2)
    local nr, ng, nb = r / 255, g / 255, b / 255

    local obj
    local ok = pcall(function()
        local line = canvas:CreateLine(nil, "OVERLAY")
        line:SetStartPoint("BOTTOMLEFT", px1, py1)
        line:SetEndPoint("BOTTOMLEFT", px2, py2)
        line:SetThickness(size)
        line:SetColorTexture(nr, ng, nb, 1)
        obj = line
    end)

    if not ok or not obj then
        -- Fallback: place a square dot at the midpoint
        local dot = canvas:CreateTexture(nil, "OVERLAY")
        local s = math.max(size, 2)
        dot:SetTexture(WHITE_TEX)
        dot:SetSize(s, s)
        dot:SetPoint("CENTER", canvas, "BOTTOMLEFT",
            (px1 + px2) / 2, (py1 + py2) / 2)
        dot:SetVertexColor(nr, ng, nb, 1)
        obj = dot
    end

    if not GWBDraw.strokeLines[strokeID] then
        GWBDraw.strokeLines[strokeID] = {}
    end
    table.insert(GWBDraw.strokeLines[strokeID], obj)
end

-- Hide all rendered objects and reset state.
function GWBDraw.ClearCanvas()
    for _, lines in pairs(GWBDraw.strokeLines) do
        for _, obj in ipairs(lines) do
            obj:Hide()
        end
    end
    GWBDraw.strokeLines = {}
end

-- Hide all objects belonging to a single stroke.
function GWBDraw.UndoStroke(strokeID)
    local lines = GWBDraw.strokeLines[strokeID]
    if not lines then return end
    for _, obj in ipairs(lines) do
        obj:Hide()
    end
    GWBDraw.strokeLines[strokeID] = nil
end

-- Redraw all strokes saved in SavedVariables (called on login).
function GWBDraw.RestoreStrokes(strokes)
    for _, seg in ipairs(strokes) do
        GWBDraw.DrawSegment(
            seg.strokeID,
            seg.x1, seg.y1, seg.x2, seg.y2,
            seg.r, seg.g, seg.b, seg.size)
    end
end
