#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN


public Plugin myinfo =
{
	name = "StartupWeapon",
	author = "TouchMe",
	description = "Add weapons on survivors while they are in the saveroom",
	version = "build0003"
};

// Libs
#define LIB_READY               "readyup"

#define TRANSLATIONS            "startup_weapon.phrases"
#define CONFIG_FILEPATH         "configs/startup_weapon.txt"

#define TEAM_SURVIVOR           2

#define WEAPON_NAME_SIZE        32
#define WEAPON_CMD_SIZE         32


// Vars
SMCParser g_hParser;

enum ConfigSection
{
	ConfigSection_None,
	ConfigSection_Weapons,
	ConfigSection_Melee,
	ConfigSection_Tier1,
	ConfigSection_Tier2,
	ConfigSection_Tier3
}

ConfigSection g_tConfigSection = ConfigSection_None;

char g_sConfigSection[WEAPON_NAME_SIZE];

bool
	g_bReadyUpAvailable = false,
	g_bRoundIsLive = false,
	g_bMeleeEnabled = false,
	g_bTier1Enabled = false,
	g_bTier2Enabled = false,
	g_bTier3Enabled = false;

Handle
	g_hWeapons = INVALID_HANDLE,
	g_hMelee = INVALID_HANDLE,
	g_hTier1 = INVALID_HANDLE,
	g_hTier2 = INVALID_HANDLE,
	g_hTier3 = INVALID_HANDLE;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded() {
	g_bReadyUpAvailable = LibraryExists(LIB_READY);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName 			Library name.
  */
public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = false;
	}
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName 			Library name.
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = true;
	}
}

/**
  * Called before OnPluginStart.
  */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
  * Called when the map loaded.
  */
public void OnMapStart() {
	g_bRoundIsLive = false;
}

public void OnPluginStart()
{
	g_hWeapons = CreateTrie();
	g_hMelee = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));
	g_hTier1 = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));
	g_hTier2 = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));
	g_hTier3 = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));

	g_bMeleeEnabled = GetConVarBool(CreateConVar("sm_sw_melee_enabled", "1"));
	g_bTier1Enabled = GetConVarBool(CreateConVar("sm_sw_tier1_enabled", "1"));
	g_bTier2Enabled = GetConVarBool(CreateConVar("sm_sw_tier2_enabled", "0"));
	g_bTier3Enabled = GetConVarBool(CreateConVar("sm_sw_tier3_enabled", "0"));

	LoadTranslations(TRANSLATIONS);

	LoadConfig(CONFIG_FILEPATH);

	RegCmds();

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("weapon_drop", Event_WeaponDrop);
}

/**
 * Called when the plugin is about to be unloaded.
 */
public void OnPluginEnd()
{
	CloseHandle(g_hWeapons);
	CloseHandle(g_hMelee);
	CloseHandle(g_hTier1);
	CloseHandle(g_hTier2);
	CloseHandle(g_hTier3);
}

void RegCmds()
{
	Handle hSnapshot = CreateTrieSnapshot(g_hWeapons);

	int iSize = TrieSnapshotLength(hSnapshot);

	char sCmd[WEAPON_CMD_SIZE];

	for(int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetTrieSnapshotKey(hSnapshot, iIndex, sCmd, sizeof(sCmd));
		RegConsoleCmd(sCmd, Cmd_GiveWeapon);
	}

	CloseHandle(hSnapshot);

	RegConsoleCmd("sm_w", Cmd_ShowMainMenu);

	g_bMeleeEnabled && RegConsoleCmd("sm_melee", Cmd_ShowWeaponMenu);
	g_bTier1Enabled && RegConsoleCmd("sm_t1", Cmd_ShowWeaponMenu);
	g_bTier2Enabled && RegConsoleCmd("sm_t2", Cmd_ShowWeaponMenu);
	g_bTier3Enabled && RegConsoleCmd("sm_t3", Cmd_ShowWeaponMenu);
}

public Action Cmd_GiveWeapon(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE];
	GetCmdArg(0, sCmd, sizeof(sCmd));

	char sWeaponName[WEAPON_NAME_SIZE];

	if (!GetTrieString(g_hWeapons, sCmd, sWeaponName, sizeof(sWeaponName))) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		PickupWeapon(iClient, sWeaponName);
	}

	return Plugin_Continue;
}

