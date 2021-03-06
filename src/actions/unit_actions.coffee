{ countBy, filter, keys, merge, sample, sum, values } = require 'lodash'
{ roles } = require 'unit_roles'
{ rooms } = require 'rooms'
{ moveTo, goTo } = require 'paths'
{ upgradeTarget, harvestTarget, reserveTarget, repairTarget,
  fortifyTarget, buildTarget, collectTarget, transferTarget,
  flagTarget, claimTarget, resupplyTarget, refillTarget,
  healTarget, mineTarget } = require 'unit_targeting'
{ flags, flag_intents } = require 'flags'
{ units } = require 'units'

upgrade = (unit) ->
  unit.memory.target or= upgradeTarget unit
  controller = Game.getObjectById(unit.memory.target)
  if unit.upgradeController(controller) == ERR_NOT_IN_RANGE
    location = pos: controller.pos, range: 3
    goTo location, unit

harvest = (unit) ->
  unit.memory.target or= harvestTarget unit
  target = Game.getObjectById unit.memory.target
  if not target?
    unit.memory.target = harvestTarget unit
    target = Game.getObjectById unit.memory.target
  if not target?
    unit.memory.target = undefined
    return

  if unit.memory.inPosition
    if unit.memory.container?
      container = Game.getObjectById unit.memory.container
      if container? and container.store.getUsedCapacity() < container.store.getCapacity()
        unit.harvest target
      return
    unit.harvest target
    return

  # If there is a container by the source, sit on top of it, else sit next to the source
  containers = filter target.pos.findInRange(FIND_STRUCTURES, 1),
                      ((s) -> s.structureType is STRUCTURE_CONTAINER)
  if containers.length
    unit.memory.container = containers[0].id
    location = pos: containers[0].pos, range: 0
  else
    location = pos: target.pos, range: 1

  # Once we reach the target location we only have to harvest
  if unit.pos.inRangeTo(location.pos, location.range)
    unit.memory.inPosition = true
  else
    goTo location, unit

mine = (unit) ->
  unit.memory.target or= mineTarget unit
  target = Game.getObjectById unit.memory.target
  if not target?
    unit.memory.target = mineTarget unit
    target = Game.getObjectById unit.memory.target
  if not target?
    unit.memory.target = undefined
    return

  if unit.memory.inPosition
    if unit.memory.container?
      container = Game.getObjectById unit.memory.container
      if container.store.getUsedCapacity() < container.store.getCapacity()
        unit.harvest target
      return
    unit.harvest target
    return

  containers = filter target.pos.findInRange(FIND_STRUCTURES, 1),
                      (s) -> s.structureType is STRUCTURE_CONTAINER

  # If there is a container by the extractor, sit on top of it, else sit next to the source
  if containers.length
    location = pos: containers[0].pos, range: 0
    unit.memory.container = containers[0].id
  else
    location = pos: target.pos, range: 1

  # Once we reach the target location we only have to harvest
  if unit.pos.inRangeTo(location.pos, location.range)
    unit.memory.inPosition = true
  else
    goTo location, unit

transfer = (unit) ->
  unit.memory.transferTarget or= transferTarget unit
  target = Game.getObjectById(unit.memory.transferTarget)

  if not target? or not target.store? or target.store.getUsedCapacity() == target.store.getCapacity()
    unit.memory.transferTarget = transferTarget unit
    target = Game.getObjectById(unit.memory.transferTarget)

  if not target?
    return

  location = pos: target.pos, range: 1
  goTo location, unit

  if unit.pos.inRangeTo(target, 1)
    type = keys(unit.store)[0]
    if unit.transfer(target, type) is OK
      unit.memory.transferTarget = undefined
      return
      # Successfully transferred resources so start heading towards the next target
#     unit.memory.transferTarget = transferTarget unit
#     target = Game.getObjectById(unit.memory.transferTarget)


