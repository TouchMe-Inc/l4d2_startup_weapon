#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>


public Plugin myinfo =
{
	name = "StartupWeapon",
	author = "TouchMe",
	description = "Add weapons on survivors while they are in the saveroom",
	version = "build0004"
};


#define TRANSLATIONS            "startup_weapon.phrases"
#define CONFIG_FILEPATH         "configs/startup_weapon.txt"

#define TEAM_SURVIVOR           2

#define WEAPON_NAME_SIZE        32
#define WEAPON_CMD_SIZE         32

// Macros
#define MELEE_ENABLE            (GetConVarBool(g_cvMelee))
#define T1_ENABLE               (GetConVarBool(g_cvTier1))
#define T2_ENABLE               (GetConVarBool(g_cvTier2))
#define T3_ENABLE               (GetConVarBool(g_cvTier3))

// Vars

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

bool g_bRoundIsLive = false;

ConVar
	g_cvMelee = null,
	g_cvTier1 = null,
	g_cvTier2 = null,
	g_cvTier3 = null;

Handle
	g_hMeleeCmd = INVALID_HANDLE,
	g_hTier1Cmd = INVALID_HANDLE,
	g_hTier2Cmd = INVALID_HANDLE,
	g_hTier3Cmd = INVALID_HANDLE,
	g_hMelee = INVALID_HANDLE,
	g_hTier1 = INVALID_HANDLE,
	g_hTier2 = INVALID_HANDLE,
	g_hTier3 = INVALID_HANDLE;


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
	LoadTranslations(TRANSLATIONS);

	// Config
	g_hMeleeCmd = CreateTrie();
	g_hTier1Cmd = CreateTrie();
	g_hTier2Cmd = CreateTrie();
	g_hTier3Cmd = CreateTrie();
	g_hMelee = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));
	g_hTier1 = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));
	g_hTier2 = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));
	g_hTier3 = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));

	LoadConfig(CONFIG_FILEPATH);

	// Cvars
	(g_cvMelee = CreateConVar("sm_sw_melee_enabled", "1"));
	(g_cvTier1 = CreateConVar("sm_sw_tier1_enabled", "1"));
	(g_cvTier2 = CreateConVar("sm_sw_tier2_enabled", "0"));
	(g_cvTier3 = CreateConVar("sm_sw_tier3_enabled", "0"));

	// Register commands
	RegCmds(g_hMeleeCmd);
	RegCmds(g_hTier1Cmd);
	RegCmds(g_hTier2Cmd);
	RegCmds(g_hTier3Cmd);

	RegConsoleCmd("sm_w", Cmd_ShowMainMenu);

	RegConsoleCmd("sm_melee", Cmd_ShowWeaponMenu);
	RegConsoleCmd("sm_t1", Cmd_ShowWeaponMenu);
	RegConsoleCmd("sm_t2", Cmd_ShowWeaponMenu);
	RegConsoleCmd("sm_t3", Cmd_ShowWeaponMenu);

	// Events
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("weapon_drop", Event_WeaponDrop);
}

void RegCmds(Handle &hType)
{
	Handle hSnapshot = CreateTrieSnapshot(hType);

	int iSize = TrieSnapshotLength(hSnapshot);

	char sCmd[WEAPON_CMD_SIZE];

	for(int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetTrieSnapshotKey(hSnapshot, iIndex, sCmd, sizeof(sCmd));
		RegConsoleCmd(sCmd, Cmd_GiveWeapon);
	}

	CloseHandle(hSnapshot);
}

void Event_RoundStart(Event hEvent, const char[] name, bool dontBroadcast) {
	g_bRoundIsLive = false;
}

void Event_LeftStartArea(Event hEvent, const char[] name, bool dontBroadcast) {
	g_bRoundIsLive = true;
}

Action Event_WeaponDrop(Event hEvent, const char[] name, bool dontBroadcast)
{
	if (g_bRoundIsLive) {
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

Action Cmd_GiveWeapon(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE];
	GetCmdArg(0, sCmd, sizeof(sCmd));

	char sWeaponName[WEAPON_NAME_SIZE];

	if ((!MELEE_ENABLE || !GetTrieString(g_hMeleeCmd, sCmd, sWeaponName, sizeof(sWeaponName)))
		&& (!T1_ENABLE || !GetTrieString(g_hTier1Cmd, sCmd, sWeaponName, sizeof(sWeaponName)))
		&& (!T2_ENABLE || !GetTrieString(g_hTier2Cmd, sCmd, sWeaponName, sizeof(sWeaponName)))
		&& (!T3_ENABLE || !GetTrieString(g_hTier3Cmd, sCmd, sWeaponName, sizeof(sWeaponName)))) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		PickupWeapon(iClient, sWeaponName);
	}

	return Plugin_Handled;
}

