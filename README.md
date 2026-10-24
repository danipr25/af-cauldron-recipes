# Cauldron Recipes

A mod for **Alchemy Factory** that shows cauldron recipes in the game. It adds a **Recipes** tab to the V menu (the item catalog) and a Cauldron section to each item's sheet. It shows the recipes you have discovered and, if you unlock them, all the others. Recipes come from the game itself, not from a list in the mod.

Requires [AF Mod Loader](https://github.com/danipr25/af-modloader) and [AF Mod Loader API](https://github.com/danipr25/af-modloader-api) 0.1.4 or newer (0.1.x).

Unofficial fan project. Alchemy Factory belongs to its developers. Status: version 0.1.4, tested on game 1.1.5024. See the [changelog](CHANGELOG.md).

## Install

1. Install AF Mod Loader and AF Mod Loader API.
2. Close the game.
3. Download `af-cauldron-recipes-<version>.zip` from [Releases](https://github.com/danipr25/af-cauldron-recipes/releases).
4. Extract it into `<game>\mods`, so you get `<game>\mods\af-cauldron-recipes\mod.json`.

To update, delete the old `<game>\mods\af-cauldron-recipes` folder first, then extract the new zip. Your discovered recipes are kept in `<game>\mods\.data` and stay.

Every release lists the SHA-256 of its files in `SHA256SUMS.txt`, and GitHub Actions builds the files and attests them. To check a download, run `Get-FileHash -Algorithm SHA256 <file>` and compare, or use the [GitHub CLI](https://cli.github.com/):

```
gh attestation verify <file> --repo danipr25/af-cauldron-recipes --signer-workflow danipr25/af-cauldron-recipes/.github/workflows/release.yml
```


## Use

**Recipes tab** (V menu, after Ledger):

- Two columns. On the left, a grid of the products that have recipes you can see. Use the search box to find one, and the button at the top to switch between the Normal and Advanced cauldron.
- Click a product to see its recipes on the right, two to a row in Normal and three in Advanced (40 and 42 per page). They are split into **Favorites**, **Discovered** and **Other recipes**. The arrows under the product's name change the page.
- **Favorites:** a star after each recipe. Click it to mark the recipe as a favorite (click again to remove it). The star changes at once and the list is not rebuilt, so favorites move to the top the next time the list is built (another page, product, filter or mode). The **Favorites** button at the top of the left column shows all your favorites for the current cauldron, grouped by product; the same button, now called **Back to recipes**, leaves that view. Favorites follow the same rules as the recipes: if a recipe is hidden by a lock (see the commands below), its favorite is hidden too and comes back when the recipe is shown again.
- **Filter:** **+ Add** picks an ingredient, and only the recipes that use it stay. You can pick as many ingredients as the cauldron has slots. Click an ingredient in the filter to remove it, or **Clear** to remove them all.

**Cauldron panel** (the panel that opens when you use a cauldron): a **Recipes** side tab under the game's Cauldron tab, with a search box, a **Show discovered** button and a list for that cauldron's kind (Normal or Advanced). It lists your favorites; **Show discovered** adds the recipes you have discovered. The search matches the names of the product and of the ingredients. Click **Use** after a recipe to set it on the cauldron you have open. If the cauldron holds items, the tab first tells you how many go back to your inventory and asks you to confirm.

**Item sheet** (V menu, Materials and Goods):

- Under a **Cauldron** heading, a product shows one row per cauldron, for example **Normal** "12 recipes, 3 discovered". Its button opens the Recipes tab on that product in that cauldron.
- An ingredient shows "Ingredient in N cauldron recipes".
- The counts include only what the tab would show you, so nothing locked is given away.

The first world you load after starting the game indexes every recipe in the background, which takes about a minute. Until it finishes, counts say "so far".

**Which recipes are shown.** The game does not record which recipes you have found, so the mod keeps a record per world:

- **Discovered**: every recipe you set on a cauldron (all slots filled). Cauldrons already placed when the mod first runs count too.
- **Unlocked**: whatever you unlock with the commands below.
- **Favorites**: the recipes you starred, kept per world in the same file.

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

**What it touches.** It writes one file per world, `<game>\mods\.data\af-cauldron-recipes-<world>.json`, with the discovered recipes, your favorites and what you unlocked or locked. From 0.1.3 the file is version 2: Cauldron Recipes 0.1.2 or earlier opening it treats it as written by a newer mod, does not write to it and tracks nothing, so your favorites are not lost, but nothing is saved until you update again. If the record of a world cannot be saved, the tab says so and shows no stars. It never writes to your save file, changes no game data and uses no network.

**What it changes in the game.** Only when you click **Use** in the cauldron panel, the mod sets the filters of that one cauldron's slots, through the game's own call (`NetCommandSetFilterName`, the one the game makes when you pick a filter), so the game saves them as usual. It never does this on its own and never on several cauldrons. Filters that already match the recipe stay; the others are cleared and set. Items in the slots that change go back to your inventory: in a normal game, what does not fit drops on the ground; in a creative save they may vanish, so empty the cauldron first if that matters. Clicking **Use** on the recipe already set changes nothing.

## Development

Needs Lua 5.4, StyLua 2.5.2 and Luacheck 1.2.0 on the PATH (how to install them is in the [AF Mod Loader README](https://github.com/danipr25/af-modloader#development)), and a game with AF Mod Loader and the API installed for testing.

| Command | What it does |
|---|---|
| `lua scripts/check.lua` | Formatting, lint and tests. `--fix` applies the formatting. |
| `lua scripts/dev-install.lua` | Copies `mod` into `<game>\mods\af-cauldron-recipes`. The game must be closed. |

The game folder defaults to the Steam one. Pass another as the first argument or set `AF_GAME_DIR`.

How the mod reads the game's data, and what is not verified in game yet: [docs/game-data.md](docs/game-data.md).

### Releasing

Work reaches `development` by pull request, and CI (the `check` job, the same as `lua scripts/check.lua`) must pass. Only the owner publishes, and only from GitHub Actions: nothing is built or uploaded from a personal machine.

1. On `development`, set the new version (`mod/mod.json` and `VERSION` in `mod/scripts/main.lua`, which must match) and write its section in [CHANGELOG.md](CHANGELOG.md).
2. Open a pull request from `development` into `main` and merge it. `main` accepts nothing else.
3. Tag the merge commit `vX.Y.Z` (the version) on `main` and push the tag. The [release workflow](.github/workflows/release.yml) checks that the commit is on `main` and that the tag matches the code, runs the checks, builds the zip, attests it and publishes a GitHub release with the CHANGELOG section as notes.

To rehearse, run the Release workflow by hand from `main` ("Run workflow"): it does everything except the attestation and the release, and keeps the files and notes as a workflow artifact.

## License

MIT. See [LICENSE](LICENSE).
