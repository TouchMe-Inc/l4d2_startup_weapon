#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdktools>
#include <colors>


public Plugin myinfo =
{
	name = "StartupWeapon",
	author = "TouchMe",
	description = "Add weapons on survivors while they are in the saveroom",
	version = "build0006",
	url = "https://github.com/TouchMe-Inc/l4d2_startup_weapon"
}


#define TRANSLATIONS            "startup_weapon.phrases"

#define DEFAULT_PATH_TO_CFG     "addons/sourcemod/configs/startup_weapon.txt"

#define TEAM_SURVIVOR           2


enum struct E_Menu
{
	char sName[32];
	Handle hItems;
}


ConVar g_cvPathToCfg = null;

bool g_bRoundIsLive = false;

Handle
	g_hWeaponSlots = null,
	g_hMenuCmds = null,    /* sm_melee => 1, sm_t1 => 2, ... */
	g_hWeaponCmds = null,  /* sm_katana => 1, ... */
	g_hMenus = null,       /* 1 => { sName = MELEE, hItems = [1,2,3,4] } ... */
	g_hWeapons = null      /* 1 => weapon_katana, ..., 5 => weapon_pistol, */
;


/**
 * Called before OnPluginStart.
 *
 * @param myself            Handle to the plugin.
 * @param late              Whether or not the plugin was loaded "late" (after map load).
 * @param error             Error message buffer in case load failed.
 * @param err_max           Maximum number of characters for error message buffer.
 * @return                  APLRes_Success | APLRes_SilentFailure.
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	g_cvPathToCfg = CreateConVar("sm_sw_path_to_cfg", DEFAULT_PATH_TO_CFG);

	HookConVarChange(g_cvPathToCfg, OnPathToCfgChanged);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("weapon_drop", Event_WeaponDrop, EventHookMode_Post);

	g_hWeaponSlots = CreateTrie();
	g_hMenuCmds = CreateTrie();
	g_hWeaponCmds = CreateTrie();
	g_hMenus = CreateArray(sizeof(E_Menu));
	g_hWeapons = CreateArray(ByteCountToCells(32));

	FillWeaponSlots(g_hWeaponSlots);

	char sPath[PLATFORM_MAX_PATH ];
	GetConVarString(g_cvPathToCfg, sPath, sizeof(sPath));

	LoadConfig(sPath);

	RegConsoleCmd("sm_w", Cmd_ShowMainMenu);

	RegConsoleCmdByMap(g_hMenuCmds, Cmd_ShowWeaponMenu);
	RegConsoleCmdByMap(g_hWeaponCmds, Cmd_GiveWeapon);
}

/**
  * Called when the map loaded.
  */
public void OnMapStart() {
	g_bRoundIsLive = false;
}

/**
 *
 */
void OnPathToCfgChanged(ConVar convar, const char[] sOldValue, const char[] sNewValue)
{
	ClearTrie(g_hMenuCmds);
	ClearTrie(g_hWeaponCmds);
	ClearArray(g_hMenus);
	ClearArray(g_hWeapons);

	LoadConfig(sNewValue);
}

void Event_RoundStart(Event event, const char[] sName, bool bDontBroadcast) {
	g_bRoundIsLive = false;
}

void Event_LeftStartArea(Event event, const char[] sName, bool bDontBroadcast) {
	g_bRoundIsLive = true;
}

Action Event_WeaponDrop(Event event, const char[] sName, bool bDontBroadcast)
{
	if (g_bRoundIsLive) {
		return Plugin_Continue;
	}

	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!iClient || !IsPlayerAlive(iClient)) {
		return Plugin_Stop;
	}

	int iEnt = GetEventInt(event, "propid");

	if (!IsValidEntity(iEnt) || !IsValidEdict(iEnt)) {
		return Plugin_Stop;
	}

	char sWeaponName[32];
	GetEventString(event, "item", sWeaponName, sizeof(sWeaponName));

	static const char sNoDupeWeapons[][] = {
		"smg_silenced", "smg", "smg_mp5",
		"pumpshotgun", "shotgun_chrome",
		"sniper_scout",
		"sniper_military", "hunting_rifle",
		"autoshotgun", "shotgun_spas",
		"rifle_ak47", "rifle_desert", "rifle_sg552", "rifle",
		"pistol_magnum", "pistol",
		"sniper_awp", "rifle_m60", "grenade_launcher"
	};

	for (int iItem = 0; iItem < sizeof(sNoDupeWeapons); iItem ++)
	{
		if (StrEqual(sNoDupeWeapons[iItem], sWeaponName, false))
		{
			RemoveEntity(iEnt);
			break;
		}
	}

	return Plugin_Continue;
}

