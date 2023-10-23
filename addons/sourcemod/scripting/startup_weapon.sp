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
	version = "build0005"
};


#define TRANSLATIONS            "startup_weapon.phrases"
#define CONFIG_FILEPATH         "configs/startup_weapon.txt"

#define TEAM_SURVIVOR           2

#define WEAPON_NAME_SIZE        32
#define WEAPON_CMD_SIZE         32


char g_sConfigCategory[][] = {"Melee", "Tier1", "Tier2", "Tier3"};

char g_sConfigSection[WEAPON_NAME_SIZE];

int g_iConfigType = -1;

bool g_bRoundIsLive = false;

enum
{
	Melee = 0,
	Tier1,
	Tier2,
	Tier3,
	TypeSize
}

ConVar g_cvWeaponEnable[TypeSize];

bool g_bWeaponEnable[TypeSize];

Handle
	g_hWeapon[TypeSize],
	g_hCmd[TypeSize];


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
	for (int type = 0; type < TypeSize; type ++)
	{
		g_hCmd[type] = CreateTrie();
		g_hWeapon[type] = CreateArray(ByteCountToCells(WEAPON_NAME_SIZE));
	}

	LoadConfig(CONFIG_FILEPATH);

	// Cvars
	HookConVarChange((g_cvWeaponEnable[Melee] = CreateConVar("sm_sw_melee_enabled", "1")), OnMeleeEnableChanged);
	HookConVarChange((g_cvWeaponEnable[Tier1] = CreateConVar("sm_sw_tier1_enabled", "1")), OnTier1EnableChanged);
	HookConVarChange((g_cvWeaponEnable[Tier2] = CreateConVar("sm_sw_tier2_enabled", "0")), OnTier2EnableChanged);
	HookConVarChange((g_cvWeaponEnable[Tier3] = CreateConVar("sm_sw_tier3_enabled", "0")), OnTier3EnableChanged);

	// Register commands
	RegConsoleCmd("sm_w", Cmd_ShowMainMenu);

	RegConsoleCmd("sm_melee", Cmd_ShowMeleeMenu);
	RegConsoleCmd("sm_t1", Cmd_ShowTier1Menu);
	RegConsoleCmd("sm_t2", Cmd_ShowTier2Menu);
	RegConsoleCmd("sm_t3", Cmd_ShowTier3Menu);

	RegConsoleCmdByMap(g_hCmd[Melee], Cmd_GiveMelee);
	RegConsoleCmdByMap(g_hCmd[Tier1], Cmd_GiveTier1);
	RegConsoleCmdByMap(g_hCmd[Tier2], Cmd_GiveTier2);
	RegConsoleCmdByMap(g_hCmd[Tier3], Cmd_GiveTier3);

	// Events
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("weapon_drop", Event_WeaponDrop);

	for (int type = 0; type < TypeSize; type ++)
	{
		g_bWeaponEnable[type] = GetConVarBool(g_cvWeaponEnable[type]);
	}
}

public void OnPluginEnd()
{
	for (int type = 0; type < TypeSize; type ++)
	{
		CloseHandle(g_hCmd[type]);
		CloseHandle(g_hWeapon[type]);
	}
}

/**
 * Called when a console variable value is changed.
 */
public void OnMeleeEnableChanged(ConVar convar, const char[] sOldWeapon, const char[] sNewWeapon) {
	g_bWeaponEnable[Melee] = GetConVarBool(convar);
}

/**
 * Called when a console variable value is changed.
 */
public void OnTier1EnableChanged(ConVar convar, const char[] sOldWeapon, const char[] sNewWeapon) {
	g_bWeaponEnable[Tier1] = GetConVarBool(convar);
}

/**
 * Called when a console variable value is changed.
 */
public void OnTier2EnableChanged(ConVar convar, const char[] sOldWeapon, const char[] sNewWeapon) {
	g_bWeaponEnable[Tier2] = GetConVarBool(convar);
}

/**
 * Called when a console variable value is changed.
 */
public void OnTier3EnableChanged(ConVar convar, const char[] sOldWeapon, const char[] sNewWeapon) {
	g_bWeaponEnable[Tier3] = GetConVarBool(convar);
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

	char sWeaponName[WEAPON_NAME_SIZE];
	GetEventString(event, "item", sWeaponName, sizeof(sWeaponName));

	static const char sNoDupeWeapons[][] = {
		"smg_silenced", "smg", "smg_mp5",
		"pumpshotgun", "shotgun_chrome",
		"sniper_scout",
		"sniper_awp", "sniper_military", "hunting_rifle",
		"autoshotgun", "shotgun_spas",
		"rifle_ak47", "rifle_desert", "rifle_sg552", "rifle",
		"pistol_magnum", "pistol",
		"rifle_m60", "grenade_launcher"
	};

	for (int iItem = 0; iItem < sizeof(sNoDupeWeapons); iItem ++)
	{
		if (StrEqual(sNoDupeWeapons[iItem], sWeaponName, false))
		{
			RemoveEntity(GetEventInt(event, "propid"));
			break;
		}
	}

	return Plugin_Continue;
}