public Action Cmd_ShowMainMenu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)
	|| !CanPickupWeapon(iClient)) {
		return Plugin_Continue;
	}

	Menu hMenu = CreateMenu(HandlerMainMenu, MenuAction_Select|MenuAction_End);

	SetMenuTitle(hMenu, "%T", "MAIN_MENU_TITLE", iClient);

	if (g_bMeleeEnabled) {
		AddMenuItem(hMenu, "melee", "Melee (!melee)");
	}

	if (g_bTier1Enabled) {
		AddMenuItem(hMenu, "tier1", "Tier1 (!t1)");
	}

	if (g_bTier2Enabled) {
		AddMenuItem(hMenu, "tier2", "Tier2 (!t2)");
	}

	if (g_bTier3Enabled) {
		AddMenuItem(hMenu, "tier3", "Tier3 (!t3)");
	}

	DisplayMenu(hMenu, iClient, -1);

	return Plugin_Continue;
}

public int HandlerMainMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			if (!CanPickupWeapon(iClient)) {
				return 0;
			}

			char sItem[16]; GetMenuItem(hMenu, iItem, sItem, sizeof(sItem));

			switch(sItem[4])
			{
				case 'e': ShowWeaponMenu(iClient, g_hMelee);
				case '1': ShowWeaponMenu(iClient, g_hTier1);
				case '2': ShowWeaponMenu(iClient, g_hTier2);
				case '3': ShowWeaponMenu(iClient, g_hTier3);
			}
		}
	}

	return 0;
}

void ShowWeaponMenu(int iClient, Handle &hType)
{
	int iSize = GetArraySize(hType);
	char sWeaponName[WEAPON_NAME_SIZE], sMenuItem[64];

	Menu hMenu = CreateMenu(HandlerWeaponMenu, MenuAction_Select|MenuAction_End);
	SetMenuTitle(hMenu, "%T", "WEAPON_MENU_TITLE", iClient);

	for (int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetArrayString(hType, iIndex, sWeaponName, sizeof(sWeaponName));

		Format(sMenuItem, sizeof(sMenuItem), "%T", sWeaponName, iClient);

		AddMenuItem(hMenu, sWeaponName, sMenuItem);
	}

	DisplayMenu(hMenu, iClient, -1);
}

public int HandlerWeaponMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			char sWeaponName[WEAPON_NAME_SIZE];
			GetMenuItem(hMenu, iItem, sWeaponName, sizeof(sWeaponName));

			if (CanPickupWeapon(iClient)) {
				PickupWeapon(iClient, sWeaponName);
			}
		}
	}

	return 0;
}

public Action Cmd_ShowWeaponMenu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)
	|| !CanPickupWeapon(iClient)) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE];
	GetCmdArg(0, sCmd, sizeof(sCmd));

	switch(sCmd[4])
	{
		case 'e': ShowWeaponMenu(iClient, g_hMelee);
		case '1': ShowWeaponMenu(iClient, g_hTier1);
		case '2': ShowWeaponMenu(iClient, g_hTier2);
		case '3': ShowWeaponMenu(iClient, g_hTier3);
	}

	return Plugin_Continue;
}

public Action Event_RoundStart(Event hEvent, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = false;
	}

	return Plugin_Continue;
}

public Action Event_LeftStartArea(Event hEvent, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = true;
	}

	return Plugin_Continue;
}

public Action Event_WeaponDrop(Event hEvent, const char[] name, bool dontBroadcast)
{
	if (g_bReadyUpAvailable && !IsInReady()
	|| !g_bReadyUpAvailable && g_bRoundIsLive) {
		return Plugin_Continue;
	}

	char sWeaponName[WEAPON_NAME_SIZE];
	GetEventString(hEvent, "item", sWeaponName, sizeof(sWeaponName));

	if (sWeaponName[0] == '\0') {
		return Plugin_Continue;
	}

	static const char sWeapons[][] = {
		"smg_silenced", "smg", "smg_mp5",
		"pumpshotgun", "shotgun_chrome",
		"sniper_scout",
		"sniper_awp", "sniper_military", "hunting_rifle",
		"autoshotgun", "shotgun_spas",
		"rifle_ak47", "rifle_desert", "rifle_sg552", "rifle",
		"pistol_magnum", "pistol",
		"rifle_m60", "grenade_launcher"
	};

	for (int iItem = 0; iItem < sizeof(sWeapons); iItem ++)
	{
		if (StrEqual(sWeapons[iItem], sWeaponName, false))
		{
			RemoveEntity(GetEventInt(hEvent, "propid"));
			break;
		}
	}

	return Plugin_Continue;
}

