#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdktools>
#include <colors>


public Plugin myinfo = {
    name        = "StartupWeapon",
    author      = "TouchMe",
    description = "Add weapons on survivors while they are in the saveroom",
    version     = "build_0008",
    url         = "https://github.com/TouchMe-Inc/l4d2_startup_weapon"
}


#define TRANSLATIONS            "startup_weapon.phrases"

#define DEFAULT_PATH_TO_CONFIG  "addons/sourcemod/configs/startup_weapon.txt"

#define TEAM_SURVIVOR           2

#define SLOT_PRIMARY            0
#define SLOT_SECONDARY          1


/*
 * String size limits.
 */
#define MAXLENGTH_NODE_KEY      32
#define MAXLENGTH_NODE_VALUE    64
#define MAXLENGTH_EL_NAME       64
#define MAXLENGTH_EL_CMD        32

enum struct NodeItem
{
    char key[MAXLENGTH_NODE_KEY];
    char value[MAXLENGTH_NODE_VALUE];
    ArrayList children;
}

enum MenuElementType
{
    Element_Item,
    Element_Category
}

enum struct MenuElement
{
    MenuElementType type;
    char name[MAXLENGTH_EL_NAME];
    char cmd[MAXLENGTH_EL_CMD];
    ArrayList children;

    void Create(MenuElementType t)
    {
        this.type = t;
        this.name[0] = '\0';
        this.cmd[0] = '\0';

        switch (t)
        {
            case Element_Category: this.children = new ArrayList(sizeof MenuElement);
            case Element_Item: this.children = null;
        }
    }

    void AddChild(MenuElement child)
    {
        if (this.type == Element_Category) {
            this.children.PushArray(child);
        }
    }

    bool IsCategory() {
        return this.type == Element_Category;
    }
}


ConVar g_cvPathToConfig = null;

bool g_bRoundIsLive = false;
bool g_bClientUseMenu[MAXPLAYERS + 1] = {false, ...};
MenuElement g_eClientActiveCategory[MAXPLAYERS + 1];

StringMap g_hWeaponSlots = null;
StringMap g_hShortWeaponNames = null;

StringMap g_smMenuElementCache = null;
ArrayList g_aMenuElements = null;


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

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
    HookEvent("weapon_drop", Event_WeaponDrop, EventHookMode_Post);

    RegConsoleCmd("sm_w", Cmd_ShowMainMenu);
    AddCommandListener(Cmd_Say, "say");
    AddCommandListener(Cmd_Say, "say_team");
    AddCommandListener(ConCmd_Any);

    g_hWeaponSlots = new StringMap();
    g_hShortWeaponNames = new StringMap();

    FillWeaponSlots(g_hWeaponSlots);
    FillShortWeaponNames(g_hShortWeaponNames);

    char szPath[PLATFORM_MAX_PATH];
    GetConVarString(g_cvPathToConfig, szPath, sizeof szPath);

    g_smMenuElementCache = new StringMap();
    g_aMenuElements = BuildMenu(szPath);
    PushMenuElementToCache(g_smMenuElementCache, g_aMenuElements);
}

/**
  * Called when the map loaded.
  */
public void OnMapStart() {
    g_bRoundIsLive = false;
}

Action Cmd_Say(int iClient, const char[] szCmd, int iArgs)
{
    if (!iClient || !IsClientConnected(iClient)) {
        return Plugin_Continue;
    }

    char szMessage[32];
    GetCmdArgString(szMessage, sizeof szMessage);
    TrimString(szMessage);
    StripQuotes(szMessage);

    MenuElement element;
    if ((szMessage[0] == '!' || szMessage[0] == '/') && g_smMenuElementCache.GetArray(szMessage[1], element, sizeof element))
    {
        if (element.IsCategory())
        {
            g_eClientActiveCategory[iClient] = element;
            ShowWeaponMenu(iClient, element);
            return Plugin_Handled;
        }

        if (!CanPickupWeapon(iClient)) {
            return Plugin_Handled;
        }

        PickupWeapon(iClient, element.name);
        g_bClientUseMenu[iClient] = true;

        return Plugin_Handled;
    }

    return Plugin_Continue;
}

Action ConCmd_Any(int iClient, const char[] szCmd, int iArgs)
{
    if (!iClient || !IsClientConnected(iClient)) {
        return Plugin_Continue;
    }

    MenuElement element;
    if (StrContains(szCmd, "sm_", false) == 0 && g_smMenuElementCache.GetArray(szCmd[3], element, sizeof element))
    {
        if (element.IsCategory())
        {
            g_eClientActiveCategory[iClient] = element;
            ShowWeaponMenu(iClient, element);
            return Plugin_Handled;
        }

        if (!CanPickupWeapon(iClient)) {
            return Plugin_Handled;
        }

        PickupWeapon(iClient, element.name);
        g_bClientUseMenu[iClient] = true;

        return Plugin_Handled;
    }

    return Plugin_Continue;
}

