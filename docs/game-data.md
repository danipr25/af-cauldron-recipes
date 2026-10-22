# Cauldrons and recipe data in the game

What the game exposes about cauldrons and recipes. Game 1.1.5023, checked on 2026-10-20 with a read-only UE4SS Lua script on a real save, plus the UE4SS C++ header dump (`BeltTD.hpp` is the game's native module).

## The game does not record discovered cauldron recipes

There is no list of discovered or brewed cauldron recipes anywhere in the reflected game data, and the game shows none in its UI. So this mod keeps its own record of recipes (see below) instead of reading one, and never writes to the save.

What the game state does keep (`ABeltTDGameStateBase.UnlockData`, read in game on a mid-game save):

| List | Entries | Contents |
|---|---|---|
| `ConstructOptionList` | 283 | Buildable things. |
| `CraftingOptionList` | 74 | Machine recipes (for example `WoodGear`, `Glass`, `SteelIngot`), not cauldron combinations. |
| `UnlockedSkillPointsList` | 262 | Skill tree. |
| `UnlockedSupplyOrderList` | 156 | Supply orders. |
| `UnlockedManualList` | 28 | Manual pages. |
| `UnlockedContractList` | 6 | Contracts. |
| `UnlockedLicenseList` | 37 | Licenses (the "Recognition" tab). |
| `UnlockedGoodsList` | 0 | |

`SavedRecipeName` was `None`.

## Cauldrons

Two Blueprint classes, each with a `CauldronFacility` component (`UCauldronFacilityComponent`):

| In game | Class | Input slots |
|---|---|---|
| Cauldron (Normal) | `BP_PewterCauldron_C` | 3 |
| Advanced Cauldron | `BP_SilverCauldron_C` | 2 |

Readable from Lua on each cauldron's `CauldronFacility`:

- `FacilityContainer.Slots`: array of `FBeltTDInventorySlotData` with `ItemName`, `ItemStack` and `SlotFilterName` (the filter the player set on that slot).
- `CachedOutputName`: product of the last recipe.
- `bCauldronActive`.

The recipe can be read even when the cauldron is idle and empty: the filters and `CachedOutputName` stay set. Verified against the in-game panels:

| Cauldron | Slot filters | `CachedOutputName` | In-game panel |
|---|---|---|---|
| Normal | `GoldCoin`, `CopperCoin`, `SilverCoin` | `GoldDust5` | Gold, copper and silver coins, product shown as a jar |
| Advanced | `GentianNectar`, `Gentian` | `Clay` | Gentian Nectar and Gentian, product Clay |

The Advanced example matches the web calculator's rules: Gentian Nectar (420) minus Gentian (400) is 20, Clay's cauldron target.

If a player leaves a slot without a filter, the recipe has to come from the slot's `ItemName` while it holds items. Not tested yet.

## Names

The game uses internal names (`GoldDust5`, `GentianNectar`). Names shown to players must come from the game's own localized data, never written by hand.

## Read from Lua (verified in game 2026-10-20)

Game 1.1.5023, UE4SS 1181, a throwaway Lua mod with a save loaded.

| What | Call | Result |
|---|---|---|
| Item table | `gameState.EnemyConfig` | `/Game/DataTables/DT_Enemies.DT_Enemies`, 180 rows (first: `PortalSigil`, `AdPortalSigil`, `GelatinousGridlock`, `CashRegister`, `Wood`) |
| Localized name | `GetItemDisplayName(FName(item), gameState, out)` on `/Game/Blueprints/Core/BP_BeltTDFunctionLib.Default__BP_BeltTDFunctionLib_C` | `out.DisplayName` = "Gentian Nectar" |
| Icon | `GetEnemyIcon(FName(item), gameState, out)` on the same library | `out.OutTexture` = `/Game/Arts/UI/Ingredients/T_UI_GentianNectar` |
| Recipe result | `gameState:GetCauldronProduct({FName...}, outTime, outHeat)` | returns the product `FName`; out tables give `outTotalTime` and `outHeatPower` |

`GetCauldronProduct` matches the panels above: `GentianNectar` + `Gentian` gives `Clay` (time 3.6, heat 4.6) and `GoldCoin` + `CopperCoin` + `SilverCoin` gives `GoldDust5` (time 27.3, heat 2278.5). So the game's own recipe resolution can be asked directly.

**Do not call `QueryEnemyConfig`** (on `BeltTDUserWidget`) from Lua: it takes one parameter and returns the whole `FBeltTDEnemyConfig` row, and calling it crashed the game. Read the cauldron values with the DataTable binding below instead.

## Cauldron values and recipe rules (verified in game 2026-10-21)

Game 1.1.5023, UE4SS 1181, a throwaway Lua mod with a save loaded.

### Reading the values

UE4SS 1181 has a native `UDataTable` binding (`UE4SS/src/LuaType/LuaUDataTable.cpp`). It reads rows straight from the table's memory, without calling a game function, and it did not crash:

```lua
local dt = gameState.EnemyConfig          -- #dt == 180
local row = dt:FindRow("Gentian")         -- row.CauldronCost == 400.0, row.CauldronTarget == 500.0, row.CauldronMulti == 0.0
dt:ForEachRow(function(name, row) ... end) -- every row, in the table's order
```

The fields are doubles (`FBeltTDEnemyConfig` in the header dump). Read on 1.1.5023: 180 rows, 170 with `CauldronCost > 0` (the items a cauldron takes) and 47 with `CauldronMulti > 0` (the items a cauldron can produce). The 10 rows without a cost are Aloe, AloeSeed, AloePaste, Salve, WoodAcid, Pottery, Ceramics, FireBrick, Granite and DriedClay. Some of the 170 are hidden in game (`bHideInGame`): which ones a player can actually put in a cauldron is not checked. The 170 include liquids, which a cauldron does not take (seen by the user in game). The mod skips rows with `IsLiquid` set (`EXCLUDE_LIQUIDS = true` in `catalog.lua`), so the ingredient count is lower than 170. This ships on ahead of the in-game check, a deliberate exception to AGENTS.md section 6; the log lists the liquids and every ingredient. The web calculator (game 1.0) excludes liquids too. Result of the in-game check: pending (game version, date and how it was checked go here).

`UDataTableFunctionLibrary:GetDataTableColumnAsString` exists as a fallback; it was not needed and is not tested.

### The game's own answer: `GetCauldronProduct`

- It is fast: 28,900 calls (every ordered pair of the 170 ingredients, liquids included) took 284 ms in Lua.
- It never returned `None` and never raised for any of 34,900 combinations.
- The order of the ingredients does not matter: every pair gave the same product in both orders. A real Advanced cauldron also gave the same product whichever slot each ingredient was in (checked by the user).
- It matches a real cauldron on a case where the rules below changed since game 1.0: Flax Seeds (`FlaxSeed`) + Impure Copper Powder (`CopperPowder`) gives Coke, both from `GetCauldronProduct` and in a real Advanced cauldron (checked by the user on 2026-10-21). The web calculator recorded Coal for this on game 1.0.

So the mod asks `GetCauldronProduct` for every product instead of reimplementing the rules: the result is the game's own, whatever a patch changes.

### What the rules look like (for understanding, not for the mod)

Compared with `GetCauldronProduct` on 28,900 Advanced pairs and 6,000 Normal triples. "Targets" are the rows with `CauldronMulti > 0`; "table order" is the order of `ForEachRow`.

- **Normal (3 slots)**: the web calculator's rules (`lib/cauldron.ts` in `alchemyfactorycalculator`) matched all 6,000 triples. The sum of the three costs is multiplied by 0.5 (three equal), 0.65 (two equal) or 1; the product is the target with the smallest `|value - CauldronTarget| * CauldronMulti`; ties go to the target first in table order. The product can be one of the ingredients.
- **Advanced (2 slots), two different items**: value = `|costA - costB|`. Candidates are the targets with `CauldronTarget` below the higher cost, except the ingredient with the higher cost (when both costs are equal, both are excluded). The lower-cost ingredient can be the product. The product is the closest candidate; ties go to the target first in table order. With no candidate the product is the target with the lowest `CauldronTarget`.
- **Advanced, the same item twice**: the product is the target with the smallest `CauldronTarget` above the item's cost, not the item itself; if there is none, the target with the highest `CauldronTarget`.
- This model matched 28,896 of 28,900 pairs. The 4 that differ are Topaz with Perfumed Soap or Perfumed Soap powder (both orders), an exact tie between Quicklime and Iron Sand that the game breaks the other way; probably a floating point detail.
- The web calculator's Advanced rules (game 1.0) differ in 380 pairs: they never let an ingredient be the product, break ties toward the higher target, and fail when there is no candidate.

## Which game is loaded

Read by AF Mod Loader API (`api.world`), and described with its verification in the API's `docs/world.md`: the world is told apart by `WorldTitleName` on `GameSaveLoadSubsystem`, read when `IsPreviewScene` is `false`. Loading another slot of the same world keeps the title. This mod keys its record file on the API's `world.key` and stores `world.title` inside the file.

Not checked yet: a brand new game's first save, sandbox worlds and multiplayer (the API logs what it sees).

## Other facts verified in game (2026-10-21, world probe)

Game 1.1.5023, UE4SS 1181, a throwaway Lua mod with a save loaded.

- `GetCauldronProduct` gave the same product in all 6 orders for 5 of 5 Normal triples (the Advanced pairs were verified earlier, see above). The recipe index therefore asks each combination once, in sorted order.
- `os.rename` onto an existing file fails ("File exists"); `os.remove` followed by `os.rename` works. The record is written to `<file>.tmp`, then the old file is removed and the copy renamed.
- `ExecuteWithDelay` followed by `ExecuteInGameThread` runs the function on the game thread.

## Detecting the recipes on the player's cauldrons (verified in game 2026-10-21)

- `FindAllOf("BP_PewterCauldron_C")` and `FindAllOf("BP_SilverCauldron_C")` list the placed cauldrons; each one's `CauldronFacility.FacilityContainer.Slots[i].SlotFilterName` and `CachedOutputName` read as in the table above (a save with one cauldron of each kind).
- A hook (single callback) on `/Script/BeltTD.CauldronFacilityComponent:NetCommandSetFilterName` fires when the player changes a slot filter. The context is the cauldron's component (`GetOwner()` is the cauldron actor) and the parameters are the slot index, counted from 0, and the new filter. Clearing a slot's filter fires it with `None`; choosing a new item fires it again with the item's name.

## Seen in the header dump only (not tested in game)

- The game state holds the DataTables `EnemyConfig` and `EnemyCraftingConfig`, the source of the cauldron values (`CauldronCost`, `CauldronTarget`, `CauldronMulti` in `DT_Enemies`).

## Not verified yet (the in-game test of version 0.1.0 checks these)

Each of these ships disabled or marked, as AGENTS.md section 6 asks.

- `IsLiquid` on the item rows (`FBeltTDEnemyConfig`, header dump): that reading it works and that it matches the items a cauldron refuses is not verified. The mod logs the liquids and any liquid product (`EXCLUDE_LIQUIDS` in `catalog.lua`).
- `bHideInGame` on the item rows (`FBeltTDEnemyConfig`, header dump): what it means for cauldron ingredients and products is unknown. The mod logs the items that have it set and reads it only to log (`EXCLUDE_HIDDEN = false` in `catalog.lua`).
- `OnInventoryUpdate` on `UCauldronFacilityComponent` (no parameters in the header dump): how often it fires, and whether a cauldron without filters can be read from the items in its slots. Behind `DETECT_FROM_ITEMS = false` in `discover.lua`.
- `UObject:GetWorld():GetAddress()` on a cauldron actor, used to skip cauldrons of another world. If it cannot be read, the mod logs it once and uses every cauldron found.
- The localized names, read with `GetItemDisplayName` for every item (180 calls): the time is logged once.
- How the page lays out a nav row above a list that fills the rest of the page, and `finding recipes N%` updating while the index is built.
- A gold `Discovered (n)` heading on a list row (color on list texts), a disabled Next arrow turning on when the page count grows while recipes are found, `enable(true)` on the Next arrow from a progress callback, "page / pages" next to the arrows updating as pages appear, the small muted status line (mode, recipes, percent) updating in place, the small Back button, the arrows and "page / pages" fitting in one row, the small text starting at the left edge, the arrow picture's size (a guess), the rows centering their tiles and "+" signs (API 0.1.5), and whether the cream status color (0.88, 0.82, 0.70) is readable on the panel.
- The ingredient filter of the recipes page: the small "Filter:" text, ingredient tiles, "+ Add" and "Clear" buttons fitting in one page row (up to 3 tiles plus both buttons), the pick page (ingredient tiles in a grid with their icons, a click adding the ingredient, search, Back), and the list, page count and status line ("F of N recipes") following the filter, also while recipes are still being found.
