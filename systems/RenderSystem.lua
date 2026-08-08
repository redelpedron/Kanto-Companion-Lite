local System = require("core.System")
local Colors = require("util.Colors")

local RenderSystem = setmetatable({}, { __index = System })
RenderSystem.__index = RenderSystem

function RenderSystem.new(locator)
    local self = setmetatable(System.new(locator), RenderSystem)
    self.components = {}
    self._drawErr = nil
    return self
end

function RenderSystem:registerComponent(comp)
    table.insert(self.components, comp)
end

function RenderSystem:unregisterComponent(comp)
    for i, c in ipairs(self.components) do
        if c == comp then
            table.remove(self.components, i)
            return
        end
    end
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
    if not ok and err ~= self._drawErr then
        self._drawErr = err
        if log then log:error("RenderSystem: %s", tostring(err)) end
    end
end

return RenderSystem