void LoadConfig(const char[] sPath)
{
	if (!FileExists(sPath)) {
		SetFailState("Couldn't load %s", sPath);
	}

	Handle hConfigList = CreateKeyValues("Weapons");

 	if (!FileToKeyValues(hConfigList, sPath)) {
		SetFailState("Failed to parse keyvalues for %s", sPath);
	}

	if (KvGotoFirstSubKey(hConfigList, false))
	{
		int iMenuIndex = 0, iWeaponIndex = 0;
		E_Menu menu;
		char sSectionName[32], sSectionKey[16], sSectionValue[32], sWeaponName[32], sWeaponKey[16], sWeaponValue[32];

		do
		{
			KvGetSectionName(hConfigList, sSectionName, sizeof(sSectionName));

			strcopy(menu.sName, sizeof(menu.sName), sSectionName);
			menu.hItems = CreateArray();

			iMenuIndex = PushArrayArray(g_hMenus, menu);

			if (KvGotoFirstSubKey(hConfigList, false))
			{
				do
				{
					KvGetSectionName(hConfigList, sSectionKey, sizeof(sSectionKey));

					if (StrEqual(sSectionKey, "cmd", false))
					{
						KvGetString(hConfigList, NULL_STRING, sSectionValue, sizeof(sSectionValue));

						SetTrieValue(g_hMenuCmds, sSectionValue, iMenuIndex);
					}

					else if (StrEqual(sSectionKey, "items", false) && KvGotoFirstSubKey(hConfigList, false))
					{
						do
						{
							KvGetSectionName(hConfigList, sWeaponName, sizeof(sWeaponName));

							iWeaponIndex = PushArrayString(g_hWeapons, sWeaponName);

							GetArrayArray(g_hMenus, iMenuIndex, menu);

							PushArrayCell(menu.hItems, iWeaponIndex);

							if (KvGotoFirstSubKey(hConfigList, false))
							{
								do
								{
									KvGetSectionName(hConfigList, sWeaponKey, sizeof(sWeaponKey));

									if (StrEqual(sWeaponKey, "cmd", false))
									{
										KvGetString(hConfigList, NULL_STRING, sWeaponValue, sizeof(sWeaponValue));

										SetTrieValue(g_hWeaponCmds, sWeaponValue, iWeaponIndex);
									}

								} while (KvGotoNextKey(hConfigList, false));

								KvGoBack(hConfigList);
							}

						} while (KvGotoNextKey(hConfigList, false));

						KvGoBack(hConfigList);
					}

				} while (KvGotoNextKey(hConfigList, false));

				KvGoBack(hConfigList);
			}
		} while (KvGotoNextKey(hConfigList, false));
	}

	CloseHandle(hConfigList);
}

Action Cmd_ShowMainMenu(int iClient, int iArgs)
{
	if (!iClient) {
		return Plugin_Handled;
	}

	if (!CanPickupWeapon(iClient)) {
		return Plugin_Handled;
	}

	ShowMainMenu(iClient);

	return Plugin_Handled;
}

Action Cmd_ShowWeaponMenu(int iClient, int iArgs)
{
	if (!iClient) {
		return Plugin_Handled;
	}

	char sCmd[32]; GetCmdArg(0, sCmd, sizeof(sCmd));
	int iMenuIndex = 0;

	if (!GetTrieValue(g_hMenuCmds, sCmd, iMenuIndex)) {
		return Plugin_Continue;
	}

	if (!CanPickupWeapon(iClient)) {
		return Plugin_Handled;
	}

	ShowWeaponMenu(iClient, iMenuIndex);

	return Plugin_Handled;
}

