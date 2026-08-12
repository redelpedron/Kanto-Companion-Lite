--- SettingsScreen: the "KANTO COMPANION LITE" pause-menu row now opens
-- this submenu instead of toggling ON/OFF directly (see AppController's
-- _wrapHooks). Each row here is its own persisted ON/OFF setting, toggled
-- with left/right, with A opening a one-line info TextBox -- the same
-- interaction pattern the quality_of_life mod's qol_options.lua uses for
-- its own "QUALITY OF LIFE" submenu.
local SCREEN_ID = "KantoCompanionLiteSettings"

local M = {}
M.SCREEN_ID = SCREEN_ID

function M.install(mod, saveSvc, locator)
    -- Each row only needs a label, a way to read/flip its own persisted
    -- value, and the info text A shows. Unlike qol_options.lua's generic
    -- "choice" schema (used there because some of its rows have more than
    -- two states, e.g. ON (BLACK)/ON (BLUE)), every setting here is a
    -- plain ON/OFF, so a small fixed row list is simpler than building
    -- out that same generic machinery for two booleans.
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
    }

    local function makeScreen(game)
        local gameService = locator:resolve("GameService")
        local OptionRows = gameService:getOptionRows()

        local screen = {
            game = game,
            rows = rows,
            index = 1,
            scroll = 0,
            isOpaque = true,
            kclSettingsScreen = true,
        }

        function screen:sgbPalettes(g)
            return gameService:getPaletteFX().wholeNamed(g.data, "MEWMON")
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
            self.scroll = OptionRows.clampScroll(
                self.index, self.scroll, #self.rows, nil)
        end

        function screen:draw()
            OptionRows.draw(self.game, self.rows, self.index, self.scroll,
                            "A:INFO B:EXIT")
        end

        return screen
    end

    mod.content.screens:register(SCREEN_ID, { new = makeScreen })
end

return M
