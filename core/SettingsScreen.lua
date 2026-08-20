local SCREEN_ID = "KantoCompanionLiteSettings"

local M = {}
M.SCREEN_ID = SCREEN_ID

local FallbackOptionRows = {}
local VISIBLE_ROWS = 6
local ROW_H = 20

function FallbackOptionRows.clampScroll(index, scroll, count)
    if index <= scroll then
        scroll = index - 1
    elseif index > scroll + VISIBLE_ROWS then
        scroll = index - VISIBLE_ROWS
    end
    return math.max(0, math.min(scroll, math.max(0, count - VISIBLE_ROWS)))
end

function FallbackOptionRows.draw(game, rows, index, scroll, footer)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0.05, 0.05, 0.08, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local y = 24
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("KANTO COMPANION LITE", 16, y)
    y = y + ROW_H + 8

    for i = scroll + 1, math.min(#rows, scroll + VISIBLE_ROWS) do
        local row = rows[i]
        local ok, value = pcall(row.value)
        local selected = (i == index)
        if selected then
            love.graphics.setColor(1, 0.9, 0.3, 1)
        else
            love.graphics.setColor(0.75, 0.75, 0.75, 1)
        end
        love.graphics.print(
            (selected and "> " or "  ") .. row.label .. ": " .. (ok and tostring(value) or "?"),
            16, y)
        y = y + ROW_H
    end

    love.graphics.setColor(0.55, 0.55, 0.55, 1)
    love.graphics.print(footer or "", 16, h - 24)
end

function M.install(mod, saveSvc, locator)

    local rows = {
        {
            label = "OVERLAY",
            value = function()
                return saveSvc:isVisible() and "ON" or "OFF"
            end,
            toggle = function()
                saveSvc:toggleVisible()
            end,
            description = "SHOWS OR HIDES THE\nCOMPANION OVERLAY\fON TOP OF THE GAME.",
        },
        {
            label = "BOTTOM TOPBAR",
            value = function()
                return saveSvc:isTopBarBottom() and "ON" or "OFF"
            end,
            toggle = function()
                saveSvc:toggleTopBarBottom()
            end,
            description = "MOVES THE TOP BAR TO\nTHE BOTTOM OF THE\fSCREEN IN LANDSCAPE\nMODE ONLY. PORTRAIT\fIS NOT AFFECTED.",
        },
        {
            label = "SHOW FPS",
            value = function()
                return saveSvc:isFpsVisible() and "ON" or "OFF"
            end,
            toggle = function()
                saveSvc:toggleFpsVisible()
            end,
            description = "SHOWS OR HIDES THE\nFPS COUNTER IN THE\fTOP BAR.",
        },
        {
            label = "SHOW BATTERY",
            value = function()
                return saveSvc:isBatteryVisible() and "ON" or "OFF"
            end,
            toggle = function()
                saveSvc:toggleBatteryVisible()
            end,
            description = "SHOWS OR HIDES THE\nBATTERY %/CHARGING\fICON IN THE TOP BAR.\nLANDSCAPE ONLY.",
        },
    }

    local function makeScreen(game)
        local gameService = locator:resolve("GameService")
        local OptionRows = gameService:getOptionRows()

        if not OptionRows and not M._warnedNoOptionRows then
            M._warnedNoOptionRows = true
            mod.log:warn("SettingsScreen: no adapter for src.ui.OptionRows on this game version -- using built-in fallback rendering. This is expected on Gen 2/Gold until the engine adds one; rows still work, styling is just simpler.")
        end
        local Rows = OptionRows or FallbackOptionRows

        local screen = {
            game = game,
            rows = rows,
            index = 1,
            scroll = 0,
            isOpaque = true,
            kclSettingsScreen = true,
        }

        function screen:sgbPalettes(g)

            local PaletteFX = gameService:getPaletteFX()
            if not PaletteFX then return nil end
            local ok, palettes = pcall(PaletteFX.wholeNamed, g.data, "MEWMON")
            return ok and palettes or nil
        end

        function screen:update()
            local input = self.game.input
            if input:wasPressed("up") then
                self.index = (self.index - 2) % #self.rows + 1
            elseif input:wasPressed("down") then
                self.index = self.index % #self.rows + 1
            elseif input:wasPressed("left") or input:wasPressed("right") then
                self.rows[self.index].toggle()
            elseif input:wasPressed("a") then
                self.game.stack:push(mod.ui.TextBox.new(
                    self.game, self.rows[self.index].description))
            elseif input:wasPressed("b") then
                self.game.stack:pop()
            end
            self.scroll = Rows.clampScroll(
                self.index, self.scroll, #self.rows, nil)
        end

        function screen:draw()
            Rows.draw(self.game, self.rows, self.index, self.scroll,
                            "A:INFO B:EXIT")
        end

        return screen
    end

    mod.content.screens:register(SCREEN_ID, { new = makeScreen })
end

return M
