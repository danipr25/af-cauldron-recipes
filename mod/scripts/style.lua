-- The look shared by the mod's texts. Every text uses the game's own dark text color, read live from the item
-- sheet's texts in game 1.1.5024 (linear R 0.022, G 0.033, B 0.053, sRGB #293341): white, gold or cream texts clash
-- with the panel.
local style = {}

style.DARK = { 0.022, 0.033, 0.053 }

-- Colors a text handle (from text, row:text or section:text) and returns it.
function style.dark(handle)
  handle:color(style.DARK[1], style.DARK[2], style.DARK[3])
  return handle
end

return style
