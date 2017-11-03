local bzutils = require("bzutils")



local createClass = bzutils.utils.createClass
local UnitComponent = bzutils.component.UnitComponent
local ComponentConfig = bzutils.component.ComponentConfig

local Handle = bzutils.bz_handle.Handle

local Satellite = createClass("aoe.Satellite", {
  new = function(self, ...)

  end,
  update = function(self, dtime)

  end
}, UnitComponent)

ComponentConfig(HeavyTurret, {
  componentName = "Satellite"
})



return Satellite