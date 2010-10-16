## Soundkit

# A thin audio layer.

class SoundKit
  constructor: ->
    @sounds = {}
    @isSupported = Audio?

  # Register the effect at the given url with the given name, and build a helper method
  # on this instance to play the sound effect.
  register: (name, url) ->
    @sounds[name] = url
    this[name] = => @play(name)

  # Wait for the given effect to be loaded, then register it.
  load: (name, url, cb) ->
    return @register(name, url) unless @isSupported
    loader = new Audio()
    $(loader).bind 'canplaythrough', =>
      @register(name, loader.currentSrc)
      cb?()
    loader.src = url
    loader.load()

  # Play the effect called `name`.
  play: (name) ->
    return unless @isSupported
    effect = new Audio()
    effect.src = @sounds[name]
    effect.play()
    effect

## Exports
module.exports = SoundKit
