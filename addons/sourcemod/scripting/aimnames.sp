#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#undef REQUIRE_EXTENSIONS
#undef AUTOLOAD_EXTENSIONS
#include <clientprefs>
#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define TF2_PLAYERCOND_DISGUISING (1 << 2)
#define TF2_PLAYERCOND_DISGUISED  (1 << 3)
#define TF2_PLAYERCOND_SPYCLOAK	  (1 << 4)

/*=================================
=            Constants            =
=================================*/

#define PLUGIN_NAME				  "Aim Names"
#define PLUGIN_AUTHOR			  "MCG-retsam, Antithasys, dragonisser, roxrosykid"
#define PLUGIN_DESC				  "Shows enemy names when crosshair is placed on them."
#define PLUGIN_VERSION			  "0.9.2"
#define PLUGIN_URL				  "https://github.com/roxrosykid/aimnames"
#define PLUGIN_PREFIX			  "[ANY]"

/*==========================================
=            Plugin Information            =
==========================================*/
public Plugin myinfo =
{
	name		= PLUGIN_NAME,
	author		= PLUGIN_AUTHOR,
	description = PLUGIN_DESC,
	version		= PLUGIN_VERSION,
	url			= PLUGIN_URL
};

enum e_SupportedMods
{
	GameType_UnSupported,
	GameType_AOC,
	GameType_HL2MP,
	GameType_INS,
	GameType_TF,
	GameType_ZM,
	GameType_SF,
	GameType_OB,
	GameType_BG2
};

enum e_ColorNames
{
	Color_Red,
	Color_Orange,
	Color_Yellow,
	Color_Green,
	Color_Blue
};

enum e_ColorValues
{
	iRed,
	iGreen,
	iBlue
};

enum struct e_PlayerData
{
	Handle		 hHudTimer;
	bool		 bHudEnabled;
	bool		 bIsAdmin;
	bool		 bHealthEnabled;
	e_ColorNames eColor;
}

Handle			g_Cvar_Enabled		 = INVALID_HANDLE;
Handle			g_Cvar_Color		 = INVALID_HANDLE;
Handle			g_Cvar_Admins		 = INVALID_HANDLE;
Handle			g_Cvar_Flag			 = INVALID_HANDLE;
Handle			g_Cvar_Health		 = INVALID_HANDLE;
Handle			g_Cvar_Holdtime		 = INVALID_HANDLE;
Handle			g_Cvar_Distance		 = INVALID_HANDLE;
Handle			g_Cvar_TimerInterval = INVALID_HANDLE;

Handle			g_hCookie_Enabled	 = INVALID_HANDLE;
Handle			g_hCookie_Color		 = INVALID_HANDLE;
Handle			g_hCookie_ShowHealth = INVALID_HANDLE;

Handle			g_hHud				 = INVALID_HANDLE;

bool			g_bEnabled;
bool			g_bAdminOnly;
bool			g_bShowHealth;
bool			g_bUseClientprefs;

float			g_fDistance;
float			g_fHoldtime;
float			g_fTimerInterval;
int				g_iDefaultColor;
int				g_iFilteredEntity = -1;

char			g_sCharAdminFlag[32];
int				g_iColors[e_ColorNames][e_ColorValues];
e_PlayerData	g_aPlayers[MAXPLAYERS + 1];
e_SupportedMods g_CurrentMod;

