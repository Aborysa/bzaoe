
-- helper functions nothing important
print("AoE!")
-- should move all these function to another file

local misc = require("aoe_misc")



local copyData = misc.copyData
local spawnByData = misc.spawnByData
local copyObject = misc.copyObject
local navMenu = misc.navMenu
local replaceByData = misc.replaceByData
local replaceHandles = misc.replaceHandles
local getBuildTree = misc.getBuildTree
local getRecursiveBuildTree = misc.getRecursiveBuildTree
local getUpgradeTable = misc.getUpgradeTable
local canBeUpgraded = misc.canBeUpgraded
local checkIfCanBuild = misc.checkIfCanBuild


-- the players units
local units = {}
local unitsByOdf = {}
-- terminate the producer trying to build something illegal
local terminateNext = {}
-- armory page
local armoryPage = "default"


local waitForPlayers = {}
local remotePlayers = {}
local localPlayer = nil
local playerCount = 0
local lastPlayer = nil
local checkLater = {}
local removeOnNext = {}
local upgradeOnNext = {}
local ready = false
local readyTime = -1
local currentNavMenu = nil


-- We have to keep track of how much scrap the scavs have
-- in order to be able to guess when they're empty
local playerScavs = setmetatable({}, {__mode = "k"})


-- list of upgrades that are in progress, one upgrade has to finish before you can complete the next one
-- APCs and Scavs will have to drop off\refil their scrap\pilot hold before upgrading
local delayedUpgradeTable = {}



local function recalcPilotHold()
  if localPlayer == nil then return end
  local pilots = GetMaxPilot(localPlayer.team)
  for i, v in pairs(units) do
    local pilot = GetPilotClass(i)
    if pilot and GetPlayerHandle() ~= i and IsAliveAndPilot(i) then
      pilots = pilots - GetODFInt(OpenODF(pilot),"GameObjectClass", "pilotCost")
    end
  end
  SetPilot(localPlayer.team, pilots)
end










local function PerformUpgrade()
  local recy = GetRecyclerHandle()
  -- you should probably lose if your recycler is dead
  print("Upgrade!")
  if IsAlive(recy) then

    --Making sure the player has enough scrap hold to not lose scrap or pilots
    --this also prevents betty from complaining about "no scrap" and "no pilots"
    AddMaxScrap(localPlayer.team,1000)
    AddMaxPilot(localPlayer.team,1000)
    local odf = OpenODF(GetOdf(recy))
    local odfUp = GetODFString(odf, "AoE_Upgrade", "nextRecy")
    local upName = GetODFString(odf, "AoE_Upgrade", "nextName")
    local nOdf = OpenODF(odfUp)
    
    --first we have to build an upgrade table by searching the producer's build list
    local buildTree1 = getRecursiveBuildTree(odf)
    local buildTree2 = getRecursiveBuildTree(nOdf)
    local upTable = getUpgradeTable(buildTree1, buildTree2)
    print("Recycler upgrade", GetOdf(recy), odfUp)
    upTable[GetOdf(recy)] = odfUp
    -- Bzone Lord code here ^^
    -- you need to go trough every unit that is on the players team using the table 'units'
    -- then you have to replace each unit by the upgraded counter part, 'upTable' contains the odf map

    local upgradeDataTable = {}

    for odf1, odf2 in pairs(upTable) do
      for handle, i in pairs(unitsByOdf[odf1] or {}) do
        if IsValid(handle) then
          --upgradeOnNext[handle] = copyData(handle, odf2)
          table.insert(upgradeDataTable, copyData(handle, odf2))
        end
      end
    end

    for i,v in pairs(upgradeDataTable) do
      --if canBeUpgraded(v.handle) then
        --Stop(v.handle, 1)
        --Doing this to move unit out of team slot
        --SetTeamNum(v.handle, 0)
        --local n = spawnByData(v)
        --replaceHandles(v.handle, n)
        --removeOnNext[v.handle] = true
      --else
        -- add to list of later to be upgraded
        delayedUpgradeTable[v.handle] = v.odf
      --end
    end
    
    SetMaxScrap(localPlayer.team,GetMaxScrap(localPlayer.team) - 1000)
    SetMaxPilot(localPlayer.team,GetMaxPilot(localPlayer.team) - 1000)
    print(("%s entered the %s"):format(localPlayer.name, upName))
    if IsNetGame() then
      DisplayMessage(("%s entered the %s"):format(localPlayer.name, upName))
      -- tell other players that I upgraded from X to Y
      Send(0, "U", upName)
    end
  end

end





