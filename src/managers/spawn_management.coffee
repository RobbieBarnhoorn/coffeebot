{ any, countBy, filter, flatten, includes, keys, map, merge, shuffle, some, values } = require 'lodash'
{ roles } = require 'unit_roles'
{ units } = require 'units'
{ spawns } = require 'spawns'
{ flags } = require 'flags'
{ flag_intents } = require 'flags'
{ rooms } = require 'rooms'
{ generateUnit } = require 'spawn_behaviours'
{ MYSELF } = require 'constants'
{ constructionSites, damagedStructures, damagedDefences, mines } = require 'unit_targeting'

priorities = [roles.HARVESTER, roles.TRANSPORTER, roles.UPGRADER, roles.BUILDER, roles.REPAIRER,
              roles.FORTIFIER, roles.MINER, roles.RESERVER, roles.CLAIMER, roles.SOLDIER,
              roles.SNIPER, roles.MEDIC]

myRooms = filter rooms, ((r) -> r.controller?.my or r.controller?.reservation?.username is MYSELF)
myControlledRooms = filter rooms, ((r) -> r.controller?.my)
mySources = flatten (s for s in r.find(FIND_SOURCES) for r in myRooms)
flagCount = countBy flags, 'color'

desired = (role) ->
  switch role
    when roles.HARVESTER        then 1 * mySources.length
    when roles.TRANSPORTER      then 1 * mySources.length
    when roles.UPGRADER         then 1 * myRooms.length
    when roles.BUILDER          then (if constructionSites.length then 3 else 0)
    when roles.REPAIRER
      if damagedStructures.length then 2 * myControlledRooms.length else 0
    when roles.FORTIFIER
      if damagedStructures.length then 2 * myControlledRooms.length else 0
    when roles.MINER            then 1 * mines.length
    when roles.RESERVER
      flagCount[flag_intents.RESERVE]
    when roles.CLAIMER
      flagCount[flag_intents.CLAIM]
    when roles.SOLDIER
      flagCount[flag_intents.ATTACK] * 4 or flagCount[flag_intents.DEFEND] * 3 or flagCount[flag_intents.INVADE] * 4
    when roles.SNIPER
      flagCount[flag_intents.ATTACK] * 4 or flagCount[flag_intents.DEFEND] * 3 or flagCount[flag_intents.INVADE] * 2
    when roles.MEDIC
      flagCount[flag_intents.ATTACK] * 4 or flagCount[flag_intents.DEFEND] * 0 or flagCount[flag_intents.INVADE] * 4

populationControl = ->
  # Count the actual populations by role
  actual = {}
  actual[v] = 0 for v in values roles
  merge actual, countBy(units, 'memory.role')
  # Filter out roles that are at desired capacity
  candidates = []
  for role,count of actual
    if count < desired role
      candidates.push role
    else
      for u in values units
        if u.memory.role == role and u.ticksToLive < 25 and not u.memory.replaced?
         candidates.push role
         u.memory.replaced = true

  choice = undefined
  for role in priorities
    if role in candidates
      choice = role
      break

  if choice?
    for spawn in shuffle keys spawns
      if generateUnit(spawn, choice) == OK
        break

failSafe =->
  parts = [ATTACK, RANGED_ATTACK]
  for r in values rooms when r.controller?.my
    if (r.find FIND_HOSTILE_CREEPS,
               filter: (c) => c.owner.username isnt 'Invader' and
                              some(parts, (p) => includes(map(c.body, (b) => b.type), p))).length
      r.controller.activateSafeMode()

module.exports = { populationControl, failSafe }