public void OnPluginStart()
{
	g_CurrentMod = GetCurrentMod();
	if (g_CurrentMod == GameType_UnSupported)
	{
		SetFailState("This mod does not support hud text");
	}
	else {
		g_hHud = CreateHudSynchronizer();
	}

	CreateConVar("sm_aimnames_version", PLUGIN_VERSION, "Aim Names version", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_Cvar_Enabled		 = CreateConVar("sm_aimnames_enabled", "1", "Enable/Disable aim names plugin. (1/0 = yes/no)");
	g_Cvar_Color		 = CreateConVar("sm_aimnames_color", "0", "Default color for hudtext. (0 = red, 1 = orange, 2 = yellow, 3 = green, 4 = blue)");
	g_Cvar_Admins		 = CreateConVar("sm_aimnames_adminonly", "0", "Enable/Disable plugin for admins only.");
	g_Cvar_Flag			 = CreateConVar("sm_aimnames_flag", "d", "Admin flag(s) to use if admin only.");
	g_Cvar_Health		 = CreateConVar("sm_aimnames_health", "1", "Enable/Disable admins viewing players health.");
	g_Cvar_Holdtime		 = CreateConVar("sm_aimnames_holdtime", "0.4", "(Default: 0.4) The hudtext number of seconds to hold/refresh the text.");
	g_Cvar_Distance		 = CreateConVar("sm_aimnames_distance", "100.0", "(Default: 100) Distance in meters for showing aim names.");
	g_Cvar_TimerInterval = CreateConVar("sm_aimnames_timerinterval", "0.1", "(Default: 0.3) Repeat timer interval. Time in seconds between executing the timer function.");

	HookConVarChange(g_Cvar_Enabled, Cvar_Changed);
	HookConVarChange(g_Cvar_Color, Cvar_Changed);
	HookConVarChange(g_Cvar_Admins, Cvar_Changed);
	HookConVarChange(g_Cvar_Flag, Cvar_Changed);
	HookConVarChange(g_Cvar_Health, Cvar_Changed);
	HookConVarChange(g_Cvar_Holdtime, Cvar_Changed);
	HookConVarChange(g_Cvar_Distance, Cvar_Changed);
	HookConVarChange(g_Cvar_TimerInterval, Cvar_Changed);

	LoadColors();

	AutoExecConfig(true, "plugin.aimnames");
}

public void OnAllPluginsLoaded()
{
	/**
	Now lets check for client prefs extension
	*/
	char sExtError[256];
	int	 iExtStatus = GetExtensionFileStatus("clientprefs.ext", sExtError, sizeof(sExtError));
	if (iExtStatus == -2)
	{
		LogAction(0, -1, "[AN] Client Preferences extension was not found.");
		LogAction(0, -1, "[AN] Plugin continued to load, but that feature will not be used.");
		g_bUseClientprefs = false;
	}
	if (iExtStatus == -1 || iExtStatus == 0)
	{
		LogAction(0, -1, "[AN] Client Preferences extension is loaded with errors.");
		LogAction(0, -1, "[AN] Status reported was [%s].", sExtError);
		LogAction(0, -1, "[AN] Plugin continued to load, but that feature will not be used.");
		g_bUseClientprefs = false;
	}
	if (iExtStatus == 1)
	{
		LogAction(0, -1, "[AN] Client Preferences extension is loaded, checking database.");
		if (!SQL_CheckConfig("clientprefs"))
		{
			LogAction(0, -1, "[AN] No 'clientprefs' database found.  Check your database.cfg file.");
			LogAction(0, -1, "[AN] Plugin continued to load, but Client Preferences will not be used.");
			g_bUseClientprefs = false;
		}
		else {
			LogAction(0, -1, "[AN] Database config 'clientprefs' was found.");
			LogAction(0, -1, "[AN] Plugin will use Client Preferences.");
			g_bUseClientprefs = true;
		}

		/**
		Deal with client cookies
		*/
		if (g_bUseClientprefs)
		{
			g_hCookie_Enabled	 = RegClientCookie("aimnnames_enabled", "Enable/Disable aim names", CookieAccess_Public);
			g_hCookie_Color		 = RegClientCookie("aimnnames_color", "Color to use for hud", CookieAccess_Public);
			g_hCookie_ShowHealth = RegClientCookie("aimnames_showhealth", "Show players health", CookieAccess_Private);
			SetCookieMenuItem(CookieMenu_TopMenu, g_hCookie_Enabled, "Aim Names");
		}
	}
}

public void OnConfigsExecuted()
{
	g_bEnabled		 = GetConVarBool(g_Cvar_Enabled);
	g_bAdminOnly	 = GetConVarBool(g_Cvar_Admins);
	g_bShowHealth	 = GetConVarBool(g_Cvar_Health);
	g_iDefaultColor	 = GetConVarInt(g_Cvar_Color);
	g_fDistance		 = GetConVarFloat(g_Cvar_Distance);
	g_fHoldtime		 = GetConVarFloat(g_Cvar_Holdtime);
	g_fTimerInterval = GetConVarFloat(g_Cvar_TimerInterval);

	GetConVarString(g_Cvar_Flag, g_sCharAdminFlag, sizeof(g_sCharAdminFlag));
}

/**
 Client callbacks
 */
public void OnClientPostAdminCheck(int client)
{
	if (IsValidAdmin(client, g_sCharAdminFlag))
	{
		g_aPlayers[client].bIsAdmin = true;
	}
	else {
		g_aPlayers[client].bIsAdmin		  = false;
		g_aPlayers[client].bHealthEnabled = false;
	}

	if (!g_bUseClientprefs)
	{
		g_aPlayers[client].bHudEnabled = g_bEnabled;
		if (g_aPlayers[client].bIsAdmin)
		{
			g_aPlayers[client].bHealthEnabled = g_bShowHealth;
		}
		g_aPlayers[client].eColor = view_as<e_ColorNames>(g_iDefaultColor);
	}
	if (g_bEnabled)
	{
		if (!g_bAdminOnly || (g_bAdminOnly && g_aPlayers[client].bIsAdmin))
		{
			g_aPlayers[client].hHudTimer = CreateTimer(g_fTimerInterval, Timer_SyncHud, client, TIMER_REPEAT);
		}
	}
}

public void OnClientCookiesCached(int client)
{
	if (g_bUseClientprefs)
	{
		char sEnabled[2];
		char sColor[4];
		char sShowHealth[2];

		GetClientCookie(client, g_hCookie_Enabled, sEnabled, sizeof(sEnabled));
		GetClientCookie(client, g_hCookie_Color, sColor, sizeof(sColor));
		GetClientCookie(client, g_hCookie_ShowHealth, sShowHealth, sizeof(sShowHealth));
		g_aPlayers[client].bHudEnabled	  = !view_as<bool>(StringToInt(sEnabled));
		g_aPlayers[client].bHealthEnabled = !view_as<bool>(StringToInt(sShowHealth));
		g_aPlayers[client].eColor		  = view_as<e_ColorNames>(StringToInt(sColor));

		if (!g_aPlayers[client].bHudEnabled)
		{
			ClearTimer(g_aPlayers[client].hHudTimer);
		}
	}
}

public void OnClientDisconnect(int client)
{
	ClearTimer(g_aPlayers[client].hHudTimer);
	g_aPlayers[client].bHudEnabled = false;
	g_aPlayers[client].bIsAdmin	   = false;
	g_aPlayers[client].eColor	   = Color_Red;
}

/**
 Timers
 */
public Action Timer_SyncHud(Handle timer, int client)
{
	if (g_bEnabled && g_aPlayers[client].bHudEnabled)
	{
		if (IsClientInGame(client) && IsClientObserver(client))
		{
			return Plugin_Continue;
		}

		int iTarget = GetClientAimTarget(client, true);
		if (!IsValidClient(iTarget, false))
		{
			return Plugin_Continue;
		}

		int Team_Player = GetClientTeam(client);
		int Team_Target = GetClientTeam(iTarget);

		if (Team_Player == Team_Target)
		{
			return Plugin_Continue;
		}

		float client_pos[3];
		float target_pos[3];
		GetClientEyePosition(client, client_pos);
		GetClientEyePosition(iTarget, target_pos);

		if (CanSeeTarget(client, client_pos, iTarget, target_pos, g_fDistance))
		{
			if (g_CurrentMod == GameType_TF && TF2_GetPlayerCond(iTarget) & (TF2_PLAYERCOND_DISGUISING | TF2_PLAYERCOND_DISGUISED | TF2_PLAYERCOND_SPYCLOAK))
			{
				return Plugin_Continue;
			}
			else {
				SetHudTextParams(-1.0, 0.59, g_fHoldtime, g_iColors[view_as<e_ColorNames>(g_aPlayers[client].eColor)][iRed], g_iColors[view_as<e_ColorNames>(g_aPlayers[client].eColor)][iGreen], g_iColors[view_as<e_ColorNames>(g_aPlayers[client].eColor)][iBlue], 255, 1);
				if (g_bShowHealth && g_aPlayers[client].bHealthEnabled)
				{
					ShowSyncHudText(client, g_hHud, "%N [%d]", iTarget, GetClientHealth(iTarget));
				}
				else {
					ShowSyncHudText(client, g_hHud, "%N", iTarget);
				}
			}
		}
	}
	else {
		g_aPlayers[client].hHudTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

/**
 Cookie menus
 */
public void CookieMenu_TopMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_DisplayOption)
	{
		// don't think we need to do anything
	}
	else {
		SendCookieSettingsMenu(client);
	}
}

public int Menu_CookieSettings(Handle menu, MenuAction action, int param1, int param2)
{
	int client = param1;
	if (action == MenuAction_Select)
	{
		char sSelection[24];
		GetMenuItem(menu, param2, sSelection, sizeof(sSelection));
		if (StrEqual(sSelection, "enable", false))
		{
			SendCookieEnabledMenu(client);
		}
		else if (StrEqual(sSelection, "color", false)) {
			SendCookieColorMenu(client);
		}
		else if (StrEqual(sSelection, "health", false)) {
			SendCookieHealthMenu(client);
		}
	}
	else if (action == MenuAction_Cancel) {
		if (param2 == MenuCancel_ExitBack)
		{
			ShowCookieMenu(client);
		}
	}
	else if (action == MenuAction_End) {
		CloseHandle(menu);
	}
	return 0;
}

public int Menu_CookieSettingsEnable(Handle menu, MenuAction action, int param1, int param2)
{
	int client = param1;
	if (action == MenuAction_Select)
	{
		char sSelection[24];
		GetMenuItem(menu, param2, sSelection, sizeof(sSelection));
		if (StrEqual(sSelection, "enable", false))
		{
			SetClientCookie(client, g_hCookie_Enabled, "0");
			g_aPlayers[client].bHudEnabled = true;
			PrintToChat(client, "[SM] Aim Names is ENABLED");
			if (g_aPlayers[client].hHudTimer == null
				&& (g_aPlayers[client].bHudEnabled)
				&& (!g_bAdminOnly || (g_bAdminOnly && g_aPlayers[client].bIsAdmin)))
			{
				g_aPlayers[client].hHudTimer = CreateTimer(g_fTimerInterval, Timer_SyncHud, client, TIMER_REPEAT);
			}
		}
		else {
			SetClientCookie(client, g_hCookie_Enabled, "1");
			g_aPlayers[client].bHudEnabled = false;
			PrintToChat(client, "[SM] Aim Names is DISABLED");
			if (g_aPlayers[client].hHudTimer != INVALID_HANDLE)
			{
				ClearTimer(g_aPlayers[client].hHudTimer);
			}
		}
	}
	else if (action == MenuAction_Cancel) {
		if (param2 == MenuCancel_ExitBack)
		{
			ShowCookieMenu(client);
		}
	}
	else if (action == MenuAction_End) {
		CloseHandle(menu);
	}
	return 0;
}

public int Menu_CookieHealthEnable(Handle menu, MenuAction action, int param1, int param2)
{
	int client = param1;
	if (action == MenuAction_Select)
	{
		char sSelection[24];
		GetMenuItem(menu, param2, sSelection, sizeof(sSelection));
		if (StrEqual(sSelection, "henable", false))
		{
			SetClientCookie(client, g_hCookie_ShowHealth, "0");
			g_aPlayers[client].bHealthEnabled = true;
			PrintToChat(client, "[SM] Aim Names health display is ENABLED");
		}
		else {
			SetClientCookie(client, g_hCookie_ShowHealth, "1");
			g_aPlayers[client].bHealthEnabled = false;
			PrintToChat(client, "[SM] Aim Names health display is DISABLED");
		}
	}
	else if (action == MenuAction_Cancel) {
		if (param2 == MenuCancel_ExitBack)
		{
			ShowCookieMenu(client);
		}
	}
	else if (action == MenuAction_End) {
		CloseHandle(menu);
	}
	return 0;
}

public int Menu_CookieSettingsColors(Handle menu, MenuAction action, int param1, int param2)
{
	int client = param1;
	if (action == MenuAction_Select)
	{
		char sSelection[24];
		GetMenuItem(menu, param2, sSelection, sizeof(sSelection));
		if (StrEqual(sSelection, "Red", false))
		{
			SetClientCookie(client, g_hCookie_Color, "0");
			g_aPlayers[client].eColor = Color_Red;
			PrintToChat(client, "[SM] Aim Names hud color set to RED");
		}
		else if (StrEqual(sSelection, "Orange", false)) {
			SetClientCookie(client, g_hCookie_Color, "1");
			g_aPlayers[client].eColor = Color_Orange;
			PrintToChat(client, "[SM] Aim Names hud color set to ORANGE");
		}
		else if (StrEqual(sSelection, "Yellow", false)) {
			SetClientCookie(client, g_hCookie_Color, "2");
			g_aPlayers[client].eColor = Color_Yellow;
			PrintToChat(client, "[SM] Aim Names hud color set to YELLOW");
		}
		else if (StrEqual(sSelection, "Green", false)) {
			SetClientCookie(client, g_hCookie_Color, "3");
			g_aPlayers[client].eColor = Color_Green;
			PrintToChat(client, "[SM] Aim Names hud color set to GREEN");
		}
		else if (StrEqual(sSelection, "Blue", false)) {
			SetClientCookie(client, g_hCookie_Color, "4");
			g_aPlayers[client].eColor = Color_Blue;
			PrintToChat(client, "[SM] Aim Names hud color set to BLUE");
		}
	}
	else if (action == MenuAction_Cancel) {
		if (param2 == MenuCancel_ExitBack)
		{
			ShowCookieMenu(client);
		}
	}
	else if (action == MenuAction_End) {
		CloseHandle(menu);
	}
	return 0;
}

public void Cvar_Changed(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_Cvar_Enabled)
	{
		if (StringToInt(newValue) == 0)
		{
			g_bEnabled = false;
			for (int x = 1; x <= MaxClients; x++)
			{
				ClearTimer(g_aPlayers[x].hHudTimer);
			}
		}
		else {
			g_bEnabled = true;
			for (int x = 1; x <= MaxClients; x++)
			{
				if (IsValidClient(x)
					&& (g_aPlayers[x].bHudEnabled)
					&& (!g_bAdminOnly || (g_bAdminOnly && g_aPlayers[x].bIsAdmin)))
				{
					g_aPlayers[x].hHudTimer = CreateTimer(g_fTimerInterval, Timer_SyncHud, x, TIMER_REPEAT);
				}
			}
		}
	}
	else if (convar == g_Cvar_Color) {
		g_iDefaultColor = StringToInt(newValue);
	}
	else if (convar == g_Cvar_Holdtime) {
		g_fHoldtime = StringToFloat(newValue);
	}
	else if (convar == g_Cvar_Distance) {
		g_fDistance = StringToFloat(newValue);
	}
	else if (convar == g_Cvar_TimerInterval) {
		g_fTimerInterval = StringToFloat(newValue);

		for (int x = 1; x <= MaxClients; x++)
		{
			ClearTimer(g_aPlayers[x].hHudTimer);

			if (IsValidClient(x)
				&& (g_aPlayers[x].bHudEnabled)
				&& (!g_bAdminOnly || (g_bAdminOnly && g_aPlayers[x].bIsAdmin)))
			{
				g_aPlayers[x].hHudTimer = CreateTimer(g_fTimerInterval, Timer_SyncHud, x, TIMER_REPEAT);
			}
		}
	}
	else if (convar == g_Cvar_Admins) {
		if (StringToInt(newValue) == 0)
		{
			g_bAdminOnly = false;
			for (int x = 1; x <= MaxClients; x++)
			{
				if (IsValidClient(x)
					&& (g_aPlayers[x].bHudEnabled)
					&& (g_aPlayers[x].hHudTimer == null))
				{
					g_aPlayers[x].hHudTimer = CreateTimer(g_fTimerInterval, Timer_SyncHud, x, TIMER_REPEAT);
				}
			}
		}
		else {
			g_bAdminOnly = true;
			for (int x = 1; x <= MaxClients; x++)
			{
				if (IsValidClient(x) && !g_aPlayers[x].bIsAdmin)
				{
					ClearTimer(g_aPlayers[x].hHudTimer);
				}
			}
		}
	}
	else if (convar == g_Cvar_Health) {
		if (StringToInt(newValue) == 0)
		{
			g_bShowHealth = false;
		}
		else {
			g_bShowHealth = true;
		}
	}
}