local function _checkAddHandle(handle)
  if not IsRemote(handle) and GetTeamNum(handle) == localPlayer.team then
    -- might want to store some additional info later on
    local odfName = GetOdf(handle)
    if unitsByOdf[odfName] == nil then unitsByOdf[odfName] = setmetatable({},{__mode="v"}) end
    unitsByOdf[odfName][handle] = true 
    -- check if the player has the correct upgrades or else remove the unit and return the scrap
    local odf = OpenODF(odfName)
    units[handle] = {odf=odfName,odfFile = odf}
      
    if GetClassLabel(handle) == "recycler" then
      relicOdf = GetODFString(odf, "AoE_Upgrade", "upgradeRelic")
    end
    
    if GetClassLabel(handle) == "scavenger" then
      playerScavs[handle] = {
        scrap = 0,
        ptarget = nil,
        scrapHold = GetODFInt(odf, "ScavengerClass", "maxScrap"),
        grace = 0
      }
    end
    if odfName == relicOdf then
      RemoveObject(handle)
      PerformUpgrade()
    end
  end
  recalcPilotHold()
end


function Start()
  print("Start")
  -- only host is in game ;-;
  for v in AllObjects() do
    AddObject(v)
  end
  if playerCount <= 1 then
    localPlayer = lastPlayer or {id=0,team=GetTeamNum(GetPlayerHandle()),name="Player"}
    ready = true
    onNetworkReady()  
  else
    DisplayMessage("Please wait for network systems...")
  end
end

-- Is called when we have our own local id
function onNetworkReady()
  print("Network ready", localPlayer.name, localPlayer.id)
  if IsNetGame() then
    DisplayMessage("Network is set up!")
    DisplayMessage(("You're %s %d"):format(localPlayer.name, localPlayer.id))
  end
  AddMaxScrap(localPlayer.team,1000)
  AddMaxPilot(localPlayer.team,1000)

  local recy = GetRecyclerHandle()
  if GetOdf(recy) ~= "1vrecy" then
    replaceByData(copyData(recy, "1vrecy"))
  end

  SetMaxScrap(localPlayer.team,GetMaxScrap(localPlayer.team) - 1000)
  SetMaxPilot(localPlayer.team,GetMaxPilot(localPlayer.team) - 1000)
end

local i=false
local init = function()
  --PerformUpgrade()
  i = true
end




function Update(dtime)
  -- wait for network to be ready
  if not ready then 
    SetVelocity(GetPlayerHandle(), SetVector(0,0,0))
    SetOmega(GetPlayerHandle(), SetVector(0,0,0))
    SetVelocity(GetRecyclerHandle(), SetVector(0,0,0))
    SetOmega(GetRecyclerHandle(), SetVector(0,0,0))
    if readyTime > 0 then
      readyTime = readyTime - dtime
      if readyTime <= 0 then
        ready = true
        onNetworkReady()
      end
    end
    return
  end
  if currentNavMenu ~= nil then currentNavMenu:update() end
  
  -- track scavenger scrap hold, will need one for APCs aswell
  for scav, d in pairs(playerScavs) do
    local ctarget = GetTarget(scav)
    d.grace = d.grace - dtime
    if IsValid(ctarget) and ctarget ~= d.ptarget then
      d.scrap = d.scrap + 1
    elseif(d.scrap >= d.scrapHold) then
      if GetDistance(scav, GetRecyclerHandle()) <= 55 then
        d.scrap = 0
        d.grace = 3
      end
      for i=TeamSlot.MIN_SILO, TeamSlot.MAX_SILO do
        local class = GetClassLabel(closestObj)
        if GetDistance(scav, GetTeamSlot(i)) <= 55 then
          d.scrap = 0
          d.grace = 3
        end
      end
      --local closestObj = GetNearestObject(scav)

    end
    d.ptarget = ctarget
  end

  local const = GetConstructorHandle()
  if IsSelected(const) and currentNavMenu==nil then
    local odf = OpenODF(GetOdf(const))
    local menuOptions = {}
    local odfSelection = {}

    
    for i=1, 10 do
      local const = GetODFString(odf, "AoE_Builder", ("constOdf%d"):format(i))
      local name = GetODFString(odf, "AoE_Builder", ("constName%d"):format(i))
      if const and name then
        table.insert(odfSelection, const)
        table.insert(menuOptions, name)
      else
        break
      end
    end

    currentNavMenu = navMenu.create(const, unpack(menuOptions))
    currentNavMenu:onItemSelect():subscribe(function(index)
      local o = odfSelection[index]
      print("Selecting", menuOptions[index])
      if GetOdf(const) ~= o then
        replaceByData(copyData(const, o))
      end
    end,nil,function()
      print("Complete!")
      currentNavMenu = nil
    end)
  end




  for i, v in pairs(removeOnNext) do
    RemoveObject(i)
    removeOnNext[i] = nil
    break
  end
  
  for i, v in pairs(checkLater) do
    _checkAddHandle(i)  
  end
  checkLater = {}
  if not i then
    init()
  end
  for i, v in pairs(terminateNext) do
    local cm = GetCurrentCommand(i)
    if IsBusy(i) or cm == AiCommand["NO_DROPOFF"] then
      Stop(i, 0)
      terminateNext[i] = nil
    elseif cm == AiCommand["BUILD"] then
      SetCommand(i, AiCommand["NO_DROPOFF"],1)
    end
  end

  for i, v in pairs(delayedUpgradeTable) do
    if canBeUpgraded(i, playerScavs) then
      AddMaxScrap(localPlayer.team,1000)
      AddMaxPilot(localPlayer.team,1000)

      print("Delayed upgrade!",i,v)
      
      local n = replaceByData(copyData(i, v))
      --Doing this to move unit out of team slot

      delayedUpgradeTable[i] = nil

      SetMaxScrap(localPlayer.team,GetMaxScrap(localPlayer.team) - 1000)
      SetMaxPilot(localPlayer.team,GetMaxPilot(localPlayer.team) - 1000)
    end
  end