Action Cmd_GiveWeapon(int iClient, int iArgs)
{
	if (!iClient) {
		return Plugin_Handled;
	}

	char sCmd[32]; GetCmdArg(0, sCmd, sizeof(sCmd));

	int iWeaponIndex = 0;

	if (!GetTrieValue(g_hWeaponCmds, sCmd, iWeaponIndex)) {
		return Plugin_Continue;
	}

	if (!CanPickupWeapon(iClient)) {
		return Plugin_Handled;
	}

	char sWeaponName[32];
	GetArrayString(g_hWeapons, iWeaponIndex, sWeaponName, sizeof(sWeaponName));

	PickupWeapon(iClient, sWeaponName);

	return Plugin_Handled;
}

void ShowMainMenu(int iClient)
{
	E_Menu menu;

	Menu hMenu = CreateMenu(HandlerMainMenu, MenuAction_Select|MenuAction_End);
	SetMenuTitle(hMenu, "%T", "MENU_MAIN",  iClient);

	int iArraySize = GetArraySize(g_hMenus);

	char sMenuItem[64], sMenuIndex[4];

	for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
	{
		GetArrayArray(g_hMenus, iIndex, menu);

		FormatEx(sMenuIndex, sizeof(sMenuIndex), "%d", iIndex);
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", menu.sName, iClient);

		AddMenuItem(hMenu, sMenuIndex, sMenuItem);
	}

	DisplayMenu(hMenu, iClient, -1);
}

int HandlerMainMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			char sMenuIndex[4];
			GetMenuItem(hMenu, iItem, sMenuIndex, sizeof(sMenuIndex));

			int iMenuIndex = StringToInt(sMenuIndex);

			ShowWeaponMenu(iClient, iMenuIndex);
		}
	}

	return 0;
}

void ShowWeaponMenu(int iClient, int iMenuIndex)
{
	E_Menu menu;

	GetArrayArray(g_hMenus, iMenuIndex, menu);

	int iArraySize = GetArraySize(menu.hItems);

	Menu hMenu = CreateMenu(HandlerWeaponMenu, MenuAction_Select|MenuAction_End);
	SetMenuTitle(hMenu, "%T", menu.sName, iClient);

	char sWeaponName[32], sMenuItem[64];
	for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
	{
		GetArrayString(g_hWeapons, GetArrayCell(menu.hItems, iIndex), sWeaponName, sizeof(sWeaponName));

		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", sWeaponName, iClient);

		AddMenuItem(hMenu, sWeaponName, sMenuItem);
	}

	DisplayMenu(hMenu, iClient, -1);
}

int HandlerWeaponMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			char sWeaponName[32];
			GetMenuItem(hMenu, iItem, sWeaponName, sizeof(sWeaponName));

			if (!CanPickupWeapon(iClient)) {
				return 0;
			}

			PickupWeapon(iClient, sWeaponName);
		}
	}

	return 0;
}

void RegConsoleCmdByMap(Handle &hType, ConCmd hCallback)
{
	Handle hSnapshot = CreateTrieSnapshot(hType);

	int iSize = TrieSnapshotLength(hSnapshot);

	char sCmd[32];

	for (int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetTrieSnapshotKey(hSnapshot, iIndex, sCmd, sizeof(sCmd));
		RegConsoleCmd(sCmd, hCallback);
	}

	CloseHandle(hSnapshot);
}

bool CanPickupWeapon(int iClient)
{
	if (g_bRoundIsLive)
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "ROUND_LIVE", iClient);
		return false;
	}

	if (!IsClientSurvivor(iClient) || !IsPlayerAlive(iClient))
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "ONLY_ALIVE_SURVIVOR", iClient);
		return false;
	}

	return true;
}

