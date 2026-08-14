local FontService = {}
FontService.__index = FontService

function FontService.new(locator)
    local self = setmetatable({}, FontService)
    self._locator = locator
    self._cache = {}
    return self
end

function FontService:getFont(px)
    px = math.max(8, math.floor(px))
    if not self._cache[px] then
        self._cache[px] = love.graphics.newFont(px)
    end
    return self._cache[px]
end

return FontService
