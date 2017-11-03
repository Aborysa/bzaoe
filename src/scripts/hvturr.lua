local bzutils = require("bzutils")



local createClass = bzutils.utils.createClass
local UnitComponent = bzutils.component.UnitComponent
local ComponentConfig = bzutils.component.ComponentConfig

local Handle = bzutils.bz_handle.Handle

local HeavyTurret = createClass("aoe.HeavyTurret", {
  new = function(self, ...)
    self:super("__init", ...)
    print("const")
    self.ct = self:getHandle():getTarget()
    self.checkCooldown = 0
    self.slot5 = self:getHandle():getWeaponClass(4)
    self.altWep = self:getHandle():getProperty("AoE_Turret", "altWep", self.slot5)
    self:getHandle():setWeaponMask(16)
  end,
  update = function(self, dtime)
    local h = self:getHandle()
    local nt = h:getCurrentWho() or h:getTarget()
    self.checkCooldown = self.checkCooldown - dtime
    if self.checkCooldown <= 0 and ((not IsValid(nt)) or (GetTime() - GetLastEnemyShot(nt)) > 5) then
      -- look for new target if it is long since we last shot at something
      local potential_targets = {}
      for v in ObjectsInRange(200, h.handle) do
        local h2 = Handle(v)
        if nt~=v and not IsFriend(h:getTeamNum(), GetTeamNum(v)) then
          print(h2:getOdf(),h2:getDps())
          table.insert(potential_targets,{
            h = v,
            p = h2:isPerson(),
            d = h:getDistance(v),
            dps = h2:getDps()
          })
        end
      end
      table.sort(potential_targets, function(a, b)
        return (b==nil and a~=nil) or (a.p and not b.p) or a.dps > b.dps or a.d < b.d
      end)
      nt = (potential_targets[1] or {}).h
      if IsValid(nt) then
        print("Attack!", GetOdf(nt))
        h:attack(nt)
      elseif(h:getCurrentCommand() ~= AiCommand["DEFEND"]) then
        h:defend(0)
      end
      self.checkCooldown = 1
    end
    if not IsValid(nt) then
      h:fireAt(nt)
    end
    if self.ct ~= nt then
      self.checkCooldown = 1
      print("Who", GetOdf(nt))
      if IsPerson(nt) then
        h:giveWeapon(self.altWep, 4)
        h:setWeaponMask(16)
      elseif IsValid(nt) then
        h:giveWeapon(self.slot5, 4)
        h:setWeaponMask(31)
      else
        h:giveWeapon(self.slot5, 4)
        h:setWeaponMask(16)
      end
    end
    self.ct = nt
  end
}, UnitComponent)

ComponentConfig(HeavyTurret, {
  componentName = "HeavyTurret"
})

--componentManager:useClass(HeavyTurret)


return HeavyTurret