Action Cmd_ShowMainMenu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	if (!CanPickupWeapon(iClient)) {
		return Plugin_Handled;
	}

	ShowMainMenu(iClient);

	return Plugin_Handled;
}

Action Cmd_ShowWeaponMenu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !CanPickupWeapon(iClient)) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE];
	GetCmdArg(0, sCmd, sizeof(sCmd));

	switch(sCmd[4])
	{
		case 'e': MELEE_ENABLE && ShowWeaponMenu(iClient, g_hMelee);
		case '1': T1_ENABLE && ShowWeaponMenu(iClient, g_hTier1);
		case '2': T2_ENABLE && ShowWeaponMenu(iClient, g_hTier2);
		case '3': T3_ENABLE && ShowWeaponMenu(iClient, g_hTier3);
	}

	return Plugin_Continue;
}

void ShowMainMenu(int iClient)
{
	Menu hMenu = CreateMenu(HandlerMainMenu, MenuAction_Select|MenuAction_End);

	SetMenuTitle(hMenu, "%T", "MAIN_MENU_TITLE", iClient);

	if (MELEE_ENABLE) {
		AddMenuItem(hMenu, "melee", "Melee (!melee)");
	}

	if (T1_ENABLE) {
		AddMenuItem(hMenu, "tier1", "Tier1 (!t1)");
	}

	if (T2_ENABLE) {
		AddMenuItem(hMenu, "tier2", "Tier2 (!t2)");
	}

	if (T3_ENABLE) {
		AddMenuItem(hMenu, "tier3", "Tier3 (!t3)");
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

int HandlerWeaponMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
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

void PickupWeapon(int iClient, const char[] sWeaponName)
{
	int iEntOldWeapon = GetPlayerWeaponSlot(iClient, IsSecondary(sWeaponName) ? 1 : 0);

	if (iEntOldWeapon != -1) {
		RemovePlayerItem(iClient, iEntOldWeapon);
	}

	GivePlayerItem(iClient, sWeaponName);
}


bool LoadConfig(const char[] sPathToConfig)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, sPathToConfig);

	if (!FileExists(sPath)) {
		SetFailState("File %s not found", sPath);
	}

	Handle hParser = SMC_CreateParser();

	int iLine = 0;
	int iColumn = 0;

	SMC_SetReaders(hParser, Parser_EnterSection, Parser_KeyValue, Parser_LeaveSection);
	
	SMCError hResult = SMC_ParseFile(hParser, sPath, iLine, iColumn);
	
	CloseHandle(hParser);

	if (hResult != SMCError_Okay)
	{
		char sError[128];
		SMC_GetErrorString(hResult, sError, sizeof(sError));
		LogError("%s on line %d, col %d of %s", sError, iLine, iColumn, sPath);
	}

	return (hResult == SMCError_Okay);
}

public SMCResult Parser_EnterSection(SMCParser smc, const char[] sSection, bool opt_quotes)
{
	if (StrEqual(sSection, "Weapons", false))
	{
		g_tConfigSection = ConfigSection_Weapons;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Melee", false))
	{
		g_tConfigSection = ConfigSection_Melee;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Tier1", false))
	{
		g_tConfigSection = ConfigSection_Tier1;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Tier2", false))
	{
		g_tConfigSection = ConfigSection_Tier2;
		return SMCParse_Continue;
	}

	if (StrEqual(sSection, "Tier3", false))
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

	if (StrEqual(sKey, "cmd", false))
	{
		switch(g_tConfigSection)
		{
			case ConfigSection_Melee: SetTrieString(g_hMeleeCmd, sValue, g_sConfigSection);
			case ConfigSection_Tier1: SetTrieString(g_hTier1Cmd, sValue, g_sConfigSection);
			case ConfigSection_Tier2: SetTrieString(g_hTier2Cmd, sValue, g_sConfigSection);
			case ConfigSection_Tier3: SetTrieString(g_hTier3Cmd, sValue, g_sConfigSection);
		}
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
