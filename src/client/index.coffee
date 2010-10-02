# This module contains all the guts of the browser client. There are two types of browser play:
#
#  * The `LocalGame` class implements a non-networked game, local to the player's computer/browser.
#  * The `NetworkGame` class implements a networked game using a WebSocket.
#
# Both of these inherit from `BaseGame`, which handles all the common stuff.


# FIXME: Better error handling all around.

Simulation       = require '../simulation'
Tank             = require '../objects/tank'
net              = require '../net'
{SimMap}         = require '../sim_map'
{unpack}         = require '../struct'
{TICK_LENGTH_MS} = require '../constants'
ClientContext    = require './net'
Loader           = require './loader'
{decodeBase64}   = require './util/base64'
DefaultRenderer  = require './renderer/offscreen_2d'
EverardIsland    = require './everard'



#### Common logic

class BaseGame
  constructor: ->
    # Setup the key handlers.
    $(document).keydown (e) =>
      @handleKeydown(e) if @sim?
    $(document).keyup (e) =>
      @handleKeyup(e) if @sim?

    # Setup game state.
    @gameTimer = @lastTick = null

    # Load resources.
    loader = new Loader()
    loader.onComplete = =>
      @resources = loader.resources
      @startup()

    loader.image 'base'
    loader.image 'styled'
    loader.image 'overlay'

    loader.finish()

  # Common initialization once the map is available
  commonInitialization: (map) ->
    @sim = new Simulation(map)
    @renderer = new DefaultRenderer(@resources.images, @sim)
    @sim.map.setView(@renderer)

  ##### Game loop.

  start: ->
    return if @gameTimer?

    @tick()
    @lastTick = Date.now()

    @gameTimer = window.setInterval =>
      @timerCallback()
    , TICK_LENGTH_MS

  stop: ->
    return unless @gameTimer?
    window.clearInterval(@gameTimer)
    @gameTimer = @lastTick = null

  timerCallback: ->
    now = Date.now()
    while now - @lastTick >= TICK_LENGTH_MS
      @tick()
      @lastTick += TICK_LENGTH_MS
    @renderer.draw()

  ##### Abstract methods.

  # Called after resources are loaded.
  startup: ->

  # Simulate a tick.
  tick: ->

  # Key press handlers.
  handleKeydown: (e) ->
  handleKeyup: (e) ->



#### Local game simulation

class LocalGame extends BaseGame
  startup: ->
    map = SimMap.load decodeBase64(EverardIsland)
    @commonInitialization(map)
    @sim.player = @sim.spawn Tank
    @renderer.initHud()
    @start()

  tick: ->
    @sim.tick()

  ##### Key press handlers.

  handleKeydown: (e) ->
    switch e.which
      when 32 then @sim.player.shooting = yes
      when 37 then @sim.player.turningCounterClockwise = yes
      when 38 then @sim.player.accelerating = yes
      when 39 then @sim.player.turningClockwise = yes
      when 40 then @sim.player.braking = yes
    e.preventDefault()

  handleKeyup: (e) ->
    switch e.which
      when 32 then @sim.player.shooting = no
      when 37 then @sim.player.turningCounterClockwise = no
      when 38 then @sim.player.accelerating = no
      when 39 then @sim.player.turningClockwise = no
      when 40 then @sim.player.braking = no
      else return
    e.preventDefault()


#### Networked game simulation

class NetworkGame extends BaseGame
  constructor: ->
    @heartbeatTimer = 0
    super

  startup: ->
    @ws = new WebSocket("ws://#{location.host}/demo")
    $(@ws).one 'message', (e) =>
      @receiveMap(e.originalEvent)

  receiveMap: (e) ->
    map = SimMap.load decodeBase64(e.data)
    @commonInitialization(map)
    @netctx = new ClientContext(@sim)
    $(@ws).bind 'message', (e) =>
      @handleMessage(e.originalEvent) if @ws?

  receiveWelcome: (tank) ->
    @sim.player = tank
    @sim.rebuildMapObjects()
    @renderer.initHud()
    @start()

  tick: ->
    @netctx.authoritative = no
    net.inContext @netctx, =>
      @sim.tick()

    # Send the heartbeat (an empty message) every 10 ticks / 400ms.
    if ++@heartbeatTimer == 10
      @heartbeatTimer = 0
      @ws.send('')

  ##### Key press handlers.

  handleKeydown: (e) ->
    return unless @ws?
    switch e.which
      when 32 then @ws.send net.START_SHOOTING
      when 37 then @ws.send net.START_TURNING_CCW
      when 38 then @ws.send net.START_ACCELERATING
      when 39 then @ws.send net.START_TURNING_CW
      when 40 then @ws.send net.START_BRAKING
      else return
    e.preventDefault()

  handleKeyup: (e) ->
    return unless @ws?
    switch e.which
      when 32 then @ws.send net.STOP_SHOOTING
      when 37 then @ws.send net.STOP_TURNING_CCW
      when 38 then @ws.send net.STOP_ACCELERATING
      when 39 then @ws.send net.STOP_TURNING_CW
      when 40 then @ws.send net.STOP_BRAKING
      else return
    e.preventDefault()

  ##### Network message handlers.

  handleMessage: (e) ->
    @netctx.authoritative = yes
    net.inContext @netctx, =>
      data = decodeBase64(e.data)
      pos = 0
      length = data.length
      while pos < length
        command = data[pos++]
        ate = @handleServerCommand command, data, pos
        if ate == -1
          # FIXME: Do something better than this when console is not available.
          console.log "Message was:", data
          return
        pos += ate

  handleServerCommand: (command, data, offset) ->
    switch command
      when net.WELCOME_MESSAGE
        [[tank_idx], bytes] = unpack('H', data, offset)
        @receiveWelcome @sim.objects[tank_idx]
        bytes

      when net.CREATE_MESSAGE
        @sim.netSpawn data, offset

      when net.DESTROY_MESSAGE
        @sim.netDestroy data, offset

      when net.MAPCHANGE_MESSAGE
        [[x, y, code, life, mine], bytes] = unpack('BBBBf', data, offset)
        ascii = String.fromCharCode(code)
        cell = @sim.map.cells[y][x]
        cell.setType(ascii, mine)
        cell.life = life
        bytes

      when net.UPDATE_MESSAGE
        @sim.netTick data, offset

      else
        # FIXME: Do something better than this when console is not available.
        console.log "Bad command '#{command}' from server, and offset #{offset - 1}"
        @stop()
        @ws.close()
        @ws = null
        # Tell handleMessage to bail.
        -1


#### Entry point

game = null

init = ->
  if location.hostname.split('.')[1] == 'github'
    game = new LocalGame()
  else
    game = new NetworkGame()


#### Exports
exports.init  = init
exports.start = -> game.start()
exports.stop  = -> game.stop()
