local SpriteService = {}
SpriteService.__index = SpriteService

function SpriteService.new(locator)
    local self = setmetatable({}, SpriteService)
    self._locator = locator
    self._cache = setmetatable({}, { __mode = "v" })
    return self
end

function SpriteService:getSprite(speciesId, pokemonData)
    if self._cache[speciesId] ~= nil then
        return self._cache[speciesId]
    end
    local def = pokemonData and pokemonData[speciesId]
    local rel = def and def.spriteFront
    local img = nil
    if rel then
        local ok, i = pcall(love.graphics.newImage, rel)
        if ok then img = i end
    end
    self._cache[speciesId] = img
    return img
end

return SpriteService
