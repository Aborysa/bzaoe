local rx = require("rx")



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


local function getBuildTree(odf)
  -- looks at the odf file of the handle to get a list of odfs
  local list = {default={}}
  local isEmpty = true
  --local odf = OpenODF(GetOdf(handle))
  for i=1, 20 do
    list.default[i] = GetODFString(odf, "ProducerClass", ("buildItem%d"):format(i))
    isEmpty = isEmpty and list.default[i]==nil
  end
  if GetODFString(odf, "GameObjectClass", "classLabel") == "armory" then
    local extraLists = {"cannon", "rocket", "mortar", "special"}
    for _, l in ipairs(extraLists) do
      list[l] = {}
      for i=1, 20 do
        list[l][i] = GetODFString(odf, "ArmoryClass", ("%sItem%d"):format(l,i))
        isEmpty = isEmpty and list[l][i]==nil
      end
    end
  end
  return list, isEmpty
end




-- get build tree of all producers 
local function getRecursiveBuildTree(odf)
  local ret = {}
  local bTree, empty = getBuildTree(odf)
  if not empty then
    for i, v in pairs(bTree.default) do
      local sub, e = getRecursiveBuildTree(OpenODF(v))
      ret[i] = {
        odf = v,
        list = not e and sub
      }
    end
  end
  return ret, empty
end


-- maps odf1 to odf2
local function getUpgradeTable(t1, t2)
  --local tree1 = getRecursiveBuildTree(odf1)
  --local tree2 = getRecursiveBuildTree(odf2)
  local buildTable = {}
  for i, item in pairs(t1) do
    if item.list then
      local subTable = getUpgradeTable(item.list, t2[i].list)
      for o1, o2 in pairs(subTable) do
        buildTable[o1] = o2
      end
    end
    buildTable[item.odf] = t2[i].odf
  end
  return buildTable
end


local function canBeUpgraded(handle)
  return 
    (not IsBusy(handle)) and 
    (playerScavs[handle]==nil or playerScavs[handle].scrap <= 0 and playerScavs[handle].grace <= 0) and
    (GetClassLabel(handle)~="apc" or GetCurrentCommand(handle) ~= AiCommand["GET_RELOAD"])
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
  receive = receive,
  getBuildTree = getBuildTree,
  getRecursiveBuildTree = getRecursiveBuildTree,
  getUpgradeTable = getUpgradeTable,
  canBeUpgraded = canBeUpgraded
}