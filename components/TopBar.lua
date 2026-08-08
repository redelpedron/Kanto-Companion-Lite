local Component = require("core.Component")
local Colors    = require("util.Colors")
local Math      = require("util.Math")
local Helpers   = require("util.Helpers")

local TopBar = setmetatable({}, { __index = Component })
TopBar.__index = TopBar
TopBar.needs = { "ConfigService", "FontService", "GameService" }

function TopBar.new(locator, props)
    local self = setmetatable(Component.new(locator, props), TopBar)
    self.trainer = {}
    self.repel = 0
    return self
end

function TopBar:init()
    self:_listen("trainer.updated", function(_, t) self.trainer = t or {} end)
    self:_listen("repel.updated",  function(_, r) self.repel = r or 0 end)
end

-- =======================================================================
-- LANDSCAPE: full "label value" text, same density/format as the
-- original bar. Landscape has width to spare, so it keeps words
-- instead of portrait's compact icon chips -- only the grouping
-- (profile info left, live status right, with FPS now in the status
-- group) and the day/night icon are new.
-- =======================================================================

local function drawLandscape(self, cfg, fonts, ctx)
    local W    = ctx.w
    local topY = ctx.y or 0
    local h    = ctx.h or cfg.TOP_BAR_H

    Colors.set(cfg.COL.panelTop, 0.95)
    love.graphics.rectangle("fill", 0, math.floor(topY), math.floor(W), math.floor(h), 0, 0)
    love.graphics.setLineWidth(1)
    Colors.set(cfg.COL.border, 0.4)
    love.graphics.line(0, topY + h, W, topY + h)

    local t  = self.trainer
    local y  = topY + math.floor((h - 11) / 2)
    local sz = 11
    local GAP = 12
    local x  = 10

    local f = fonts:getFont(sz)
    love.graphics.setFont(f)

    local function drawText(str, col, advance)
        Colors.set(col, 1)
        love.graphics.print(str, math.floor(x), math.floor(y))
        if advance ~= false then
            x = x + f:getWidth(str .. "  ") + GAP
        end
    end

    -- Left group: profile info (Name, Gold, Badges, Time Played, Caught, Seen)
    local name = (t.name ~= "" and t.name) or "Trainer"
    drawText(name, cfg.COL.text)
    drawText("$" .. tostring(t.money or 0), cfg.COL.gold)

    drawText("Badges", cfg.COL.dim, false)
    x = x + f:getWidth("Badges ")
    drawText((t.badgeCount or 0) .. "/8", cfg.COL.gold)

    drawText("Played", cfg.COL.dim, false)
    x = x + f:getWidth("Played ")
    drawText(Math.formatPlayTime(t.playTime or 0), cfg.COL.dim)

    drawText("Caught", cfg.COL.dim, false)
    x = x + f:getWidth("Caught ")
    drawText(tostring(t.dexOwned or 0), cfg.COL.hi)

    drawText("Seen", cfg.COL.dim, false)
    x = x + f:getWidth("Seen ")
    drawText(tostring(t.dexSeen or 0), cfg.COL.text)

    if self.repel and self.repel > 0 then
        drawText("Repel " .. self.repel, cfg.COL.mid)
    end

    -- Right group: live status (FPS, Location, day/night icon + Real Time)
    local rightElems = {}
    local fps = love.timer and love.timer.getFPS and love.timer.getFPS()
    if fps then
        rightElems[#rightElems + 1] = { text = fps .. " FPS", col = Colors.fpsColor(fps) }
    end
    if t.location and t.location ~= "" then
        rightElems[#rightElems + 1] = { text = t.location, col = cfg.COL.xp }
    end

    local ok, now = pcall(os.date, "*t")
    local iconSz, iconGap = cfg.TOPBAR_ICON_SZ, cfg.TOPBAR_ICON_GAP
    if ok and now then
        local dayCol, _, isDay = Colors.timeOfDayColor(now.hour)
        rightElems[#rightElems + 1] = {
            text = string.format("%02d:%02d", now.hour, now.min), col = cfg.COL.text,
            icon = isDay and "sun" or "moon", iconCol = dayCol,
        }
    end

    local rightW = 0
    for i, e in ipairs(rightElems) do
        local w = (e.icon and (iconSz + iconGap) or 0) + f:getWidth(e.text)
        rightW = rightW + w
        if i < #rightElems then rightW = rightW + f:getWidth("  ") + GAP end
    end

    local rx = W - 10 - rightW
    if rx < x + 10 then rx = x + 10 end
    for i, e in ipairs(rightElems) do
        if e.icon then
            Colors.set(e.iconCol, 1)
            Helpers.drawIcon(e.icon, rx + iconSz / 2, topY + h / 2, iconSz, cfg.COL.panelTop)
            rx = rx + iconSz + iconGap
        end
        Colors.set(e.col, 1)
        love.graphics.print(e.text, math.floor(rx), math.floor(y))
        rx = rx + f:getWidth(e.text .. "  ") + GAP
    end
end

-- =======================================================================
-- PORTRAIT: compact icon+value chips (screen width is tight here, and
-- this is the orientation where a front-camera notch actually sits in
-- the content). Chip descriptors are measured up front so the same
-- `drawRow` can left-, right-, or center-align any group.
-- =======================================================================

local function hasIcon(chip)
    return chip.icon and chip.icon ~= "none"
end

local function chipWidth(f, cfg, chip)
    local hasText = chip.text and chip.text ~= ""
    local w = 0
    if hasIcon(chip) then
        w = w + cfg.TOPBAR_ICON_SZ
        if hasText then w = w + cfg.TOPBAR_ICON_GAP end
    end
    if hasText then
        w = w + f:getWidth(chip.text)
    end
    return w
end

local function rowWidth(f, cfg, chips)
    local gap, total = cfg.TOPBAR_GAP, 0
    for i, chip in ipairs(chips) do
        total = total + chipWidth(f, cfg, chip)
        if i < #chips then total = total + gap end
    end
    return total
end

--- Low-level: draws `chips` left-to-right starting at `x`, using a
-- fixed `gap` between consecutive chips. `bg` is the row's background
-- color, needed only so the moon icon can cut its crescent correctly.
-- Every other chip-drawing helper below bottoms out here.
local function drawChipsAt(f, cfg, chips, x, cy, gap, bg)
    love.graphics.setFont(f)
    local cx = x
    for _, chip in ipairs(chips) do
        local hasText = chip.text and chip.text ~= ""
        local tx = cx

        if hasIcon(chip) then
            local iconCx = cx + cfg.TOPBAR_ICON_SZ / 2
            Colors.set(chip.color, 1)
            Helpers.drawIcon(chip.icon, iconCx, cy, cfg.TOPBAR_ICON_SZ, bg)
            tx = cx + cfg.TOPBAR_ICON_SZ + (hasText and cfg.TOPBAR_ICON_GAP or 0)
        end

        if hasText then
            Colors.set(chip.textColor or chip.color, 1)
            love.graphics.print(chip.text, math.floor(tx), math.floor(cy - f:getHeight() / 2))
        end

        cx = cx + chipWidth(f, cfg, chip) + gap
    end
end

--- Draws `chips` in a single row inside [x, x+w] at vertical center
-- `cy`. `align` is "left" or "right".
local function drawRow(f, cfg, chips, x, w, cy, align, bg)
    if #chips == 0 then return end
    local totalW = rowWidth(f, cfg, chips)
    local startX = (align == "right") and (x + w - totalW) or x
    drawChipsAt(f, cfg, chips, startX, cy, cfg.TOPBAR_GAP, bg)
end

--- Draws up to three chip groups in one row: `left` pinned to the left
-- edge, `right` pinned to the right edge, `center` centered in
-- whatever room is left. Used to spread a row's content around a
-- top-center notch instead of clustering it all on one side.
local function drawAligned(f, cfg, x, w, cy, bg, left, center, right)
    if left and #left > 0 then
        drawRow(f, cfg, left, x, w, cy, "left", bg)
    end
    if right and #right > 0 then
        drawRow(f, cfg, right, x, w, cy, "right", bg)
    end
    if center and #center > 0 then
        local cw = rowWidth(f, cfg, center)
        local cx = x + (w - cw) / 2
        drawRow(f, cfg, center, cx, cw, cy, "left", bg)
    end
end

--- Spreads `chips` across [x, x+w] with equal gaps between them --
-- like CSS's `justify-content: space-between`: the first chip's left
-- edge sits at x, the last chip's right edge sits at x+w. Never
-- shrinks the gap below the normal TOPBAR_GAP, so a very full row
-- overflows gracefully (right edge) instead of crowding chips together.
local function drawEvenlySpaced(f, cfg, chips, x, w, cy, bg)
    local n = #chips
    if n == 0 then return end
    if n == 1 then
        drawChipsAt(f, cfg, chips, x, cy, cfg.TOPBAR_GAP, bg)
        return
    end

    local totalChipW = 0
    for _, chip in ipairs(chips) do
        totalChipW = totalChipW + chipWidth(f, cfg, chip)
    end
    local gap = math.max(cfg.TOPBAR_GAP, (w - totalChipW) / (n - 1))
    drawChipsAt(f, cfg, chips, x, cy, gap, bg)
end

-- Row 1 (profile): Name, Gold, Badges, Caught, Seen spread evenly
-- across the full row width (Time Played moved to row 2 -- see below).
-- Repel is a bonus field, tacked onto the end only when active so it
-- doesn't shift the fixed fields' positions on the frames it's absent.
local function profileChips(cfg, t, repel)
    local name = (t.name ~= "" and t.name) or "Trainer"
    local chips = {
        { icon = "none",   color = cfg.COL.text, text = name },
        { icon = "coin",   color = cfg.COL.gold, text = "$" .. tostring(t.money or 0) },
        { icon = "badge",  color = cfg.COL.gold, text = (t.badgeCount or 0) .. "/8" },
        { icon = "caught", color = cfg.COL.hi,   text = tostring(t.dexOwned or 0) },
        { icon = "seen",   color = cfg.COL.text, text = tostring(t.dexSeen or 0) },
    }
    if repel and repel > 0 then
        chips[#chips + 1] = { icon = "dot", color = cfg.COL.mid, text = "Repel " .. repel }
    end
    return chips
end

-- Row 2 (live status): Time Played + Location pinned left, FPS + real
-- time pinned right -- leaves the top-center notch clear between them.
local function statusLeftChips(cfg, t)
    local chips = {
        { icon = "clock", color = cfg.COL.dim, text = Math.formatPlayTime(t.playTime or 0) },
    }
    if t.location and t.location ~= "" then
        chips[#chips + 1] = { icon = "pin", color = cfg.COL.xp, text = t.location }
    end
    return chips
end

local function statusRightChips(cfg)
    local chips = {}
    local fps = love.timer and love.timer.getFPS and love.timer.getFPS()
    if fps then
        chips[#chips + 1] = { icon = "dot", color = Colors.fpsColor(fps), text = fps .. " FPS" }
    end
    local ok, now = pcall(os.date, "*t")
    if ok and now then
        local dayCol, _, isDay = Colors.timeOfDayColor(now.hour)
        chips[#chips + 1] = {
            icon = isDay and "sun" or "moon", color = dayCol,
            text = string.format("%02d:%02d", now.hour, now.min), textColor = cfg.COL.text,
        }
    end
    return chips
end

local function drawPortrait(self, cfg, fonts, ctx)
    local W      = ctx.w
    local topY   = ctx.y or 0
    local h      = ctx.h or cfg.TOP_BAR_ROW_H
    local section = ctx.section or "player"
    local bg     = cfg.COL.panelTop

    Colors.set(bg, 0.95)
    love.graphics.rectangle("fill", 0, math.floor(topY), math.floor(W), math.floor(h), 0, 0)
    love.graphics.setLineWidth(1)
    Colors.set(cfg.COL.border, 0.55)
    love.graphics.line(0, topY, W, topY)
    Colors.set(cfg.COL.border, 0.4)
    love.graphics.line(0, topY + h, W, topY + h)

    local t = self.trainer
    local f = fonts:getFont(cfg.TOPBAR_FONT_SZ)
    love.graphics.setFont(f)

    local padX = cfg.TOPBAR_PAD_X
    local cy   = topY + h / 2
    local rowW = W - padX * 2

    if section == "player" then
        drawEvenlySpaced(f, cfg, profileChips(cfg, t, self.repel), padX, rowW, cy, bg)
    else
        drawAligned(f, cfg, padX, rowW, cy, bg,
            statusLeftChips(cfg, t), nil, statusRightChips(cfg))
    end
end

function TopBar:draw(ctx)
    local cfg   = self:_service("ConfigService")
    local fonts = self:_service("FontService")

    if ctx.isPortrait then
        drawPortrait(self, cfg, fonts, ctx)
    else
        drawLandscape(self, cfg, fonts, ctx)
    end
end

return TopBar
