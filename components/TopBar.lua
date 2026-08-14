local Component = require("core.Component")
local Colors    = require("util.Colors")
local Math      = require("util.Math")
local Helpers   = require("util.Helpers")

local TopBar = setmetatable({}, { __index = Component })
TopBar.__index = TopBar
TopBar.__name = "TopBar"
TopBar.needs = { "ConfigService", "FontService", "GameService", "SaveService" }

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

local function drawLandscape(self, cfg, fonts, ctx, showFps)
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

    local rightElems = {}
    if showFps then
        local fps = love.timer and love.timer.getFPS and love.timer.getFPS()
        if fps then
            rightElems[#rightElems + 1] = { text = fps .. " FPS", col = Colors.fpsColor(fps) }
        end
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

local function drawRow(f, cfg, chips, x, w, cy, align, bg)
    if #chips == 0 then return end
    local totalW = rowWidth(f, cfg, chips)
    local startX = (align == "right") and (x + w - totalW) or x
    drawChipsAt(f, cfg, chips, startX, cy, cfg.TOPBAR_GAP, bg)
end

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

local function statusLeftChips(cfg, t)
    local chips = {
        { icon = "clock", color = cfg.COL.dim, text = Math.formatPlayTime(t.playTime or 0) },
    }
    if t.location and t.location ~= "" then
        chips[#chips + 1] = { icon = "pin", color = cfg.COL.xp, text = t.location }
    end
    return chips
end

local function statusRightChips(cfg, showFps)
    local chips = {}
    if showFps then
        local fps = love.timer and love.timer.getFPS and love.timer.getFPS()
        if fps then
            chips[#chips + 1] = { icon = "dot", color = Colors.fpsColor(fps), text = fps .. " FPS" }
        end
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

local function drawPortrait(self, cfg, fonts, ctx, showFps)
    local W      = ctx.w
    local topY   = ctx.y or 0
    local h      = ctx.h or cfg.TOP_BAR_ROW_H
    local stackMode = ctx.stackMode or false
    local section = ctx.section or "player"
    local bg     = cfg.COL.panelTop

    if stackMode then

        local rowH = h / 2
        local t = self.trainer
        local f = fonts:getFont(cfg.TOPBAR_FONT_SZ)
        love.graphics.setFont(f)

        local padX = cfg.TOPBAR_PAD_X
        local rowW = W - padX * 2

        Colors.set(bg, 0.95)
        love.graphics.rectangle("fill", 0, math.floor(topY), math.floor(W), math.floor(rowH), 0, 0)
        love.graphics.setLineWidth(1)
        Colors.set(cfg.COL.border, 0.55)
        love.graphics.line(0, topY, W, topY)
        Colors.set(cfg.COL.border, 0.4)
        love.graphics.line(0, topY + rowH, W, topY + rowH)

        local cy1 = topY + rowH / 2
        drawEvenlySpaced(f, cfg, profileChips(cfg, t, self.repel), padX, rowW, cy1, bg)

        Colors.set(bg, 0.95)
        love.graphics.rectangle("fill", 0, math.floor(topY + rowH), math.floor(W), math.floor(rowH), 0, 0)
        Colors.set(cfg.COL.border, 0.4)
        love.graphics.line(0, topY + h, W, topY + h)

        local cy2 = topY + rowH + rowH / 2
        drawAligned(f, cfg, padX, rowW, cy2, bg,
            statusLeftChips(cfg, t), nil, statusRightChips(cfg, showFps))
    else

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
                statusLeftChips(cfg, t), nil, statusRightChips(cfg, showFps))
        end
    end
end

function TopBar:draw(ctx)
    local cfg   = self:_service("ConfigService")
    local fonts = self:_service("FontService")

    local showFps = self:_service("SaveService"):isFpsVisible()

    if ctx.isPortrait then
        drawPortrait(self, cfg, fonts, ctx, showFps)
    else
        drawLandscape(self, cfg, fonts, ctx, showFps)
    end
end

return TopBar
