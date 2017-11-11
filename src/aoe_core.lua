local bzutils = require("bzutils")

local net = bzutils.net

local createClass = bzutils.utils.createClass
local HeavyTurret = require("hvturr")

local misc = require("misc")


local copyData = misc.copyData
local spawnByData = misc.spawnByData
local copyObject = misc.copyObject
local navMenu = misc.navMenu
local replaceByData = misc.replaceByData
local replaceHandles = misc.replaceHandles

local aoe_core = createClass("aoe.core", {
  new = function(self)
    self.checkLater = {}
    self.removeOnNext = {}
    self.upgradeOnNext = {}
    self.currentNavMenu = nil
    self.socket = nil
    self.playerScavs = setmetatable({}, {__mode = "k"})
    self.delayedUpgradeTable = {}
  end,
  recalcPilotHold = function(self)
    if self.localPlayer == nil then return end
    local pilots = GetMaxPilot(self.localPlayer.team)
    for i, v in pairs(self.units) do
      local pilot = GetPilotClass(i)
      if pilot and GetPlayerHandle() ~= i and IsAliveAndPilot(i) then
        pilots = pilots - GetODFInt(OpenODF(pilot),"GameObjectClass", "pilotCost")
      end
    end
    SetPilot(self.localPlayer.team, pilots)
  end,
  addObject = function()
  end,
  deleteObject = function()
  end,
  createObject = function()
  end,
  update = function()
  end,
  gameKey = function()
  end
}, bzutils.utils.module)