/**
 Stocks
 */
stock void LoadColors()
{
	g_iColors[Color_Red][iRed]		= 255;
	g_iColors[Color_Red][iGreen]	= 30;
	g_iColors[Color_Red][iBlue]		= 30;

	g_iColors[Color_Orange][iRed]	= 255;
	g_iColors[Color_Orange][iGreen] = 100;
	g_iColors[Color_Orange][iBlue]	= 0;

	g_iColors[Color_Yellow][iRed]	= 255;
	g_iColors[Color_Yellow][iGreen] = 255;
	g_iColors[Color_Yellow][iBlue]	= 30;

	g_iColors[Color_Green][iRed]	= 32;
	g_iColors[Color_Green][iGreen]	= 200;
	g_iColors[Color_Green][iBlue]	= 0;

	g_iColors[Color_Blue][iRed]		= 0;
	g_iColors[Color_Blue][iGreen]	= 80;
	g_iColors[Color_Blue][iBlue]	= 255;
}

stock bool IsValidAdmin(int client, const char[] flags)
{
	int ibFlags = ReadFlagString(flags);
	if ((GetUserFlagBits(client) & ibFlags) == ibFlags)
	{
		return true;
	}
	if (GetUserFlagBits(client) & ADMFLAG_ROOT)
	{
		return true;
	}
	return false;
}

