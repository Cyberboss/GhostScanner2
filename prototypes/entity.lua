
local sprites = make_4way_animation_from_spritesheet({
  layers = {
    {
      scale = 0.5,
      filename = "__GhostScanner3__/graphics/entity/hr-ghost-scanner.png",
      width = 114,
      height = 102,
      frame_count = 1,
      shift = util.by_pixel(0, 5),
    },
    {
      scale = 0.5,
      filename = "__base__/graphics/entity/combinator/constant-combinator-shadow.png",
      width = 98,
      height = 66,
      frame_count = 1,
      shift = util.by_pixel(8.5, 5.5),
      draw_as_shadow = true,
    },
  }
})

local scanner = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
scanner.name = "ghost-scanner"
scanner.icon = "__GhostScanner3__/graphics/icons/ghost-scanner.png"
scanner.icon_size = 32
scanner.icon_mipmaps = 1
scanner.minable.result = "ghost-scanner"
scanner.sprites = sprites
scanner.item_slot_count = 1000

data:extend({ scanner })