end




-- all objects passed to this function should be local to the player
function AddObject(handle)
  -- double check if it is remote and if it is on the players team
  if localPlayer ~= nil then
    _checkAddHandle(handle)
  else
    checkLater[handle] = true
  end
end

function CreateObject(handle)
end


function DeleteObject(handle)
  local odf = units[handle] and units[handle].odf
  units[handle] = nil
  playerScavs[handle] = nil
  if odf and unitsByOdf[odf] then
    recalcPilotHold()
    unitsByOdf[odf][handle] = nil
  end
end




function GameKey(key)
  if localPlayer == nil then return end
  buildKey = key:match("Alt%+(%d)") or key:match("^(%d)") or key:match("Shift%+(%d)")
  
  if (key == "U") and not IsNetGame() then
    PerformUpgrade()
    return
  end
  if not IsSelected(GetArmoryHandle()) or key == "Tab" then
    armoryPage = "default"
  end
  if buildKey ~= nil and tonumber(buildKey) > 0 then
    kv = tonumber(buildKey)
    for v in SelectedObjects() do
      page = "default"
      if GetClassLabel(v) == "armory" and CanBuild(v) then
        page = armoryPage
        if page == "default" and kv >= 6 and kv <= 9 then
          armoryPage = ({"cannon", "rocket", "mortar", "special"})[kv-5]
          break
        end
      end
      local cb, item, req = checkIfCanBuild(v, kv, page, unitsByOdf)
      if not cb then
        print(("%s requires %s to be built"):format(item,req))
        if IsNetGame() then
          DisplayMessage(("%s requires %s to be built"):format(item,req))
        end
        terminateNext[v] = true
      end
    end
  end
end

-- networking stuff
function CreatePlayer(id, name, team)
  print("CreatePlayer", id, name, team)
  lastPlayer = {id = id, name = name, team = team}
  playerCount = playerCount + 1
end

function AddPlayer(id, name, team)
  remotePlayers[id] = {id=id,name=name,team=team}
  waitForPlayers[id] = true
  print("AddPlayer", id, name, team)
  Send(id, "P", id, name, team)
end


function DeletePlayer(id, name, team)
  remotePlayers[id] = nil
  waitForPlayers[id] = nil
  playerCount = playerCount - 1
end




function Receive(from, t, ...)
  print("Receive", from, t, ...)
  misc.receive(from, t, ...)
  if t == "P" then
    waitForPlayers[from] = nil
    if localPlayer == nil then
      id, name, team = ...
      readyTime = 15
      localPlayer = {id=id,name=name,team=team}
    end
    if not ready then
      local left = 0
      for i, v in pairs(waitForPlayers) do
        left = left + 1
      end
      DisplayMessage(("Connected to %d/%d"):format(playerCount-left-1, playerCount - 1))
      if left <= 0 then
        ready = true
        onNetworkReady()
      end
    end
  elseif t == "U" then
    local era = ...
    DisplayMessage(("%s entered the %s"):format((remotePlayers[from] or {name="Unknown"}).name, era))
  end
end