stock bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
	{
		return false;
	}
	return IsClientInGame(client);
}

stock int TF2_GetPlayerCond(int client)
{
	return GetEntProp(client, Prop_Send, "m_nPlayerCond");
}

stock void ClearTimer(Handle &timer)
{
	if (timer != INVALID_HANDLE)
	{
		delete timer;
	}
	timer = INVALID_HANDLE;
}

stock bool CanSeeTarget(int origin, float pos[3], int target, float targetPos[3], float range)
{
	float fDistance;
	fDistance = GetVectorDistanceMeter(pos, targetPos);
	if (fDistance >= range)
	{
		return false;
	}

	Handle hTraceEx = INVALID_HANDLE;
	float  hitPos[3];
	g_iFilteredEntity = origin;
	hTraceEx		  = TR_TraceRayFilterEx(pos, targetPos, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter);
	TR_GetEndPosition(hitPos, hTraceEx);
	CloseHandle(hTraceEx);

	if (GetVectorDistanceMeter(hitPos, targetPos) <= 1.0)
	{
		return true;
	}

	return false;
}

public bool TraceFilter(int ent, int contentMask)
{
	return (ent == g_iFilteredEntity) ? false : true;
}

stock float UnitToMeter(float distance)
{
	return distance / 50.00;
}

