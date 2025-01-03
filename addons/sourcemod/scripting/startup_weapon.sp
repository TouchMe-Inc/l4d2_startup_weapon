#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdktools>
#include <colors>


public Plugin myinfo = {
    name        = "StartupWeapon",
    author      = "TouchMe",
    description = "Add weapons on survivors while they are in the saveroom",
    version     = "build_0007",
    url         = "https://github.com/TouchMe-Inc/l4d2_startup_weapon"
}


#define TRANSLATIONS            "startup_weapon.phrases"

#define DEFAULT_PATH_TO_CONFIG  "addons/sourcemod/configs/startup_weapon.txt"

#define TEAM_SURVIVOR           2

#define SLOT_PRIMARY            0
#define SLOT_SECONDARY          1


enum struct E_Menu
{
    char sName[32];
    Handle hItems;
}


ConVar g_cvPathToConfig = null;

bool g_bRoundIsLive = false;

Handle
    g_hWeaponSlots = null,
    g_hShortWeaponNames = null,
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

    g_cvPathToConfig = CreateConVar("sm_sw_path_to_cfg", DEFAULT_PATH_TO_CONFIG);
    HookConVarChange(g_cvPathToConfig, OnPathToCfgChanged);
    char sPath[PLATFORM_MAX_PATH]; GetConVarString(g_cvPathToConfig, sPath, sizeof(sPath));

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
    HookEvent("weapon_drop", Event_WeaponDrop, EventHookMode_Post);

    RegConsoleCmd("sm_w", Cmd_ShowMainMenu);

    FillWeaponSlots(g_hWeaponSlots = CreateTrie());
    FillShortWeaponNames(g_hShortWeaponNames = CreateTrie());

    g_hMenuCmds = CreateTrie();
    g_hWeaponCmds = CreateTrie();
    g_hMenus = CreateArray(sizeof(E_Menu));
    g_hWeapons = CreateArray(ByteCountToCells(32));
    LoadConfig(sPath);

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

    E_Menu menu;
    for (int iIndex = 0; iIndex < GetArraySize(g_hMenus); iIndex ++)
    {
        GetArrayArray(g_hMenus, iIndex, menu);
        CloseHandle(menu.hItems);
    }

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

    if (!IsValidEntity(iEnt)) {
        return Plugin_Stop;
    }

    char szWeaponName[32];
    GetEventString(event, "item", szWeaponName, sizeof(szWeaponName));

    int iDummy = 0;
    if (GetTrieValue(g_hShortWeaponNames, szWeaponName, iDummy)) {
        RemoveEntity(iEnt);
    }

    return Plugin_Continue;
}

Action Cmd_ShowMainMenu(int iClient, int iArgs)
{
    if (iClient <= 0 || !CanPickupWeapon(iClient)) {
        return Plugin_Handled;
    }

    ShowMainMenu(iClient);

    return Plugin_Handled;
}

Action Cmd_ShowWeaponMenu(int iClient, int iArgs)
{
    if (iClient <= 0) {
        return Plugin_Handled;
    }

    char szCmd[32]; GetCmdArg(0, szCmd, sizeof(szCmd));

    int iMenuIndex = 0;

    if (!GetTrieValue(g_hMenuCmds, szCmd, iMenuIndex)) {
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
    if (iClient <= 0) {
        return Plugin_Handled;
    }

    char szCmd[32]; GetCmdArg(0, szCmd, sizeof(szCmd));

    int iWeaponIndex = 0;

    if (!GetTrieValue(g_hWeaponCmds, szCmd, iWeaponIndex)) {
        return Plugin_Continue;
    }

    if (!CanPickupWeapon(iClient)) {
        return Plugin_Handled;
    }

    char szWeaponName[32];
    GetArrayString(g_hWeapons, iWeaponIndex, szWeaponName, sizeof(szWeaponName));

    PickupWeapon(iClient, szWeaponName);

    return Plugin_Handled;
}

void ShowMainMenu(int iClient)
{
    E_Menu menu;

    Menu hMenu = CreateMenu(HandlerMainMenu, MenuAction_Select|MenuAction_End);
    SetMenuTitle(hMenu, "%T", "MENU_MAIN", iClient);

    int iArraySize = GetArraySize(g_hMenus);

    char szMenuItem[64], szMenuIndex[4];

    for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
    {
        GetArrayArray(g_hMenus, iIndex, menu);

        FormatEx(szMenuIndex, sizeof(szMenuIndex), "%d", iIndex);
        FormatEx(szMenuItem, sizeof(szMenuItem), "%T", menu.sName, iClient);

        AddMenuItem(hMenu, szMenuIndex, szMenuItem);
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
            char szMenuIndex[4];
            GetMenuItem(hMenu, iItem, szMenuIndex, sizeof(szMenuIndex));

            int iMenuIndex = StringToInt(szMenuIndex);

            ShowWeaponMenu(iClient, iMenuIndex);
        }
    }

    return 0;
}

