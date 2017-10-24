local rx = require("rx")


local _unpack = unpack
local _GetOdf = GetOdf
local _GetPilotClass = GetPilotClass
local _GetWeaponClass = GetWeaponClass
local _BuildObject = BuildObject
local _OpenODF = OpenODF
local _RemoveObject = RemoveObject


function RemoveObject(handle)
  print("Removing", GetOdf(handle), handle)
  Send(0, "R", handle)
  _RemoveObject(handle)
end


local function receive(from, t, ...)
  if t == "R" then
    _RemoveObject(...)
  end
end

local _openOdfs = setmetatable({},{__mode="v"})
-- Rewrite to cache odf files, they will be auto discarded as they're no logner referenced
OpenODF = function(odf)
  if _openOdfs[odf] == nil then
    _openOdfs[odf] = _OpenODF(odf)
  end
  return _openOdfs[odf]
end



if IsNetGame() then
  BuildObject = function(...)
    local h = _BuildObject(...)
    SetLocal(h)
    return h
  end
end
BuildLocal = function(...)
  return _BuildObject(...)
end
GetOdf = function(...)
  return (_GetOdf(...) or ""):gmatch("[^%c]*")()
end
GetPilotClass = function(...)
  return (_GetPilotClass(...) or ""):gmatch("[^%c]*")()
end
GetWeaponClass = function(...)
  return (_GetWeaponClass(...) or ""):gmatch("[^%c]*")()
end
table.pack = function(...)
  local l = select("#", ...)
  return setmetatable({
    __n = l,
    ...
  }, {
    __len = function()
      return l
    end
  })
end
unpack = function(t, ...)
  if (t.__n ~= nil) then
    return _unpack(t, 1, t.__n)
  end
  return _unpack(t, ...)
end

local rHandles = {}

local function onReplace(h)
  if not rHandles[h] then
    rHandles[h] = rx.Subject.create()
  end
  return rHandles[h]
end

local replaceHandles

replaceHandles = function(h1, h2)
  if rHandles[h1] then
    rHandles[h1]:onNext(h2, h1)
    onReplace(h2):subscribe(function(new, old)
      replaceHandles(old, new)
    end)
  end
end

local copyData = function(handle, odf, team, location, keepWeapons, kill, fraction)
  if keepWeapons == nil then
    keepWeapons = false
  end
  if kill == nil then
    kill = false
  end
  if fraction == nil then
    fraction = true
  end
  local loc = location ~= nil and location or GetTransform(handle)
  odf = odf ~= nil and odf or GetOdf(handle)
  team = team ~= nil and team or GetTeamNum(handle)
 
  weapons = {
    GetWeaponClass(handle, 0),
    GetWeaponClass(handle, 1),
    GetWeaponClass(handle, 2),
    GetWeaponClass(handle, 3),
    GetWeaponClass(handle, 4)
  }

  return {
    handle = handle,
    location = loc,
    team = team,
    kill = kill,
    keepWeapons = keepWeapons,
    alive = IsAlive(handle),
    pilot = GetPilotClass(handle),
    aliveAndPilot = IsAliveAndPilot(handle),
    health = fraction and GetHealth(handle) or GetCurHealth(handle),
    ammo = fraction and GetAmmo(handle) or GetCurAmmo(handle),
    fraction = fraction,
    omega = GetOmega(handle),
    deployed = IsDeployed(handle),
    independence = GetIndependence(handle),
    weapons = weapons,
    owner = GetOwner(handle),
    velocity = GetVelocity(handle),
    odf = odf
  }
end

local spawnByData = function(data)
  local nObject = BuildObject(data.odf, data.team, data.location)
  SetTransform(nObject, data.location)
  if (data.aliveAndPilot) then
    SetPilotClass(nObject, data.pilot)
  elseif ((not data.alive) and data.kill) then
    RemovePilot(nObject)
  end
  SetCurHealth(nObject, data.fraction and data.health*GetMaxHealth(nObject) or data.health)
  SetCurAmmo(nObject, data.fraction and data.ammo*GetMaxAmmo(nObject) or data.ammo)
  SetVelocity(nObject, data.velocity)
  SetOmega(nObject, data.omega)
  if data.deployed then
    Deploy(nObject)
  end
  SetIndependence(nObject, data.independence)
  if data.keepWeapons then
    for i, v in pairs(data.weapons) do
      GiveWeapon(nObject, v, i - 1)
    end
  end
  SetOwner(nObject, data.owner)
  return nObject
end

local copyObject = function(...)
  return spawnByData(copyData(...))
end

local replaceByData = function(data)
  local h = spawnByData(data)
  replaceHandles(h, data.handle)
  RemoveObject(data.handle)
  SetTeamNum(h,0)
  SetTeamNum(h,data.team)
  return h
end



local function createNavMenu(team,...)
  local names = {...}
  local ret = {}
  local oldNavs = {}
  -- go trough the nav slots
  for i=TeamSlot.MIN_BEACON, TeamSlot.MAX_BEACON do
    local nav = GetTeamSlot(i, team)
    if IsValid(nav) then
      SetTeamNum(nav,0)
      table.insert(oldNavs, nav)
    end
  end
  for i, v in ipairs(names) do
    local b = BuildObject("apcamr", team, SetVector(0,0,0))
    table.insert(ret, b)
    SetObjectiveName(b, v)
  end
  for i,v in ipairs(oldNavs) do
    SetTeamNum(v, team)
  end
  return ret, oldNavs
end

-- only one nav menu at any time
local navMenu
navMenu = {
  create = function(handle, ...)
    --creats a nav menu attached to handle
    local navs, old = createNavMenu(GetTeamNum(handle), ...)
    local inst = setmetatable({
      handle = handle,
      team = GetTeamNum(handle),
      navs = {},
      old = old,
      dead = false,
      subject = rx.Subject.create(),
      subs = {}
    }, {__index = navMenu})

    for i, v in pairs(navs) do
      inst.navs[v] = i
      table.insert(inst.subs,onReplace(v):subscribe(function(new, old)
        print("Nav replaced!", new, old)
        inst.navs[new] = inst.navs[old]
        inst.navs[old] = nil
      end))
    end
    return inst
  end,
  update = function(self)
    if not self.dead then
      local who = GetCurrentWho(self.handle)
      for i, v in pairs(self.navs) do
        if who == i then
          self.subject:onNext(v)
          Stop(self.handle, 0)
          break
        end
      end
      if not IsSelected(self.handle) then
        --remove menu
        self:remove()
      end
    end
  end,
  onItemSelect = function(self)
    return self.subject
  end,
  remove = function(self)
    for i, v in pairs(self.subs) do
      v:unsubscribe()
    end
    for i, v in pairs(self.navs) do
      RemoveObject(i)
    end
    for i, v in ipairs(self.old) do
      SetTeamNum(v, 15)
      SetTeamNum(v, self.team)
    end
    self.dead = true
    self.subject:onCompleted()
  end
}







return {
  copyData = copyData,
  spawnByData = spawnByData,
  copyObject = copyObject,
  navMenu = navMenu,
  onReplace = onReplace,
  replaceByData = replaceByData,
  replaceHandles = replaceHandles,
  receive = receive
}