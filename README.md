# Cauldron Recipes

A mod for **Alchemy Factory** that adds a Cauldron Recipes tab to the TAB menu: search, Normal and Advanced modes, and the recipes you have already discovered. It also adds console commands to show or hide recipes. Requires AF Mod Loader and AF Mod Loader API.

Status: version 0.1.0, written but not yet tested in the game. Behaviour that has not been verified in game is listed in `docs/game-data.md`.

Unofficial fan project. Alchemy Factory belongs to its developers.

## What you get

- A **Cauldron Recipes** tab next to Player, World and Recognition.
  - Buttons for **Normal** and **Advanced** cauldrons, and a search box. The search looks at the item names as the game shows them. It ignores the case of the letters A to Z only: other letters (accents, for example) must match exactly.
  - A grid of the products that have at least one visible recipe in that mode. Click one to see its recipes, 20 per page, with Previous, Next and Back.
  - A recipe shows its ingredients, then the product. Recipes you have already set on one of your cauldrons are marked "discovered".
- Recipes come from the game, never from a list in the mod: the mod asks the game which product each combination gives. Each time the game starts, the first world you load builds an index of every combination in the background, a few milliseconds per frame; the page shows "Indexing..." with a percentage until it is done. Indexing takes about a minute in the background and uses about 25 MB of Lua memory.

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

- It adds a tab to the TAB menu and the `recipes.*` console commands.
- It writes only to the game's `mods\.data` folder: one file per world, `af-cauldron-recipes-<world>.json`, next to its siblings `.json.tmp` (a copy being written) and `.broken-<time>.json` (a file the mod could not read, kept for you).
- It never writes to your save, and it does not change any game data.
- It uses no network.

If the file of a world comes from a newer version of the mod, or from another world with a similar name, the mod does not write it and says so in `UE4SS.log`.

## Development

See `AGENTS.md`. `lua scripts/check.lua` runs formatting, lint and the tests. `lua scripts/dev-install.lua` copies `mod\` into a game that has AF Mod Loader and its API installed (a developer tool, not part of the mod).

## License

MIT. See [LICENSE](LICENSE).
