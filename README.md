# About startup_weapon
Add weapons on survivors while they are in the saveroom.

## Commands
- `!w` - show menu with types weapons.
- `!t1` - show menu with tier1 weapons.
- `!t2` - show menu with tier2 weapons.
- `!t3` - show menu with tier3 weapons.
- `!<weapon>` - get "weapon" (!smg, !pump).

## ConVars
| ConVar               | Value         | Description                                                                        |
| -------------------- | ------------- | ---------------------------------------------------------------------------------- |
| sm_sw_melee_enabled  | 1             | Allow receiving melee                                                              |
| sm_sw_tier1_enabled  | 1             | Allow receiving t1 weapons                                                         |
| sm_sw_tier2_enabled  | 0             | Allow receiving t3 weapons                                                         |
| sm_sw_tier3_enabled  | 0             | Allow receiving t3 weapons                                                         |

## NULL Ent 'weapon_###' in GiveNamedItem!
This error occurs if weapons are blocked on the map.
Install [Melee Spawn Control](https://forums.alliedmods.net/showthread.php?t=327605) or similar extension.
