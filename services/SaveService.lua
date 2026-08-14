local SaveService = {}
SaveService.__index = SaveService

function SaveService.new(locator)
    local self = setmetatable({}, SaveService)
    self._locator = locator
    self._modSave = nil
    self._visible = true
    self._topBarBottom = false
    self._showFps = true
    return self
end

function SaveService:setModSave(modSave)
    self._modSave = modSave
    self:syncVisibility()
    self:syncTopBarBottom()
    self:syncShowFps()
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

function SaveService:syncTopBarBottom()
    local ok, v = pcall(function()
        return self._modSave:get("topBarBottom", false)
    end)
    self._topBarBottom = ok and (v == true)
    local bus = self._locator:resolve("EventBus")
    bus:publish("topbar.bottom.changed", self._topBarBottom)
end

function SaveService:isTopBarBottom()
    return self._topBarBottom
end

function SaveService:setTopBarBottom(val)
    local ok, err = pcall(function()
        self._modSave:set("topBarBottom", val)
    end)
    if ok then
        self:syncTopBarBottom()
    else
        local log = self._locator:resolve("LogService")
        if log then log:error("SaveService:setTopBarBottom: %s", tostring(err)) end
    end
end

function SaveService:toggleTopBarBottom()
    self:setTopBarBottom(not self._topBarBottom)
end

function SaveService:syncShowFps()
    local ok, v = pcall(function()
        return self._modSave:get("showFps", true)
    end)
    self._showFps = ok and (v ~= false)
    local bus = self._locator:resolve("EventBus")
    bus:publish("fps.visibility.changed", self._showFps)
end

function SaveService:isFpsVisible()
    return self._showFps
end

function SaveService:setFpsVisible(val)
    local ok, err = pcall(function()
        self._modSave:set("showFps", val)
    end)
    if ok then
        self:syncShowFps()
    else
        local log = self._locator:resolve("LogService")
        if log then log:error("SaveService:setFpsVisible: %s", tostring(err)) end
    end
end

function SaveService:toggleFpsVisible()
    self:setFpsVisible(not self._showFps)
end

return SaveService
