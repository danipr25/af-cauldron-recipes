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

## Seen in the header dump only (not tested in game)

- `ABeltTDGameStateBase.GetCauldronProduct(const TArray<FName>& ingList, double& outTotalTime, double& outHeatPower)`: the game's own recipe resolution.
- The game state holds the DataTables `EnemyConfig` and `EnemyCraftingConfig`, the source of the cauldron values (`CauldronCost`, `CauldronTarget`, `CauldronMulti` in `DT_Enemies`).
- `UCauldronFacilityComponent.NetCommandSetFilterName(int32 slotIndex, FName FilterName)`: called when a filter changes.
