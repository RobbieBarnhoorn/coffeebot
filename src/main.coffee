{ garbageCollection } = require 'memory_actions'
{ populationControl } = require 'spawn_management'
{ unitManagement } = require 'unit_management'
{ towerManagement } = require 'tower_management'

module.exports.loop = ->
  do garbageCollection
  do populationControl
  do unitManagement
  do towerManagement
