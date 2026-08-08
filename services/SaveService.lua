
--- SaveService: wraps mod.save with safe pcall access and event publishing.
local SaveService = {}
SaveService.__index = SaveService

function SaveService.new(locator)
    local self = setmetatable({}, SaveService)
    self._locator = locator
    self._modSave = nil
    self._visible = true
    return self
end

function SaveService:setModSave(modSave)
    self._modSave = modSave
    self:syncVisibility()
end

function SaveService:syncVisibility()
    local ok, v = pcall(function()
        return self._modSave:get("visible", true)
    end)
    self._visible = ok and (v ~= false)
    local bus = self._locator:resolve("EventBus")
    bus:publish("hud.visibility.changed", self._visible)
end

function SaveService:isVisible()
    return self._visible
end

function SaveService:setVisible(val)
    local ok, err = pcall(function()
        self._modSave:set("visible", val)
    end)
    if ok then
        self:syncVisibility()
    else
        local log = self._locator:resolve("LogService")
        if log then log:error("SaveService:setVisible: %s", tostring(err)) end
    end
end

function SaveService:toggleVisible()
    self:setVisible(not self._visible)
end

return SaveService