bool CanPickupWeapon(int iClient)
{
	if (g_bReadyUpAvailable && !IsInReady())
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "LEFT_READYUP", iClient);
		return false;
	}

	if (!g_bReadyUpAvailable && g_bRoundIsLive)
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

void PickupWeapon(int iClient, const char[] sWeaponName)
{
	int iEntOldWeapon = GetPlayerWeaponSlot(iClient, IsSecondary(sWeaponName) ? 1 : 0);

	if (iEntOldWeapon != -1) {
		RemovePlayerItem(iClient, iEntOldWeapon);
	}

	GivePlayerItem(iClient, sWeaponName);
}


void LoadConfig(const char[] sPathToConfig)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, sPathToConfig);

	if (!FileExists(sPath)) {
		SetFailState("File %s not found", sPath);
	}

	g_hParser = new SMCParser();
	g_hParser.OnEnterSection = Parser_EnterSection;
	g_hParser.OnKeyValue = Parser_KeyValue;
	g_hParser.OnLeaveSection = Parser_LeaveSection;

	SMCError err = g_hParser.ParseFile(sPath);

	if (err != SMCError_Okay)
	{
		char buffer[64];
		if (g_hParser.GetErrorString(err, buffer, sizeof(buffer))) {
			LogError("%s", buffer);
		}
	}
}

public SMCResult Parser_EnterSection(SMCParser smc, const char[] sSection, bool opt_quotes)
{
	if (StrEqual(sSection, "Weapons", false))
	{
		g_tConfigSection = ConfigSection_Weapons;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Melee", false) && g_bMeleeEnabled)
	{
		g_tConfigSection = ConfigSection_Melee;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Tier1", false) && g_bTier1Enabled)
	{
		g_tConfigSection = ConfigSection_Tier1;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Tier2", false) && g_bTier2Enabled)
	{
		g_tConfigSection = ConfigSection_Tier2;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Tier3", false) && g_bTier3Enabled)
	{
		g_tConfigSection = ConfigSection_Tier3;
		return SMCParse_Continue;
	}

	strcopy(g_sConfigSection, sizeof(g_sConfigSection), sSection);

	return SMCParse_Continue;
}

public SMCResult Parser_KeyValue(SMCParser smc,
									const char[] sKey,
									const char[] sValue,
									bool key_quotes,
									bool value_quotes)
{
	if (g_tConfigSection != ConfigSection_Melee
	&& g_tConfigSection != ConfigSection_Tier1
	&& g_tConfigSection != ConfigSection_Tier2
	&& g_tConfigSection != ConfigSection_Tier3) {
		return SMCParse_Continue;
	}

	if (StrEqual(sKey, "cmd", false)) {
		SetTrieString(g_hWeapons, sValue, g_sConfigSection);
	}

	return SMCParse_Continue;
}

public SMCResult Parser_LeaveSection(SMCParser smc)
{
	if (g_tConfigSection == ConfigSection_Melee
	|| g_tConfigSection == ConfigSection_Tier1
	|| g_tConfigSection == ConfigSection_Tier2
	|| g_tConfigSection == ConfigSection_Tier3)
	{
		if (g_sConfigSection[0] != '\0')
		{
			switch(g_tConfigSection)
			{
				case ConfigSection_Melee: PushArrayString(g_hMelee, g_sConfigSection);
				case ConfigSection_Tier1: PushArrayString(g_hTier1, g_sConfigSection);
				case ConfigSection_Tier2: PushArrayString(g_hTier2, g_sConfigSection);
				case ConfigSection_Tier3: PushArrayString(g_hTier3, g_sConfigSection);
			}

			g_sConfigSection[0] = '\0';
		}

		else {
			g_tConfigSection = ConfigSection_Weapons;
		}
	}

	return SMCParse_Continue;
}

bool IsSecondary(const char[] sWeaponName)
{
	static const char sWeapons[][] = {
		"weapon_pistol_magnum", "weapon_pistol",
		"baseball_bat", "cricket_bat",
		"crowbar", "electric_guitar",
		"fireaxe", "frying_pan",
		"golfclub", "katana",
		"knife", "machete",
		"pitchfork", "shovel",
		"tonfa"
	};

	for (int iItem = 0; iItem < sizeof(sWeapons); iItem ++)
	{
		if (StrEqual(sWeapons[iItem], sWeaponName, false)) {
			return true;
		}
	}

	return false;
}

bool IsValidClient(int iClient) {
	return (iClient > 0 && iClient <= MaxClients);
}

bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}