int PickupWeapon(int iClient, const char[] sWeaponName)
{
	int iSlot = 0;

	if (!GetTrieValue(g_hWeaponSlots, sWeaponName, iSlot)) {
		return -1;
	}

	int iEntOldWeapon = GetPlayerWeaponSlot(iClient, iSlot);

	if (iEntOldWeapon != -1) {
		RemovePlayerItem(iClient, iEntOldWeapon);
	}

	return GivePlayerItem(iClient, sWeaponName);
}

bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

void FillWeaponSlots(Handle hWeaponSlot)
{
	SetTrieValue(hWeaponSlot, "weapon_pistol", 1);
	SetTrieValue(hWeaponSlot, "weapon_smg", 0);
	SetTrieValue(hWeaponSlot, "weapon_pumpshotgun", 0);
	SetTrieValue(hWeaponSlot, "weapon_autoshotgun", 0);
	SetTrieValue(hWeaponSlot, "weapon_rifle", 0);
	SetTrieValue(hWeaponSlot, "weapon_hunting_rifle", 0);
	SetTrieValue(hWeaponSlot, "weapon_smg_silenced", 0);
	SetTrieValue(hWeaponSlot, "weapon_shotgun_chrome", 0);
	SetTrieValue(hWeaponSlot, "weapon_rifle_desert", 0);
	SetTrieValue(hWeaponSlot, "weapon_sniper_military", 0);
	SetTrieValue(hWeaponSlot, "weapon_shotgun_spas", 0);
	SetTrieValue(hWeaponSlot, "weapon_first_aid_kit", 3);
	SetTrieValue(hWeaponSlot, "weapon_molotov", 2);
	SetTrieValue(hWeaponSlot, "weapon_pipe_bomb", 2);
	SetTrieValue(hWeaponSlot, "weapon_pain_pills", 4);
	SetTrieValue(hWeaponSlot, "weapon_melee", 1);
	SetTrieValue(hWeaponSlot, "weapon_chainsaw", 1);
	SetTrieValue(hWeaponSlot, "weapon_grenade_launcher", 0);
	SetTrieValue(hWeaponSlot, "weapon_ammo_pack", 3);
	SetTrieValue(hWeaponSlot, "weapon_adrenaline", 4);
	SetTrieValue(hWeaponSlot, "weapon_defibrillator", 3);
	SetTrieValue(hWeaponSlot, "weapon_vomitjar", 2);
	SetTrieValue(hWeaponSlot, "weapon_rifle_ak47", 0);
	SetTrieValue(hWeaponSlot, "weapon_upgradepack_incendiary", 3);
	SetTrieValue(hWeaponSlot, "weapon_upgradepack_explosive", 3);
	SetTrieValue(hWeaponSlot, "weapon_pistol_magnum", 1);
	SetTrieValue(hWeaponSlot, "weapon_smg_mp5", 0);
	SetTrieValue(hWeaponSlot, "weapon_rifle_sg552", 0);
	SetTrieValue(hWeaponSlot, "weapon_sniper_awp", 0);
	SetTrieValue(hWeaponSlot, "weapon_sniper_scout", 0);
	SetTrieValue(hWeaponSlot, "weapon_rifle_m60", 0);
	SetTrieValue(hWeaponSlot, "baseball_bat", 1);
	SetTrieValue(hWeaponSlot, "cricket_bat", 1);
	SetTrieValue(hWeaponSlot, "crowbar", 1);
	SetTrieValue(hWeaponSlot, "electric_guitar", 1);
	SetTrieValue(hWeaponSlot, "fireaxe", 1);
	SetTrieValue(hWeaponSlot, "frying_pan", 1);
	SetTrieValue(hWeaponSlot, "golfclub", 1);
	SetTrieValue(hWeaponSlot, "katana", 1);
	SetTrieValue(hWeaponSlot, "knife", 1);
	SetTrieValue(hWeaponSlot, "machete", 1);
	SetTrieValue(hWeaponSlot, "pitchfork", 1);
	SetTrieValue(hWeaponSlot, "shovel", 1);
	SetTrieValue(hWeaponSlot, "tonfa", 1);
}