/**
 *
 */
void OnPathToCfgChanged(ConVar cv, const char[] szOldPath, const char[] szNewPath)
{
    delete g_smMenuElementCache;
    delete g_aMenuElements;

    char szPath[PLATFORM_MAX_PATH];
    GetConVarString(cv, szPath, sizeof szPath);

    g_smMenuElementCache = new StringMap();
    g_aMenuElements = BuildMenu(szPath);
    PushMenuElementToCache(g_smMenuElementCache, g_aMenuElements);
}

void Event_RoundStart(Event event, const char[] sName, bool bDontBroadcast)
{
    g_bRoundIsLive = false;

    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        g_bClientUseMenu[iClient] = false;
    }
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

    if (!g_bClientUseMenu[iClient]) {
        return Plugin_Continue;
    }

    int iEnt = GetEventInt(event, "propid");

    if (!IsValidEntity(iEnt)) {
        return Plugin_Stop;
    }

    char szWeaponName[32];
    GetEventString(event, "item", szWeaponName, sizeof szWeaponName);

    int iDummy = 0;
    if (GetTrieValue(g_hShortWeaponNames, szWeaponName, iDummy)) {
        RemoveEntity(iEnt);
    }

    return Plugin_Continue;
}

Action Cmd_ShowMainMenu(int iClient, int iArgs)
{
    if (!iClient) {
        return Plugin_Handled;
    }

    ShowMainMenu(iClient);

    return Plugin_Handled;
}

void ShowMainMenu(int iClient)
{
    Menu menu = CreateMenu(HandlerMainMenu, MenuAction_Select|MenuAction_End);
    menu.SetTitle("%T", "MENU_MAIN", iClient);

    char szMenuItem[64], szMenuIndex[4];

    MenuElement element;
    int iArraySize = g_aMenuElements.Length;
    for (int iIdx = 0; iIdx < iArraySize; iIdx++)
    {
        GetArrayArray(g_aMenuElements, iIdx, element);

        FormatEx(szMenuIndex, sizeof szMenuIndex, "%d", iIdx);

        if (TranslationPhraseExists(element.name)) {
            FormatEx(szMenuItem, sizeof szMenuItem, "%T", element.name, iClient);
        } else {
            FormatEx(szMenuItem, sizeof szMenuItem, "%s", element.name);
        }

        menu.AddItem(szMenuIndex, szMenuItem);
    }

    menu.Display(iClient, MENU_TIME_FOREVER);
}

int HandlerMainMenu(Menu menu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szMenuIndex[4];
            menu.GetItem(iItem, szMenuIndex, sizeof szMenuIndex);

            int iMenuIndex = StringToInt(szMenuIndex);

            MenuElement element;
            g_aMenuElements.GetArray(iMenuIndex, element);

            if (element.IsCategory())
            {
                g_eClientActiveCategory[iClient] = element;
                ShowWeaponMenu(iClient, element);
                return 0;
            }

            if (!CanPickupWeapon(iClient))
            {
                ShowMainMenu(iClient);
                return 0;
            }

            PickupWeapon(iClient, element.name);
            g_bClientUseMenu[iClient] = true;
        }
    }

    return 0;
}

void ShowWeaponMenu(int iClient, MenuElement element)
{
    Menu menu = CreateMenu(HandlerWeaponMenu, MenuAction_Select|MenuAction_End);
    TranslationPhraseExists(element.name);

    if (TranslationPhraseExists(element.name)) {
        menu.SetTitle("%T", element.name, iClient);
    } else {
        menu.SetTitle("%s", element.name);
    }

    char szMenuItem[64], szMenuIndex[4];

    MenuElement sub;
    for (int iIdx = 0, iArraySize = element.children.Length; iIdx < iArraySize; iIdx ++)
    {
        element.children.GetArray(iIdx, sub, sizeof sub);

        FormatEx(szMenuIndex, sizeof szMenuIndex, "%d", iIdx);

        if (TranslationPhraseExists(sub.name)) {
            FormatEx(szMenuItem, sizeof szMenuItem, "%T", sub.name, iClient);
        } else {
            FormatEx(szMenuItem, sizeof szMenuItem, "%s", sub.name);
        }

        menu.AddItem(szMenuIndex, szMenuItem);
    }

    menu.Display(iClient, MENU_TIME_FOREVER);
}

