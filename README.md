# Cauldron Recipes

A mod for **Alchemy Factory** that adds a Recipes tab to the V menu (the item catalog with Materials, Goods, Stats and Ledger): search, Normal and Advanced modes, and the recipes you have already discovered. It also adds a Cauldron section to the item sheet of that menu, and console commands to show or hide recipes. Requires AF Mod Loader and AF Mod Loader API 0.1.7 or newer (0.1.x).

Status: version 0.1.0. The core (the filter hook, commands, worlds, the recipe index and its memory use) has been tested in the game, and so have the tab layout and the ingredient filter (game 1.1.5024, 2026-10-22). The tab was verified in game in the TAB menu; its move to the V menu and the item sheet section have not been tested in game yet. Behaviour that has not been verified in game is listed in `docs/game-data.md`.

Unofficial fan project. Alchemy Factory belongs to its developers.

## What you get

- A **Recipes** tab in the V menu, after Materials, Goods, Stats and Ledger. (It is no longer in the TAB menu.)
  - The grid page shows which cauldron you are looking at (Normal or Advanced, in gold), a small button to switch to the other one, a search box and a short status line with the number of products. The search looks at the item names as the game shows them. It ignores the case of the letters A to Z only: other letters (accents, for example) must match exactly.
  - Below it, a grid of the products that have at least one visible recipe in that mode. Click one to see its recipes.
  - The recipes page has one row with a small Back button, a previous arrow, "page / pages" and a next arrow (20 recipes per page; an arrow is grey when there is no page in that direction), then the product and its name in gold. A small status line under them says, for example, "Normal cauldron, 12 recipes".
  - The list has a gold **Discovered (n)** heading for the recipes you have already set on one of your cauldrons, then **Other recipes (n)**. Each heading shows up on the pages that have recipes of its kind, and its number counts them across all pages. A recipe is a row of its ingredients with a + between them: the product is the one shown at the top.
  - **Filter by ingredient.** Under the status line, a row with "Filter:", the ingredients you picked, a small **+ Add** button and a small **Clear** button (shown only when an ingredient is picked). **+ Add** opens a page with a search box and a grid of the ingredients that appear in this product's recipes (the ones that match your filter so far); click one to add it and go back to the list. You can pick as many as the cauldron has slots (3 Normal, 2 Advanced), and the same ingredient twice keeps only recipes that use it twice. The list, its page count and the headings then show only the matching recipes, and the status line says, for example, "Normal cauldron, 12 of 300 recipes". Click an ingredient in the filter (with any mouse button) to remove just that one (a quick double click on two different ingredients may remove both). **Clear** removes every ingredient. The filter is not saved: opening another product or switching cauldron clears it.
- A **Cauldron** section on the item sheet of the V menu (Materials and Goods), under "Used in Crafting". For an item a cauldron can make it has one row per cauldron that has recipes for it: a small **Cauldron Recipes** button (Normal) or **Advanced Cauldron Recipes** button, followed by, for example, "12 recipes (3 discovered)" for that cauldron only. The button opens the Recipes tab on that item in that cauldron's mode, whatever mode the tab was in. For an item that can be an ingredient it says "Used in 40 cauldron recipes". It counts only what the Recipes tab would show you, so it gives nothing away that is still locked, and says "so far" while the recipes are still being found. An item with nothing to say shows nothing. The section updates when you click another item.
- Recipes come from the game, never from a list in the mod: the mod asks the game which product each combination gives. Each time the game starts, the first world you load builds an index of every combination in the background, a few milliseconds per frame; the page shows "finding recipes" with a percentage until it is done (the grid shows it only once some product is unlocked), and "Other recipes" says "so far" until then. Finding them takes about a minute in the background and uses about 25 MB of Lua memory.

## Which recipes are shown

The game does not record which cauldron recipes you have found, so the mod keeps its own record for each world.

- **Discovered**: every recipe you set (all slots with a filter) on a Normal or Advanced cauldron, from the cauldrons already placed when the mod first runs and from then on. Recipes you pass through while changing filters one by one count too. The record is kept for good.
- **Unlocked** by the console commands below.

Recipes that need ingredients you have not unlocked yet are shown like any other.

## Console commands

Open the console (F10, or the key left of 1) and press the key twice for the full console. Use `af.help` to list every command.

| Command | What it does |
|---|---|
| `recipes.unlockall` | Asks to confirm with `recipes.unlockall confirm`. Then every recipe is shown. |
| `recipes.lockall` | Asks to confirm. Hides every recipe, the discovered ones too. The record is kept. |
| `recipes.safe-lockall` | Asks to confirm. Hides every recipe except the discovered ones. |
| `recipes.unlock <item>` | Shows every recipe of the item, discovered ones included. |
| `recipes.lock <item>` | Hides every recipe of the item, discovered ones too. |
| `recipes.safe-lock <item>` | Hides every recipe of the item except the discovered ones. |
| `recipes.status` | The world, how many recipes are discovered (and hidden), unlocked and locked, and the index progress. |

`<item>` is the internal name, the name shown in game, or part of either, without caring about case; use quotes for names with spaces. If several items match, the command lists their internal names. Only items a cauldron can make are accepted. Setting a cauldron filter to a recipe that is hidden brings that product back.

To go back after `recipes.lock <item>`: `recipes.unlock <item>` shows everything of it again, then `recipes.safe-lock <item>` keeps only the discovered ones.

Without a loaded save the commands answer "Load a save first."

## What it changes

- It adds a tab and a section to the V menu (item catalog) and the `recipes.*` console commands. Both appear while the game runs, in memory.
- It writes only to the game's `mods\.data` folder: one file per world, `af-cauldron-recipes-<world>.json`, next to its siblings `.json.tmp` (a copy being written) and `.broken-<time>.json` (a file the mod could not read, kept for you).
- It never writes to your save, and it does not change any game data.
- It uses no network.

If the file of a world comes from a newer version of the mod, or from another world with a similar name, the mod does not write it and says so in `UE4SS.log`.

## Development

Needs Lua 5.4, StyLua and Luacheck. `lua scripts/check.lua` runs formatting, lint and the tests. `lua scripts/dev-install.lua` copies `mod\` into a game that has AF Mod Loader and its API installed (a developer tool, not part of the mod).

## License

MIT. See [LICENSE](LICENSE).
