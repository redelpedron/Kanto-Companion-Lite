local SCREEN_ID = "KantoCompanionLiteSettings"

local M = {}
M.SCREEN_ID = SCREEN_ID

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
