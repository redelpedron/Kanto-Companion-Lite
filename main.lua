return function(mod)
  -- =====================================================================
  -- Kanto In-Game Companion -- draws the same panels as the streaming mod
  -- (Kanto Stream Companion) but INSIDE the game with love.graphics, on top
  -- of the widescreen view. No server / threads / browser: it reads game.save
  -- each frame and draws. Toggle with the on-screen button. READ-ONLY.
  --
  -- State lives on a global so F5 hot-reload re-runs this file without
  -- re-wrapping love.draw / game.update / game.keypressed.
  -- =====================================================================

  local REF_H      = 1440        -- design reference height; everything scales off this
  local INTERVAL   = 0.12        -- seconds between save reads

  local C = _G.__KANTO_INGAME or {}
  _G.__KANTO_INGAME = C
  if C.visible == nil then C.visible = false end   -- off by default; tap the toggle button to show
  if C.partyStyle == nil then C.partyStyle = 1 end   -- 1 = full, 2 = compact (F7)
  C.fonts   = C.fonts or {}
  C.sprites = C.sprites or {}
  C.dispHP  = C.dispHP or {}      -- animated HP values keyed by "p1".."p6"/"enemy"
  C.dispSp  = C.dispSp or {}      -- species behind each animated value (reset on change)

  -- engine modules (same sources the streaming mod uses)
  local function req(p) local ok, m = pcall(require, p); return ok and m or nil end
  C.game     = C.game or req("src.core.Game")
  C.TypeChart = C.TypeChart or req("src.battle.TypeChart")
  C.Catching = C.Catching or req("src.battle.Catching")
  C.Growth   = C.Growth or req("src.pokemon.Growth")
  C.Badges   = C.Badges or req("src.inventory.Badges")
  C.BattleState = C.BattleState or req("src.battle.BattleState")
  C.Boxes    = C.Boxes or req("src.pokemon.Boxes")
  C.Party    = C.Party or req("src.pokemon.Party")
  C.Bag      = C.Bag or req("src.inventory.Bag")
  C.Stats    = C.Stats or req("src.pokemon.Stats")
  mod.events:on("game.ready", function(p) C.game = (p and p.game) or C.game end)

  -- ---------------------------------------------------------------------
  -- Palette (0..1)
  -- ---------------------------------------------------------------------
  local function hex(s)
    return { tonumber(s:sub(1,2),16)/255, tonumber(s:sub(3,4),16)/255, tonumber(s:sub(5,6),16)/255 }
  end
  local COL = {
    panel = hex("10121a"), border = hex("ffffff"),
    text = hex("ffffff"), dim = hex("b9bdc9"),
    hi = hex("7dd87d"), mid = hex("e6d24a"), lo = hex("e05a5a"),
    xp = hex("5ab0ff"), gold = hex("ffd54a"), money = hex("ffe27a"),
    barbg = hex("ffffff"), threat = hex("ffb38a"),
    super = hex("7dd87d"), resist = hex("e0906a"),
  }
  local TYPE = {
    NORMAL=hex("9a9a80"), FIRE=hex("e0632c"), WATER=hex("3a86e8"), ELECTRIC=hex("e0b330"),
    GRASS=hex("5fb04a"), ICE=hex("5fc7c7"), FIGHTING=hex("b23a2e"), POISON=hex("8a3a9a"),
    GROUND=hex("c8a84a"), FLYING=hex("7a8fe0"), PSYCHIC=hex("e0508a"), BUG=hex("8a9a20"),
    ROCK=hex("a89440"), GHOST=hex("5a4a8a"), DRAGON=hex("5a4ae0"),
  }

  -- ---------------------------------------------------------------------
  -- Cheap caches: scaled fonts + species sprites
  -- ---------------------------------------------------------------------
  local function getFont(sizePx)
    sizePx = math.max(8, math.floor(sizePx))
    local f = C.fonts[sizePx]
    if not f then f = love.graphics.newFont(sizePx); C.fonts[sizePx] = f end
    return f
  end
  local function getSprite(speciesId, dPoke)
    if C.sprites[speciesId] ~= nil then return C.sprites[speciesId] or nil end
    local def = dPoke[speciesId]
    local rel = def and def.spriteFront
    local img = false
    if rel then local ok, i = pcall(love.graphics.newImage, rel); if ok then img = i end end
    C.sprites[speciesId] = img
    return img or nil
  end

  -- Gym-badge spritesheet (16px wide; each gym badge tile is at (0, i*32+16),
  -- in the same gym order as Badges.list). Cached; nearest-filtered for crisp
  -- pixels when scaled up.
  local function badgeSheet()
    if C.badgeSheet == nil then
      local ok, img = pcall(love.graphics.newImage, "assets/generated/trainer_card/badges.png")
      if ok and img then
        img:setFilter("nearest", "nearest")
        local iw, ih = img:getDimensions()
        local q = {}
        for i = 0, 7 do q[i] = love.graphics.newQuad(0, i * 32 + 16, 16, 16, iw, ih) end
        C.badgeSheet = { img = img, quads = q }
      else
        C.badgeSheet = false
      end
    end
    return C.badgeSheet or nil
  end

  -- Item classification for the Items panel (Gen 1 has no bag pockets, so we
  -- sort by id ourselves). Balls = anything with BALL; Healing = HP/PP/status.
  local HEAL_IDS = {
    POTION=true, SUPER_POTION=true, HYPER_POTION=true, MAX_POTION=true, FULL_RESTORE=true,
    FULL_HEAL=true, ANTIDOTE=true, BURN_HEAL=true, ICE_HEAL=true, AWAKENING=true, PARLYZ_HEAL=true,
    REVIVE=true, MAX_REVIVE=true, ETHER=true, MAX_ETHER=true, ELIXER=true, MAX_ELIXER=true,
    FRESH_WATER=true, SODA_POP=true, LEMONADE=true,
  }
  local function isBallItem(id) return id:find("BALL", 1, true) ~= nil end
  local function isHealItem(id)
    return HEAL_IDS[id]
      or id:find("POTION", 1, true) or id:find("HEAL", 1, true) or id:find("REVIVE", 1, true)
      or id:find("RESTORE", 1, true) or id:find("ETHER", 1, true) or id:find("ELIXER", 1, true)
  end

  -- ---------------------------------------------------------------------
  -- STATE: read game.save into a small table we can draw (ported/trimmed
  -- from the streaming snapshot; no JSON, keeps species ids for sprites).
  -- ---------------------------------------------------------------------
  local function currentBattle()
    local g = C.game; local stk = g and g.stack
    if not (stk and stk.states and C.BattleState) then return nil end
    for i = #stk.states, 1, -1 do
      if getmetatable(stk.states[i]) == C.BattleState then return stk.states[i] end
    end
    return nil
  end

  -- Detects the game's own full-screen list-menu widget (Start menu, and
  -- likely Bag/Pokédex/PC box lists too, since they all appear to share this
  -- same shape) so the overlay can get out of its way instead of overlapping
  -- it. No class name/metatable available for this one (see kanto_ingame
  -- debug notes), so this matches on its distinctive field signature instead.
  local function menuOpen()
    local g = C.game; local stk = g and g.stack
    if not (stk and stk.states and #stk.states > 0) then return false end
    local top = stk.states[#stk.states]
    return type(top) == "table" and top.items ~= nil and top.index ~= nil and top.screenId ~= nil
  end

  local function buildState()
    local game = C.game
    local save = game and game.save
    if not save then return nil end
    local data  = game.data or {}
    local dPoke = data.pokemon or {}
    local dMove = data.moves or {}
    local dItem = data.items or {}
    C.dPoke = dPoke

    local function dispTypes(raw)
      local o = {}
      for _, t in ipairs(raw or {}) do o[#o+1] = (C.TypeChart and C.TypeChart.displayName(t)) or t end
      return o
    end
    local function brief(mon)
      if not mon then return nil end
      local d = dPoke[mon.species]
      return {
        name = mon.nickname or (d and d.name) or tostring(mon.species),
        species = mon.species, level = mon.level, hp = mon.hp,
        maxhp = mon.stats and mon.stats.hp, status = mon.status or "OK",
        types = dispTypes(d and d.types),
      }
    end

    local battle = currentBattle()
    local activeMon = battle and battle.player and battle.player.mon or nil
    local teamTypes = {}

    -- enemy types, computed early so bench mons' moves can also be checked
    -- for effectiveness against the current opponent (not just the active mon)
    local enemyMon = battle and battle.enemy and battle.enemy.mon or nil
    local enemyTypes = (enemyMon and dPoke[enemyMon.species] and dPoke[enemyMon.species].types) or {}
    if battle and enemyMon and C.TypeChart and not C.tcReady then
      C.tcReady = pcall(C.TypeChart.load, data)
    end

    -- party
    local party = {}
    for i, mon in ipairs(save.party or {}) do
      local def = dPoke[mon.species]
      local moves = {}
      for _, mv in ipairs(mon.moves or {}) do
        local md = dMove[mv.id]
        local moveOut = { name = (md and md.name) or mv.id, pp = mv.pp, maxpp = md and md.pp }
        if battle and enemyMon and md and C.TypeChart and C.tcReady
          and md.category ~= "status" and (md.power or 0) > 0 then
          local ok, mult = pcall(C.TypeChart.effectiveness, md.type, enemyTypes)
          if ok then moveOut.mult = mult end
        end
        moves[#moves+1] = moveOut
      end
      local raw = (def and def.types) or {}
      if #raw > 0 then teamTypes[#teamTypes+1] = raw end
      local xpProg, xpNext
      if C.Growth and def and def.growthRate and mon.exp and mon.level then
        local rates = data.growth_rates
        local cur = C.Growth.expForLevel(def.growthRate, mon.level, rates)
        local nxt = C.Growth.expForLevel(def.growthRate, mon.level + 1, rates)
        if mon.level >= 100 or nxt <= cur then xpProg, xpNext = 1, 0
        else xpProg = math.max(0, math.min(1, (mon.exp - cur)/(nxt - cur))); xpNext = math.max(0, nxt - mon.exp) end
      end
      party[i] = {
        slot = i, name = mon.nickname or (def and def.name) or tostring(mon.species),
        species = mon.species, level = mon.level, hp = mon.hp,
        maxhp = mon.stats and mon.stats.hp, status = mon.status or "OK",
        types = dispTypes(raw), moves = moves, exp = mon.exp,
        xpProgress = xpProg, xpToNext = xpNext,
        active = (activeMon ~= nil and mon == activeMon) or nil,
      }
    end

    -- trainer
    local badges, badgeCount = {}, 0
    if C.Badges and data then
      for i, e in ipairs(C.Badges.list(data)) do
        local owned = save.inventory[C.Badges.itemFor(e)] and true or false
        if owned then badgeCount = badgeCount + 1 end
        local id = e.id or ("BADGE"..i); local base = id:gsub("BADGE$", "")
        badges[i] = { name = e.name or (base:sub(1,1)..base:sub(2):lower()), owned = owned }
      end
    end
    local dex = save.pokedex or {}
    local function countTrue(t) local n=0; if t then for _,v in pairs(t) do if v then n=n+1 end end end; return n end
    local dexTotal = 0
    for _, d in pairs(dPoke) do if d.dex and d.dex > dexTotal then dexTotal = d.dex end end
    local trainer = {
      name = (save.player and save.player.name) or "", money = save.money or 0,
      version = save.version or "", playTime = math.floor(save.playTime or 0),
      badges = badges, badgeCount = badgeCount, dexSeen = countTrue(dex.seen),
      dexOwned = countTrue(dex.owned), dexTotal = dexTotal > 0 and dexTotal or nil,
      partyCount = #(save.party or {}),
    }

    -- route (grass + surf)
    local BK = (data.constants and data.constants.encounterBuckets)
      or { 51,102,141,166,191,216,229,242,253,256 }
    local function encTable(part)
      if not part or not part.slots or (part.rate or 0) == 0 then return nil end
      local bk = part.buckets or BK
      local agg, order, prev = {}, {}, 0
      for i, slot in ipairs(part.slots) do
        local top = bk[i] or 256; local w = top - prev; prev = top
        if slot and slot.species then
          local a = agg[slot.species]
          if not a then a = { species = slot.species, weight = 0, minL = slot.level, maxL = slot.level }; agg[slot.species]=a; order[#order+1]=a end
          a.weight = a.weight + w; a.minL = math.min(a.minL, slot.level); a.maxL = math.max(a.maxL, slot.level)
        end
      end
      local list = {}
      for _, a in ipairs(order) do
        local d = dPoke[a.species]
        list[#list+1] = { name = (d and d.name) or tostring(a.species), species = a.species,
          pct = math.floor(a.weight/256*100 + 0.5), minLevel = a.minL, maxLevel = a.maxL }
      end
      table.sort(list, function(x,y) return x.pct > y.pct end)
      return { rate = math.floor((part.rate or 0)/256*100 + 0.5), species = list }
    end
    local route
    local ov = game.overworld
    local mapId = ov and ov.map and ov.map.id
    if mapId then
      route = { name = (mapId:lower():gsub("_"," "):gsub("(%a)(%w*)", function(a,b) return a:upper()..b end)) }
      local enc = (data.encounters or {})[mapId]
      if enc then route.grass = encTable(enc.grass); route.water = encTable(enc.water) end
    end

    -- battle + matchup + catch
    local battleBlock
    if battle then
      local pMon, eMon = battle.player and battle.player.mon, battle.enemy and battle.enemy.mon
      local myTypes = (pMon and dPoke[pMon.species] and dPoke[pMon.species].types) or {}
      local enTypes = (eMon and dPoke[eMon.species] and dPoke[eMon.species].types) or {}
      local matchup
      if C.TypeChart and pMon and eMon then
        if not C.tcReady then C.tcReady = pcall(C.TypeChart.load, data) end
        local ok, res = pcall(function()
          local eff, disp, cat = C.TypeChart.effectiveness, C.TypeChart.displayName, C.TypeChart.category
          local function has(l,t) for _,x in ipairs(l) do if x==t then return true end end return false end
          local myMoves, bi, bs = {}, nil, -1
          for _, mv in ipairs(pMon.moves or {}) do
            local md = dMove[mv.id]
            if md then
              local pow = md.power or 0
              local st = (md.category == "status") or pow == 0
              local mult = eff(md.type, enTypes); local stab = has(myTypes, md.type)
              myMoves[#myMoves+1] = { name = md.name or mv.id, type = disp(md.type),
                power = pow > 0 and pow or nil, pp = mv.pp, maxpp = md.pp,
                mult = mult, stab = stab or nil, status = st or nil }
              if not st and mult > 0 then local sc = mult*pow*(stab and 15 or 10); if sc > bs then bs=sc; bi=#myMoves end end
            end
          end
          if bi then myMoves[bi].best = true end
          local threats = {}
          for _, mv in ipairs(eMon.moves or {}) do
            local md = dMove[mv.id]
            if md and md.category ~= "status" and (md.power or 0) > 0 then
              local mult = eff(md.type, myTypes)
              if mult > 10 then threats[#threats+1] = { name = md.name or mv.id, type = disp(md.type), mult = mult } end
            end
          end
          table.sort(threats, function(a,b) return a.mult > b.mult end)
          local mS, eS = pMon.stats and pMon.stats.speed, eMon.stats and eMon.stats.speed
          local faster; if mS and eS then faster = (mS>eS) and "you" or ((eS>mS) and "them" or "tie") end
          return { speed = { faster = faster }, myMoves = myMoves, threats = threats }
        end)
        if ok then matchup = res end
      end
      -- catch odds (wild)
      local catch
      if battle.kind == "wild" and eMon then
        local okc, res = pcall(function()
          local eDef = dPoke[eMon.species]; local rate = eDef and eDef.catchRate
          local maxhp = eMon.stats and eMon.stats.hp; local hp = eMon.hp
          if not (rate and maxhp and hp) then return nil end
          local s = eMon.status
          local sb = (s=="SLP" or s=="FRZ") and 25 or (s and 12 or 0)
          local bd = data.balls
          local function def(id) return (bd and bd[id]) or (C.Catching and C.Catching.BALLS and C.Catching.BALLS[id]) end
          local function odds(d)
            if not d then return nil end
            if d.autoCatch then return 100 end
            local rm, hf = d.randMax, d.hpFactor; if not (rm and hf) then return nil end
            local N = rm + 1; local hq = math.max(1, math.floor(hp/4))
            local f = math.min(255, math.floor(math.floor(maxhp*255/hf)/hq))
            local p1 = sb/N; local hi = math.min(rm, rate+sb)
            local pp = math.max(0, hi-sb+1)/N; return (p1 + pp*(f+1)/256)*100
          end
          local list = {}
          for _, id in ipairs({ "POKE_BALL","GREAT_BALL","ULTRA_BALL","SAFARI_BALL","MASTER_BALL" }) do
            local qty = (save.inventory and save.inventory[id]) or 0; local d = def(id)
            if d and qty > 0 then local it = dItem[id]; list[#list+1] = { name = (it and it.name) or id, pct = odds(d), qty = qty } end
          end
          if #list == 0 then local d = def("POKE_BALL"); if d then local it = dItem["POKE_BALL"]; list[1] = { name = (it and it.name) or "POKE_BALL", pct = odds(d), qty = 0 } end end
          return (#list > 0) and list or nil
        end)
        if okc then catch = res end
      end
      battleBlock = { kind = battle.kind, trainer = battle.trainer and battle.trainer.name or nil,
        enemy = brief(eMon), active = brief(pMon), matchup = matchup, catch = catch }
    end

    -- Items: Balls + Healing (for the right-column items panel), in bag order.
    local balls, heals, seen = {}, {}, {}
    local function addItem(id)
      local qty = save.inventory[id]; if not qty or qty <= 0 then return end
      local nm = (dItem[id] and dItem[id].name) or id
      if isBallItem(id) then balls[#balls + 1] = { name = nm, qty = qty }
      elseif isHealItem(id) then heals[#heals + 1] = { name = nm, qty = qty } end
    end
    local ord = save.bagOrder
    if ord then for _, id in ipairs(ord) do if save.inventory[id] and not seen[id] then seen[id] = true; addItem(id) end end end
    for id in pairs(save.inventory or {}) do if not seen[id] then seen[id] = true; addItem(id) end end

    return { active = true, party = party, trainer = trainer, route = route,
      battle = battleBlock, items = { balls = balls, heals = heals } }
  end

  -- ---------------------------------------------------------------------
  -- Per-frame: throttled save read + HP animation easing
  -- ---------------------------------------------------------------------
  local function easeHP(key, target, dt)
    local cur = C.dispHP[key]
    if cur == nil then cur = target end
    cur = cur + (target - cur) * math.min(1, (dt or 0) * 7)
    if math.abs(cur - target) < 0.5 then cur = target end
    C.dispHP[key] = cur
    return cur
  end

  C.onFrame = function(dt)
    C.acc = (C.acc or 0) + (dt or 0)
    if not C.state or C.acc >= INTERVAL then
      C.acc = 0
      local ok, st = pcall(buildState)
      if ok then C.state = st
      elseif st ~= C.buildErr then C.buildErr = st; mod.log:error("kanto_ingame build: %s", tostring(st)) end
    end
    -- advance HP eases toward the freshest values every frame
    local st = C.state
    if st then
      for i = 1, 6 do
        local m = st.party and st.party[i]
        local key = "p" .. i
        if m then
          if C.dispSp[key] ~= m.species then C.dispSp[key] = m.species; C.dispHP[key] = m.hp end
          easeHP(key, m.hp or 0, dt or 0)
        else C.dispHP[key] = nil; C.dispSp[key] = nil end
      end
      local en = st.battle and st.battle.enemy
      if en then
        if C.dispSp.enemy ~= en.species then C.dispSp.enemy = en.species; C.dispHP.enemy = en.hp end
        easeHP("enemy", en.hp or 0, dt or 0)
      else C.dispHP.enemy = nil; C.dispSp.enemy = nil end
    end
  end

  -- ---------------------------------------------------------------------
  -- Draw helpers (all inputs in DESIGN units; multiplied by C.s)
  -- ---------------------------------------------------------------------
  local s = 1
  -- LÖVE's built-in Vera font lacks these glyphs (they'd draw a missing-glyph
  -- box), so swap them for safe equivalents before printing. ♀/♂ come straight
  -- from Nidoran's name; the rest are battle-panel decorations.
  local SUB = {
    ["\226\153\128"] = " (F)",  -- ♀ U+2640
    ["\226\153\130"] = " (M)",  -- ♂ U+2642
    ["\226\152\133"] = "*",    -- ★ U+2605 (STAB)
    ["\226\154\160"] = "!",    -- ⚠ U+26A0 (threat)
    ["\226\150\186"] = ">",    -- ► U+25BA (you first)
    ["\226\151\132"] = "<",    -- ◄ U+25C4 (enemy first)
    ["\226\151\134"] = "*",    -- ◆ U+25C6 (badge earned)
    ["\226\151\135"] = "·",    -- ◇ U+25C7 (badge not earned)
  }
  local function sanitize(str)
    if type(str) ~= "string" then str = tostring(str) end
    for k, v in pairs(SUB) do str = str:gsub(k, v) end
    return str
  end
  local function setc(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
  local function rrect(mode, x, y, w, h, r)
    love.graphics.rectangle(mode, math.floor(x*s), math.floor(y*s), math.floor(w*s), math.floor(h*s),
      (r or 0)*s, (r or 0)*s)
  end
  local function txt(str, x, y, size, col, align, a)
    str = sanitize(str)
    local f = getFont(size*s); love.graphics.setFont(f); setc(col or COL.text, a)
    local X = x*s
    if align == "right" then X = X - f:getWidth(str)
    elseif align == "center" then X = X - f:getWidth(str)/2 end
    love.graphics.print(str, math.floor(X), math.floor(y*s))
  end
  local function textW(str, size) return getFont(size*s):getWidth(str) / s end
  -- shrink a string with ".." until it fits maxW (design units)
  local function ellipsize(str, size, maxW)
    if textW(str, size) <= maxW then return str end
    local s2 = str
    while #s2 > 1 and textW(s2 .. "..", size) > maxW do s2 = s2:sub(1, #s2 - 1) end
    return s2 .. ".."
  end
  local function panel(x, y, w, h, activeGold)
    setc(COL.panel, 0.98); rrect("fill", x, y, w, h, 14)
    love.graphics.setLineWidth(math.max(1, s))
    if activeGold then setc(COL.gold, 0.9) else setc(COL.border, 0.12) end
    rrect("line", x, y, w, h, 14)
  end
  local function bar(x, y, w, h, frac, col)
    setc(COL.barbg, 0.15); rrect("fill", x, y, w, h, h/2)
    if frac and frac > 0 then setc(col, 1); rrect("fill", x, y, w*math.min(1,frac), h, h/2) end
  end
  local function hpCol(f) return f > 0.5 and COL.hi or (f > 0.2 and COL.mid or COL.lo) end
  local function chip(x, y, label, col, sz, ht)
    sz = sz or 11
    ht = ht or 17
    local f = getFont(sz * s)
    local textH = f:getHeight() / s
    txt(label, x, y + (ht - textH) / 2, sz, col)
    return f:getWidth(label) / s + 12
  end
  local function money(n) local s2 = tostring(math.floor(n or 0)); local o = s2:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,",""); return "¥"..o end
  local function fmtTime(sec) sec = sec or 0; return string.format("%d:%02d", math.floor(sec/3600), math.floor(sec/60)%60) end
  local function pct(p) if p == nil then return "—" end; if p >= 100 then return "100%" end; if p < 1 then return (p < 0.1 and "<0.1%") or (string.format("%.1f%%", p)) end; return math.floor(p+0.5).."%" end
  local EFFLBL = { [0]="×0", [2]="×¼", [5]="×½", [10]="×1", [20]="×2", [40]="×4" }
  local function effText(m) return EFFLBL[m] or ("×"..(m/10)) end

  -- ---------------------------------------------------------------------
  -- Panel renderers. Each returns the height it drew (design units).
  -- ---------------------------------------------------------------------
  local COLW = 468        -- side column width (design units)
  local PAD = 16

  -- Party rows are BOXLESS (thin dividers between mons). Two styles toggled
  -- with F7: 1 = full (types, HP, XP, moves), 2 = compact (no moves, tighter).
  local function dispName(nm)
    nm = nm or ""
    nm = nm:gsub("♀", " (F)")
    nm = nm:gsub("♂", " (M)")
    return nm
  end
  local function moveRows(m) return math.ceil(math.max(1, #(m.moves or {})) / 2) end
  local function measureMon(m, style)
    if style == 2 or style == 3 then
      local W, H = love.graphics.getDimensions()
      local isLandscape = (W / H) > 1.2
      -- headerH must match exactly what drawMonRow draws for name+HP-bar
      -- before anything else (moves, or the row just ending) -- it was
      -- overshooting by 11-12px on every row, which is most of the excess
      -- whitespace before the divider.
      local headerH = isLandscape and 54 or 43
      if style == 2 or m.active then
        -- no moves shown: just enough extra for the XP bar + a little cushion
        return headerH + (isLandscape and 12 or 10)
      end
      local gap, rh2, pad = (isLandscape and 26 or 18), (isLandscape and 24 or 20), 0
      return headerH + gap + moveRows(m) * rh2 + pad
    end
    local hasTypes = m.types and #m.types > 0
    local hasXP = m.xpProgress ~= nil
    local bodyH = 30 + (hasTypes and 22 or 0) + 36 + (hasXP and 32 or 0) + 6 + moveRows(m)*20
    return math.max(72, bodyH)
  end

  local function drawMonRow(m, x, y, w, key, style)
    local rowH = measureMon(m, style)
    local dispHp = C.dispHP[key] or m.hp or 0
    local frac = math.max(0, math.min(1, dispHp / (m.maxhp or 1)))
    local W2, H2 = love.graphics.getDimensions()
    local isLandscape = (W2 / H2) > 1.2
    local sp = (style == 2 or style == 3) and (isLandscape and 60 or 48) or 72
    local bodyX = sp + (isLandscape and 14 or 12)
    local bodyW = w - bodyX

    local img = getSprite(m.species, C.dPoke)
    if img then
      local iw, ih = img:getDimensions(); local sc = (sp / math.max(iw, ih)) * s
      setc(COL.text, dispHp <= 0 and 0.5 or 1)
      love.graphics.draw(img, math.floor(x*s), math.floor((y + (rowH-sp)/2)*s), 0, sc, sc)
    end
    if style == 2 or style == 3 then
      -- COMPACT: name + types + Lv on one line, HP bar w/ inline number, thin XP
      local nameSz, lvSz = (isLandscape and 22 or 19), (isLandscape and 16 or 14)
      local chipSz2, chipHt2 = (isLandscape and 16 or 14), (isLandscape and 28 or 22)
      local cy = y + (isLandscape and 4 or 3)
      txt(dispName(m.name), x + bodyX, cy, nameSz, COL.text)
      local tx = x + bodyX + textW(dispName(m.name), nameSz) + (isLandscape and 10 or 8)
      if m.types then for _, t in ipairs(m.types) do tx = tx + chip(tx, cy - (isLandscape and 2 or 1), t, TYPE[t] or COL.dim, chipSz2, chipHt2) end end
      if m.status and m.status ~= "OK" then tx = tx + chip(tx, cy - (isLandscape and 2 or 1), m.status, COL.lo, chipSz2, chipHt2) end
      txt("Lv " .. (m.level or "?"), x + w, cy + (isLandscape and 3 or 2), lvSz, COL.dim, "right")
      cy = cy + (isLandscape and 28 or 22)
      local numStr = string.format("%d/%d", math.floor(dispHp + 0.5), m.maxhp or 0)
      local numW = textW(numStr, lvSz) + (isLandscape and 10 or 8)
      bar(x + bodyX, cy + 2, bodyW - numW, (isLandscape and 12 or 10), frac, hpCol(frac))
      txt(numStr, x + w, cy + 1, lvSz, COL.text, "right", 0.9)
      cy = cy + (isLandscape and 22 or 18)
      if m.xpProgress ~= nil then bar(x + bodyX, cy, bodyW, (isLandscape and 8 or 6), m.xpProgress, COL.xp) end
      -- Bench-only moves/PP list (style 3): the active mon's moves are already
      -- visible in the battle panel, so skip repeating them here.
      if style == 3 and not m.active and m.moves and #m.moves > 0 then
        cy = cy + (isLandscape and 26 or 18)
        local colW2 = bodyW / 2
        local mf = isLandscape and 14 or 13
        local moveRowH = isLandscape and 24 or 20
        local ppGap = isLandscape and 20 or 18
        local ppRight = isLandscape and 10 or 8
        for i, mv in ipairs(m.moves) do
          local col = (i-1) % 2; local row = math.floor((i-1)/2)
          local mx = x + bodyX + col*colW2; local my = cy + row*moveRowH
          local pp = (mv.pp ~= nil and mv.maxpp ~= nil) and (mv.pp.."/"..mv.maxpp) or (mv.pp and tostring(mv.pp) or "")
          local ppW = textW(pp, mf)
          local nameCol = (mv.mult and mv.mult > 10) and COL.super or COL.text
          txt(ellipsize(mv.name, mf, colW2 - ppW - ppGap), mx, my, mf, nameCol, nil, 0.88)
          txt(pp, mx + colW2 - ppRight, my, mf, COL.dim, "right")
        end
      end
      return rowH
    end

    -- FULL
    local cy = y
    txt(dispName(m.name), x + bodyX, cy, 24, COL.text)
    txt("Lv " .. (m.level or "?"), x + w, cy + 4, 16, COL.dim, "right")
    local cx = x + bodyX + textW(dispName(m.name), 24) + 8
    if m.active then
      local ow = textW("OUT", 12)
      setc(COL.gold, 1); rrect("fill", cx, cy + 2, ow + 12, 18, 5)
      txt("OUT", cx + 6, cy + 3, 12, {0.1, 0.08, 0})
      cx = cx + ow + 20
    end
    if m.status and m.status ~= "OK" then chip(cx, cy + 2, m.status, COL.lo) end
    cy = cy + 30
    if m.types and #m.types > 0 then
      local tx = x + bodyX; for _, t in ipairs(m.types) do tx = tx + chip(tx, cy, t, TYPE[t] or COL.dim) end
      cy = cy + 22
    end
    bar(x + bodyX, cy, bodyW, 12, frac, hpCol(frac)); cy = cy + 16
    txt(string.format("%d / %d HP", math.floor(dispHp + 0.5), m.maxhp or 0), x + bodyX, cy, 16, COL.text, nil, 0.9); cy = cy + 20
    if m.xpProgress ~= nil then
      bar(x + bodyX, cy, bodyW, 8, m.xpProgress, COL.xp); cy = cy + 12
      local lbl = (m.xpToNext and m.xpToNext > 0) and (money(m.xpToNext):gsub("¥","") .. " XP to Lv " .. ((m.level or 0)+1))
        or (((m.exp and money(m.exp):gsub("¥","")) or "0") .. " XP · Max")
      txt(lbl, x + bodyX, cy, 14, COL.dim); cy = cy + 20
    end
    cy = cy + 6
    local colW2 = bodyW / 2
    local mf = 14
    for i, mv in ipairs(m.moves or {}) do
      local col = (i-1) % 2; local row = math.floor((i-1)/2)
      local mx = x + bodyX + col*colW2; local my = cy + row*20
      local pp = (mv.pp ~= nil and mv.maxpp ~= nil) and (mv.pp.."/"..mv.maxpp) or (mv.pp and tostring(mv.pp) or "")
      local ppW = textW(pp, mf)
      txt(ellipsize(mv.name, mf, colW2 - ppW - 12), mx, my, mf, COL.text, nil, 0.92)
      txt(pp, mx + colW2 - 8, my, mf, COL.dim, "right")
    end
    return rowH
  end

  local function party(st, x, y, styleOverride, widthOverride)
    local w = widthOverride or COLW; local style = styleOverride or C.partyStyle or 1
    local list = st.party or {}
    local h = PAD + 34 + 8
    for _, m in ipairs(list) do h = h + measureMon(m, style) + (m.active and 8 or 10) end
    h = h + PAD - 10
    panel(x, y, w, h, false)
    txt("Active Party", x + PAD, y + PAD, 28, COL.text)
    txt(((style == 2 or style == 3) and "B" or "A") .. "  ·  " .. #list .. "/6", x + w - PAD, y + PAD + 10, 14, COL.dim, "right")
    local cy = y + PAD + 34 + 8
    for i, m in ipairs(list) do
      local rh = measureMon(m, style)
      if m.active then setc(COL.gold, 0.10); rrect("fill", x + PAD - 6, cy - 6, w - PAD*2 + 12, rh + 12, 8) end
      drawMonRow(m, x + PAD, cy, w - PAD*2, "p" .. i, style)
      cy = cy + rh
      if i < #list then
        setc(COL.border, 0.10); love.graphics.setLineWidth(math.max(1, s))
        love.graphics.line((x+PAD)*s, math.floor((cy+5)*s), (x+w-PAD)*s, math.floor((cy+5)*s))
      end
      -- the active row's highlight box already extends 6px past rh into this
      -- gap, so it needs slightly less than the standard row gap on top
      cy = cy + (m.active and 8 or 10)
    end
    return h
  end

  -- Trainer panel
  local function trainer(st, x, y, widthOverride)
    local t = st.trainer; if not t then return 0 end
    local w = widthOverride or COLW
    local W, H = love.graphics.getDimensions()
    local isLandscape = (W / H) > 1.2
    local function L(v) return isLandscape and math.floor(v * 1.35 + 0.5) or v end
    local den = t.dexTotal and ("/"..t.dexTotal) or ""
    local rows = {
      { "Money", money(t.money), COL.money }, { "Play Time", fmtTime(t.playTime), COL.text },
      { "Badges", (t.badgeCount or 0).."/"..#(t.badges or {}), COL.text }, { "Party", (t.partyCount or 0).."/6", COL.text },
      { "Pokédex Owned", (t.dexOwned or 0)..den, COL.text }, { "Pokédex Seen", (t.dexSeen or 0)..den, COL.text },
    }
    local badgeRows = math.ceil(#(t.badges or {}) / 4)
    local rowH, badgeRowH = L(60), L(50)
    local h = PAD + L(30) + L(18) + (math.ceil(#rows/2))*rowH + L(26) + badgeRows*badgeRowH + PAD + L(8)
    panel(x, y, w, h, false)
    local cy = y + PAD
    txt(t.name ~= "" and t.name or "—", x + PAD, cy, L(30), COL.text); cy = cy + L(32)
    txt((t.version or ""):upper() .. " VERSION", x + PAD, cy, L(13), COL.dim); cy = cy + L(20)
    local colW2 = (w - PAD*2) / 2
    for i, r in ipairs(rows) do
      local col = (i-1)%2; local row = math.floor((i-1)/2)
      local rx = x + PAD + col*colW2; local ry = cy + row*rowH
      txt(r[1]:upper(), rx, ry, L(12), COL.dim)
      txt(r[2], rx, ry + L(22), L(24), r[3])
    end
    cy = cy + math.ceil(#rows/2)*rowH + L(10)
    txt("GYM BADGES", x + PAD, cy, L(12), COL.dim); cy = cy + L(26)
    local sheet = badgeSheet()
    local bw = (w - PAD*2 - 3*14) / 4
    for i, b in ipairs(t.badges or {}) do
      local col = (i-1)%4; local row = math.floor((i-1)/4)
      local bx = x + PAD + col*(bw+14); local by = cy + row*badgeRowH
      local tint = b.owned and COL.text or COL.dim
      local a = b.owned and 1 or 0.55
      local q = sheet and sheet.quads[i-1]
      if q then
        local size = L(24); local sc2 = (size/16)*s
        setc(tint, a)
        love.graphics.draw(sheet.img, q, math.floor((bx + bw/2 - size/2)*s), math.floor(by*s), 0, sc2, sc2)
      else
        txt(b.owned and "◆" or "◇", bx + bw/2, by, L(16), tint, "center", a)
      end
      txt(b.name, bx + bw/2, by + L(28), L(11), tint, "center", a)
    end
    return h
  end

  -- Route panel
  local function drawEncSection(title, tab, x, y, w, col)
    if not tab or not tab.species or #tab.species == 0 then return 0 end
    local W, H = love.graphics.getDimensions()
    local isLandscape = (W / H) > 1.2
    local function L(v) return isLandscape and math.floor(v * 1.35 + 0.5) or v end
    local cy = y
    txt(title .. " · " .. tab.rate .. "% / step", x, cy, L(13), COL.dim); cy = cy + L(26)
    for _, sp in ipairs(tab.species) do
      local img = getSprite(sp.species, C.dPoke)
      local spriteSz = L(36)
      if img then local iw, ih = img:getDimensions(); local sc2 = (spriteSz/math.max(iw,ih))*s
        setc(COL.text, 1); love.graphics.draw(img, math.floor(x*s), math.floor((cy-4)*s), 0, sc2, sc2) end
      txt(sp.name, x + L(48), cy, L(18), COL.text)
      local lv = (sp.minLevel == sp.maxLevel) and ("Lv "..sp.minLevel) or ("Lv "..sp.minLevel.."-"..sp.maxLevel)
      local pctStr = sp.pct .. "%"
      local pctW = textW(pctStr, L(18))
      txt(pctStr, x + w, cy, L(18), COL.text, "right")
      txt(lv, x + w - pctW - L(14), cy, L(15), COL.dim, "right")
      bar(x + L(48), cy + L(27), w - L(48), L(5), sp.pct/100, col); cy = cy + L(46)
    end
    return cy - y
  end
  local function route(st, x, y, widthOverride)
    local r = st.route; if not r then return 0 end
    local w = widthOverride or COLW
    local W, H = love.graphics.getDimensions()
    local isLandscape = (W / H) > 1.2
    local function L(v) return isLandscape and math.floor(v * 1.35 + 0.5) or v end
    -- measure
    local function secH(tab) if not tab or not tab.species or #tab.species==0 then return 0 end return L(26) + #tab.species*L(46) end
    local h = PAD + L(30) + secH(r.grass) + (r.grass and L(12) or 0) + secH(r.water) + PAD
    if not r.grass and not r.water then h = PAD + L(30) + L(24) + PAD end
    panel(x, y, w, h, false)
    local cy = y + PAD
    txt(r.name, x + PAD, cy, L(26), COL.text); cy = cy + L(34)
    local used = 0
    used = drawEncSection("Grass", r.grass, x + PAD, cy, w - PAD*2, COL.hi)
    cy = cy + used + (used > 0 and L(12) or 0)
    used = drawEncSection("Surfing", r.water, x + PAD, cy, w - PAD*2, COL.xp)
    if not r.grass and not r.water then txt("No wild encounters here", x + PAD, cy, L(16), COL.dim, nil, 0.6) end
    return h
  end

  -- Battle panel
      local function battle(st, x, y, targetH, widthOverride)
    local b = st.battle; if not b then return 0 end
    local W, H = love.graphics.getDimensions()
    local isLandscape = (W / H) > 1.2
    local margin = 28
    local designW = W / s
    local w = widthOverride or (isLandscape and 828 or math.max(320, designW - margin*2))
    local en = b.enemy or {}; local m = b.matchup or {}
    local nMoves = #(m.myMoves or {}); local nThreat = math.max(1, #(m.threats or {}))
    local nCatch = b.catch and #b.catch or 0

    -- landscape sizing constants (must match drawing code below exactly)
    local nameSz   = isLandscape and 36 or 24
    local lvSz     = isLandscape and 22 or 16
    local moveSz   = isLandscape and 20 or 16
    local smallSz  = isLandscape and 15 or 13
    local chipSz   = isLandscape and 16 or 11
    local chipHt   = isLandscape and 26 or 17
    local spSz     = isLandscape and 20 or 16
    local rowH     = isLandscape and 44 or 26
    local rowOff   = isLandscape and math.floor((rowH - moveSz) / 2) or 0
    local spriteSz = isLandscape and 120 or 60
    local titleGap = isLandscape and 56 or 20
    local enemyH   = isLandscape and 164 or 66
    local hpGap    = isLandscape and 30 or 24
    local speedGap = isLandscape and 28 or 22
    local hdrGap   = isLandscape and 28 or 22
    local secGap   = isLandscape and 10 or 6
    local catchGap = isLandscape and 10 or 4
    local catchHdr = isLandscape and 28 or 22
    local botPad   = isLandscape and 64 or 0

    local h = PAD + titleGap + spriteSz + 12 + 16 + hpGap + speedGap + hdrGap
              + (nMoves * rowH) + secGap + hdrGap + (nThreat * rowH)
              + (nCatch > 0 and (catchGap + catchHdr + nCatch * rowH) or 0)
              + PAD + botPad
    if targetH and targetH > h then h = targetH end

    panel(x, y, w, h, false)
    local cy = y + PAD
    local title = b.kind == "trainer" and (b.trainer and (b.trainer.."'s Pokémon") or "Trainer Battle") or "Wild Battle"
    txt(title:upper(), x + PAD, cy, 13, COL.dim); cy = cy + titleGap

    -- enemy sprite + name + level + types
    local img = getSprite(en.species, C.dPoke)
    local spriteTop = cy
    if img then local iw, ih = img:getDimensions(); local sc = (spriteSz/math.max(iw,ih))*s
      setc(COL.text,1); love.graphics.draw(img, math.floor((x+PAD)*s), math.floor(spriteTop*s), 0, sc, sc) end
    -- name + level to the right of sprite
    local nameX = x + PAD + spriteSz + 14
    txt(en.name or "?", nameX, spriteTop, nameSz, COL.text)
    txt("Lv " .. (en.level or "?"), nameX + textW(en.name or "?", nameSz) + 10, spriteTop + (isLandscape and 10 or 6), lvSz, COL.dim)
    -- types below name, aligned with name column
    local tx = nameX
    local typeY = spriteTop + (isLandscape and 42 or 30)
    for _, t in ipairs(en.types or {}) do tx = tx + chip(tx, typeY, t, TYPE[t] or COL.dim, chipSz, chipHt) end
    -- advance cy to just below the sprite for HP bar
    cy = spriteTop + spriteSz + 12

    -- HP bar
    local eh = C.dispHP.enemy or en.hp or 0
    local ef = math.max(0, math.min(1, eh / (en.maxhp or 1)))
    bar(x + PAD, cy, w - PAD*2, 12, ef, hpCol(ef)); cy = cy + 16
    txt(string.format("%d / %d HP", math.floor(eh+0.5), en.maxhp or 0), x + PAD, cy, spSz, COL.text, nil, 0.9); cy = cy + hpGap

    -- speed indicator
    if m.speed and m.speed.faster then
      local sp = m.speed.faster == "you" and "> You move first" or (m.speed.faster == "them" and "< Enemy moves first" or "= Speed tie")
      txt(sp, x + PAD, cy, spSz, COL.gold);
    end
    cy = cy + speedGap

    -- YOUR MOVES
    txt("YOUR MOVES", x + PAD, cy, smallSz, COL.dim); cy = cy + hdrGap
    for _, mv in ipairs(m.myMoves or {}) do
      local cx = x + PAD
      cx = cx + chip(cx, cy + rowOff, mv.type, TYPE[mv.type] or COL.dim, chipSz, chipHt)
      txt(mv.name .. (mv.stab and "  ★" or ""), cx, cy + rowOff, moveSz, COL.text)
      if mv.status then
        txt("STATUS " .. (mv.pp or "?") .. "/" .. (mv.maxpp or "?"), x + w - PAD, cy + rowOff, smallSz, COL.dim, "right")
      else
        local tier = mv.mult == 0 and COL.lo or (mv.mult > 10 and COL.super or (mv.mult == 10 and COL.dim or COL.resist))
        local powStr = (mv.power and (mv.power.." pow") or "—") .. " · " .. (mv.pp or "?") .. "/" .. (mv.maxpp or "?")
        local powW = textW(powStr, smallSz)
        txt(effText(mv.mult), x + w - PAD - powW - 10, cy + rowOff, moveSz, tier, "right")
        txt(powStr, x + w - PAD, cy + rowOff, smallSz, COL.dim, "right")
      end
      cy = cy + rowH
    end

    -- THREATS
    cy = cy + secGap
    txt("THREATS", x + PAD, cy, smallSz, COL.dim); cy = cy + hdrGap
    if m.threats and #m.threats > 0 then
      for _, t in ipairs(m.threats) do
        local cx = x + PAD; setc(COL.threat, 1)
        txt("!", cx, cy + rowOff, moveSz, COL.threat); cx = cx + 22
        cx = cx + chip(cx, cy + rowOff, t.type, TYPE[t.type] or COL.dim, chipSz, chipHt)
        txt(t.name .. "  " .. effText(t.mult), cx, cy + rowOff, moveSz, COL.threat)
        cy = cy + rowH
      end
    else
      txt("No super-effective moves from its set.", x + PAD, cy + rowOff, smallSz, COL.dim, nil, 0.6); cy = cy + rowH
    end

    -- CATCH ODDS
    if nCatch > 0 then
      cy = cy + catchGap; txt("CATCH ODDS", x + PAD, cy, smallSz, COL.dim); cy = cy + catchHdr
      for _, c in ipairs(b.catch) do
        local a = c.qty > 0 and 1 or 0.45
        txt(c.name .. (c.qty > 0 and (" ×"..c.qty) or " (none)"), x + PAD, cy + rowOff, moveSz, COL.text, nil, a)
        local pcol = c.pct >= 60 and COL.hi or (c.pct >= 25 and COL.mid or COL.resist)
        txt(pct(c.pct), x + w - PAD, cy + rowOff, moveSz, pcol, "right", a)
        cy = cy + rowH
      end
    end
    return h
  end


  -- Items panel: two fixed columns (Balls | Healing), capped with "+N more".
  local ITEM_CAP = 4
  local function items(st, x, y, widthOverride)
    local it = st.items
    local w = widthOverride or COLW; local colGap = 18
    local W, H = love.graphics.getDimensions()
    local isLandscape = (W / H) > 1.2
    local function L(v) return isLandscape and math.floor(v * 1.35 + 0.5) or v end
    if not it or (#it.balls == 0 and #it.heals == 0) then
      local h = PAD + L(34) + L(30) + PAD
      panel(x, y, w, h, false)
      txt("Items", x + PAD, y + PAD, L(26), COL.text)
      txt("No items yet", x + PAD, y + PAD + L(34), L(14), COL.dim, nil, 0.7)
      return h
    end
    local cw = (w - PAD*2 - colGap) / 2
    local nB = math.min(ITEM_CAP, #it.balls); local nH = math.min(ITEM_CAP, #it.heals)
    local moreB, moreH = #it.balls - nB, #it.heals - nH
    local rows = math.max(nB, nH, 1)
    local extra = (moreB > 0 or moreH > 0) and L(18) or 0
    local rowH = L(22)
    local h = PAD + L(34) + L(22) + rows*rowH + extra + PAD
    panel(x, y, w, h, false)
    txt("Items", x + PAD, y + PAD, L(26), COL.text)
    local lcx = x + PAD; local rcx = x + PAD + cw + colGap
    local hy = y + PAD + L(34)
    txt("BALLS", lcx, hy, L(13), COL.dim)
    txt("HEALING", rcx, hy, L(13), COL.dim)
    local cy0 = hy + L(22)
    for i = 1, nB do local b = it.balls[i]; local ry = cy0 + (i-1)*rowH
      txt(b.name, lcx, ry, L(16), COL.text); txt("×" .. b.qty, lcx + cw, ry, L(16), COL.dim, "right") end
    for i = 1, nH do local hh = it.heals[i]; local ry = cy0 + (i-1)*rowH
      txt(hh.name, rcx, ry, L(16), COL.text); txt("×" .. hh.qty, rcx + cw, ry, L(16), COL.dim, "right") end
    if #it.balls == 0 then txt("—", lcx, cy0, L(16), COL.dim, nil, 0.5) end
    if #it.heals == 0 then txt("—", rcx, cy0, L(16), COL.dim, nil, 0.5) end
    if moreB > 0 then txt("+" .. moreB .. " more", lcx, cy0 + nB*rowH, L(12), COL.dim, nil, 0.7) end
    if moreH > 0 then txt("+" .. moreH .. " more", rcx, cy0 + nH*rowH, L(12), COL.dim, nil, 0.7) end
    return h
  end

  -- =====================================================================
  -- Interactive management screens (i = items, p = party/boxes).
  -- Touch-driven: tap to pick up, tap a highlighted target to drop.
  -- A lightweight state is pushed onto game.stack so the engine routes ALL
  -- keys to it (Game:keypressed -> top.onKeyPressed) and freezes the world
  -- (stack:update only ticks the top). We draw in raw window coords here.
  -- Milestone 1: open/close/freeze/cursor/capture + read-only panels + hover.
  -- =====================================================================
  if C.screen == nil then C.screen = false end   -- false | "items" | "party"
  C.held    = C.held or nil        -- what the cursor is carrying (later milestones)
  C.boxView = C.boxView or nil     -- which box is shown on the right
  C.hit     = C.hit or {}          -- clickable regions recorded each draw
  C.status  = C.status or nil      -- transient footer message
  C.mx, C.my = C.mx or 0, C.my or 0
  C.iv      = C.iv or nil           -- item view order: { bag={ids}, pc={ids} }
  C.isort   = C.isort or { bag = { mode = "custom", dir = 1 }, pc = { mode = "custom", dir = 1 } }
  C.iscroll = C.iscroll or { bag = 0, pc = 0 }
  C.iLayout = C.iLayout or {}        -- per-side panel geometry, for drop hit-testing
  C.savedFlash = C.savedFlash or {}  -- per-side "Saved!" flash timestamps
  C.pLayout = C.pLayout or {}        -- party/box slot + rail geometry, for drop hit-testing

  -- item categories (same buckets as the Pocket PC app) -> a colour swatch
  local HEAL_IDS = {
    POTION=1,SUPER_POTION=1,HYPER_POTION=1,MAX_POTION=1,FULL_RESTORE=1,FULL_HEAL=1,ANTIDOTE=1,
    BURN_HEAL=1,ICE_HEAL=1,AWAKENING=1,PARLYZ_HEAL=1,REVIVE=1,MAX_REVIVE=1,ETHER=1,MAX_ETHER=1,
    ELIXER=1,MAX_ELIXER=1,FRESH_WATER=1,SODA_POP=1,LEMONADE=1,
  }
  local BATTLE_IDS = { X_ATTACK=1,X_DEFEND=1,X_SPEED=1,X_SPECIAL=1,X_ACCURACY=1,DIRE_HIT=1,GUARD_SPEC=1,POKE_DOLL=1 }
  local KEY_IDS = { BICYCLE=1,TOWN_MAP=1,ITEMFINDER=1,OLD_ROD=1,GOOD_ROD=1,SUPER_ROD=1,S_S_TICKET=1,
    BIKE_VOUCHER=1,GOLD_TEETH=1,CARD_KEY=1,LIFT_KEY=1,SILPH_SCOPE=1,POKE_FLUTE=1,OAKS_PARCEL=1,
    SECRET_KEY=1,EXP_ALL=1,COIN_CASE=1,DOME_FOSSIL=1,HELIX_FOSSIL=1,OLD_AMBER=1 }
  local function itemCat(id, def)
    if (def and def.ball) or id:find("BALL", 1, true) then return "BALLS" end
    if (def and def.machine) or id:match("^TM") or id:match("^HM") then return "TM" end
    if HEAL_IDS[id] or id:find("POTION",1,true) or id:find("HEAL",1,true) or id:find("REVIVE",1,true)
      or id:find("RESTORE",1,true) or id:find("ETHER",1,true) or id:find("ELIXER",1,true) then return "HEALING" end
    if BATTLE_IDS[id] then return "BATTLE" end
    if KEY_IDS[id] or (def and def.keyItem) or (def and def.tossable == false) then return "KEY" end
    return "OTHER"
  end
  local CATCOL = {
    BALLS = hex("e05a5a"), HEALING = hex("7dd87d"), BATTLE = hex("e0b330"),
    KEY = hex("7a8fe0"), TM = hex("b06fd0"), OTHER = hex("9a9a80"),
  }
  local CATORD = { BALLS = 1, HEALING = 2, BATTLE = 3, TM = 4, OTHER = 5, KEY = 6 }
  local PC_ITEM_CAP = 50

  local function itemName(id)
    local d = C.game and C.game.data and C.game.data.items and C.game.data.items[id]
    return (d and d.name) or tostring(id)
  end
  local function monMax(mon, def)
    if mon.stats and mon.stats.hp then return mon.stats.hp end
    if C.Stats and def and def.baseStats then
      local ok, st = pcall(C.Stats.calc, def, mon.level or 1, mon.dvs or {}, mon.statExp)
      if ok and st then return st.hp end
    end
    return mon.hp or 1
  end
  local function bagList()
    local save = C.game and C.game.save; if not save then return {} end
    local inv, order = save.inventory or {}, save.bagOrder
    local list, seen = {}, {}
    local function add(id)
      if inv[id] and inv[id] > 0 and not seen[id]
        and not (C.Bag and C.Bag.isBadge and C.Bag.isBadge(id)) then
        seen[id] = true; list[#list+1] = { id = id, name = itemName(id), qty = inv[id] }
      end
    end
    if order then for _, id in ipairs(order) do add(id) end end
    for id in pairs(inv) do add(id) end
    return list
  end
  local function pcItemList()
    local save = C.game and C.game.save; if not save then return {} end
    local pc, order = save.pcItems or {}, save.pcOrder
    local list, seen = {}, {}
    local function add(id)
      if pc[id] and pc[id] > 0 and not seen[id] then
        seen[id] = true; list[#list+1] = { id = id, name = itemName(id), qty = pc[id] }
      end
    end
    if order then for _, id in ipairs(order) do add(id) end end
    for id in pairs(pc) do add(id) end
    return list
  end

  -- record a clickable region (design units) + report hover
  local function region(x, y, w, h, tag, data)
    C.hit[#C.hit+1] = { x = x, y = y, w = w, h = h, tag = tag, data = data }
    return C.mx >= x and C.mx <= x+w and C.my >= y and C.my <= y+h
  end
  local function listPanel(px, py, pw, ph, title, sub, rows, sideTag)
    panel(px, py, pw, ph, false)
    txt(title, px+PAD, py+14, 22, COL.text)
    if sub then txt(sub, px+pw-PAD, py+18, 15, COL.dim, "right") end
    local ry, rh = py+56, 40
    local maxRows = math.max(1, math.floor((ph - 70) / rh))
    for i = 1, math.min(#rows, maxRows) do
      local r = rows[i]; local y = ry + (i-1)*rh
      local hov = region(px+8, y, pw-16, rh-4, sideTag, i)
      if hov then setc(COL.gold, 0.13); rrect("fill", px+8, y, pw-16, rh-4, 8) end
      txt(ellipsize(r.name, 18, pw - PAD*2 - 70), px+PAD, y+5, 18, COL.text)
      if r.right then txt(r.right, px+pw-PAD, y+6, 15, COL.dim, "right") end
    end
    if #rows == 0 then txt("- empty -", px+PAD, ry, 16, COL.dim, nil, 0.6) end
    if #rows > maxRows then txt("+"..(#rows-maxRows).." more", px+PAD, py+ph-26, 13, COL.dim) end
  end

  local function invOf(side)
    local save = C.game and C.game.save; if not save then return {} end
    return side == "bag" and (save.inventory or {}) or (save.pcItems or {})
  end
  local function isBadgeItem(id) return C.Bag and C.Bag.isBadge and C.Bag.isBadge(id) end
  local function buildItemView()
    C.iv = { bag = {}, pc = {} }
    for _, r in ipairs(bagList()) do C.iv.bag[#C.iv.bag+1] = r.id end
    -- the in-game PC always shows items A-Z, so open the PC view that way to match
    local pcRows = pcItemList()
    table.sort(pcRows, function(a, b) return a.name < b.name end)
    for _, r in ipairs(pcRows) do C.iv.pc[#C.iv.pc+1] = r.id end
    C.isort.pc = { mode = "name", dir = 1 }
  end
  local function itemRows(side)
    if not C.iv then buildItemView() end
    local inv, seen, rows = invOf(side), {}, {}
    for _, id in ipairs(C.iv[side] or {}) do
      if inv[id] and inv[id] > 0 and not seen[id] and not (side == "bag" and isBadgeItem(id)) then
        seen[id] = true
        rows[#rows+1] = { id = id, name = itemName(id), qty = inv[id], cat = itemCat(id, C.game.data.items[id]) }
      end
    end
    for id, q in pairs(inv) do   -- newly-acquired items not yet in the view order
      if q > 0 and not seen[id] and not (side == "bag" and isBadgeItem(id)) then
        seen[id] = true; C.iv[side][#C.iv[side]+1] = id
        rows[#rows+1] = { id = id, name = itemName(id), qty = q, cat = itemCat(id, C.game.data.items[id]) }
      end
    end
    return rows
  end
  local function sortSide(side, mode)
    local st = C.isort[side]
    if st.mode == mode then st.dir = -st.dir else st.dir, st.mode = 1, mode end
    local rows, dir = itemRows(side), st.dir
    table.sort(rows, function(a, b)
      local pa, pb
      if mode == "type" then pa, pb = CATORD[a.cat] or 9, CATORD[b.cat] or 9
      elseif mode == "qty" then pa, pb = a.qty, b.qty
      else pa, pb = a.name, b.name end
      if pa == pb then return a.name < b.name end
      if dir < 0 then return pa > pb else return pa < pb end
    end)
    C.iv[side] = {}; for _, r in ipairs(rows) do C.iv[side][#C.iv[side]+1] = r.id end
    C.status = side == "bag"
      and ("Sorted Bag view by "..mode.."  -  press Save order to keep it in-game")
      or  ("Sorted PC view by "..mode.."  -  browsing only (the in-game PC is always A-Z)")
  end
  local function orderIds(list, inv)
    local out = {}
    for _, id in ipairs(list or {}) do if inv[id] and inv[id] > 0 then out[#out+1] = id end end
    return out
  end
  local function viewIds(side)  return orderIds(C.iv[side], invOf(side)) end
  local function savedIds(side)
    local save = C.game.save
    return orderIds(side == "bag" and save.bagOrder or save.pcOrder, invOf(side))
  end
  local function isDirty(side)
    local a, b = viewIds(side), savedIds(side)
    if #a ~= #b then return true end
    for i = 1, #a do if a[i] ~= b[i] then return true end end
    return false
  end
  local function applyOrder(side)
    local order = viewIds(side)
    if side == "bag" then C.game.save.bagOrder = order else C.game.save.pcOrder = order end
    C.savedFlash[side] = love.timer.getTime()
    C.status = "Saved this order to your in-game "..(side=="bag" and "Bag" or "PC")
  end
  -- insert `id` before `beforeId` (or append if nil/not found)
  local function insertBefore(v, id, beforeId)
    if beforeId and beforeId ~= id then
      for i, vid in ipairs(v) do if vid == beforeId then table.insert(v, i, id); return end end
    end
    v[#v+1] = id
  end
  local function reorderView(side, id, beforeId)
    local v = C.iv[side]
    for i, vid in ipairs(v) do if vid == id then table.remove(v, i); break end end
    insertBefore(v, id, beforeId)
  end
  local function doTransfer(fromSide, id, qty, toSide, beforeId)
    local save = C.game.save
    qty = math.max(1, math.floor(qty or 1))
    if fromSide == toSide then reorderView(fromSide, id, beforeId); return true end
    if fromSide == "bag" then
      local inv = save.inventory or {}
      qty = math.min(qty, inv[id] or 0)
      if qty <= 0 then return false, "Nothing to move" end
      local pc = save.pcItems or {}; save.pcItems = pc
      if not pc[id] then local n=0; for _ in pairs(pc) do n=n+1 end
        if n >= PC_ITEM_CAP then return false, "PC is full" end end
      C.Bag.remove(save, id, qty); pc[id] = (pc[id] or 0) + qty
    else
      local pc = save.pcItems or {}
      qty = math.min(qty, pc[id] or 0)
      if qty <= 0 then return false, "Nothing to move" end
      if not C.Bag.add(save, id, qty) then return false, "Bag can't hold more" end
      pc[id] = pc[id] - qty; if pc[id] <= 0 then pc[id] = nil end
    end
    if not (invOf(fromSide)[id] and invOf(fromSide)[id] > 0) then
      for i, vid in ipairs(C.iv[fromSide]) do if vid == id then table.remove(C.iv[fromSide], i); break end end
    end
    local inDest = false
    for _, vid in ipairs(C.iv[toSide]) do if vid == id then inDest = true; break end end
    if not inDest then insertBefore(C.iv[toSide], id, beforeId) end
    return true
  end
  -- resolve a cursor position to { side, beforeId } from the recorded row geometry
  local function dropTarget(dx, dy)
    for _, side in ipairs({ "bag", "pc" }) do
      local L = C.iLayout[side]
      if L and dx >= L.x and dx <= L.x+L.w and dy >= L.y-30 and dy <= L.y+L.h+40 then
        for _, it in ipairs(L.items or {}) do
          if dy < it.y + it.h/2 then return side, it.id end
        end
        return side, nil   -- past the last row -> append
      end
    end
    return nil
  end
  -- why a drop onto `toSide` would be refused (nil = it's fine). Mirrors doTransfer.
  local function dropBlockedReason(fromSide, id, qty, toSide)
    if fromSide == toSide then return nil end     -- same-side reorder is always ok
    local save = C.game.save
    if toSide == "pc" then
      local pc = save.pcItems or {}
      if not pc[id] then
        local n = 0; for _ in pairs(pc) do n = n + 1 end
        if n >= PC_ITEM_CAP then return "PC is full" end
      end
    else
      local inv = save.inventory or {}
      local slots = (C.Bag and C.Bag.slots and C.Bag.slots(save)) or 0
      if not inv[id] and slots >= ((C.Bag and C.Bag.CAPACITY) or 20) then return "Bag is full" end
      if (inv[id] or 0) + (qty or 1) > 99 then return "Stack maxed (99)" end
    end
    return nil
  end

  local SORTS = { {"type","Type"}, {"name","A-Z"}, {"qty","Qty"} }
  local function triangle(cx, cy, up)
    local d = 4
    if up then love.graphics.polygon("fill", cx*s, (cy-d)*s, (cx-d)*s, (cy+d)*s, (cx+d)*s, (cy+d)*s)
    else       love.graphics.polygon("fill", (cx-d)*s, (cy-d)*s, (cx+d)*s, (cy-d)*s, cx*s, (cy+d)*s) end
  end
  local function itemPanel(side, px, py, pw, ph)
    local rows = itemRows(side)
    local cap = side == "bag" and ((C.Bag and C.Bag.CAPACITY) or 20) or PC_ITEM_CAP
    local ds = dropTarget(C.mx, C.my)
    local isTarget = C.held and C.held.from ~= side and ds == side
    local blocked = isTarget and dropBlockedReason(C.held.from, C.held.id, C.held.qty, side)
    panel(px, py, pw, ph, isTarget and not blocked)   -- gold glow only when droppable
    if blocked then
      setc(COL.lo, 0.08); rrect("fill", px, py, pw, ph, 14)
      love.graphics.setLineWidth(math.max(2, 2*s)); setc(COL.lo, 0.85); rrect("line", px, py, pw, ph, 14)
    end
    txt(side == "bag" and "BAG" or "PC ITEMS", px+PAD, py+12, 22, COL.text)
    txt(#rows.."/"..cap.." slots", px+pw-PAD, py+16, 14, #rows>=cap and COL.lo or COL.dim, "right")
    -- controls: Sort [Type][A-Z][Qty]   Save
    local st = C.isort[side]
    local sy, sx = py+46, px+PAD
    txt("Sort", sx, sy+5, 13, COL.dim); sx = sx + textW("Sort", 13) + 8
    for _, m in ipairs(SORTS) do
      local active = st.mode == m[1]
      local bw = textW(m[2], 13) + (active and 30 or 16)
      region(sx, sy, bw, 26, "sort", { side = side, mode = m[1] })
      setc(active and COL.gold or COL.panel, active and 0.92 or 0.6); rrect("fill", sx, sy, bw, 26, 6)
      txt(m[2], sx+8, sy+5, 13, active and COL.panel or COL.dim)
      if active then setc(COL.panel, 1); triangle(sx+bw-12, sy+13, st.dir > 0) end
      sx = sx + bw + 6
    end
    if side == "bag" then  -- Save order: dim when clean, gold when dirty, green flash on save
      local flash = C.savedFlash[side] and (love.timer.getTime() - C.savedFlash[side] < 1.3)
      local dirty = isDirty(side)
      local lbl = flash and "Saved!" or (dirty and "Save order" or "Saved")
      local bw = textW(lbl, 13) + 18
      local bx = px+pw-PAD-bw
      if dirty and not flash then region(bx, sy, bw, 26, "apply", side) end
      local lit = dirty or flash
      setc(flash and COL.hi or (dirty and COL.gold or COL.panel), lit and 0.9 or 0.45); rrect("fill", bx, sy, bw, 26, 6)
      txt(lbl, bx+9, sy+5, 13, lit and COL.panel or COL.dim, nil, lit and 1 or 0.6)
    else  -- PC order can't be saved: the in-game PC always displays A-Z
      txt("view only - PC is always A-Z in-game", px+pw-PAD, sy+7, 12, COL.dim, "right", 0.7)
    end
    -- build display list (category headers when sorted by Type)
    local grouped = st.mode == "type"
    local disp = {}
    if grouped then
      local counts = {}; for _, r in ipairs(rows) do counts[r.cat] = (counts[r.cat] or 0)+1 end
      local prev
      for _, r in ipairs(rows) do
        if r.cat ~= prev then disp[#disp+1] = { head = true, cat = r.cat, n = counts[r.cat] }; prev = r.cat end
        disp[#disp+1] = { r = r }
      end
    else
      for _, r in ipairs(rows) do disp[#disp+1] = { r = r } end
    end
    local headH, itemH = 26, 38
    local ry = py + 84
    local listH = ph - (ry - py) - 40
    local contentH = 0
    for _, e in ipairs(disp) do contentH = contentH + (e.head and headH or itemH) end
    local maxScroll = math.max(0, contentH - listH)
    C.iscroll[side] = math.max(0, math.min(maxScroll, C.iscroll[side] or 0))
    local scroll = C.iscroll[side]
    local items = {}
    love.graphics.setScissor(math.floor(px*s), math.floor(ry*s), math.ceil(pw*s), math.ceil(listH*s))
    local yy = ry - scroll
    for _, e in ipairs(disp) do
      if e.head then
        if yy + headH > ry and yy < ry + listH then
          setc(CATCOL[e.cat] or CATCOL.OTHER, 0.95); rrect("fill", px+PAD, yy+headH-11, 10, 10, 2)
          local cname = e.cat:sub(1,1) .. e.cat:sub(2):lower()
          txt(cname, px+PAD+16, yy+3, 13, COL.dim)
          txt("("..e.n..")", px+PAD+18+textW(cname, 13), yy+4, 12, COL.dim, nil, 0.65)
          setc(COL.border, 0.09); love.graphics.setLineWidth(math.max(1, s))
          love.graphics.line((px+PAD)*s, (yy+headH-1)*s, (px+pw-PAD)*s, (yy+headH-1)*s)
        end
        yy = yy + headH
      else
        local r = e.r
        if yy + itemH > ry and yy < ry + listH then
          local held = C.held and C.held.from == side and C.held.id == r.id
          local hov = region(px+8, yy, pw-16, itemH-3, "itemrow", { side = side, id = r.id })
          local cc = CATCOL[r.cat] or CATCOL.OTHER
          if held then setc(COL.gold, 0.06) elseif hov then setc(cc, 0.16) else setc(cc, 0.06) end
          rrect("fill", px+8, yy, pw-16, itemH-3, 7)
          setc(cc, held and 0.4 or 1); rrect("fill", px+PAD, yy+itemH/2-7, 12, 12, 3)
          txt(ellipsize(r.name, 17, pw - PAD*3 - 96), px+PAD+22, yy+7, 17, held and COL.dim or COL.text)
          txt("x"..r.qty, px+pw-PAD, yy+8, 16, COL.dim, "right")
        end
        items[#items+1] = { y = yy, h = itemH, id = r.id }
        yy = yy + itemH
      end
    end
    -- insertion line while holding over this side (not when the drop is blocked)
    if C.held and ds == side and not blocked then
      local ly = ry + listH
      local _, bId = dropTarget(C.mx, C.my)
      for _, it in ipairs(items) do if it.id == bId then ly = it.y; break end end
      ly = math.max(ry+1, math.min(ly, ry + listH - 1))
      setc(COL.gold, 0.95); love.graphics.setLineWidth(math.max(2, 3*s))
      love.graphics.line((px+PAD)*s, ly*s, (px+pw-PAD-8)*s, ly*s)
    end
    love.graphics.setScissor()
    C.iLayout[side] = { x = px, y = ry, w = pw, h = listH, items = items, contentH = contentH }
    if #rows == 0 then
      txt(C.held and "drop items here" or "No items - drag some here", px+PAD, ry+8, 16, COL.dim, nil, 0.6)
    end
    if maxScroll > 0 then      -- scrollbar (draggable)
      local tx, tw = px+pw-11, 6
      local thumbH = math.max(30, listH * (listH / contentH))
      local thumbY = ry + (scroll / maxScroll) * (listH - thumbH)
      local dragging = C.scrollDrag and C.scrollDrag.side == side
      local hov = region(tx-14, ry, tw+28, listH, "scrollbar", { side = side })  -- wide hit zone, easier to grab on touch
      setc(COL.border, 0.10); rrect("fill", tx, ry, tw, listH, 3)
      setc((dragging or hov) and COL.gold or COL.dim, dragging and 0.9 or 0.7); rrect("fill", tx, thumbY, tw, thumbH, 3)
    end
    bar(px+PAD, py+ph-22, pw-PAD*2, 8, #rows/cap, #rows>=cap and COL.lo or COL.hi)
    if blocked then          -- big "FULL" warning badge over the panel
      local bw = textW(blocked, 22) + 56
      local bx, by = px+pw/2 - bw/2, py + ph*0.42
      setc(COL.lo, 0.95); rrect("fill", bx, by, bw, 46, 12)
      txt(blocked, px+pw/2, by+11, 22, COL.panel, "center")
    end
  end
  local function drawItemsPanels(x1, y1, x2, y2, pw, ph)
    itemPanel("bag", x1, y1, pw, ph)
    itemPanel("pc",  x2, y2, pw, ph)
  end
  local function drawHeldItem()
    local h = C.held; if not h then return end
    local cat = itemCat(h.id, C.game.data.items[h.id])
    if h.mode == "armed" then       -- pulsing arrow toward the other panel
      local toSide = h.from == "bag" and "pc" or "bag"
      local from, to = C.iLayout[h.from], C.iLayout[toSide]
      if from and to then
        local pulse = 0.5 + 0.5*math.abs(math.sin(love.timer.getTime()*3.5))
        setc(COL.gold, pulse); love.graphics.setLineWidth(math.max(2, 5*s))
        if math.abs(from.x - to.x) >= math.abs(from.y - to.y) then
          -- side-by-side panels (landscape): horizontal arrow
          local midY = from.y + from.h/2
          local dirR = to.x > from.x
          local x0 = dirR and (from.x+from.w-30) or (from.x+30)
          local x1 = dirR and (to.x+30) or (to.x+to.w-30)
          love.graphics.line(x0*s, midY*s, x1*s, midY*s)
          local hs = dirR and 1 or -1
          love.graphics.polygon("fill", x1*s, midY*s, (x1-hs*26)*s, (midY-16)*s, (x1-hs*26)*s, (midY+16)*s)
          txt("click to move here", (x0+x1)/2, midY-46, 18, COL.gold, "center", pulse)
        else
          -- stacked panels (portrait): vertical arrow
          local midX = from.x + from.w/2
          local dirD = to.y > from.y
          local y0 = dirD and (from.y+from.h-30) or (from.y+30)
          local y1 = dirD and (to.y+30) or (to.y+to.h-30)
          love.graphics.line(midX*s, y0*s, midX*s, y1*s)
          local vs = dirD and 1 or -1
          love.graphics.polygon("fill", midX*s, y1*s, (midX-16)*s, (y1-vs*26)*s, (midX+16)*s, (y1-vs*26)*s)
          txt("click to move here", midX, (y0+y1)/2 - 10, 18, COL.gold, "center", pulse)
        end
      end
    end
    local dsz = dropTarget(C.mx, C.my)
    local blk = dsz and dsz ~= h.from and dropBlockedReason(h.from, h.id, h.qty, dsz)
    local gx, gy = C.mx, C.my         -- ghost chip riding the cursor
    local qtyStr = (h.max and h.max > 1) and ("  x"..h.qty) or ""
    local label = itemName(h.id) .. qtyStr
    local w = textW(label, 17) + 46
    setc(COL.panel, 0.97); rrect("fill", gx+16, gy-16, w, 34, 8)
    setc(blk and COL.lo or COL.gold, 0.9); love.graphics.setLineWidth(math.max(1, s)); rrect("line", gx+16, gy-16, w, 34, 8)
    setc(CATCOL[cat] or CATCOL.OTHER, 1); rrect("fill", gx+26, gy-3, 12, 12, 3)
    txt(label, gx+46, gy-9, 17, COL.text)
    if blk then txt(blk, gx+16, gy+22, 13, COL.lo)
    elseif h.max and h.max > 1 then txt("wheel = qty", gx+16, gy+22, 12, COL.gold, nil, 0.85) end
  end
  -- ===================== Party / Boxes screen =========================
  local NBOX = (C.Boxes and C.Boxes.COUNT) or 12
  local BCAP = (C.Boxes and C.Boxes.CAPACITY) or 20
  local PMAX = (C.Party and C.Party.MAX) or 6
  local function boxesEnsure()
    if C.Boxes then C.Boxes.ensure(C.game.save) end
    return C.game.save.boxes or {}
  end
  local function arrayOf(loc, boxN)
    if loc == "party" then return C.game.save.party or {} end
    return boxesEnsure()[boxN] or {}
  end
  local function targetMonAt(t) return (t and t.index) and arrayOf(t.loc, t.box)[t.index] or nil end
  -- reason a MOVE (not a swap) onto `tgt` would fail (nil = fine / it's a swap)
  local function isHealthy(m)
    if not m then return false end
    local hp = m.hp
    return hp == nil or hp > 0            -- box mons may store nil hp = full
  end
  local function partyHealthy()
    local n = 0
    for _, m in ipairs(arrayOf("party")) do if isHealthy(m) then n = n + 1 end end
    return n
  end
  -- reason a placement (MOVE or SWAP) would be refused (nil = allowed)
  local function placeBlocked(src, tgt)
    if not (src and tgt) then return nil end
    local sMon = arrayOf(src.loc, src.box)[src.index]
    local tMon = targetMonAt(tgt)
    local isSwap = tMon and tMon ~= sMon
    if not isSwap then         -- capacity + can't-empty-party apply to moves only
      if src.loc == "party" and tgt.loc ~= "party" and #arrayOf("party") <= 1 then return "Can't deposit your last Pokemon" end
      if tgt.loc == "party" and #arrayOf("party") >= PMAX then return "Party is full (6/6)" end
      if tgt.loc == "box" and #arrayOf("box", tgt.box) >= BCAP then return ("Box %d is full"):format(tgt.box) end
    end
    -- the party must always keep >=1 non-fainted Pokemon. Work out how many
    -- healthy mons the party would have AFTER this op; block only if it drops
    -- from >=1 to 0 (so an all-fainted party can still be rescued by a swap-in).
    local cur, res = partyHealthy(), partyHealthy()
    if src.loc == "party" and tgt.loc ~= "party" then           -- a party mon leaves
      if isHealthy(sMon) then res = res - 1 end
      if isSwap and isHealthy(tMon) then res = res + 1 end       -- swap brings a box mon in
    elseif src.loc ~= "party" and tgt.loc == "party" and isSwap then  -- party mon out, box mon in
      if isHealthy(tMon) then res = res - 1 end
      if isHealthy(sMon) then res = res + 1 end
    end
    if cur >= 1 and res < 1 then return "Keep a healthy Pokemon in your party" end
    return nil
  end
  local function doMonPlace(src, tgt)
    if not tgt then return true end
    local sArr = arrayOf(src.loc, src.box); local sMon = sArr[src.index]
    if not sMon then return false, "Nothing to move" end
    if src.loc == tgt.loc and src.box == tgt.box and src.index == tgt.index then return true end
    local blk = placeBlocked(src, tgt); if blk then return false, blk end
    local tArr = arrayOf(tgt.loc, tgt.box); local tMon = tgt.index and tArr[tgt.index]
    if tMon and tMon ~= sMon then                -- SWAP
      sArr[src.index], tArr[tgt.index] = tMon, sMon; return true
    end
    table.remove(sArr, src.index)
    local at = tgt.index
    if src.loc == tgt.loc and src.box == tgt.box and at and at > src.index then at = at - 1 end
    if at and at >= 1 and at <= #tArr + 1 then table.insert(tArr, at, sMon) else tArr[#tArr+1] = sMon end
    return true
  end
  local function ptIn(x, y, w, h) return C.mx >= x and C.mx <= x+w and C.my >= y and C.my <= y+h end
  local function railAt(dx, dy)
    for _, r in ipairs(C.pLayout.rail or {}) do if dx>=r.x and dx<=r.x+r.w and dy>=r.y and dy<=r.y+r.h then return r end end
  end
  local function monSlotAt(dx, dy)
    for _, r in ipairs(C.pLayout.party or {}) do if dx>=r.x and dx<=r.x+r.w and dy>=r.y and dy<=r.y+r.h then return { loc="party", index=r.index, mon=r.mon } end end
    for _, r in ipairs(C.pLayout.grid or {}) do if dx>=r.x and dx<=r.x+r.w and dy>=r.y and dy<=r.y+r.h then return { loc="box", box=C.pLayout.curBox, index=r.index, mon=r.mon } end end
  end
  local function dropTargetMon(dx, dy)
    local t = railAt(dx, dy); if t then return { loc="box", box=t.box } end   -- rail tab -> append to that box
    for _, r in ipairs(C.pLayout.party or {}) do if dx>=r.x and dx<=r.x+r.w and dy>=r.y and dy<=r.y+r.h then return { loc="party", index=r.index } end end
    for _, r in ipairs(C.pLayout.grid or {}) do if dx>=r.x and dx<=r.x+r.w and dy>=r.y and dy<=r.y+r.h then return { loc="box", box=C.pLayout.curBox, index=r.index } end end
  end
  local function drawSpriteIn(img, x, y, bw, bh)
    if not img then return end
    local iw, ih = img:getDimensions()
    img:setFilter("nearest", "nearest")
    local sc = math.min(bw/iw, bh/ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, (x+bw/2)*s, (y+bh/2)*s, 0, sc*s, sc*s, iw/2, ih/2)
  end
  local function heldIsAt(loc, box, index)
    local h = C.held and C.held.src
    return h and h.loc == loc and h.box == box and h.index == index
  end
  local function partyPanel(px, py, pw, ph)
    local dPoke = C.game.data.pokemon
    local party = C.game.save.party or {}
    local hs = C.held and C.held.src
    panel(px, py, pw, ph, false)
    txt("PARTY", px+PAD, py+12, 22, COL.text)
    txt(#party.."/6", px+pw-PAD, py+16, 14, COL.dim, "right")
    local ry = py + 54
    local rh = math.min(150, (ph - 64) / 6)
    C.pLayout.party = {}
    for i = 1, 6 do
      local y = ry + (i-1)*rh
      local mon = party[i]
      C.pLayout.party[#C.pLayout.party+1] = { x=px+8, y=y, w=pw-16, h=rh-6, index=i, mon=mon }
      local held = heldIsAt("party", nil, i)
      local hov = ptIn(px+8, y, pw-16, rh-6)
      local tgt = hs and hov
      local blk = tgt and placeBlocked(hs, { loc="party", index=i })
      if held then setc(COL.gold, 0.05)
      elseif tgt and blk then setc(COL.lo, 0.16)
      elseif tgt then setc(COL.hi, 0.14)
      elseif hov and mon then setc(COL.gold, 0.10)
      else setc(COL.border, mon and 0.03 or 0.012) end
      rrect("fill", px+8, y, pw-16, rh-6, 8)
      if mon then
        local def = dPoke[mon.species]
        local ss = math.min(rh-6-16, 96)
        drawSpriteIn(getSprite(mon.species, dPoke), px+PAD, y+(rh-6-ss)/2, ss, ss)
        local nx = px+PAD+ss+14
        local mx = monMax(mon, def); local hp = mon.hp or mx
        local frac = mx > 0 and hp/mx or 0
        txt(sanitize(mon.nickname or (def and def.name) or mon.species), nx, y + rh*0.16, 20, held and COL.dim or COL.text)
        txt("Lv"..(mon.level or 1), nx, y + rh*0.16 + 28, 15, COL.dim)
        bar(nx, y + rh*0.63, pw - (nx-px) - PAD, 10, frac, hpCol(frac))
        txt(hp.."/"..mx, px+pw-PAD, y + rh*0.63 - 22, 14, COL.dim, "right")
      else
        txt("- empty -", px+PAD, y+(rh-6)/2-10, 15, COL.dim, nil, 0.4)
      end
    end
  end
  local function boxPanel(px, py, pw, ph)
    local save = C.game.save
    local boxes = boxesEnsure()
    local cur = C.boxView or save.currentBox or 1
    C.pLayout.curBox = cur
    local hs = C.held and C.held.src
    panel(px, py, pw, ph, false)
    txt("BOXES", px+PAD, py+12, 22, COL.text)
    local curCount = #(boxes[cur] or {})
    txt("Box "..cur.."   "..curCount.."/"..BCAP, px+pw-PAD, py+16, 14, curCount>=BCAP and COL.lo or COL.dim, "right")
    -- rail: all 12 boxes (empty ones smaller/dimmer, current highlighted, drop targets)
    C.pLayout.rail = {}
    local ry0 = py + 46
    local tw = (pw - PAD*2 - (NBOX-1)*4) / NBOX
    local th = 46
    for n = 1, NBOX do
      local cnt = #(boxes[n] or {})
      local empty = cnt == 0
      local tx = px+PAD + (n-1)*(tw+4)
      local ty = ry0                                   -- all tabs same size + baseline
      local sel = n == cur
      local hov = ptIn(tx, ty, tw, th)
      C.pLayout.rail[#C.pLayout.rail+1] = { x=tx, y=ty, w=tw, h=th, box=n }
      local dropHi = hs and hov
      local blk = dropHi and placeBlocked(hs, { loc="box", box=n })
      setc(sel and COL.gold or (dropHi and (blk and COL.lo or COL.hi) or COL.panel), sel and 0.9 or (empty and 0.35 or 0.72))
      rrect("fill", tx, ty, tw, th, 5)
      txt(tostring(n), tx+tw/2, ty+5, 18, sel and COL.panel or (empty and COL.dim or COL.text), "center")
      txt(empty and "-" or (cnt.."/"..BCAP), tx+tw/2, ty+28, 11, sel and COL.panel or COL.dim, "center", empty and 0.5 or 0.9)
    end
    -- 4x5 grid of the current box
    local box = boxes[cur] or {}
    local gcols, grows, gap = 4, 5, 10
    local gy0 = ry0 + 46 + 16
    local cwd = (pw - PAD*2 - (gcols-1)*gap) / gcols
    local chh = math.min((ph - (gy0-py) - PAD - 6) / grows - gap, cwd*1.1)
    C.pLayout.grid = {}
    for i = 1, gcols*grows do
      local col, row = (i-1)%gcols, math.floor((i-1)/gcols)
      local tx = px+PAD + col*(cwd+gap)
      local ty = gy0 + row*(chh+gap)
      local mon = box[i]
      C.pLayout.grid[#C.pLayout.grid+1] = { x=tx, y=ty, w=cwd, h=chh, index=i, mon=mon }
      local held = heldIsAt("box", cur, i)
      local hov = ptIn(tx, ty, cwd, chh)
      local tgt = hs and hov
      local blk = tgt and placeBlocked(hs, { loc="box", box=cur, index=i })
      if held then setc(COL.gold, 0.05)
      elseif tgt and blk then setc(COL.lo, 0.16)
      elseif tgt then setc(COL.hi, 0.14)
      elseif hov and mon then setc(COL.gold, 0.12)
      else setc(COL.border, mon and 0.04 or 0.02) end
      rrect("fill", tx, ty, cwd, chh, 8)
      if mon then
        local def = C.game.data.pokemon[mon.species]
        drawSpriteIn(getSprite(mon.species, C.game.data.pokemon), tx+6, ty+2, cwd-12, chh-42)
        local nm = sanitize(mon.nickname or (def and def.name) or mon.species)
        txt(ellipsize(nm, 13, cwd-8), tx+cwd/2, ty+chh-37, 13, held and COL.dim or COL.text, "center")
        txt("Lv"..(mon.level or 1), tx+cwd/2, ty+chh-19, 12, COL.dim, "center")
      end
    end
  end
  local function drawPartyPanels(x1, y1, x2, y2, pw, ph)
    C.pLayout = C.pLayout or {}
    partyPanel(x1, y1, pw, ph)
    boxPanel(x2, y2, pw, ph)
  end
  local function drawHeldMon()
    local h = C.held; if not h or not h.mon then return end
    local def = C.game.data.pokemon[h.mon.species]
    local blk = placeBlocked(h.src, dropTargetMon(C.mx, C.my))
    local gx, gy = C.mx, C.my
    local w = 214
    setc(COL.panel, 0.97); rrect("fill", gx+16, gy-28, w, 58, 8)
    setc(blk and COL.lo or COL.gold, 0.9); love.graphics.setLineWidth(math.max(1, s)); rrect("line", gx+16, gy-28, w, 58, 8)
    drawSpriteIn(getSprite(h.mon.species, C.game.data.pokemon), gx+20, gy-26, 54, 54)
    txt(sanitize(h.mon.nickname or (def and def.name) or h.mon.species), gx+80, gy-20, 16, COL.text)
    txt("Lv"..(h.mon.level or 1), gx+80, gy+4, 13, COL.dim)
    if blk then txt(blk, gx+16, gy+34, 13, COL.lo)
    else txt("drop on a slot or box", gx+16, gy+34, 12, COL.gold, nil, 0.85) end
  end

  -- ---- open / close + input --------------------------------------------
  local function canOpen()
    local g = C.game
    return g and g.stack and g.overworld and g.stack:top() == g.overworld
      and g.save and g.save.party and #g.save.party > 0
  end
  local function ensureModalState()
    if not C.modalState then
      C.modalState = {
        isOpaque = false, screenId = "KantoManageScreen",
        onKeyPressed = function(_, key)
          local c = _G.__KANTO_INGAME; if c and c.onScreenKey then c.onScreenKey(key) end
        end,
        update = function() end,
        draw = function() end,
      }
    end
    return C.modalState
  end
  C.openScreen = function(kind)
    if not canOpen() then return end
    C.screen = kind
    C.held, C.status = nil, nil
    C.boxView = C.game.save.currentBox or 1
    if kind == "items" then buildItemView(); C.iscroll = { bag = 0, pc = 0 } end
    C.game.stack:push(ensureModalState())
  end
  C.closeScreen = function()
    if C.game and C.game.stack and C.game.stack:top() == C.modalState then C.game.stack:pop() end
    C.screen, C.held = false, nil
  end
  -- Only "escape" is kept here: on this engine it's how the Android back
  -- button gets reported while a screen is open, so it closes the modal
  -- instead of falling through to whatever back normally does.
  C.onScreenKey = function(key)
    if key == "escape" then C.closeScreen(); return end
  end

  local function topHit(dx, dy)
    for i = #C.hit, 1, -1 do
      local r = C.hit[i]
      if dx >= r.x and dx <= r.x+r.w and dy >= r.y and dy <= r.y+r.h then return r.tag, r.data end
    end
  end
  C.onScreenMouse = function(px, py, button)   -- press (touch or mouse button 1)
    if not C.screen then return end
    s = love.graphics.getHeight() / REF_H
    local dx, dy = px/s, py/s
    local tag, data = topHit(dx, dy)
    if tag == "close" then C.closeScreen(); return end
    if tag == "scrollbar" and not (C.held and C.held.mode == "armed") then
      C.held = nil
      C.scrollDrag = { side = data.side, startY = dy, startScroll = C.iscroll[data.side] or 0 }
      return
    end
    if C.screen == "party" then
      if C.held and C.held.mode == "armed" then          -- placing an armed mon
        local tgt = dropTargetMon(dx, dy)
        if tgt then local ok, err = doMonPlace(C.held.src, tgt); if not ok and err then C.status = err end end
        C.held = nil; return
      end
      local slot = monSlotAt(dx, dy)
      if slot and slot.mon then                            -- grab a Pokemon
        C.held = { mon = slot.mon, src = { loc = slot.loc, box = slot.box, index = slot.index },
                   mode = "pending", downX = dx, downY = dy }
        return
      end
      local tab = railAt(dx, dy)
      if tab then C.boxView = tab.box; return end          -- click a box tab -> view it
      C.held = nil
      return
    end
    -- ITEMS ------------------------------------------------------------
    if tag == "sort"  then C.held = nil; sortSide(data.side, data.mode); return end
    if tag == "apply" then C.held = nil; applyOrder(data); return end
    if C.held and C.held.mode == "armed" then     -- placing an armed item
      local tside, tidx = dropTarget(dx, dy)
      if tside then local ok, err = doTransfer(C.held.from, C.held.id, C.held.qty, tside, tidx); if not ok then C.status = err end end
      C.held = nil; return
    end
    if tag == "itemrow" and not (data.side == "bag" and isBadgeItem(data.id)) then
      local full = invOf(data.side)[data.id] or 1
      C.held = { from = data.side, id = data.id, qty = full, max = full, mode = "pending", downX = dx, downY = dy }
      return
    end
    C.held = nil
  end
  C.onScreenRelease = function(px, py, button)   -- mouse UP
    C.scrollDrag = nil
    if not C.screen or not C.held or button ~= 1 then return end
    s = love.graphics.getHeight() / REF_H
    local dx, dy = px/s, py/s
    if C.screen == "items" then
      if C.held.mode == "drag" then
        local tside, bId = dropTarget(dx, dy)
        if tside then local ok, err = doTransfer(C.held.from, C.held.id, C.held.qty, tside, bId); if not ok then C.status = err end end
        C.held = nil
      elseif C.held.mode == "pending" then C.held.mode = "armed" end
    elseif C.screen == "party" then
      if C.held.mode == "drag" then
        local tgt = dropTargetMon(dx, dy)
        if tgt then local ok, err = doMonPlace(C.held.src, tgt); if not ok and err then C.status = err end end
        C.held = nil
      elseif C.held.mode == "pending" then C.held.mode = "armed" end
    end
  end
  C.drawScreen = function()
    if not C.screen or not (C.game and C.game.save) then return end
    local W, H = love.graphics.getDimensions()
    s = H / REF_H
    C.hit = {}
    local rmx, rmy = love.mouse.getPosition(); C.mx, C.my = rmx/s, rmy/s
    -- promote a pending press to a drag once the cursor moves past a threshold
    if C.held and C.held.mode == "pending" and love.mouse.isDown(1) then
      local ddx, ddy = C.mx - C.held.downX, C.my - C.held.downY
      if ddx*ddx + ddy*ddy > 196 then C.held.mode = "drag" end
    end
    -- live scrollbar drag: follow the cursor 1:1, clamped to valid range next frame in itemPanel
    if C.scrollDrag then
      if love.mouse.isDown(1) then
        local d = C.scrollDrag
        C.iscroll[d.side] = math.max(0, (d.startScroll or 0) + (C.my - d.startY))
      else
        C.scrollDrag = nil
      end
    end
    love.graphics.push("all")
    local ok, err = pcall(function()
      love.graphics.origin()
      setc({0,0,0}, 0.72); love.graphics.rectangle("fill", 0, 0, W, H)
      local fullW = W / s
      local M, G, headerH, footerH = 40, 26, 74, 56
      local maxW = 1180
      local isLandscape = (W / H) > 1.2
      local contentW
      if (C.screen == "items" or C.screen == "party") and isLandscape then
        contentW = fullW - 2*M   -- backpack / party, landscape: panels split the full width 50/50
      else
        contentW = math.min(fullW - 2*M, maxW)
      end
      local ox = (fullW - contentW) / 2      -- centre the whole layout
      local py = M + headerH
      local ph = REF_H - py - footerH - M
      local pw, x1, y1, x2, y2
      if isLandscape then
        pw = (contentW - G) / 2
        x1, y1 = ox, py
        x2, y2 = ox + pw + G, py
      else
        -- portrait: stack the two panels top/bottom (each full width) instead
        -- of squeezing them side by side into a narrow column each
        pw = contentW
        local panelH = (ph - G) / 2
        x1, y1 = ox, py
        x2, y2 = ox, py + panelH + G
        ph = panelH
      end
      txt(C.screen == "items" and "ITEMS      Bag  <->  PC"
                               or "POKEMON      Party  <->  Boxes", ox, M+16, 30, COL.gold)
      local cw = 44; local cx, cy = ox+contentW-cw, M+6
      local hovX = region(cx, cy, cw, cw, "close")
      setc(hovX and COL.lo or COL.panel, 0.95); rrect("fill", cx, cy, cw, cw, 10)
      setc(COL.border, 0.3); rrect("line", cx, cy, cw, cw, 10)
      txt("X", cx+cw/2, cy+7, 24, COL.text, "center")
      if C.screen == "items" then
        drawItemsPanels(x1, y1, x2, y2, pw, ph)
        if C.held then drawHeldItem() end
      else
        drawPartyPanels(x1, y1, x2, y2, pw, ph)
        if C.held then drawHeldMon() end
      end
      local hint = C.screen == "items"
        and "Drag across, or click then click the other side  -  wheel = qty / scroll  -  right-click cancels  -  Esc closes"
        or  "Drag a Pokemon onto a slot or box tab (onto an occupied slot = swap)  -  wheel / click a tab changes box  -  Esc closes"
      txt(C.status or hint, ox, REF_H - footerH + 8, 18, C.status and COL.mid or COL.dim)
    end)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end

  -- ---------------------------------------------------------------------
  -- Compose: draw everything, anchored to the window edges (widescreen).
  -- ---------------------------------------------------------------------
      C.drawToggleButton = function()
    if not (C.game and C.game.save) then return end
    local W, H = love.graphics.getDimensions()
    s = H / REF_H
    love.graphics.push("all")
    local ok, err = pcall(function()
      love.graphics.origin()
      -- Separate sizing for landscape vs portrait
      local isLandscape = (W / H) > 1.2
      local btnSize = math.floor(isLandscape and REF_H * 0.09 or REF_H * 0.055)  -- Landscape: ~130px, Portrait: ~79px
      local padding = 20  -- fixed padding
      local cx = (W / s) - (btnSize / 2) - padding  -- circle center x
      local cy = (H / s) - (btnSize / 2) - padding  -- circle center y
      local radius = btnSize / 2
      C.toggleBtn = { x = cx - radius, y = cy - radius, w = btnSize, h = btnSize }  -- store as square for hit detection
      local mx, my = love.mouse.getPosition()
      local hov = (mx >= (cx-radius)*s and mx <= (cx+radius)*s and my >= (cy-radius)*s and my <= (cy+radius)*s)

      -- Draw circular button background
      setc(COL.panel, 0.95); love.graphics.circle("fill", math.floor(cx*s), math.floor(cy*s), math.floor(radius*s))
      setc(hov and COL.gold or COL.border, hov and 0.9 or 0.35); love.graphics.setLineWidth(math.max(1, s)); 
      love.graphics.circle("line", math.floor(cx*s), math.floor(cy*s), math.floor(radius*s))

      -- Draw centered horizontal bar with color based on visibility state
      local barWidth = btnSize * 0.5
      local barHeight = btnSize * 0.15
      local barX = cx - (barWidth / 2)
      local barY = cy - (barHeight / 2)
      setc(C.visible and COL.lo or COL.hi, 1.0)
      rrect("fill", barX, barY, barWidth, barHeight, 3)
    end)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end

  C.drawBackpackButton = function()
    if not (C.game and C.game.save) then return end
    if not C.visible then return end  -- Only show when overlay is visible
    local W, H = love.graphics.getDimensions()
    s = H / REF_H
    love.graphics.push("all")
    local ok, err = pcall(function()
      love.graphics.origin()
      -- Separate sizing for landscape vs portrait
      local isLandscape = (W / H) > 1.2
      local btnSize = math.floor(isLandscape and REF_H * 0.09 or REF_H * 0.055)  -- Landscape: ~130px, Portrait: ~79px
      local padding = 20  -- fixed padding
      local cx = (W / s) - (btnSize / 2) - padding - btnSize - padding  -- next to toggle button
      local cy = (H / s) - (btnSize / 2) - padding  -- circle center y
      local radius = btnSize / 2
      C.backpackBtn = { x = cx - radius, y = cy - radius, w = btnSize, h = btnSize }
      local mx, my = love.mouse.getPosition()
      local hov = (mx >= (cx-radius)*s and mx <= (cx+radius)*s and my >= (cy-radius)*s and my <= (cy+radius)*s)

      -- Draw circular button background
      setc(COL.panel, 0.95); love.graphics.circle("fill", math.floor(cx*s), math.floor(cy*s), math.floor(radius*s))
      setc(hov and COL.gold or COL.border, hov and 0.9 or 0.35); love.graphics.setLineWidth(math.max(1, s)); 
      love.graphics.circle("line", math.floor(cx*s), math.floor(cy*s), math.floor(radius*s))

      -- Draw backpack icon: body, top flap, front pocket, shoulder straps
      local col = (C.screen == "items") and COL.lo or COL.hi
      local bw, bh = btnSize * 0.36, btnSize * 0.38
      local bx, by = cx - bw/2, cy - bh/2 + btnSize*0.03
      local flapW, flapH = bw * 0.82, bh * 0.28
      local fx, fy = cx - flapW/2, by - flapH*0.6
      -- shoulder straps (drawn first, sit behind the body)
      setc(col, 1.0); love.graphics.setLineWidth(math.max(2, bw*0.14*s))
      love.graphics.line((cx-bw*0.26)*s, (fy-btnSize*0.03)*s, (cx-bw*0.26)*s, (by+bh*0.12)*s)
      love.graphics.line((cx+bw*0.26)*s, (fy-btnSize*0.03)*s, (cx+bw*0.26)*s, (by+bh*0.12)*s)
      -- main body
      setc(col, 1.0); rrect("fill", bx, by, bw, bh, bw*0.24)
      -- top flap
      rrect("fill", fx, fy, flapW, flapH, flapW*0.3)
      -- front pocket (cut-out look)
      setc(COL.panel, 0.95)
      rrect("fill", bx + bw*0.2, by + bh*0.42, bw*0.6, bh*0.4, bw*0.14)
    end)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end

  C.drawPartyButton = function()
    if not (C.game and C.game.save) then return end
    if not C.visible then return end  -- Only show when overlay is visible
    local W, H = love.graphics.getDimensions()
    s = H / REF_H
    love.graphics.push("all")
    local ok, err = pcall(function()
      love.graphics.origin()
      -- Separate sizing for landscape vs portrait
      local isLandscape = (W / H) > 1.2
      local btnSize = math.floor(isLandscape and REF_H * 0.09 or REF_H * 0.055)  -- Landscape: ~130px, Portrait: ~79px
      local padding = 20  -- fixed padding
      local cx = (W / s) - (btnSize / 2) - padding - 2*(btnSize + padding)  -- one slot further left of the backpack button
      local cy = (H / s) - (btnSize / 2) - padding  -- circle center y
      local radius = btnSize / 2
      C.partyBtn = { x = cx - radius, y = cy - radius, w = btnSize, h = btnSize }
      local mx, my = love.mouse.getPosition()
      local hov = (mx >= (cx-radius)*s and mx <= (cx+radius)*s and my >= (cy-radius)*s and my <= (cy+radius)*s)

      -- Draw circular button background
      setc(COL.panel, 0.95); love.graphics.circle("fill", math.floor(cx*s), math.floor(cy*s), math.floor(radius*s))
      setc(hov and COL.gold or COL.border, hov and 0.9 or 0.35); love.graphics.setLineWidth(math.max(1, s));
      love.graphics.circle("line", math.floor(cx*s), math.floor(cy*s), math.floor(radius*s))

      -- Draw a Poke Ball icon: top/bottom halves, center band + button
      local ballR = btnSize * 0.19
      local active = (C.screen == "party")
      local topCol = active and COL.lo or COL.hi
      love.graphics.setScissor(math.floor((cx-ballR)*s), math.floor((cy-ballR)*s), math.ceil(ballR*2*s), math.ceil(ballR*s))
      setc(topCol, 1.0); love.graphics.circle("fill", math.floor(cx*s), math.floor(cy*s), math.floor(ballR*s))
      love.graphics.setScissor(math.floor((cx-ballR)*s), math.floor(cy*s), math.ceil(ballR*2*s), math.ceil(ballR*s))
      setc(COL.text, 1.0); love.graphics.circle("fill", math.floor(cx*s), math.floor(cy*s), math.floor(ballR*s))
      love.graphics.setScissor()
      setc(COL.border, 0.6); love.graphics.setLineWidth(math.max(1, s * 0.6))
      love.graphics.line(math.floor((cx-ballR)*s), math.floor(cy*s), math.floor((cx+ballR)*s), math.floor(cy*s))
      love.graphics.circle("line", math.floor(cx*s), math.floor(cy*s), math.floor(ballR*s))
      setc(COL.panel, 1.0); love.graphics.circle("fill", math.floor(cx*s), math.floor(cy*s), math.floor(ballR*0.38*s))
      setc(COL.border, 0.6); love.graphics.circle("line", math.floor(cx*s), math.floor(cy*s), math.floor(ballR*0.38*s))
    end)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end
  C.drawBackpackMenu = function()
    -- Backpack menu is disabled - causes graphics stack overflow
    -- TODO: Implement with separate rendering approach
  end

  local function pageDots(x, y, count, active, totalW)
    -- Indicator only -- navigation happens via swipe, so these are small and not tappable.
    local dotR, gap = 5, 12
    local rowW = count * (dotR * 2) + (count - 1) * gap
    local startX = x + math.max(0, (totalW - rowW) / 2)
    local padX, padY = 8, 5
    setc(COL.panel, 0.85)
    rrect("fill", startX - padX, y - padY, rowW + padX * 2, dotR * 2 + padY * 2, 8)
    for i = 1, count do
      local cx = startX + (i - 1) * (dotR * 2 + gap)
      setc(i == active and COL.gold or COL.dim, i == active and 1 or 0.8)
      rrect("fill", cx, y, dotR * 2, dotR * 2, dotR)
    end
    C.rightDots = { count = count }   -- swipe handler still needs to know the page count
    return dotR * 2 + padY * 2
  end

  C.drawOverlay = function()
    C.rightDots = nil
    if not C.visible or C.screen then return end
    if menuOpen() then return end
    local st = C.state
    if not st or not st.active then return end
    if not (st.party and #st.party > 0) then return end
    local W, H = love.graphics.getDimensions()
    s = H / REF_H
    love.graphics.push("all")
    local ok, err = pcall(function()
      love.graphics.origin()
      local margin = 28
      local isLandscape = (W / H) > 1.2
      local designW = W / s

      if not isLandscape and st.battle then
        -- PORTRAIT BATTLE: 3-page carousel (Battle/Items/Party) instead of a
        -- fixed stack -- stacking Battle+Items always left a chunk of unused
        -- space above the controls, and hid Party entirely. One full-width
        -- page at a time uses the space better, and brings Party (with the
        -- bench-effectiveness colors, useful mid-fight) back within reach.
        local pw = math.max(320, designW - margin*2)
        local pages = { "battle", "items", "party" }
        C.rightPage = C.rightPage or 1
        if C.rightPage < 1 or C.rightPage > #pages then C.rightPage = 1 end
        local kind = pages[C.rightPage]
        local ph
        if kind == "battle" then ph = battle(st, margin, margin, nil)
        elseif kind == "items" then ph = items(st, margin, margin, pw)
        elseif kind == "party" then ph = party(st, margin, margin, 3, pw) end
        pageDots(margin, margin + (ph or 0) + 16, #pages, C.rightPage, pw)
        return
      end

      if not isLandscape and not st.battle then
        -- PORTRAIT EXPLORATION: same narrow-screen problem as battle above,
        -- but with 4 things that used to fight for the same space (Party,
        -- Trainer, Items, Route). Carousel instead: one full-width panel at a
        -- time, bigger tappable dots since this is the primary portrait view.
        -- Supports swipe gestures left/right to change pages.
        local pw = math.max(320, designW - margin*2)
        local pages = { "party", "trainer", "items", "route" }
        C.rightPage = C.rightPage or 1
        if C.rightPage < 1 or C.rightPage > #pages then C.rightPage = 1 end
        local kind = pages[C.rightPage]
        local ph
        if kind == "party" then ph = party(st, margin, margin, 2, pw)
        elseif kind == "trainer" then ph = trainer(st, margin, margin, pw)
        elseif kind == "items" then ph = items(st, margin, margin, pw)
        elseif kind == "route" then ph = route(st, margin, margin, pw) end
        -- Position dots below the panel with some spacing to avoid obstruction
        pageDots(margin, margin + (ph or 0) + 20, #pages, C.rightPage, pw)
        return
      end

      -- Left and right panels are 26% of screen width each, with the center 48%
      -- left clear so the player's character (always centered on the wide
      -- overworld view) never sits behind a panel. Left side for Party,
      -- right side for Trainer/Route (or Battle/Items in a fight).
      -- Floor keeps columns readable near the landscape cutoff.
      --
      -- Each column is also height-capped to the top 3/4 of the screen (design
      -- space is always REF_H tall, so that's a fixed cutoff) -- the bottom
      -- quarter is where the on-screen D-pad / A-B / Select-Start touch
      -- controls live, and panels must stay clear of them instead of drawing
      -- underneath. A scissor clip enforces the cap even if a panel's content
      -- would otherwise run long.
      local colW = math.max(320, designW * 0.26 - margin * 1.5)
      local lx = margin
      local rx = designW - margin - colW
      local ry = margin
      local maxColH = REF_H * 0.75 - margin   -- bottom quarter reserved for touch controls

      local function clip(x, y, w, h)
        love.graphics.setScissor(math.floor(x * s), math.floor(y * s), math.ceil(w * s), math.ceil(h * s))
      end
      local function unclip() love.graphics.setScissor() end

      clip(lx, margin, colW, maxColH)
      party(st, lx, margin, 3, colW)
      unclip()

      if st.battle then
        -- BATTLE: paginate Battle/Items with tappable dots (space is tight)
        local pages = { "battle", "items" }
        C.rightPage = C.rightPage or 1
        if C.rightPage < 1 or C.rightPage > #pages then C.rightPage = 1 end
        local kind = pages[C.rightPage]
        clip(rx, ry, colW, maxColH)
        local ph = (kind == "battle") and battle(st, rx, ry, nil, colW) or items(st, rx, ry, colW)
        unclip()
        local dotsY = math.min(ry + (ph or 0) + 10, margin + maxColH - 40)
        pageDots(rx, dotsY, #pages, C.rightPage, colW)
      else
        -- EXPLORATION: Trainer + Spawns always both visible, no Items, no pagination
        clip(rx, ry, colW, maxColH)
        local th = trainer(st, rx, ry, colW)
        route(st, rx, ry + th + 22, colW)
        unclip()
      end
    end)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end



  -- ---------------------------------------------------------------------
  -- Hooks (guarded so hot-reload doesn't double-wrap)
  -- ---------------------------------------------------------------------
  if not C.wrappedUpdate and C.game and C.game.update then
    C.origUpdate = C.game.update
    C.game.update = function(self, dt)
      C.origUpdate(self, dt)
      local c = _G.__KANTO_INGAME; if c and c.onFrame then pcall(c.onFrame, dt) end
    end
    C.wrappedUpdate = true
  end
  if not C.wrappedDraw then
    C.origDraw = love.draw
    love.draw = function(...)
      if C.origDraw then C.origDraw(...) end
      local c = _G.__KANTO_INGAME
      if c and c.drawOverlay then
        local ok, err = pcall(c.drawOverlay)
        if not ok and err ~= c.drawErr then c.drawErr = err; mod.log:error("kanto_ingame draw: %s", tostring(err)) end
      end
      if c and c.drawToggleButton then
        local ok, err = pcall(c.drawToggleButton)
        if not ok and err ~= c.toggleErr then c.toggleErr = err; mod.log:error("kanto_ingame toggle: %s", tostring(err)) end
      end
      if c and c.drawBackpackButton then
        local ok, err = pcall(c.drawBackpackButton)
        if not ok and err ~= c.backpackErr then c.backpackErr = err; mod.log:error("kanto_ingame backpack: %s", tostring(err)) end
      end
      if c and c.drawPartyButton then
        local ok, err = pcall(c.drawPartyButton)
        if not ok and err ~= c.partyBtnErr then c.partyBtnErr = err; mod.log:error("kanto_ingame party button: %s", tostring(err)) end
      end
      if c and c.drawBackpackMenu then
        -- Disabled - causes graphics stack overflow
        -- local ok, err = pcall(c.drawBackpackMenu)
        -- if not ok and err ~= c.menuErr then c.menuErr = err; mod.log:error("kanto_ingame menu: %s", tostring(err)) end
      end
      if c and c.screen and c.drawScreen then
        local ok, err = pcall(c.drawScreen)
        if not ok and err ~= c.screenErr then c.screenErr = err; mod.log:error("kanto_ingame screen: %s", tostring(err)) end
      end
    end
    C.wrappedDraw = true
  end
  -- Global keybinds removed (Android-only fork, no physical keyboard) --
  -- overlay visibility and screen-opening are handled by the on-screen
  -- toggle/backpack/party buttons instead. See onScreenKey for the one
  -- remaining key check (escape / Android back button, while a screen is open).
  if not C.wrappedMouse then
    C.origMousepressed = love.mousepressed
    love.mousepressed = function(x, y, button, ...)
      local c = _G.__KANTO_INGAME
      if c and c.screen and c.onScreenMouse then pcall(c.onScreenMouse, x, y, button); return end
      -- Store swipe start position for carousel navigation
      if c and button == 1 then
        local s2 = love.graphics.getHeight() / REF_H
        c.swipeStartX = x / s2
        c.swipeStartY = y / s2
        c.swipeStartTime = love.timer.getTime()
      end
      -- toggle button click (when no screen is open)
      if c and c.toggleBtn and button == 1 then
        local s2 = love.graphics.getHeight() / REF_H
        local dx, dy = x/s2, y/s2
        local b = c.toggleBtn
        if dx >= b.x and dx <= b.x+b.w and dy >= b.y and dy <= b.y+b.h then
          c.visible = not c.visible
          return
        end
      end
      -- backpack button click (open backpack/PC menu)
      if c and c.backpackBtn and button == 1 then
        local s2 = love.graphics.getHeight() / REF_H
        local dx, dy = x/s2, y/s2
        local b = c.backpackBtn
        if dx >= b.x and dx <= b.x+b.w and dy >= b.y and dy <= b.y+b.h then
          if c.screen == "items" then
            if c.closeScreen then c.closeScreen() end
          elseif c.openScreen then
            c.openScreen("items")
          end
          return
        end
      end
      -- party button click (open active Pokemon <-> PC boxes menu)
      if c and c.partyBtn and button == 1 then
        local s2 = love.graphics.getHeight() / REF_H
        local dx, dy = x/s2, y/s2
        local b = c.partyBtn
        if dx >= b.x and dx <= b.x+b.w and dy >= b.y and dy <= b.y+b.h then
          if c.screen == "party" then
            if c.closeScreen then c.closeScreen() end
          elseif c.openScreen then
            c.openScreen("party")
          end
          return
        end
      end
      if C.origMousepressed then return C.origMousepressed(x, y, button, ...) end
    end
    C.origMousereleased = love.mousereleased
    love.mousereleased = function(x, y, button, ...)
      local c = _G.__KANTO_INGAME
      if c and c.screen then if c.onScreenRelease then pcall(c.onScreenRelease, x, y, button) end; return end
      -- Handle swipe gesture for carousel navigation
      if c and button == 1 and c.swipeStartX then
        local s2 = love.graphics.getHeight() / REF_H
        local endX = x / s2
        local deltaX = endX - c.swipeStartX
        local deltaTime = love.timer.getTime() - (c.swipeStartTime or 0)
        -- Swipe threshold: 40+ pixels or fast flick (< 0.3 seconds)
        local minSwipeDist = 40
        if math.abs(deltaX) >= minSwipeDist and deltaTime < 0.5 then
          if c.rightPage and c.rightDots then
            if deltaX > 0 then
              -- Swipe right: go to previous page
              c.rightPage = math.max(1, c.rightPage - 1)
            else
              -- Swipe left: go to next page
              c.rightPage = math.min(c.rightDots.count, c.rightPage + 1)
            end
          end
        end
        c.swipeStartX = nil
        c.swipeStartY = nil
        c.swipeStartTime = nil
      end
      if C.origMousereleased then return C.origMousereleased(x, y, button, ...) end
    end
    C.wrappedMouse = true
  end

  mod.log:info("kanto_companion: overlay=o  items=i  party=p")
end
