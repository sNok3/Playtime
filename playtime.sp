#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <multicolors>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = 
{
	name = "[SM] Advanced hour system",
	author = "sNok3",
	description = "Advanced playtime tracker",
	version = "1.0",
	url = "https://fairside.ro"
}

ConVar	g_ConVar_Playtime_refresh 	= null,
	g_ConVar_Playtime_database 	= null,
	g_ConVar_Playtime_prefix 	= null,
	g_ConVar_Playtime_website 	= null,
	g_ConVar_Playtime_table 	= null,
	g_ConVar_Playtime_team 		= null,
	g_ConVar_Playtime_version 	= null,
	g_ConVar_Playtime_mode 		= null,
	g_ConVar_Playtime_mintime 	= null;

Database hDatabase = null;

Handle g_hTimer = null;

char g_sPlayTimeTable[128], 
     g_sPlaytimeDatabase[128],
     g_sPlaytimePrefix[128],
     g_sPlaytimeWebsite[128];


public void OnPluginStart()
{
	g_ConVar_Playtime_version  	= CreateConVar("sm_playtime_version", 	PLUGIN_VERSION, "Plugin version", 0 | FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_ConVar_Playtime_refresh  	= CreateConVar("sm_playtime_refresh", 	"5", "Time (in seconds) of database updates.", FCVAR_NOTIFY, true, 5.0, true, 60.0);
	g_ConVar_Playtime_database 	= CreateConVar("sm_playtime_database", 	"playtime", "Database (in databases.cfg) for use (Do not change)!");
	g_ConVar_Playtime_prefix   	= CreateConVar("sm_playtime_prefix", 	"{darkred}「FRS」{default}", "Prefix for chat messages.");
	g_ConVar_Playtime_website  	= CreateConVar("sm_playtime_website", 	"https://fairside.ro", "The website where your players should apply for a rank.");
	g_ConVar_Playtime_table    	= CreateConVar("sm_playtime_table", 	"playtime", "The table in your SQL database to use. (Do not change)!");
	g_ConVar_Playtime_team     	= CreateConVar("sm_playtime_team", 	"1","Who to track: 0 = all, 1 = only those who are in the team.", _, true, 0.0, true, 1.0);
	g_ConVar_Playtime_mode     	= CreateConVar("sm_playtime_mode", 	"0", "Track mode: 0 = when upgraded, 1 = when disconnected.", _, true, 0.0, true, 1.0);
	g_ConVar_Playtime_mintime   	= CreateConVar("sm_playtime_mintime", 	"25", "Number of required hours in order to apply.", _, true, 0.0, true, 1000.0);
	
	RegConsoleCmd("sm_ore",		Command_MyTime,	"Gets your time on the server");
	RegConsoleCmd("sm_time", 	Command_MyTime,	"Gets your time on the server");
	RegConsoleCmd("sm_timeplayed", 	Command_MyTime,	"Gets your time on the server");
	
	AutoExecConfig(true, "playtime");
	
	g_ConVar_Playtime_table.	GetString(g_sPlayTimeTable,	sizeof(g_sPlayTimeTable));
	g_ConVar_Playtime_database.	GetString(g_sPlaytimeDatabase,	sizeof(g_sPlaytimeDatabase));
	g_ConVar_Playtime_prefix.  	GetString(g_sPlaytimePrefix,	sizeof(g_sPlaytimePrefix));
	g_ConVar_Playtime_website. 	GetString(g_sPlaytimeWebsite,	sizeof(g_sPlaytimeWebsite));
	
	if(hDatabase == null)
		Database.Connect(DBConnect, g_sPlaytimeDatabase);
	
	HookConVarChange(g_ConVar_Playtime_refresh,	ModeChanged);
	HookConVarChange(g_ConVar_Playtime_mode,	ModeChanged);
	ModeChanged(g_ConVar_Playtime_version, "", "");
}

public Action Command_MyTime(int client, int args)
{
	TimeCommand(client, client);
	return Plugin_Handled;
}

void TimeCommand(int client, int target)
{
	char query[256], steamid[32];
	GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));

	if (hDatabase == null) {
		LogError("ERROR: Database is not connected!");
		return;
	}
	
	hDatabase.Format(query, sizeof(query), "SELECT playtime FROM %s WHERE steamid = '%s'", g_sPlayTimeTable, steamid);
	hDatabase.Query(TimeCommand_Callback, query, (client << 8) + target);
}

