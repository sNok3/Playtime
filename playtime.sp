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

ConVar sm_playtime_refresh = null,
	   sm_playtime_database = null,
	   sm_playtime_prefix = null,
	   sm_playtime_website = null,
	   sm_playtime_table = null,
	   sm_playtime_team = null,
	   sm_playtime_version = null,
	   sm_playtime_mode = null,
	   sm_playtime_number =	null;

Database hDatabase = null;

Handle refreshTimer = null;

char	playtimeTable[128], 
     	playtimeDatabase[128],
     	playtimePrefix[128],
     	playtimeWebsite[128];


public void OnPluginStart()
{
	sm_playtime_version  =	CreateConVar("sm_playtime_version", 	PLUGIN_VERSION, "Plugin version", 0 | FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	sm_playtime_refresh  =	CreateConVar("sm_playtime_refresh", 	"5", "Time (in seconds) of database updates.", FCVAR_NOTIFY, true, 5.0, true, 60.0);
	sm_playtime_database =	CreateConVar("sm_playtime_database", 	"playtime", "Database (in databases.cfg) for use (Do not change)!");
	sm_playtime_prefix   =	CreateConVar("sm_playtime_prefix", 	"{darkred}「FRS」{default}", "Prefix for chat messages.");
	sm_playtime_website   =	CreateConVar("sm_playtime_website", 	"https://fairside.ro", "The website where your players should apply for a rank.");
	sm_playtime_table    =	CreateConVar("sm_playtime_table", 	"playtime", "The table in your SQL database to use. (Do not change)!");
	sm_playtime_team     =	CreateConVar("sm_playtime_team", 	"1","Who to track: 0 = all, 1 = only those who are in the team.",	_, true, 0.0, true, 1.0);
	sm_playtime_mode     = 	CreateConVar("sm_playtime_mode", 	"0", "Track mode: 0 = when upgraded, 1 = when disconnected.",	_, true, 0.0, true, 1.0);
	sm_playtime_number   = 	CreateConVar("sm_playtime_number", 	"25", "Number of required hours in order to apply.",	_, true, 0.0, true, 1000.0);
	
	RegConsoleCmd("sm_ore",		Command_MyTime,		"Gets your time on the server");
	RegConsoleCmd("sm_time", 	Command_MyTime,		"Gets your time on the server");
	RegConsoleCmd("sm_timeplayed", 	Command_MyTime,		"Gets your time on the server");
	
	AutoExecConfig(true, "playtime");
	
	sm_playtime_table.	GetString(playtimeTable,	sizeof(playtimeTable));
	sm_playtime_database.	GetString(playtimeDatabase,	sizeof(playtimeDatabase));
	sm_playtime_prefix.  	GetString(playtimePrefix,	sizeof(playtimePrefix));
	sm_playtime_website.  	GetString(playtimeWebsite,	sizeof(playtimeWebsite));
	SQL_TConnect(DBConnect, playtimeDatabase);
	
	HookConVarChange(sm_playtime_refresh,	ModeChanged);
	HookConVarChange(sm_playtime_mode,	ModeChanged);
	ModeChanged(sm_playtime_version, "", "");
}

public Action Command_MyTime(int client, int args)
{
	TimeCommand(client, client);
	return Plugin_Handled;
}

void TimeCommand(int client, int target)
{
	static char query[256], steamid[32];
	GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
	Format(query, sizeof(query), "SELECT playtime FROM %s WHERE steamid = '%s'", playtimeTable, steamid);
	DBCheckConnect();
	SQL_TQuery(hDatabase, TimeCommand_Callback, query, (client << 8) + target);
}

public void TimeCommand_Callback(Handle owner, Handle hQuery, const char[] error, any data)
{
	if(hQuery == INVALID_HANDLE)
		LogError("%sERROR: Problem with the TimeCommand request! error: %s", sm_playtime_prefix, error);
		
	int client = (view_as<int>(data) >> 8), target = view_as<int>(data) - ((view_as<int>(data) >> 8) << 8);
	static char name[65], time_str[32];
	
	if(SQL_FetchRow(hQuery))
	{
		int playtime = SQL_FetchInt(hQuery, 0);
		if(playtime/3600 < 1)
			FormatTime(time_str, sizeof(time_str), "%M:%S", playtime);
		else
			FormatTime(time_str, sizeof(time_str), ":%M:%S", playtime);
		if(client != target)
			GetClientName(target, name, sizeof(name));
		else
		if(GetUserAdmin(client) == INVALID_ADMIN_ID){
			if(playtime/3600 == sm_playtime_number.IntValue){
				CPrintToChat(client, "{darkred}============================================================================================");
				CPrintToChat(client, "%s Felicitari! Ai atins numarul de ore necesare pentru a aplica pentru functia de {darkred}Helper{default}!", playtimePrefix);
				CPrintToChat(client, "%s Forum: {darkred}%s{default}", playtimePrefix, playtimeWebsite);
				CPrintToChat(client, "{darkred}=============================================================================================");
			} else if(playtime/3600 > sm_playtime_number.IntValue){
				CPrintToChat(client, "{darkred}=============================================================================================");
				CPrintToChat(client, "%s Ai depasit numarul minim de ore necesare pentru functia de {darkred}Helper{default}; te invitam sa aplici pe forum!", playtimePrefix);
				CPrintToChat(client, "%s Forum: {darkred}%s{default}", playtimePrefix, playtimeWebsite);
				CPrintToChat(client, "{darkred}============================================================================================");
			}
		}
		if(playtime/3600 < 1)
			CPrintToChatAll("%s {darkred}%N{default} has spent: {green}%s {default}minute(s) on the server", playtimePrefix, client, time_str);
		else if(playtime/3600 == 1)
			CPrintToChatAll("%s {darkred}%N{default} has spent: {green}%d{green}%s {default}hour on the server", playtimePrefix, client, playtime/3600, time_str);
		else
			CPrintToChatAll("%s {darkred}%N{default} has spent: {green}%d{green}%s {default}hour(s) on the server", playtimePrefix, client, playtime/3600, time_str);
	}
}

public void OnClientDisconnect(int client)
{
	if(sm_playtime_mode.IntValue != 0 && !IsFakeClient(client) && IsClientAuthorized(client))
		IncreaseClientTime(client, RoundToFloor(GetClientTime(client)));
}

public Action UpdateTimes(Handle timer)
{
	for(int i=1; i <= MaxClients && IsClientInGame(i); i++)
	{
		if (!IsFakeClient(i) && IsClientAuthorized(i) && !(sm_playtime_team.IntValue == 1 && GetClientTeam(i) < 2))
			IncreaseClientTime(i, sm_playtime_refresh.IntValue);
	}
	return Plugin_Continue;
}

public void IncreaseClientTime(int client, int time)
{
	static char name[65], escaped_name[128], steamid[32], query[256];
	
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	SQL_EscapeString(hDatabase, name, escaped_name, sizeof(escaped_name));
	
	DBCheckConnect();
	Format(query, sizeof(query), "INSERT INTO %s (steamid, name, playtime) VALUES (\"%s\",\"%s\", %i) ON DUPLICATE KEY UPDATE name=VALUES(name),playtime=playtime+VALUES(playtime)", playtimeTable, steamid, escaped_name, time);
	SQL_TQuery(hDatabase, TQuery_Callback, query, 1);
}

public void DBConnect(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Connection error! %s", error);
		return;
	}
	hDatabase = view_as<Database>(hndl);
	
	char query[256];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s` (`name` varchar(64) CHARACTER SET utf8 NOT NULL, `steamid` varchar(64) NOT NULL, `playtime` int(64) NOT NULL, UNIQUE KEY `steamid` (`steamid`))", playtimeTable);
	SQL_TQuery(hDatabase, TQuery_Callback, query, 2);
}

public void DBCheckConnect()
{
	if(hDatabase != null)
		return;
	char error[256];
	hDatabase = SQL_Connect(playtimeDatabase, true, error, sizeof(error));
	if (hDatabase == null)
		LogError("An error occurred while verifying the connection! %s", error);
}

public void ModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	CloseHandle(refreshTimer);
	if(sm_playtime_mode.IntValue == 0)
		refreshTimer = CreateTimer(sm_playtime_refresh.FloatValue, UpdateTimes, _, TIMER_REPEAT);
}

public void TQuery_Callback(Handle owner, Handle hQuery, const char[] error, any data)
{
	if(hQuery == INVALID_HANDLE)
		LogError("ERROR: A problem with SQL query! ID: %i Error: %s", data, error);
	CloseHandle(hQuery);
}
