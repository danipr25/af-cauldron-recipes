# Changelog

All notable changes to Cauldron Recipes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a minor version may change how the mod behaves and says how here.

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