void ShowWeaponMenu(int iClient, int iMenuIndex)
{
    E_Menu menu;

    GetArrayArray(g_hMenus, iMenuIndex, menu);

    Menu hMenu = CreateMenu(HandlerWeaponMenu, MenuAction_Select|MenuAction_End);
    SetMenuTitle(hMenu, "%T", menu.sName, iClient);

    int iArraySize = GetArraySize(menu.hItems);

    char szWeaponName[32], szMenuItem[64];

    for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
    {
        GetArrayString(g_hWeapons, GetArrayCell(menu.hItems, iIndex), szWeaponName, sizeof(szWeaponName));

        FormatEx(szMenuItem, sizeof(szMenuItem), "%T", szWeaponName, iClient);

        AddMenuItem(hMenu, szWeaponName, szMenuItem);
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
            char szWeaponName[32];
            GetMenuItem(hMenu, iItem, szWeaponName, sizeof(szWeaponName));

            if (!CanPickupWeapon(iClient)) {
                return 0;
            }

            PickupWeapon(iClient, szWeaponName);
        }
    }

    return 0;
}

void RegConsoleCmdByMap(Handle &hType, ConCmd hCallback)
{
    Handle hSnapshot = CreateTrieSnapshot(hType);

    int iSize = TrieSnapshotLength(hSnapshot);

    char szCmd[32];

    for (int iIndex = 0; iIndex < iSize; iIndex ++)
    {
        GetTrieSnapshotKey(hSnapshot, iIndex, szCmd, sizeof(szCmd));
        RegConsoleCmd(szCmd, hCallback);
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

int PickupWeapon(int iClient, const char[] szWeaponName)
{
    int iSlot = 0;

    if (!GetTrieValue(g_hWeaponSlots, szWeaponName, iSlot)) {
        return -1;
    }

    int iEntOldWeapon = GetPlayerWeaponSlot(iClient, iSlot);

    if (iEntOldWeapon != -1) {
        RemovePlayerItem(iClient, iEntOldWeapon);
    }

    return GivePlayerItem(iClient, szWeaponName);
}

bool IsClientSurvivor(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SURVIVOR);
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
        char sSectionName[32], sSectionKey[16], sSectionValue[32], szWeaponName[32], sWeaponKey[16], sWeaponValue[32];

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
                            KvGetSectionName(hConfigList, szWeaponName, sizeof(szWeaponName));

                            iWeaponIndex = PushArrayString(g_hWeapons, szWeaponName);

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

void FillWeaponSlots(Handle hWeaponSlot)
{
    SetTrieValue(hWeaponSlot, "weapon_smg",              SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_pumpshotgun",      SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_autoshotgun",      SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_rifle",            SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_hunting_rifle",    SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_smg_silenced",     SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_shotgun_chrome",   SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_rifle_desert",     SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_sniper_military",  SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_shotgun_spas",     SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_grenade_launcher", SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_rifle_ak47",       SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_smg_mp5",          SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_rifle_sg552",      SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_sniper_awp",       SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_sniper_scout",     SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_rifle_m60",        SLOT_PRIMARY);
    SetTrieValue(hWeaponSlot, "weapon_melee",            SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "weapon_chainsaw",         SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "weapon_pistol",           SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "weapon_pistol_magnum",    SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "baseball_bat",            SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "cricket_bat",             SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "crowbar",                 SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "electric_guitar",         SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "fireaxe",                 SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "frying_pan",              SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "golfclub",                SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "katana",                  SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "knife",                   SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "machete",                 SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "pitchfork",               SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "shovel",                  SLOT_SECONDARY);
    SetTrieValue(hWeaponSlot, "tonfa",                   SLOT_SECONDARY);
}

void FillShortWeaponNames(Handle hShortWeaponNames)
{
    SetTrieValue(hShortWeaponNames, "smg",              0);
    SetTrieValue(hShortWeaponNames, "pumpshotgun",      0);
    SetTrieValue(hShortWeaponNames, "autoshotgun",      0);
    SetTrieValue(hShortWeaponNames, "rifle",            0);
    SetTrieValue(hShortWeaponNames, "hunting_rifle",    0);
    SetTrieValue(hShortWeaponNames, "smg_silenced",     0);
    SetTrieValue(hShortWeaponNames, "shotgun_chrome",   0);
    SetTrieValue(hShortWeaponNames, "rifle_desert",     0);
    SetTrieValue(hShortWeaponNames, "sniper_military",  0);
    SetTrieValue(hShortWeaponNames, "shotgun_spas",     0);
    SetTrieValue(hShortWeaponNames, "grenade_launcher", 0);
    SetTrieValue(hShortWeaponNames, "rifle_ak47",       0);
    SetTrieValue(hShortWeaponNames, "smg_mp5",          0);
    SetTrieValue(hShortWeaponNames, "rifle_sg552",      0);
    SetTrieValue(hShortWeaponNames, "sniper_awp",       0);
    SetTrieValue(hShortWeaponNames, "sniper_scout",     0);
    SetTrieValue(hShortWeaponNames, "rifle_m60",        0);
    SetTrieValue(hShortWeaponNames, "melee",            0);
    SetTrieValue(hShortWeaponNames, "chainsaw",         0);
    SetTrieValue(hShortWeaponNames, "pistol",           0);
    SetTrieValue(hShortWeaponNames, "pistol_magnum",    0);
}