collect = (unit) ->
  unit.memory.collectTarget or= collectTarget unit
  target = Game.getObjectById(unit.memory.collectTarget)

  if not target?
    unit.memory.collectTarget = collectTarget unit
    target = Game.getObjectById(unit.memory.collectTarget)

  if not target?
    unit.memory.collectTarget = undefined
    return

  # How much does this unit need
  collectAmount = unit.store.getCapacity() - unit.store.getUsedCapacity()
  if target.amount?
    if target.amount < collectAmount
      unit.memory.collectTarget = undefined
      return
    leftOver = Math.max 0, (target.amount - collectAmount)
    target.amount = leftOver
  else
    if sum(target.store) < collectAmount
      unit.memory.collectTarget = undefined
      return
    for type in keys(target.store)
      leftOver = Math.max 0, (target.store[type] - collectAmount)
      collectAmount -= leftOver
      target.store[type] = leftOver

  location = pos: target.pos, range: 1
  goTo location, unit

  if unit.pos.inRangeTo(target, 1)
    if not target.store?
      result = unit.pickup(target)
    else
      type = keys(target.store)[0]
      result = unit.withdraw(target, type)
    if result is OK
      # Successfully collected resources so start heading towards the target we want to transfer them to
      unit.memory.collectTarget = undefined
      return
#     unit.memory.transferTarget = transferTarget unit
#     target = Game.getObjectById(unit.memory.transferTarget)
#     if not target?
#       return

build = (unit) ->
  if unit.memory.resupplyTarget?
    unit.memory.resupplyTarget = undefined
    unit.memory.buildTarget = buildTarget unit
    target = Game.getObjectById(unit.memory.buildTarget)

  unit.memory.buildTarget or= buildTarget unit
  target = Game.getObjectById(unit.memory.buildTarget)
  if not target? or not target.room?
    unit.memory.buildTarget = buildTarget unit
    target = Game.getObjectById(unit.memory.buildTarget)
    if not target?
      unit.memory.buildTarget = undefined
      return false

  # Move to and build the target
  if target.progress?
    unit.build target
  else
    if target.hits < target.hitsMax and target.hits < 10000
      unit.repair target
    else
      unit.memory.buildTarget = undefined

  location = pos: target.pos, range: 1
  goTo location, unit
  return true

repair = (unit) ->
  # If we have an existing target we should try to repair it
  # If the target no longer exists, find a new one
  # If we've already finished repairing it, choose another target
  if unit.memory.resupplyTarget?
    unit.memory.resupplyTarget = undefined
    unit.memory.repairTarget = repairTarget unit
    target = Game.getObjectById(unit.memory.repairTarget)

  unit.memory.repairTarget or= repairTarget unit
  target = Game.getObjectById(unit.memory.repairTarget)
  if not target? or not target.room? or target.hits >= target.hitsMax
    unit.memory.repairTarget = repairTarget unit
    target = Game.getObjectById(unit.memory.repairTarget)
  # Couldn't find a visible target
  if not target? or not target.room?
    return false
  # Move to and repair the target
  unit.repair target
  location = pos: target.pos, range: 1
  goTo location, unit
  return true

fortify = (unit) ->
  # If we have an existing target we should try to fortify it
  # If the target no longer exists, find a new one
  # If we've already finished fortifying it, choose another target
  if unit.memory.resupplyTarget?
    unit.memory.resupplyTarget = undefined
    unit.memory.fortifyTarget = fortifyTarget unit
    target = Game.getObjectById unit.memory.fortifyTarget

  unit.memory.fortifyTarget or= fortifyTarget unit
  target = Game.getObjectById unit.memory.fortifyTarget
  if not target? or not target.room? or target.hits >= target.hitsMax
    unit.memory.fortifyTarget = fortifyTarget unit
    target = Game.getObjectById unit.memory.fortifyTarget
    # Couldn't find a visible target
    if not target? or not target.room?
      unit.memory.fortifyTarget = undefined
      return false
  # Move to and fortify the target
  unit.repair(target)
  location = pos: target.pos, range: 1
  goTo location, unit
  return true

refillTower = (unit) ->
  unit.memory.refillTarget or= refillTarget unit
  target = Game.getObjectById(unit.memory.refillTarget)
  if not target? or target.store[RESOURCE_ENERGY] >= target.store.getCapacity(RESOURCE_ENERGY)
    unit.memory.refillTarget = refillTarget unit
    target = Game.getObjectById(unit.memory.refillTarget)
  if not target?
    return false
  if unit.transfer(target, RESOURCE_ENERGY) == ERR_NOT_IN_RANGE
    location = pos: target.pos, range: 1
    goTo location, unit
  return true

