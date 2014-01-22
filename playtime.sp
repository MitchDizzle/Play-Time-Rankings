#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <scp>
#define VERSION "2.0"

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
	String:TagC[16],
	String:TagC2[16],
	bool:TagTeamC,
	String:NameC[16],
	String:NameC2[16],
	bool:NamTeamC,
	String:TextC[16],
	String:TextC2[16],
	bool:TexTeamC,
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

	SQL_TConnect(SQLCallback_Connect, "storage-local");

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
		strcopy(TagHandler[X][TagC], 16, "");
		strcopy(TagHandler[X][TagC2], 16, "");
		strcopy(TagHandler[X][NameC], 16, "T");
		strcopy(TagHandler[X][NameC2], 16, "");
		strcopy(TagHandler[X][TextC], 16, "");
		strcopy(TagHandler[X][TextC2], 16, "");
		TagHandler[X][PlayTimeNeeded] = 0;
		TagHandler[X][TagTeamC] = false;
		TagHandler[X][NamTeamC] = false;
		TagHandler[X][TexTeamC] = false;
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
				//Tag Colors
				KvGetString(kvs, "tagc", TagHandler[TagCount][TagC], 10, "");
				if(!StrEqual(TagHandler[TagCount][TagC],"",false)) CalcColorTag(TagHandler[TagCount][TagC]);
				KvGetString(kvs, "tagc2", TagHandler[TagCount][TagC2], 10, "");
				if(!StrEqual(TagHandler[TagCount][TagC2],"",false)) {
					CalcColorTag(TagHandler[TagCount][TagC2]);
					TagHandler[TagCount][TagTeamC] = true;
				}
				//Name Colors
				KvGetString(kvs, "namec", TagHandler[TagCount][NameC], 10, "T");
				CalcColorTag(TagHandler[TagCount][NameC]);
				KvGetString(kvs, "namec2", TagHandler[TagCount][NameC2], 10, "");
				if(!StrEqual(TagHandler[TagCount][NameC2],"",false)) {
					CalcColorTag(TagHandler[TagCount][NameC2]);
					TagHandler[TagCount][NamTeamC] = true;
				}
				//Text Colors
				KvGetString(kvs, "textc", TagHandler[TagCount][TextC], 10, "");
				if(!StrEqual(TagHandler[TagCount][TextC],"",false)) CalcColorTag(TagHandler[TagCount][TextC]);
				KvGetString(kvs, "textc2", TagHandler[TagCount][TextC2], 10, "");
				if(!StrEqual(TagHandler[TagCount][TextC2],"",false)) {
					CalcColorTag(TagHandler[TagCount][TextC2]);
					TagHandler[TagCount][TexTeamC] = true;
				}
				//Needed Play time.
				TagHandler[TagCount][PlayTimeNeeded] = KvGetNum(kvs, "playtime", 0);
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

public CalcColorTag(String:Color[])
{
	decl String:tsColor[16];
	Format(tsColor, sizeof(tsColor), "%s", Color);
	ReplaceString(tsColor, sizeof(tsColor), "#", "");
	if(StrEqual(tsColor, "T", false))
		Format(Color, sizeof(tsColor), "\x03");
	else if(StrEqual(tsColor, "G", false))
		Format(Color, sizeof(tsColor), "\x04");
	else if(StrEqual(tsColor, "O", false))
		Format(Color, sizeof(tsColor), "\x05");
	else if(strlen(tsColor) == 6)
		Format(Color, sizeof(tsColor), "\x07%s", tsColor);
	else if(strlen(tsColor) == 8)
		Format(Color, sizeof(tsColor), "\x08%s", tsColor);
	else
		Format(Color, sizeof(tsColor), "\x01");
}

public Action:OnChatMessage(&author, Handle:recipients, String:name[], String:message[]) {
	//Message Config, and Message Handling
	new TagNum = PlayerTagNum[author];
	if(TagNum == -1)
	{
		return Plugin_Continue;
	}
	//This is pretty much Dr.McKay's Customchat color code, just replaced variables.
	new String:sTagColor[16];
	new String:sNamColor[16];
	if(strlen(TagHandler[TagNum][Tag]) > 0) Format(sTagColor, sizeof(sTagColor), "%s", (TagHandler[TagCount][TagTeamC] && iTeam[author] == 3) ? TagHandler[TagNum][TagC2] : TagHandler[TagNum][TagC]);
	Format(sNamColor, sizeof(sNamColor), "%s", (TagHandler[TagCount][NamTeamC] && iTeam[author] == 3) ? TagHandler[TagNum][NameC2] : TagHandler[TagNum][NameC]);
	Format(name, MAXLENGTH_NAME, "%s%s%s%s",  sTagColor, TagHandler[TagNum][Tag], sNamColor, name);
	
	new String:sTexColor[16];
	Format(sTexColor, sizeof(sTexColor), "%s", (TagHandler[TagCount][TexTeamC] && iTeam[author] == 3) ? TagHandler[TagNum][TextC2] : TagHandler[TagNum][TextC]);
	Format(message, MAXLENGTH_MESSAGE, "%s%s", sTexColor, message);
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
		decl String:BufferQuery[512];
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

GetPlayerSettings(client)
{
	if(IsClientInGame(client))
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

SavePlayerSettings(client)
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