Action Cmd_GiveMelee(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Melee]) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE]; GetCmdArg(0, sCmd, sizeof(sCmd));

	return GiveWeaponByTypeAndCmd(iClient, Melee, sCmd);
}

Action Cmd_GiveTier1(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Tier1]) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE]; GetCmdArg(0, sCmd, sizeof(sCmd));

	return GiveWeaponByTypeAndCmd(iClient, Tier1, sCmd);
}

Action Cmd_GiveTier2(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Tier2]) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE]; GetCmdArg(0, sCmd, sizeof(sCmd));

	return GiveWeaponByTypeAndCmd(iClient, Tier2, sCmd);
}

Action Cmd_GiveTier3(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Tier3]) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE]; GetCmdArg(0, sCmd, sizeof(sCmd));

	return GiveWeaponByTypeAndCmd(iClient, Tier3, sCmd);
}

Action Cmd_ShowMainMenu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		ShowMainMenu(iClient);
	}

	return Plugin_Handled;
}

Action Cmd_ShowMeleeMenu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Melee]) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		ShowWeaponMenu(iClient, g_hWeapon[Melee]);
	}

	return Plugin_Handled;
}

Action Cmd_ShowTier1Menu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Tier1]) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		ShowWeaponMenu(iClient, g_hWeapon[Tier1]);
	}

	return Plugin_Handled;
}

Action Cmd_ShowTier2Menu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Tier2]) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		ShowWeaponMenu(iClient, g_hWeapon[Tier3]);
	}

	return Plugin_Handled;
}

Action Cmd_ShowTier3Menu(int iClient, int iArgs)
{
	if (!IsValidClient(iClient) || !g_bWeaponEnable[Tier3]) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		ShowWeaponMenu(iClient, g_hWeapon[Tier3]);
	}

	return Plugin_Handled;
}

void ShowMainMenu(int iClient)
{
	Menu hMenu = CreateMenu(HandlerMainMenu, MenuAction_Select|MenuAction_End);

	SetMenuTitle(hMenu, "%T", "MAIN_MENU_TITLE", iClient);

	if (g_bWeaponEnable[Melee]) {
		AddMenuItem(hMenu, "melee", "Melee (!melee)");
	}

	if (g_bWeaponEnable[Tier1]) {
		AddMenuItem(hMenu, "tier1", "Tier1 (!t1)");
	}

	if (g_bWeaponEnable[Tier2]) {
		AddMenuItem(hMenu, "tier2", "Tier2 (!t2)");
	}

	if (g_bWeaponEnable[Tier3]) {
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
				case 'e': ShowWeaponMenu(iClient, g_hWeapon[Melee]);
				case '1': ShowWeaponMenu(iClient, g_hWeapon[Tier1]);
				case '2': ShowWeaponMenu(iClient, g_hWeapon[Tier2]);
				case '3': ShowWeaponMenu(iClient, g_hWeapon[Tier3]);
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

void RegConsoleCmdByMap(Handle &hType, ConCmd hCallback)
{
	Handle hSnapshot = CreateTrieSnapshot(hType);

	int iSize = TrieSnapshotLength(hSnapshot);

	char sCmd[WEAPON_CMD_SIZE];

	for (int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetTrieSnapshotKey(hSnapshot, iIndex, sCmd, sizeof(sCmd));
		RegConsoleCmd(sCmd, hCallback);
	}

	CloseHandle(hSnapshot);
}

Action GiveWeaponByTypeAndCmd(int iClient, int iType, const char[] sCmd)
{
	char sWeaponName[WEAPON_NAME_SIZE];

	if (!GetTrieString(g_hCmd[iType], sCmd, sWeaponName, sizeof(sWeaponName))) {
		return Plugin_Continue;
	}

	if (CanPickupWeapon(iClient)) {
		PickupWeapon(iClient, sWeaponName);
	}

	return Plugin_Handled;
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

	g_iConfigType = -1;
	g_sConfigSection[0] = '\0';

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
	if (StrEqual(sSection, "Weapons", false)) {
		g_iConfigType = -1;
		return SMCParse_Continue;
	}

	for (int type = 0; type < TypeSize; type ++)
	{
		if (StrEqual(sSection, g_sConfigCategory[type], false))
		{
			g_iConfigType = type;
			return SMCParse_Continue;
		}
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
	if (g_iConfigType == -1) {
		return SMCParse_Continue;
	}

	if (StrEqual(sKey, "cmd", false)) {
		SetTrieString(g_hCmd[g_iConfigType], sValue, g_sConfigSection);
	}

	return SMCParse_Continue;
}

public SMCResult Parser_LeaveSection(SMCParser smc)
{
	if (g_iConfigType == -1) {
		return SMCParse_Continue;
	}

	if (g_sConfigSection[0] != '\0')
	{
		PushArrayString(g_hWeapon[g_iConfigType], g_sConfigSection);
		g_sConfigSection[0] = '\0';
	}
	
	else {
		g_iConfigType = -1;
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
