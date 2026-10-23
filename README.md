# Cauldron Recipes

A mod for **Alchemy Factory** that shows cauldron recipes in the game. It adds a **Recipes** tab to the V menu (the item catalog) and a Cauldron section to each item's sheet. It shows the recipes you have discovered and, if you unlock them, all the others. Recipes come from the game itself, not from a list in the mod.

Requires [AF Mod Loader](https://github.com/danipr25/af-modloader) and [AF Mod Loader API](https://github.com/danipr25/af-modloader-api) 0.1.0 or newer (0.1.x).

Unofficial fan project. Alchemy Factory belongs to its developers. Status: version 0.1.0, tested on game 1.1.5024.

## Install

1. Install AF Mod Loader and AF Mod Loader API.
2. Close the game.
3. Copy the `mod` folder to `<game>\mods` and rename the copy to `af-cauldron-recipes`.

## Use

**Recipes tab** (V menu, after Ledger):

- A grid of the products that have recipes you can see. Use the search box to find one, and the button at the top to switch between the Normal and Advanced cauldron.
- Click a product to see its recipes, 20 per page. They are split into **Discovered** and **Other recipes**.
- **Filter:** **+ Add** picks an ingredient, and only the recipes that use it stay. You can pick as many ingredients as the cauldron has slots. Click an ingredient in the filter to remove it, or **Clear** to remove them all.

**Item sheet** (V menu, Materials and Goods):

- A product shows one row per cauldron, for example **Cauldron Recipes** "12 recipes (3 discovered)". Its button opens the Recipes tab on that product in that cauldron.
- An ingredient shows "Used in N cauldron recipes".
- The counts include only what the tab would show you, so nothing locked is given away.

The first world you load after starting the game indexes every recipe in the background, which takes about a minute. Until it finishes, counts say "so far".

**Which recipes are shown.** The game does not record which recipes you have found, so the mod keeps a record per world:

- **Discovered**: every recipe you set on a cauldron (all slots filled). Cauldrons already placed when the mod first runs count too.
- **Unlocked**: whatever you unlock with the commands below.

**Console commands.** Open the console with F10 or the key left of 1. `af.help` lists them all. `<item>` is the internal name, the name shown in game, or part of either. Use quotes for names with spaces.

| Command | What it does |
|---|---|
| `recipes.unlockall` | Shows every recipe. Confirm with `recipes.unlockall confirm`. |
| `recipes.lockall` | Hides every recipe, discovered ones too. Asks to confirm. |
| `recipes.safe-lockall` | Hides every recipe except the discovered ones. Asks to confirm. |
| `recipes.unlock <item>` | Shows every recipe of an item. |
| `recipes.lock <item>` | Hides every recipe of an item. |
| `recipes.safe-lock <item>` | Hides an item's recipes except the discovered ones. |
| `recipes.status` | Shows counts and the index progress. |

**What it touches.** It writes one file per world, `<game>\mods\.data\af-cauldron-recipes-<world>.json`. It never writes to your save, changes no game data and uses no network.

## Development

Needs Lua 5.4, StyLua 2.5.2 and Luacheck 1.2.0 on the PATH (how to install them is in the [AF Mod Loader README](https://github.com/danipr25/af-modloader#development)), and a game with AF Mod Loader and the API installed for testing.

| Command | What it does |
|---|---|
| `lua scripts/check.lua` | Formatting, lint and tests. `--fix` applies the formatting. |
| `lua scripts/dev-install.lua` | Copies `mod` into `<game>\mods\af-cauldron-recipes`. The game must be closed. |

The game folder defaults to the Steam one. Pass another as the first argument or set `AF_GAME_DIR`.

How the mod reads the game's data, and what is not verified in game yet: [docs/game-data.md](docs/game-data.md).

## License

MIT. See [LICENSE](LICENSE).
