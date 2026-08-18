local PCService = {}
PCService.__index = PCService

local PC_ITEM_CAP = 50

function PCService.new(locator)
    local self = setmetatable({}, PCService)
    self._locator = locator
    self._gameService = nil

    self._modalState = nil
    return self
end

function PCService:_getGameService()
    if not self._gameService then
        self._gameService = self._locator:resolve("GameService")
    end
    return self._gameService
end

function PCService:getSave()
    return self:_getGameService():getSave()
end

function PCService:_boxes()
    return self:_getGameService():getBoxesModule()
end

function PCService:_party()
    return self:_getGameService():getPartyModule()
end

function PCService:_bag()
    return self:_getGameService():getBagModule()
end

function PCService:getItems()
    local save = self:getSave()
    return (save and save.pcItems) or {}
end

function PCService:getItemCount(itemId)
    local items = self:getItems()
    return items[itemId] or 0
end

function PCService:getBagItems()
    return self:_getGameService():getInventory()
end

function PCService:bagCapacity()
    local bag = self:_bag()
    return (bag and bag.CAPACITY) or 20
end

function PCService:pcItemCapacity()
    return PC_ITEM_CAP
end

function PCService:bagSlotCount()
    local bag = self:_bag()
    local save = self:getSave()

    if bag and bag.slots and save then
        local ok, n = pcall(bag.slots, save)
        if ok and type(n) == "number" then return n end
    end

    local n = 0
    for _, q in pairs(self:getBagItems()) do
        if type(q) == "number" and q > 0 then n = n + 1 end
    end
    return n
end

function PCService:pcSlotCount()
    local n = 0
    for _, q in pairs(self:getItems()) do
        if type(q) == "number" and q > 0 then n = n + 1 end
    end
    return n
end

function PCService:transferItem(fromSide, itemId, toSide)
    if fromSide == toSide then return true end
    local save = self:getSave()
    if not save then return false, "No save loaded" end
    local bag = self:_bag()

    if fromSide == "bag" then
        local inv = save.inventory or {}
        local qty = inv[itemId] or 0
        if qty <= 0 then return false, "Nothing to move" end

        local pc = save.pcItems or {}
        save.pcItems = pc
        if not pc[itemId] and self:pcSlotCount() >= PC_ITEM_CAP then
            return false, "PC is full"
        end

        if bag and bag.remove then
            local ok = bag.remove(save, itemId, qty)
            if ok == false then return false, "Couldn't remove from Bag" end
        else
            inv[itemId] = nil
        end
        pc[itemId] = (pc[itemId] or 0) + qty
        return true
    else
        local pc = save.pcItems or {}
        local qty = pc[itemId] or 0
        if qty <= 0 then return false, "Nothing to move" end

        local inv = save.inventory or {}
        save.inventory = inv

        if (inv[itemId] or 0) + qty > 99 then
            return false, "Stack maxed (99)"
        end

        if bag and bag.add then
            local ok = bag.add(save, itemId, qty)
            if not ok then return false, "Bag can't hold more" end
        else

            if not inv[itemId] and self:bagSlotCount() >= self:bagCapacity() then
                return false, "Bag is full"
            end
            inv[itemId] = (inv[itemId] or 0) + qty
        end

        pc[itemId] = pc[itemId] - qty
        if pc[itemId] <= 0 then pc[itemId] = nil end
        return true
    end
end

function PCService:getBoxCount()
    local b = self:_boxes()
    return (b and b.COUNT) or 12
end

function PCService:getBoxCapacity()
    local b = self:_boxes()
    return (b and b.CAPACITY) or 20
end

function PCService:getPartyMax()
    local p = self:_party()
    return (p and p.MAX) or 6
end

function PCService:getCurrentBox()
    local save = self:getSave()
    return (save and save.currentBox) or 1
end

function PCService:getBoxes()
    local save = self:getSave()
    local b = self:_boxes()
    if b and b.ensure and save then
        pcall(b.ensure, save)
    end
    return (save and save.boxes) or {}
end

function PCService:getBoxPokemon(boxNumber)
    local boxes = self:getBoxes()
    return boxes[boxNumber] or {}