stock float GetVectorDistanceMeter(const float vec1[3], const float vec2[3], bool squared = false)
{
	return UnitToMeter(GetVectorDistance(vec1, vec2, squared));
}

stock void SendCookieSettingsMenu(int client)
{
	Handle hMenu = CreateMenu(Menu_CookieSettings);
	SetMenuTitle(hMenu, "Options (Current Setting)");
	if (g_aPlayers[client].bHudEnabled)
	{
		AddMenuItem(hMenu, "enable", "Enabled/Disable (Enabled)");
	}
	else {
		AddMenuItem(hMenu, "enable", "Enabled/Disable (Disabled)");
	}
	if (g_aPlayers[client].bIsAdmin)
	{
		if (g_aPlayers[client].bHealthEnabled)
		{
			AddMenuItem(hMenu, "health", "Enabled/Disable health display (Enabled)");
		}
		else {
			AddMenuItem(hMenu, "health", "Enabled/Disable health display (Disabled)");
		}
	}
	switch (g_aPlayers[client].eColor)
	{
		case Color_Red:
		{
			AddMenuItem(hMenu, "color", "Color (Red)");
		}
		case Color_Orange:
		{
			AddMenuItem(hMenu, "color", "Color (Orange)");
		}
		case Color_Yellow:
		{
			AddMenuItem(hMenu, "color", "Color (Yellow)");
		}
		case Color_Green:
		{
			AddMenuItem(hMenu, "color", "Color (Green)");
		}
		case Color_Blue:
		{
			AddMenuItem(hMenu, "color", "Color (Blue)");
		}
	}
	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock void SendCookieEnabledMenu(int client)
{
	Handle hMenu = CreateMenu(Menu_CookieSettingsEnable);
	SetMenuTitle(hMenu, "Enable/Disable Aim Names");

	if (g_aPlayers[client].bHudEnabled)
	{
		AddMenuItem(hMenu, "enable", "Enable (Set)");
		AddMenuItem(hMenu, "disable", "Disable");
	}
	else {
		AddMenuItem(hMenu, "enable", "Enabled");
		AddMenuItem(hMenu, "disable", "Disable (Set)");
	}

	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock void SendCookieColorMenu(int client)
{
	Handle hMenu = CreateMenu(Menu_CookieSettingsColors);
	SetMenuTitle(hMenu, "Select Hud Color");
	switch (g_aPlayers[client].eColor)
	{
		case Color_Red:
		{
			AddMenuItem(hMenu, "Red", "Red (Set)");
			AddMenuItem(hMenu, "Orange", "Orange");
			AddMenuItem(hMenu, "Yellow", "Yellow");
			AddMenuItem(hMenu, "Green", "Green");
			AddMenuItem(hMenu, "Blue", "Blue");
		}
		case Color_Orange:
		{
			AddMenuItem(hMenu, "Red", "Red");
			AddMenuItem(hMenu, "Orange", "Orange (Set)");
			AddMenuItem(hMenu, "Yellow", "Yellow");
			AddMenuItem(hMenu, "Green", "Green");
			AddMenuItem(hMenu, "Blue", "Blue");
		}
		case Color_Yellow:
		{
			AddMenuItem(hMenu, "Red", "Red");
			AddMenuItem(hMenu, "Orange", "Orange");
			AddMenuItem(hMenu, "Yellow", "Yellow (Set)");
			AddMenuItem(hMenu, "Green", "Green");
			AddMenuItem(hMenu, "Blue", "Blue");
		}
		case Color_Green:
		{
			AddMenuItem(hMenu, "Red", "Red");
			AddMenuItem(hMenu, "Orange", "Orange");
			AddMenuItem(hMenu, "Yellow", "Yellow");
			AddMenuItem(hMenu, "Green", "Green (Set)");
			AddMenuItem(hMenu, "Blue", "Blue");
		}
		case Color_Blue:
		{
			AddMenuItem(hMenu, "Red", "Red");
			AddMenuItem(hMenu, "Orange", "Orange");
			AddMenuItem(hMenu, "Yellow", "Yellow");
			AddMenuItem(hMenu, "Green", "Green");
			AddMenuItem(hMenu, "Blue", "Blue (Set)");
		}
	}
	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock void SendCookieHealthMenu(int client)
{
	Handle hMenu = CreateMenu(Menu_CookieHealthEnable);
	SetMenuTitle(hMenu, "Enable/Disable Health Display");

	if (g_aPlayers[client].bHealthEnabled)
	{
		AddMenuItem(hMenu, "henable", "Enable (Set)");
		AddMenuItem(hMenu, "hdisable", "Disable");
	}
	else {
		AddMenuItem(hMenu, "henable", "Enabled");
		AddMenuItem(hMenu, "hdisable", "Disable (Set)");
	}

	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock e_SupportedMods GetCurrentMod()
{
	char sGameType[64];
	GetGameFolderName(sGameType, sizeof(sGameType));

	if (StrEqual(sGameType, "aoc", false) || StrEqual(sGameType, "ageofchivalry", false))
	{
		return GameType_AOC;
	}
	if (StrEqual(sGameType, "hl2mp", false))
	{
		return GameType_HL2MP;
	}
	if (StrEqual(sGameType, "insurgency", false) || StrEqual(sGameType, "ins", false))
	{
		return GameType_INS;
	}
	if (StrEqual(sGameType, "tf", false))
	{
		return GameType_TF;
	}
	if (StrEqual(sGameType, "zombie_master", false))
	{
		return GameType_ZM;
	}
	if (StrEqual(sGameType, "sourceforts", false))
	{
		return GameType_SF;
	}
	if (StrEqual(sGameType, "obsidian", false))
	{
		return GameType_OB;
	}
	if (StrEqual(sGameType, "bg2", false))
	{
		return GameType_BG2;
	}
	return GameType_UnSupported;
}