resupply = (unit) ->
  # If we have an existing target we should go there
  # If the target no longer exists, find a new one
  # If we've already finished resupplying, choose another target
  unit.memory.resupplyTarget or= resupplyTarget unit
  target = Game.getObjectById(unit.memory.resupplyTarget)
  if not target? or not target.store? or not target.amount?
    unit.memory.resupplyTarget = resupplyTarget unit
    target = Game.getObjectById(unit.memory.resupplyTarget)

  # Couldn't find a target
  if not target?
    return false

  # How much does this unit need
  resupplyAmount = unit.store.getCapacity() - unit.store.getUsedCapacity()
  if target.amount?
    if target.amount < resupplyAmount
      unit.memory.resupplyTarget = undefined
      return
    leftOver = Math.max 0, (target.amount - resupplyAmount)
    target.amount = leftOver
  else
    leftOver = Math.max 0, (target.store[RESOURCE_ENERGY] - resupplyAmount)
    resupplyAmount -= leftOver
    target.store[RESOURCE_ENERGY] = leftOver

  # Move to target resources and use them to resupply
  if unit.pickup(target) is OK or unit.withdraw(target, RESOURCE_ENERGY) is OK
    return true
  else
    location = pos: target.pos, range: 1
    goTo location, unit

reserve = (unit) ->
  unit.memory.target or= reserveTarget unit
  target = flags[unit.memory.target]
  if not target?
    unit.memory.target = reserveTarget unit
    target = flags[unit.memory.target]
  return if not target?
  room = rooms[target.pos.roomName]
  if not room?
    location = pos: target.pos, range: 1
    goTo location, unit
  else if unit.reserveController(room.controller) == ERR_NOT_IN_RANGE
    location = pos: room.controller.pos, range: 1
    goTo location, unit

claim = (unit) ->
  unit.memory.target or= claimTarget unit
  target = flags[unit.memory.target]
  if not target?
    unit.memory.target = claimTarget unit
    target = flags[unit.memory.target]
  return if not target?
  room = rooms[target.pos.roomName]
  if not room?
    location = pos: target.pos, range: 1
    goTo location, unit
  else
    controller = room.controller
    if controller.owner? and not controller.my
      if unit.attackController(controller) == ERR_NOT_IN_RANGE
        location = pos: room.controller.pos, range: 1
        goTo location, unit
    else
      if unit.claimController(controller) == ERR_NOT_IN_RANGE
        location = pos: room.controller.pos, range: 1
        goTo location, unit

invade = (unit) ->
  switch unit.memory.role
    when roles.MEDIC
      return if heal unit
    else
      return if attackUnit(unit) or attackStructure(unit)

  unit.memory.shouldInvade or= shouldInvade()
  if unit.memory.shouldInvade
    unit.memory.target or= flagTarget unit, flag_intents.INVADE
  else
    unit.memory.target or= flagTarget unit, flag_intents.GARRISON

  target = flags[unit.memory.target]
  if not target?
    if unit.memory.shouldInvade
      unit.memory.target = flagTarget unit, flag_intents.INVADE
    else
      unit.memory.target = flagTarget unit, flag_intents.GARRISON
    target = flags[unit.memory.target]
  return if not target?

  location = pos: target.pos, range: 3
  goTo location, unit

attack = (unit) ->
  switch unit.memory.role
    when roles.MEDIC
      return if heal unit
    else
      return if attackUnit(unit) or attackStructure(unit)

  unit.memory.target or= flagTarget unit, flag_intents.ATTACK
  target = flags[unit.memory.target]
  if not target?
    unit.memory.target = flagTarget unit, flag_intents.ATTACK
    target = flags[unit.memory.target]
  return if not target?

  location = pos: target.pos, range: 3
  goTo location, unit

defend = (unit) ->
  switch unit.memory.role
    when roles.MEDIC
      return if heal unit
    else
      return if attackUnit(unit) or attackStructure(unit)

  unit.memory.target or= flagTarget unit, flag_intents.DEFEND
  target = flags[unit.memory.target]
  if not target?
    unit.memory.target = flagTarget unit, flag_intents.DEFEND
    target = flags[unit.memory.target]
  return if not target?

  location = pos: target.pos, range: 3
  goTo location, unit