end

function PCService:getParty()
    return self:_getGameService():getParty()
end

function PCService:_arrayOf(loc, boxN)
    if loc == "party" then return self:getParty() end
    return self:getBoxes()[boxN] or {}
end

local function isHealthyMon(m)
    if not m then return false end
    local hp = m.hp
    return hp == nil or hp > 0
end

function PCService:_partyHealthyCount()
    local n = 0
    for _, m in ipairs(self:getParty()) do
        if isHealthyMon(m) then n = n + 1 end
    end
    return n
end

function PCService:placeBlockedReason(src, tgt)
    if not (src and tgt) then return nil end
    local sMon = self:_arrayOf(src.loc, src.box)[src.index]
    local tMon = tgt.index and self:_arrayOf(tgt.loc, tgt.box)[tgt.index] or nil
    local isSwap = tMon ~= nil and tMon ~= sMon

    if not isSwap then
        if src.loc == "party" and tgt.loc ~= "party" and #self:getParty() <= 1 then
            return "Can't deposit your last Pokemon"
        end
        if tgt.loc == "party" and #self:getParty() >= self:getPartyMax() then
            return "Party is full"
        end
        if tgt.loc == "box" and #self:_arrayOf("box", tgt.box) >= self:getBoxCapacity() then
            return ("Box %d is full"):format(tgt.box)
        end
    end

    local cur = self:_partyHealthyCount()
    local res = cur
    if src.loc == "party" and tgt.loc ~= "party" then
        if isHealthyMon(sMon) then res = res - 1 end
        if isSwap and isHealthyMon(tMon) then res = res + 1 end
    elseif src.loc ~= "party" and tgt.loc == "party" and isSwap then
        if isHealthyMon(tMon) then res = res - 1 end
        if isHealthyMon(sMon) then res = res + 1 end
    end
    if cur >= 1 and res < 1 then return "Keep a healthy Pokemon in your party" end
    return nil
end

function PCService:moveMon(src, tgt)
    if not tgt then return true end
    local sArr = self:_arrayOf(src.loc, src.box)
    local sMon = sArr[src.index]
    if not sMon then return false, "Nothing to move" end
    if src.loc == tgt.loc and src.box == tgt.box and src.index == tgt.index then
        return true
    end

    local blocked = self:placeBlockedReason(src, tgt)
    if blocked then return false, blocked end

    local tArr = self:_arrayOf(tgt.loc, tgt.box)
    local tMon = tgt.index and tArr[tgt.index]
    if tMon and tMon ~= sMon then
        sArr[src.index], tArr[tgt.index] = tMon, sMon
        return true
    end

    table.remove(sArr, src.index)
    local at = tgt.index
    if src.loc == tgt.loc and src.box == tgt.box and at and at > src.index then
        at = at - 1
    end
    if at and at >= 1 and at <= #tArr + 1 then
        table.insert(tArr, at, sMon)
    else
        tArr[#tArr + 1] = sMon
    end
    return true
end

function PCService:canOpen()
    local game = self:_getGameService()
    local save = game:getSave()
    if not (save and save.party and #save.party > 0) then return false end

    if not game:isInGame() then return false end
    if game:isMenuOpen() then return false end
    local battle = self._locator:has("BattleService") and self._locator:resolve("BattleService")
    if battle and battle:isInBattle() then return false end
    return true
end

function PCService:openModal()
    local stack = self:_getGameService():getStack()
    if not (stack and stack.push) then return end
    if not self._modalState then
        self._modalState = {
            isOpaque = false,
            screenId = "VoxelPCScreen",
            onKeyPressed = function() end,
            update = function() end,
            draw = function() end,
        }
    end
    pcall(function() stack:push(self._modalState) end)
end

function PCService:closeModal()
    local stack = self:_getGameService():getStack()
    if not (stack and self._modalState) then return end
    local ok, top = pcall(function() return stack.top and stack:top() end)
    if ok and top == self._modalState and stack.pop then
        pcall(function() stack:pop() end)
    end
end

return PCService
