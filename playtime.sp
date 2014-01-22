#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <scp>
#define VERSION "1.01"

new TotalTime[MAXPLAYERS+1];
new PlayerTagNum[MAXPLAYERS+1] = {-1,...};
new iTeam[MAXPLAYERS+1];

new bool:bCountSpec;
new bool:bCountCT;
new bool:bCountT;
new Handle:g_hDatabase = INVALID_HANDLE;
new bool:SQL_DBLoaded = false;

#define MAXTAGS 40
enum Tags
{
	String:Tag[32],
	String:TagC[10],
	//String:TagC2[10],
	//String:NameC[10],
	//String:NameC2[10],
	//String:TextC[10],
	//String:TextC2[10], ToDo: add name color, text color, and team checking differences.
	PlayTimeNeeded
}
new TagHandler[MAXTAGS+1][Tags];
new TagCount;

new Handle:CountSpecs = INVALID_HANDLE;
new Handle:AllowCT = INVALID_HANDLE;
new Handle:AllowT = INVALID_HANDLE;

public Plugin:myinfo =
{
	name = "Play Time Ranking",
	author = "Mitch.",
	description = "Play Tag Ranks",
	version = VERSION,
	url = "http://snbx.info/"
}

public OnPluginStart()
{
	CreateTimer(60.0, CheckTime, _, TIMER_REPEAT);
	LoadConfig();
	CountSpecs = CreateConVar("sm_playtime_countspec", "0", "Addtime if the players are in spec?");
	AllowT = CreateConVar("sm_playtime_count2", "1", "Addtime if the players are in Terrorist/Red?");
	AllowCT = CreateConVar("sm_playtime_count3", "1", "Addtime if the players are in Counter-Terrorist/blue?");
	AutoExecConfig(true, "playtime");
	bCountSpec = GetConVarBool(CountSpecs);
	bCountT = GetConVarBool(AllowT);
	bCountCT = GetConVarBool(AllowCT);	
	HookConVarChange(CountSpecs,	CvarUpdated);
	HookConVarChange(AllowT,		CvarUpdated);
	HookConVarChange(AllowCT,		CvarUpdated);

	HookEvent("player_team", Event_Team);

	SQL_TConnect(SQLCallback_Connect, "playtime");

	CreateConVar("playtime_version", VERSION, "Tag Ranking Version", FCVAR_DONTRECORD|FCVAR_NOTIFY|FCVAR_CHEAT);	
	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			iTeam[client] = GetClientTeam(client);
			GetPlayerSettings(client);
		}
		else
		{
			iTeam[client] = 0;
		}
	}
}

public CvarUpdated(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(convar == CountSpecs)
	{
		bCountSpec = GetConVarBool(CountSpecs);
	}
	else if(convar == AllowT)
	{
		bCountT = GetConVarBool(AllowT);
	}
	else if(convar == AllowCT)
	{
		bCountCT = GetConVarBool(AllowCT);
	}
}

public OnPluginEnd()
{
	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			OnClientDisconnect(client);
		}
	}
}

public Action:Event_Team(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	iTeam[client] = GetEventInt(event, "team"); //GetClientTeam(client);
}

LoadConfig() {
	
	for(new X = 0; X < MAXTAGS; X++)
	{
		strcopy(TagHandler[X][Tag], 32, "");
		strcopy(TagHandler[X][TagC], 10, "");
		TagHandler[X][PlayTimeNeeded] = 0;
	}
	new Handle:kvs = CreateKeyValues("TagConfig");
	decl String:sPaths[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPaths, sizeof(sPaths),"configs/ranktime.cfg");
	if(FileToKeyValues(kvs, sPaths))
	{
		if (KvGotoFirstSubKey(kvs))
		{
			TagCount = 0;
			do
			{
				KvGetSectionName(kvs, TagHandler[TagCount][Tag], 32);
				KvGetString(kvs, "color", TagHandler[TagCount][TagC], 10);
				TagHandler[TagCount][PlayTimeNeeded] = KvGetNum(kvs, "playtime", 0);
				ReplaceString(TagHandler[TagCount][TagC], 32, "#", "");
				TagCount++;
			} while (KvGotoNextKey(kvs));
		}
	}
	CloseHandle(kvs);
}

DefaultAll()
{
	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			GetPlayerSettings(client);
		}
	}
}

FindPlayerTagNum(client)
{
	if(TagCount > 0)
	{
		for(new X = 0; X < TagCount; X++)
		{
			if(TagHandler[X][PlayTimeNeeded] <= TotalTime[client])
			{
				PlayerTagNum[client] = X;
				break;
			}
		}
	}
}