public void TimeCommand_Callback(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null) {
		LogError("ERROR: Query execution failed: %s", error);
		return;
	}
		
	int client = (view_as<int>(data) >> 8), target = view_as<int>(data) - ((view_as<int>(data) >> 8) << 8);
	char name[MAX_NAME_LENGTH], time_str[32];
	
	if (result.FetchRow()) {
		int playtime = result.FetchInt(0);
		if (playtime/3600 < 1)
			FormatTime(time_str, sizeof(time_str), "%M:%S", playtime);
		else
			FormatTime(time_str, sizeof(time_str), ":%M:%S", playtime);
		if (client != target)
			GetClientName(target, name, sizeof(name));
		else if (GetUserAdmin(client) == INVALID_ADMIN_ID){
			if(playtime/3600 == g_ConVar_Playtime_mintime.IntValue){
				CPrintToChat(client, "{darkred}============================================================================================");
				CPrintToChat(client, "%s Felicitari! Ai atins numarul de ore necesare pentru a aplica pentru functia de {darkred}Helper{default}!", g_sPlaytimePrefix);
				CPrintToChat(client, "%s Forum: {darkred}%s{default}", g_sPlaytimePrefix, g_sPlaytimeWebsite);
				CPrintToChat(client, "{darkred}=============================================================================================");
			} else if(playtime/3600 > g_ConVar_Playtime_mintime.IntValue){
				CPrintToChat(client, "{darkred}=============================================================================================");
				CPrintToChat(client, "%s Ai depasit numarul minim de ore necesare pentru functia de {darkred}Helper{default}; te invitam sa aplici pe forum!", g_sPlaytimePrefix);
				CPrintToChat(client, "%s Forum: {darkred}%s{default}", g_sPlaytimePrefix, g_sPlaytimeWebsite);
				CPrintToChat(client, "{darkred}============================================================================================");
			}
		}
		if (playtime/3600 < 1)
			CPrintToChatAll("%s {darkred}%N{default} has spent: {green}%s {default}minute(s) on the server", g_sPlaytimePrefix, client, time_str);
		else if (playtime/3600 == 1)
			CPrintToChatAll("%s {darkred}%N{default} has spent: {green}%d{green}%s {default}hour on the server", g_sPlaytimePrefix, client, playtime/3600, time_str);
		else
			CPrintToChatAll("%s {darkred}%N{default} has spent: {green}%d{green}%s {default}hour(s) on the server", g_sPlaytimePrefix, client, playtime/3600, time_str);
	}
}

public void OnClientDisconnect(int client)
{
	if (g_ConVar_Playtime_mode.IntValue != 0 && !IsFakeClient(client) && IsClientAuthorized(client))
		IncreaseClientTime(client, RoundToFloor(GetClientTime(client)));
}

public Action UpdateTimes(Handle timer)
{
	for (int i=1; i <= MaxClients && IsClientInGame(i); i++) {
		if (!IsFakeClient(i) && IsClientAuthorized(i) && !(g_ConVar_Playtime_team.IntValue == 1 && GetClientTeam(i) < 2))
			IncreaseClientTime(i, g_ConVar_Playtime_refresh.IntValue);
	}
	return Plugin_Continue;
}

public void IncreaseClientTime(int client, int time)
{
	char name[MAX_NAME_LENGTH], steamid[32], query[256];

	int lenght = strlen(name) * 2 + 1;
	char[] escapedName = new char[lenght];
	hDatabase.Escape(name, escapedName, lenght);
	
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	
	if (hDatabase == null) {
		LogError("ERROR: Database is not connected!");
		return;
	}

	hDatabase.Format(query, sizeof(query), "INSERT INTO %s (steamid, name, playtime) VALUES (\"%s\",\"%s\", %i) ON DUPLICATE KEY UPDATE name=VALUES(name),playtime=playtime+VALUES(playtime)", g_sPlayTimeTable, steamid, escapedName, time);
	hDatabase.Query(TQuery_Callback, query, 1);
}

public void DBConnect(Database database, const char[] error, any data)
{
	if (database != null) {
		LogError("ERROR: Database connection failure: %s", error);
		return;
	} else
		hDatabase = database;
	
	char query[256];
	
	hDatabase.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s` (`name` varchar(64) CHARACTER SET utf8 NOT NULL, `steamid` varchar(64) NOT NULL, `playtime` int(64) NOT NULL, UNIQUE KEY `steamid` (`steamid`))", g_sPlayTimeTable);
	hDatabase.Query(TQuery_Callback, query, 2);
}

public void ModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	delete g_hTimer;

	if (g_ConVar_Playtime_mode.IntValue == 0)
		g_hTimer = CreateTimer(g_ConVar_Playtime_refresh.FloatValue, UpdateTimes, _, TIMER_REPEAT);
}

public void TQuery_Callback(Handle owner, Handle hQuery, const char[] error, any data)
{
	if (hQuery == INVALID_HANDLE)
		LogError("ERROR: problem with an SQL query! ID: %i Error: %s", data, error);

	delete hQuery;
}
