# Changelog

All notable changes to Cauldron Recipes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a minor version may change how the mod behaves and says how here.

## [0.1.4] - 2026-10-24

- A **Recipes** side tab on the cauldron panel (Normal and Advanced): a search box over the product and ingredient names, and the recipes for that cauldron as the V menu shows them (favorites, then discovered, then the other recipes of the unlocked products, with no recipe twice), the first 40 at a time. While the recipe index is still being built the tab shows what is found so far and the progress. Each row shows the product, its name, the ingredients and a **Use** mark.
- **Use** sets that recipe on the cauldron you have open, through the game's own `NetCommandSetFilterName`, and goes back to the Cauldron tab. Filters that already match are left as they are; the others are cleared and then set, in that order, so the mod's own discovery never records a partial recipe (slots without a filter are set directly). There is no confirmation: items in the cauldron go back to your inventory and what does not fit drops on the ground (seen in a normal save), and they may vanish in a save played in creative mode. It is the only change the mod makes to the game world and it happens only on that click.
- Needs AF Mod Loader API 0.1.4 or later (`api.panels.tab`, `api.defer`, the tile `scale` option).

## [0.1.3] - 2026-10-24

- Favorite recipes: a star after each recipe in the Recipes tab. A click marks or unmarks it, changing the star in place without rebuilding the list. Favorites are kept per world, in the world's record in `mods\.data`, never in the save.
- A product's recipes now start with **Favorites (n)**, then **Discovered (n)** and **Other recipes (n)**. A recipe is listed once, under the first heading that has it. The status line still counts all discovered recipes.
- A **Favorites** button in the left pane shows every favorite of the current cauldron, grouped by product and paged. The button reads **Back to recipes** while the view is open. Switching between Normal and Advanced keeps the view.
- A favorite is shown only where its recipe would be shown: locking a product (or `recipes.lockall`) hides its favorites without removing them, and unlocking brings them back. Favorites that use items the game no longer has stay in the record, hidden, and are counted in the log.
- The record file is now version 2 (it holds the favorites). Version 1 files load as they are. Cauldron Recipes 0.1.2 or earlier treats a version 2 file as written by a newer mod and will not save recipes for that world until it is updated.
- In a world whose record cannot be saved, no stars are shown, the Favorites button is hidden, and the notice says discovered recipes are not tracked and favorites are not available.
- Needs AF Mod Loader API 0.1.3 or later (`row:mark`, the clickable star).

## [0.1.2] - 2026-10-23

- The Recipes tab follows the game's look: all its text is the game's dark text color (no gold, cream or white), a divider between the two columns, between the mode and the search box, and between the product, the filter and the recipe list, and a vertical line between the recipes of a row instead of a gap.
- Advanced recipes are listed three to a row, 42 per page (Normal stays two to a row, 40 per page): a page size is a whole number of rows. A page that shows both Discovered and Other recipes can still end on a short row of each kind.
- The status line under the product's name no longer repeats the cauldron mode (the left side shows it): for example "3 of 25158 recipes, 0 discovered".
- A little more room between the lines of the item sheet section and around the page label and the filter row.
- The Cauldron section on item sheets has the game's divider with the heading "Cauldron", and its text is dark.
- Needs AF Mod Loader API 0.1.2 or later (dividers, column divider, game scrollbar and search box, page padding).
- Switching between Normal and Advanced no longer flickers the menu: only the two columns are rebuilt, not the whole page.

## [0.1.1] - 2026-10-23

- The Recipes tab has two columns: the product grid on the left, the recipes of the clicked product on the right. Clicking a product rebuilds only the right side, not the whole page, so the grid keeps its scroll.
- Recipes are listed two to a row, 40 per page, with the page arrows under the product's name and the filter below them.
- The Cauldron section on item sheets has a "Cauldron" heading with a gap above it and short Normal and Advanced buttons.
- Needs AF Mod Loader API 0.1.1 or later (columns, clearing one pane, spacing).

## [0.1.0] - 2026-10-23

First public release.

- A Recipes tab in the V menu (the item catalog): search, Normal and Advanced cauldrons, and the recipes you have discovered, 20 per page.
- A Cauldron section on each item's sheet with how many recipes make or use the item.
- An ingredient filter for the recipe list.
- Recipes come from the game itself at runtime, not from a list in the mod. The mod keeps its own record of discovered recipes per world and never writes to your save.
- Console commands, including an explicit unlock-all that asks for confirmation.
