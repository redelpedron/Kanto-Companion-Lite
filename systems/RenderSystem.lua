local RenderSystem = {}
RenderSystem.__index = RenderSystem

function RenderSystem.new(locator)
    local self = setmetatable({}, RenderSystem)
    self._locator = locator
    self.components = {}
    self._drawErr = nil
    self._drawErrCount = 0
    self._drawErrTime = 0
    return self
end

function RenderSystem:registerComponent(comp)
    table.insert(self.components, comp)
end

function RenderSystem:draw()
    if not (love and love.graphics) then return end
    local log = self._locator:has("LogService") and self._locator:resolve("LogService") or nil
    love.graphics.push("all")
    local ok, err = pcall(function()
        love.graphics.origin()
        for _, comp in ipairs(self.components) do
            if comp:isActive() and comp.draw then
                local ctx = comp._props or {}
                comp:draw(ctx)
            end
        end
    end)
    love.graphics.pop()
    
    if not ok then
        local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
        if err == self._drawErr then
            self._drawErrCount = self._drawErrCount + 1
            -- Log every 60 occurrences or every 5 seconds to catch persistent errors
            if self._drawErrCount % 60 == 0 or (now - self._drawErrTime) > 5 then
                if log then log:error("RenderSystem: %s (occurred %d times)", tostring(err), self._drawErrCount) end
                self._drawErrTime = now
            end
        else
            -- New error string: log immediately and reset counter
            self._drawErr = err
            self._drawErrCount = 1
            self._drawErrTime = now
            if log then log:error("RenderSystem: %s", tostring(err)) end
        end
    else
        -- No error: reset state
        self._drawErr = nil
        self._drawErrCount = 0
        self._drawErrTime = 0
    end
end

return RenderSystem