patrol = (unit) ->
  switch unit.memory.role
    when roles.MEDIC
      return if heal unit
    else
      return if attackUnit(unit) or attackStructure(unit)

  unit.memory.target or= flagTarget unit, flag_intents.PATROL
  target = flags[unit.memory.target]
  if not target?
    unit.memory.target = flagTarget unit, flag_intents.PATROL
    target = flags[unit.memory.target]
  return if not target?

  if unit.pos.inRangeTo(target.pos, 1)
    unit.memory.target = flagTarget(unit, flag_intents.PATROL, exclude=unit.memory.target)
    target = flags[unit.memory.target]
  else
    location = pos: target.pos, range: 1
    goTo location, unit

attackUnit = (unit) ->
  if not unit.room.controller?.my and unit.room.controller?.safeMode?
    return false
  if unit.memory.unitTarget?
    target = Game.getObjectById unit.memory.unitTarget
  if not target?
    target = unit.pos.findClosestByRange FIND_HOSTILE_CREEPS
  return false if not target?
  unit.memory.unitTarget = target.id
  switch unit.memory.role
    when roles.SNIPER
      # Kite enemies by staying *just* within range, and moving away if they get closer
      if unit.pos.getRangeTo(target.pos) < 3
        deltaX = unit.pos.x - target.pos.x
        deltaY = unit.pos.y - target.pos.y
        xPos = Math.max(Math.min(unit.pos.x + deltaX, 49), 1)
        yPos = Math.max(Math.min(unit.pos.y + deltaY, 49), 1)
        location = pos: new RoomPosition(xPos, yPos, unit.room.name), range: 0
      else
        location = pos: target.pos, range: 3
      goTo location, unit
      unit.rangedAttack(target)
    else
      if unit.attack(target) == ERR_NOT_IN_RANGE
        location = pos: target.pos, range: 1
        goTo location, unit
  return true

attackStructure = (unit) ->
  # Don't try attack if we're in an enemy room which has safemode active
  if not unit.room.controller?.my and unit.room.controller?.safeMode?
    return false
  target = unit.pos.findClosestByPath FIND_HOSTILE_STRUCTURES,
                                      filter: (s) => s.structureType isnt STRUCTURE_CONTROLLER
  return false if not target?
  switch unit.memory.role
    when roles.SNIPER
      # Kite enemies by staying *just* within range, and moving away if they get closer
      if unit.pos.getRangeTo(target.pos) < 3
        deltaX = unit.pos.x - target.pos.x
        deltaY = unit.pos.y - target.pos.y
        xPos = Math.max(Math.min(unit.pos.x + deltaX, 49), 1)
        yPos = Math.max(Math.min(unit.pos.y + deltaY, 49), 1)
        location = pos: new RoomPosition(xPos, yPos, unit.room.name), range: 0
      else
        location = pos: target.pos, range: 3
      goTo location, unit
      unit.rangedAttack(target)
    else
      if unit.attack(target) == ERR_NOT_IN_RANGE
        location = pos: target.pos, range: 1
        goTo location, unit
  return true

heal = (unit) ->
  if not unit.room.controller?.my and unit.room.controller?.safeMode
    return false
  unit.memory.target or= healTarget unit
  target = Game.getObjectById unit.memory.target
  if not target? or target.hits == target.hitsMax
    unit.memory.target = healTarget unit
    target = Game.getObjectById unit.memory.target
  if not target?
    unit.memory.target = undefined
    target = unit.pos.findClosestByRange FIND_MY_CREEPS,
                                         filter: (c) -> c.name isnt unit.name
    if unit.heal(target) == ERR_NOT_IN_RANGE
      unit.rangedHeal target
    return false
  if unit.heal(target) == ERR_NOT_IN_RANGE
    unit.rangedHeal target
    moveTo target, unit
  return true

shouldWork = (unit) ->
  if unit.store.getUsedCapacity() == unit.store.getCapacity()
    true
  else if unit.store.getUsedCapacity() == 0
    false
  else
    unit.memory.working

shouldInvade = ->
  actual = {}
  actual[v] = 0 for v in values roles
  merge actual, countBy(filter(units, (u) => not u.spawning), 'memory.role')
  actual[roles.MEDIC] >= 3 and actual[roles.SOLDIER] >= 2 and actual[roles.SNIPER] >= 2

module.exports = { upgrade, harvest, transfer, build,
                   repair, fortify, refillTower, shouldWork,
                   moveTo, resupply, collect, claim,
                   reserve, patrol, attack, invade,
                   defend, mine }