public Action:CheckTime(Handle:timer)
{
	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			if(((iTeam[client] > 2) && bCountSpec) || ((iTeam[client] == 2) && bCountT) || ((iTeam[client] == 3) && bCountCT))
			{
				TotalTime[client]++;
				FindPlayerTagNum(client);
			}
		}
	}
	return Plugin_Continue;
}

public OnClientDisconnect(client)
{
	SavePlayerSettings(client);
}

public OnClientAuthorized(client, const String:auth[])
{
	GetPlayerSettings(client);
}

public Action:OnChatMessage(&author, Handle:recipients, String:name[], String:message[]) {
	//Message Config, and Message Handling
	new TagNum = PlayerTagNum[author];
	if(TagNum == -1)
	{
		return Plugin_Continue;
	}
	//This is pretty much Dr.McKay's Customchat color code, just replaced variables.
	//Tag:
	new String:TagColor[16];
	//new String:TagText[48];
	//new String:NameColor[16];
	if(strlen(TagHandler[TagNum][Tag]) > 0)
	{
		if(StrEqual(TagHandler[TagNum][TagC], "T", false))
			Format(TagColor, sizeof(TagColor), "\x03");
		else if(StrEqual(TagHandler[TagNum][TagC], "G", false))
			Format(TagColor, sizeof(TagColor), "\x04");
		else if(StrEqual(TagHandler[TagNum][TagC], "O", false))
			Format(TagColor, sizeof(TagColor), "\x05");
		else if(strlen(TagHandler[TagNum][TagC]) == 6)
			Format(TagColor, sizeof(TagColor), "\x07%s", TagHandler[TagNum][TagC]);
		else if(strlen(TagHandler[TagNum][TagC]) == 8)
			Format(TagColor, sizeof(TagColor), "\x08%s", TagHandler[TagNum][TagC]);
		else
			Format(TagColor, sizeof(TagColor), "\x01");
		Format(name, MAXLENGTH_NAME, "%s%s \x03%s",  TagColor, TagHandler[TagNum][Tag], name);
	}
	return Plugin_Changed;
}

//****************************//
//     Ugly SQL Stuff D:      //
//****************************//
public SQLCallback_Connect(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		SetFailState("Error connecting to database. %s", error);
	} else {
		g_hDatabase = hndl;
		new String:BufferQuery[512];
		Format(BufferQuery, sizeof(BufferQuery), "CREATE TABLE IF NOT EXISTS `playtimedata` (`steamid` varchar(32) NOT NULL, `playtime` int(11) DEFAULT 0)");
		SQL_TQuery(g_hDatabase, SQLCallback_Enabled, BufferQuery);
	}
}
public SQLCallback_Enabled(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		SetFailState("Error connecting to database. %s", error);
	} else {
		SQL_DBLoaded = true;
		DefaultAll();
	}
}

GetPlayerSettings(client=0)
{
	if(client)
	{
		if(SQL_DBLoaded)
		{
			new String:authid[32];
			new String:query[256];
			GetClientAuthString(client, authid, sizeof(authid));
			Format(query, sizeof(query), "SELECT * FROM `playtimedata` WHERE steamid=\"%s\"", authid);
			SQL_TQuery(g_hDatabase, SQLCallback_GetPlayer, query, GetClientUserId(client));
		}
	}
}

SavePlayerSettings(client=0)
{
	if(client)
	{
		if(SQL_DBLoaded)
		{
			new String:query[256];
			new String:authid[32];
			GetClientAuthString(client, authid, sizeof(authid));
			Format(query, sizeof(query), "UPDATE `playtimedata` SET playtime=%i  WHERE steamid=\"%s\"", TotalTime[client], authid);
			SQL_TQuery(g_hDatabase, SQLCallback_Void, query);
		}
	}
}
public SQLCallback_GetPlayer(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	if (hndl == INVALID_HANDLE)
	{
		SetFailState("Error. %s", error);
	} else {
		new client = GetClientOfUserId(userid);
		if(client == 0)
			return;
		
		if(SQL_GetRowCount(hndl)>=1)
		{
			SQL_FetchRow(hndl);
			TotalTime[client] = SQL_FetchInt(hndl, 1);
			FindPlayerTagNum(client);
		}
		else
		{
			new String:query[256];
			new String:authid[32];
			GetClientAuthString(client, authid, sizeof(authid));
			Format(query, sizeof(query), "INSERT INTO `playtimedata` (steamid, playtime) VALUES(\"%s\", 0)", authid);
			SQL_TQuery(g_hDatabase, SQLCallback_Void, query, userid);
		}
	}

}
public SQLCallback_Void(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("Error. %s", error);
	}
}