int HandlerWeaponMenu(Menu menu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_End: delete menu;

        case MenuAction_Select:
        {
            char szMenuIndex[4];
            menu.GetItem(iItem, szMenuIndex, sizeof szMenuIndex);

            int iMenuIndex = StringToInt(szMenuIndex);

            MenuElement sub;
            g_eClientActiveCategory[iClient].children.GetArray(iMenuIndex, sub);

            if (sub.IsCategory())
            {
                g_eClientActiveCategory[iClient] = sub;
                ShowWeaponMenu(iClient, sub);
                return 0;
            }

            if (!CanPickupWeapon(iClient))
            {
                ShowWeaponMenu(iClient, g_eClientActiveCategory[iClient]);
                return 0;
            }

            PickupWeapon(iClient, sub.name);
            g_bClientUseMenu[iClient] = true;
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

ArrayList BuildMenu(char[] szPath)
{
    if (!FileExists(szPath)) {
        SetFailState("Couldn't load %s", szPath);
    }

    KeyValues kv = CreateKeyValues("Weapons");

    if (!kv.ImportFromFile(szPath)) {
        SetFailState("Failed to parse keyvalues for %s", szPath);
    }

    ArrayList hierarchy = BuildHierarchy(kv);
    ArrayList root = new ArrayList(sizeof MenuElement);

    NodeItem node;
    MenuElement menu;
    for (int iIdx = 0; iIdx < hierarchy.Length; iIdx++)
    {
        hierarchy.GetArray(iIdx, node, sizeof NodeItem);
        ParseNodeToMenuElement(node, menu);
        root.PushArray(menu);
    }

    delete hierarchy;
    delete kv;

    return root;
}

/**
 * Recursively constructs a tree of NodeItem structs from a KeyValues object.
 *
 * This function traverses all immediate subkeys of the current KeyValues position,
 * creating a NodeItem for each key. Each node stores its name, value, and a list
 * of child nodes built recursively from its own subkeys.
 *
 * @param kv         The KeyValues object to read from. Assumes current position is valid.
 * @return           An ArrayList containing NodeItem structs representing the hierarchy.
 *                   Each NodeItem owns its own children list.
 */
ArrayList BuildHierarchy(KeyValues kv)
{
    // Create a new list to hold nodes at the current level
    ArrayList nodes = new ArrayList(sizeof NodeItem);

    // Attempt to enter the first child key (includes both sections and leaf nodes)
    if (!KvGotoFirstSubKey(kv, false)) {
        return nodes; // No children — return empty list
    }

    char szKey[MAXLENGTH_NODE_KEY];
    char szValue[MAXLENGTH_NODE_VALUE];

    do
    {
        KvGetSectionName(kv, szKey, sizeof szKey);

        NodeItem node;
        strcopy(node.key, sizeof node.key, szKey);

        if (KvGotoFirstSubKey(kv, false)) // Section
        {
            KvGoBack(kv);
            node.value[0] = '\0';
            node.children = BuildHierarchy(kv);
        }
        else // Leaf
        {
            KvGetString(kv, NULL_STRING, szValue, sizeof szValue);
            strcopy(node.value, sizeof node.value, szValue);
            node.children = null;
        }

        nodes.PushArray(node);

    } while (KvGotoNextKey(kv, false));

    // Return to parent level after traversal
    KvGoBack(kv);
    return nodes;
}

void PushMenuElementToCache(StringMap cache, ArrayList elements)
{
    int iArraySize = elements.Length;

    for (int iIdx = 0; iIdx < iArraySize; iIdx++)
    {
        MenuElement element;
        elements.GetArray(iIdx, element, sizeof element);

        if (element.children != null && element.children.Length > 0) {
            PushMenuElementToCache(cache, element.children);
        }

        cache.SetArray(element.cmd, element, sizeof element);
    }
}

void ParseNodeToMenuElement(const NodeItem node, MenuElement out)
{
    NodeItem child;

    if (StrEqual(node.key, "category"))
    {
        out.Create(Element_Category);

        for (int iIdx = 0; iIdx < node.children.Length; iIdx++)
        {
            node.children.GetArray(iIdx, child, sizeof NodeItem);

            if (StrEqual(child.key, "name", false))
                strcopy(out.name, sizeof out.name, child.value);
            else if (StrEqual(child.key, "cmd", false))
                strcopy(out.cmd, sizeof out.cmd, child.value);
        }

        for (int iIdx = 0; iIdx < node.children.Length; iIdx++)
        {
            node.children.GetArray(iIdx, child, sizeof NodeItem);

            if (StrEqual(child.key, "items", false))
            {
                for (int j = 0; j < child.children.Length; j++)
                {
                    NodeItem subChild;
                    child.children.GetArray(j, subChild, sizeof NodeItem);

                    MenuElement sub;
                    ParseNodeToMenuElement(subChild, sub);
                    out.AddChild(sub);
                }
            }
        }
    }
    else if (StrEqual(node.key, "item", false))
    {
        out.Create(Element_Item);

        for (int iIdx = 0; iIdx < node.children.Length; iIdx++)
        {
            node.children.GetArray(iIdx, child, sizeof NodeItem);

            if (StrEqual(child.key, "name", false))
                strcopy(out.name, sizeof out.name, child.value);
            else if (StrEqual(child.key, "cmd", false))
                strcopy(out.cmd, sizeof out.cmd, child.value);
        }
    }
}
