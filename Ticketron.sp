#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.0.1"

#include <sourcemod>
#include <morecolors_store>
#include <EventLogs>
#include <Ticketron>
#include <SteamWorks>
#include <steamtools>

#pragma newdecls required

#define Divider_Left "▬▬▬▬ι══════════════ﺤ(̲̅ ̲̅(̲̅"
#define Divider_Right ") ̲̅)-══════════════ι▬▬▬▬▬";

#define Divider_Success "{grey}▬▬▬▬▬ι══════════════ﺤ{lightseagreen}(̲̅ ̲̅(̲̅Success) ̲̅){grey}-══════════════ι▬▬▬▬▬"
#define Divider_Failure "{grey}▬▬▬▬▬ι══════════════ﺤ{lightseagreen}(̲̅ ̲̅(̲̅Failure) ̲̅){grey}-══════════════ι▬▬▬▬▬"
#define Divider_Pagination "{grey}▬▬▬▬▬ι══════════════ﺤ{lightseagreen}(̲̅ ̲̅(̲̅   %i{grey}/{lightseagreen}%i   ) ̲̅){grey}-══════════════ι▬▬▬▬▬"

#define PageLimit 5

//<!-- Main -->
Database hDB;

char g_cIP[64];
char g_cHostname[128];
char g_cBreed[32];
char g_cGroupID32[32];

bool InGroup[MAXPLAYERS + 1];

float g_fPollingRate = 10.0;

Handle g_hPollingTimer;

int IID = -1;

//<!--- ConVars --->
ConVar cPollingRate;
ConVar cBreed;
ConVar cGroupID32;

public Plugin myinfo = 
{
	name = "Ticketron",
	author = PLUGIN_AUTHOR,
	description = "A fully-featured ticket support system",
	version = PLUGIN_VERSION,
	url = "https://keybase.io/rumblefrog"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	hDB = SQL_Connect("ticketron", true, error, err_max);
	
	if (hDB == INVALID_HANDLE)
		return APLRes_Failure;
	
	//Tickets table must be created before others due to foreign key references	
	char TicketsCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Ticketron_Tickets` ( `id` INT NOT NULL AUTO_INCREMENT , `host` VARBINARY(16) NOT NULL , `hostname` VARCHAR(64) NOT NULL , `breed` VARCHAR(32) NOT NULL , `target_name` VARCHAR(32) NULL DEFAULT NULL , `target_steamid` VARCHAR(32) NULL DEFAULT NULL , `target_ip` VARBINARY(16) NULL DEFAULT NULL, `reporter_name` VARCHAR(32) NOT NULL , `reporter_steamid` VARCHAR(32) NOT NULL , `reporter_ip` VARBINARY(16) NOT NULL, `reporter_seed` TINYINT(1) NOT NULL, `reason` TEXT NOT NULL , `handler_name` VARCHAR(32) NULL DEFAULT NULL , `handler_steamid` VARCHAR(32) NULL DEFAULT NULL , `handled` TINYINT(1) NOT NULL DEFAULT '0' , `data` TEXT NULL DEFAULT NULL, `time_reported` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , `time_handled` TIMESTAMP NULL DEFAULT NULL , `time_closed` TIMESTAMP NULL DEFAULT NULL , `closed` TINYINT(1) NOT NULL DEFAULT '0', `external_handled` TINYINT(1) NOT NULL DEFAULT '0' , PRIMARY KEY (`id`), INDEX (`breed`), INDEX (`handler_steamid`), INDEX (`handled`), INDEX (`target_steamid`), INDEX (`target_ip`), INDEX (`reporter_steamid`), INDEX (`reporter_ip`), INDEX(`reporter_seed`), INDEX (`closed`), INDEX (`external_handled`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	char RepliesCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Ticketron_Replies` ( `id` INT NOT NULL AUTO_INCREMENT , `ticket_id` INT NOT NULL , `replier_name` VARCHAR(32) NOT NULL , `replier_steamid` VARCHAR(32) NOT NULL , `message` LONGTEXT NOT NULL , `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , PRIMARY KEY (`id`), INDEX (`ticket_id`), INDEX (`replier_steamid`), FOREIGN KEY (`ticket_id`) REFERENCES `Ticketron_Tickets` (`id` )) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	char NotificationsCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Ticketron_Notifications` ( `id` INT NOT NULL AUTO_INCREMENT , `ticket_id` INT NOT NULL , `message` TEXT NOT NULL , `receiver` TINYINT(1) NOT NULL, `internal_handled` TINYINT(1) NOT NULL DEFAULT '0' , `external_handled` TINYINT(1) NOT NULL DEFAULT '0' , `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , PRIMARY KEY (`id`), INDEX (`ticket_id`), INDEX (`receiver`), INDEX (`internal_handled`), INDEX (`external_handled`), FOREIGN KEY (`ticket_id`) REFERENCES `Ticketron_Tickets` (`id` )) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	
	SQL_SetCharset(hDB, "utf8mb4");
			
	SQL_TQuery(hDB, OnTableCreate, TicketsCreateSQL, DBPrio_High);
	SQL_TQuery(hDB, OnTableCreate, RepliesCreateSQL);
	SQL_TQuery(hDB, OnTableCreate, NotificationsCreateSQL);
	
	RegPluginLibrary("Ticketron");

	CreateNative("Ticketron_AddNotification", NativeAddNotification);
	
	return APLRes_Success;
}

public void OnTableCreate(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == INVALID_HANDLE)
	{
		EL_LogPlugin(LOG_FATAL, "Unable to create table: %s", error);
		SetFailState("Unable to create table: %s", error);
	}
}

public void OnPluginStart()
{
	CreateConVar("sm_ticketron_version", PLUGIN_VERSION, "Ticketron Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	cPollingRate = CreateConVar("sm_ticketron_rate", "10", "Ticketron Notification Polling Rate", FCVAR_NONE, true, 1.0, false);
	cBreed = CreateConVar("sm_ticketron_breed", "global", "Ticketron External Breed Identifier", FCVAR_NONE);
	cGroupID32 = CreateConVar("sm_ticketron_groupid32", "0", "Steam Group 32-Bit ID", FCVAR_NONE);
	
	AutoExecConfig(true, "ticketron");
	
	RegAdminCmd("sm_ticket", CreateTicketCmd, 0, "Creates ticket");
	RegAdminCmd("sm_handle", HandleTicketCmd, ADMFLAG_GENERIC, "Handles ticket");
	RegAdminCmd("sm_unhandle", UnhandleTicketCmd, ADMFLAG_GENERIC, "Unhandles ticket");
	RegAdminCmd("sm_mytickets", MyTicketsCmd, 0, "View my tickets");
	RegAdminCmd("sm_ticketqueue", TicketQueueCmd, 0, "View unhandled tickets");
	RegAdminCmd("sm_viewticket", ViewTicketCmd, 0, "View ticket details");
	RegAdminCmd("sm_replyticket", ReplyTicketCmd, 0, "Reply to ticket");
	
	RegAdminCmd("ticketron_donor", VoidCmd, ADMFLAG_RESERVATION, "Ticketron Donor Permission Check");
	RegAdminCmd("ticketron_admin", VoidCmd, ADMFLAG_GENERIC, "Ticketron Admin Permission Check");
	
	if (!SteamWorks_IsConnected())
	{
		int ip = GetConVarInt(FindConVar("hostip"));
		Format(g_cIP, sizeof(g_cIP), "%d.%d.%d.%d:%d", ((ip & 0xFF000000) >> 24) & 0xFF, ((ip & 0x00FF0000) >> 16) & 0xFF, ((ip & 0x0000FF00) >>  8) & 0xFF, ((ip & 0x000000FF) >>  0) & 0xFF, GetConVarInt(FindConVar("hostport")));
	}
	
	GetConVarString(FindConVar("hostname"), g_cHostname, sizeof g_cHostname);
	
	
	g_fPollingRate = cPollingRate.FloatValue;
	HookConVarChange(cPollingRate, OnConvarChanged);
	
	cBreed.GetString(g_cBreed, sizeof g_cBreed);
	HookConVarChange(cBreed, OnConvarChanged);
	
	cGroupID32.GetString(g_cGroupID32, sizeof g_cGroupID32);
	HookConVarChange(cGroupID32, OnConvarChanged);
	
	g_hPollingTimer = CreateTimer(g_fPollingRate, PollingTimer, _, TIMER_REPEAT);
}

public Action CreateTicketCmd(int client, int args)
{
	char buffer[2048];
		
	ReplySource CmdOrigin = GetCmdReplySource();
	GetCmdArgString(buffer, sizeof buffer);
	
	if (strlen(buffer) < 15)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Please add some details");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return Plugin_Handled;
	}
	
	int buffer_len = strlen(buffer) * 2 + 1;
	int Client_Seed = GetClientSeed(client);
	
	char Client_Name[MAX_NAME_LENGTH], Client_SteamID64[32], Client_IP[45], Escaped_Name[128];
	char[] Escaped_Reason = new char[buffer_len];
	char[] InsertQuery = new char[1024 + buffer_len];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	GetClientIP(client, Client_IP, sizeof Client_IP);
	
	SQL_EscapeString(hDB, Client_Name, Escaped_Name, sizeof Escaped_Name);
	SQL_EscapeString(hDB, buffer, Escaped_Reason, buffer_len);
	
	Format(InsertQuery, 1024 + buffer_len, "INSERT INTO `Ticketron_Tickets` (`host`, `hostname`, `breed`, `reporter_name`, `reporter_steamid`, `reporter_ip`, `reporter_seed`, `reason`) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%i', '%s')", g_cIP, g_cHostname, g_cBreed, Escaped_Name, Client_SteamID64, Client_IP, Client_Seed, Escaped_Reason);
	
	DataPack pData = CreateDataPack();
	WritePackCell(pData, CmdOrigin);
	WritePackCell(pData, client);
	
	hDB.Query(SQL_OnTicketCreate, InsertQuery, pData);
		
	return Plugin_Handled;
}

public void SQL_OnTicketCreate(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to insert row: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while creating the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	int ticketid = results.InsertId;
	
	CReplyToCommand(client, "%s", Divider_Success);
	CReplyToCommand(client, "{grey}Your ticket ID: {chartreuse}%i{grey}.", ticketid);
	CReplyToCommand(client, "{grey}View your ticket using {chartreuse}!ViewTicket %i{grey}.", ticketid);
	CReplyToCommand(client, "%s", Divider_Success);
}

public Action HandleTicketCmd(int client, int args)
{
	ReplySource CmdOrigin = GetCmdReplySource();
	char buffer[16], Select_Query[256];
	int ticket;
	
	GetCmdArg(1, buffer, sizeof buffer);
	ticket = StringToInt(buffer);
	
	Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Tickets` WHERE `id` = %i AND `closed` = 0", ticket);
	
	DataPack pData = CreateDataPack();
	
	WritePackCell(pData, CmdOrigin);
	WritePackCell(pData, client);
	WritePackCell(pData, ticket);
	
	hDB.Query(SQL_OnTicketHandleSelect, Select_Query, pData);
	
	return Plugin_Handled;
}

public void SQL_OnTicketHandleSelect(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to select row: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while assigning the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	if (results.RowCount == 0)
	{		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Insufficient permission or the ticket does not exist.");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	results.FetchRow();
	
	if (results.FetchInt(14) == 1)
	{
		char Handler[MAX_NAME_LENGTH];
		results.FetchString(12, Handler, sizeof Handler);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Ticket is currently being handled by {chartreuse}%s{grey}.", Handler);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	char UpdateQuery[512], Client_Name[MAX_NAME_LENGTH], Escaped_Name[128], Client_SteamID64[32];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	
	db.Escape(Client_Name, Escaped_Name, sizeof Escaped_Name);
	
	Format(UpdateQuery, sizeof UpdateQuery, "UPDATE `Ticketron_Tickets` SET `handler_name` = '%s', `handler_steamid` = '%s', `handled` = 1, `time_handled` = CURRENT_TIMESTAMP() WHERE `id` = '%i'", Escaped_Name, Client_SteamID64, ticket);
	
	db.Query(SQL_OnTicketHandleUpdate, UpdateQuery, pData);
}

public void SQL_OnTicketHandleUpdate(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to insert row: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while assigning the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	CReplyToCommand(client, "%s", Divider_Success);
	CReplyToCommand(client, "{grey}Now handling ticket ID: {chartreuse}%i{grey}.", ticket);
	CReplyToCommand(client, "{grey}Unhandle the ticket using {chartreuse}!UnhandleTicket #{grey}.");
	CReplyToCommand(client, "{grey}View the ticket using {chartreuse}!ViewTicket %i{grey}.", ticket);
	CReplyToCommand(client, "%s", Divider_Success);
	
	char Client_Name[MAX_NAME_LENGTH];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	
	Ticketron_AddNotification(ticket, false, "%s Is now handling your ticket", Client_Name);
}

public Action UnhandleTicketCmd(int client, int args)
{
	ReplySource CmdOrigin = GetCmdReplySource();
	char buffer[16], Select_Query[256], Client_SteamID64[32];
	int ticket;
	
	GetCmdArg(1, buffer, sizeof buffer);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	ticket = StringToInt(buffer);
	
	Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Tickets` WHERE `id` = %i AND `handler_steamid` = '%s' AND `handled` = 1 AND `closed` = 0", ticket, Client_SteamID64);
	
	DataPack pData = CreateDataPack();
	
	WritePackCell(pData, CmdOrigin);
	WritePackCell(pData, client);
	WritePackCell(pData, ticket);
	
	hDB.Query(SQL_OnTicketUnhandleSelect, Select_Query, pData);
	
	return Plugin_Handled;
}

public void SQL_OnTicketUnhandleSelect(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to insert row: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while authorizing the action. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
		
	} else if (results.RowCount == 0)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Insufficient permission while attempting to unhandle.");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	char UpdateQuery[512];
	
	Format(UpdateQuery, sizeof UpdateQuery, "UPDATE `Ticketron_Tickets` SET `handler_name` = NULL, `handler_steamid` = NULL, `handled` = 0, `time_handled` = NULL WHERE `id` = '%i'", ticket);
	
	db.Query(SQL_OnTicketUnhandleUpdate, UpdateQuery, pData);
}

public void SQL_OnTicketUnhandleUpdate(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to insert row: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while unassigning the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	CReplyToCommand(client, "%s", Divider_Success);
	CReplyToCommand(client, "{grey}Unhandled ticket ID: {chartreuse}%i{grey}.", ticket);
	CReplyToCommand(client, "%s", Divider_Success);
	
	char Client_Name[MAX_NAME_LENGTH];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	
	Ticketron_AddNotification(ticket, false, "%s Unhandled your ticket", Client_Name);
}

public Action MyTicketsCmd(int client, int args)
{
	ReplySource CmdOrigin = GetCmdReplySource();
	
	char Client_SteamID64[32], Select_Query[256], buffer[16];
	
	GetCmdArg(1, buffer, sizeof buffer);
	
	int page = StringToInt(buffer);
	
	if (page < 0)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Page number cannot be negative");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return Plugin_Handled;
	}
	
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	
	Format(Select_Query, sizeof Select_Query, "SELECT count(*) as count FROM `Ticketron_Tickets` WHERE `reporter_steamid` = '%s'", Client_SteamID64);
	
	DataPack pData = CreateDataPack();
	
	WritePackCell(pData, CmdOrigin);
	WritePackCell(pData, client);
	WritePackCell(pData, page);
	
	hDB.Query(SQL_OnMyTicketsCount, Select_Query, pData);
	
	return Plugin_Handled;
}

public void SQL_OnMyTicketsCount(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int page = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to select tickets: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while querying. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
		
	}
	
	results.FetchRow();
	int count = results.FetchInt(0);
	
	if (count == 0)
	{
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "{grey}Could not find any tickets :P");
		CReplyToCommand(client, "%s", Divider_Success);
		
		return;
	}
	
	ResetPack(pData);
	
	WritePackCell(pData, count);
	
	int offset = (page != 1 && page != 0) ? ((page - 1) * PageLimit) : 0;
	
	char Select_Query[256], Client_SteamID64[32];
	
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	
	Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Tickets` WHERE `reporter_steamid` = '%s' ORDER BY `id` DESC LIMIT %i OFFSET %i", Client_SteamID64, PageLimit, offset);
	
	db.Query(SQL_OnMyTicketsSelect, Select_Query, pData);
}

public void SQL_OnMyTicketsSelect(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int page = ReadPackCell(pData);
	int count = ReadPackCell(pData);
	int totalpages = RoundToCeil(view_as<float>(count / PageLimit));
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to select tickets: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while querying. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
		
	} else if (results.RowCount == 0)
	{
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "{grey}Could not find any tickets :P");
		CReplyToCommand(client, "%s", Divider_Success);
		
		return;
	}
	
	int ticketid;
	char timestamp[64];
	
	CReplyToCommand(client, "%s", Divider_Success);
	
	while (results.FetchRow())
	{
		ticketid = results.FetchInt(0);
		results.FetchString(16, timestamp, sizeof timestamp);
		
		CReplyToCommand(client, "{grey}#{lightseagreen}%i {grey}- {lightseagreen}%s", ticketid, timestamp);
	}
		
	CReplyToCommand(client, Divider_Pagination, page+1, totalpages+1);
	
}

public Action TicketQueueCmd(int client, int args)
{
	ReplySource CmdOrigin = GetCmdReplySource();
	
	char Select_Query[256], buffer[16];
	
	GetCmdArg(1, buffer, sizeof buffer);
	
	int page = StringToInt(buffer);
	
	if (page < 0)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Page number cannot be negative");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return Plugin_Handled;
	}
	
	Format(Select_Query, sizeof Select_Query, "SELECT count(*) as count FROM `Ticketron_Tickets` WHERE `handled` = 0");
	
	DataPack pData = CreateDataPack();
	
	WritePackCell(pData, CmdOrigin);
	WritePackCell(pData, client);
	WritePackCell(pData, page);
	
	hDB.Query(SQL_OnTicketQueueCount, Select_Query, pData);
	
	return Plugin_Handled;
}

public void SQL_OnTicketQueueCount(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int page = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to select tickets: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while querying. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
		
	}
	
	results.FetchRow();
	int count = results.FetchInt(0);
	
	if (count == 0)
	{
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "{grey}Could not find any tickets :P.");
		CReplyToCommand(client, "%s", Divider_Success);
		
		return;
	}
	
	ResetPack(pData);
	
	WritePackCell(pData, count);
	
	int offset = (page != 1 && page != 0) ? ((page - 1) * PageLimit) : 0;
	
	char Select_Query[256];
		
	Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Tickets` WHERE `handled` = 0 AND `closed` = 0 ORDER BY `id`, `reporter_seed` DESC LIMIT %i OFFSET %i", PageLimit, offset);
	
	db.Query(SQL_OnTicketQueueSelect, Select_Query, pData);
}

public void SQL_OnTicketQueueSelect(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int page = ReadPackCell(pData);
	int count = ReadPackCell(pData);
	int totalpages = RoundToCeil(view_as<float>(count / PageLimit));
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to select tickets: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while querying. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
		
	} else if (results.RowCount == 0)
	{
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "{grey}Could not find any tickets :P.");
		CReplyToCommand(client, "%s", Divider_Success);
		
		return;
	}
	
	int ticketid;
	char timestamp[64];
	
	CReplyToCommand(client, "%s", Divider_Success);
	
	while (results.FetchRow())
	{
		ticketid = results.FetchInt(0);
		results.FetchString(16, timestamp, sizeof timestamp);
		
		CReplyToCommand(client, "{grey}#{lightseagreen}%i {grey}- {lightseagreen}%s", ticketid, timestamp);
	}
		
	CReplyToCommand(client, Divider_Pagination, page+1, totalpages+1);
}

public Action ViewTicketCmd(int client, int args)
{
	ReplySource CmdOrigin = GetCmdReplySource();
	char buffer[16], Select_Query[256], Client_SteamID64[32];
	int ticket;
	
	GetCmdArg(1, buffer, sizeof buffer);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	ticket = StringToInt(buffer);
	
	if (ticket < 1)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Ticket number must be greater or equal to 1");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return Plugin_Handled;
	}
	
	if (CheckCommandAccess(client, "ticketron_admin", ADMFLAG_GENERIC))
		Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Tickets` WHERE `id` = %i", ticket);
	else
		Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Tickets` WHERE `id` = %i AND `reporter_steamid` = '%s'", ticket, Client_SteamID64);
	
	DataPack pData = CreateDataPack();
	
	WritePackCell(pData, CmdOrigin);
	WritePackCell(pData, client);
	WritePackCell(pData, ticket);
	
	hDB.Query(SQL_OnViewTicket, Select_Query, pData);
	
	return Plugin_Handled;
}

public void SQL_OnViewTicket(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to view ticket: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while selecting the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	if (results.RowCount == 0)
	{		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Ticket does not exist.");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	char hostname[64], breed[32], target_name[32], reporter_name[32], reporter_steamid[32], reason[2048], handler_name[32], handler_steamid[32], timestamp[32], Select_Query[512];
	
	results.FetchRow();
	results.FetchString(2, hostname, sizeof hostname);
	results.FetchString(3, breed, sizeof breed);
	results.FetchString(4, target_name, sizeof target_name);
	results.FetchString(7, reporter_name, sizeof reporter_name);
	results.FetchString(8, reporter_steamid, sizeof reporter_steamid);
	results.FetchString(11, reason, sizeof reason);
	results.FetchString(12, handler_name, sizeof handler_name);
	results.FetchString(13, handler_steamid, sizeof handler_steamid);
	results.FetchString(16, timestamp, sizeof timestamp);
	
	WritePackString(pData, hostname);
	WritePackString(pData, breed);
	WritePackString(pData, target_name);
	WritePackString(pData, reporter_name);
	WritePackString(pData, reporter_steamid);
	WritePackString(pData, reason);
	WritePackString(pData, handler_name);
	WritePackString(pData, handler_steamid);
	WritePackString(pData, timestamp);
	
	Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Replies` WHERE `ticket_id` = '%i' ORDER BY id", ticket);
	
	db.Query(SQL_OnViewTicketReplies, Select_Query, pData);
}

public void SQL_OnViewTicketReplies(Database db, DBResultSet results, const char[] error, any pData)
{
	char hostname[64], breed[32], target_name[32], reporter_name[32], reporter_steamid[32], reason[2048], handler_name[32], handler_steamid[32], timestamp[32];
	
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);	
	ReadPackString(pData, hostname, sizeof hostname);
	ReadPackString(pData, breed, sizeof breed);
	ReadPackString(pData, target_name, sizeof target_name);
	ReadPackString(pData, reporter_name, sizeof reporter_name);
	ReadPackString(pData, reporter_steamid, sizeof reporter_steamid);
	ReadPackString(pData, reason, sizeof reason);
	ReadPackString(pData, handler_name, sizeof handler_name);
	ReadPackString(pData, handler_steamid, sizeof handler_steamid);
	ReadPackString(pData, timestamp, sizeof timestamp);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to view ticket: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while selecting the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	CReplyToCommand(client, "%s", Divider_Success);
	CReplyToCommand(client, "{grey}Overview: #{chartreuse}%i {grey}| {chartreuse}%s {grey}| {chartreuse}%s {grey}| {chartreuse}%s", ticket, hostname, breed, timestamp);
	if (target_name[0])
		CReplyToCommand(client, "{grey}Target: {chartreuse}%s", target_name);
	CReplyToCommand(client, "{grey}Reporter: {chartreuse}%s", reporter_name);
	if (handler_name[0])
		CReplyToCommand(client, "{grey}Handler: {chartreuse}%s", handler_name);
	CReplyToCommand(client, "{grey}Message: {chartreuse}%s", reason);
	
	char Replier_Name[32], Replier_SteamID[32], Message[1024];
	
	while(results.FetchRow())
	{
		results.FetchString(2, Replier_Name, sizeof Replier_Name);
		results.FetchString(3, Replier_SteamID, sizeof Replier_SteamID);
		results.FetchString(4, Message, sizeof Message);
			
		if (StrEqual(Replier_SteamID, reporter_steamid))
			CReplyToCommand(client, "{community}%s {white}: {gray}%s", Replier_Name, Message);
		else
			CReplyToCommand(client, "{crimson}%s {white}: {gray}%s", Replier_Name, Message);
	}
	
	CReplyToCommand(client, "%s", Divider_Success);
}

public Action ReplyTicketCmd(int client, int args)
{
	ReplySource CmdOrigin = GetCmdReplySource();
	char buffer[16], Select_Query[256], Client_SteamID64[32], Message[1024], arg[64];
	int ticket;
		
	GetCmdArg(1, buffer, sizeof buffer);
	
	for (int i = 2; i <= args; i++)
	{
		GetCmdArg(i, arg, sizeof arg);
		Format(Message, sizeof Message, "%s %s", Message, arg);
	}
	
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	ticket = StringToInt(buffer);
	
	if (ticket < 1)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Ticket number must be greater or equal to 1");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return Plugin_Handled;
	}
	
	if (strlen(Message) < 5)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Please add some details");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return Plugin_Handled;
	}
		
	Format(Select_Query, sizeof Select_Query, "SELECT * FROM `Ticketron_Tickets` WHERE `id` = '%i' AND (`reporter_steamid` = '%s' OR `handler_steamid` = '%s')", ticket, Client_SteamID64, Client_SteamID64);
	
	DataPack pData = CreateDataPack();
	
	WritePackCell(pData, CmdOrigin);
	WritePackCell(pData, client);
	WritePackCell(pData, ticket);
	WritePackString(pData, Message);
	
	hDB.Query(SQL_OnReplyTicketSelect, Select_Query, pData);
	
	return Plugin_Handled;
}

public void SQL_OnReplyTicketSelect(Database db, DBResultSet results, const char[] error, any pData)
{
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to reply to ticket: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while replying to the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	if (results.RowCount == 0)
	{		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Insufficient permission or the ticket does not exist.");
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	char Insert_Query[512], Client_Name[MAX_NAME_LENGTH], Escaped_Name[65], Client_SteamID64[32], Message[1024], Escaped_Message[2049], Search_ID[32];
	
	results.FetchRow();
	results.FetchString(8, Search_ID, sizeof Search_ID);
	
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	GetClientName(client, Client_Name, sizeof Client_Name);
	ReadPackString(pData, Message, sizeof Message);
	
	int isOwn = (StrEqual(Search_ID, Client_SteamID64)) ? 1 : 0;
	WritePackCell(pData, isOwn);
	
	WritePackString(pData, Client_Name);
	
	db.Escape(Client_Name, Escaped_Name, sizeof Escaped_Name);
	db.Escape(Message, Escaped_Message, sizeof Escaped_Message);
	
	Format(Insert_Query, sizeof Insert_Query, "INSERT INTO `Ticketron_Replies` (`ticket_id`, `replier_name`, `replier_steamid`, `message`) VALUES ('%i', '%s', '%s', '%s')", ticket, Escaped_Name, Client_SteamID64, Escaped_Message);
	
	db.Query(SQL_OnReplyTicketInsert, Insert_Query, pData);
}

public void SQL_OnReplyTicketInsert(Database db, DBResultSet results, const char[] error, any pData)
{
	char message[1024];
	
	ResetPack(pData);
	
	ReplySource CmdOrigin = ReadPackCell(pData);
	int client = ReadPackCell(pData);
	int ticket = ReadPackCell(pData);
	ReadPackString(pData, message, sizeof message);
	int isOwn = ReadPackCell(pData);
	
	SetCmdReplySource(CmdOrigin);
	
	if (results == null)
	{
		int rid = EL_LogPlugin(LOG_ERROR, "Unable to reply to ticket: %s", error);
		
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "{grey}Error while replying to the ticket. RID: {chartreuse}%i{grey}.", rid);
		CReplyToCommand(client, "%s", Divider_Failure);
		
		return;
	}
	
	CReplyToCommand(client, "%s", Divider_Success);
	CReplyToCommand(client, "{grey}Replied to ticket ID: {chartreuse}%i{grey}.", ticket);
	CReplyToCommand(client, "{grey}View the ticket ising {chartreuse}!ViewTicket %i{grey}.", ticket);
	CReplyToCommand(client, "%s", Divider_Success);
	
	char Client_Name[MAX_NAME_LENGTH];
	ReadPackString(pData, Client_Name, sizeof Client_Name);
	
	if (!isOwn)
		Ticketron_AddNotification(ticket, false, "%s Replied to your ticket", Client_Name);
	else
		Ticketron_AddNotification(ticket, true, "Got a reply from user");
}

public Action PollingTimer(Handle timer)
{
	char SelectQuery[512];
	
	Format(SelectQuery, sizeof SelectQuery, "SELECT n.`*`, t.`reporter_steamid`, t.`handler_steamid` FROM `Ticketron_Notifications` n INNER JOIN `Ticketron_Tickets` t ON t.`id` = n.`ticket_id` AND n.`internal_handled` = 0");
	
	hDB.Query(SQL_OnPollingTimerSelect, SelectQuery);
}

public void SQL_OnPollingTimerSelect(Database db, DBResultSet results, const char[] error, any pData)
{
	//Not going to log because it'd flood the database due to a repeated action
	
	if (results == null)
		return;
	
	int NID, Ticket, Receiver;
	char Message[256], Client_SteamID64[32], Handler_SteamID64[32], Search_SteamID64[32], UpdateQuery[256];

	while(results.FetchRow())
	{
		NID = results.FetchInt(0);
		Ticket = results.FetchInt(1);
		results.FetchString(2, Message, sizeof Message);
		Receiver = results.FetchInt(3);
		results.FetchString(7, Client_SteamID64, sizeof Client_SteamID64);
		results.FetchString(8, Handler_SteamID64, sizeof Handler_SteamID64);
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if(Client_IsValid(i))
			{
				GetClientAuthId(i, AuthId_SteamID64, Search_SteamID64, sizeof Search_SteamID64);
				
				if (Receiver)
				{
					if (StrEqual(Handler_SteamID64, Search_SteamID64, false))
					{
						MoreColors_CPrintToChat(i, "{lightseagreen}Ticket #%i: {grey}%s", Ticket, Message);
					
						Format(UpdateQuery, sizeof UpdateQuery, "UPDATE `Ticketron_Notifications` SET `internal_handled` = 1 WHERE `id` = '%i'", NID);
						db.Query(SQL_OnPollingTimerUpdate, UpdateQuery);
					}
				} else
				{
					if (StrEqual(Client_SteamID64, Search_SteamID64, false))
					{
						MoreColors_CPrintToChat(i, "{lightseagreen}Ticket #%i: {grey}%s", Ticket, Message);
					
						Format(UpdateQuery, sizeof UpdateQuery, "UPDATE `Ticketron_Notifications` SET `internal_handled` = 1 WHERE `id` = '%i'", NID);
						db.Query(SQL_OnPollingTimerUpdate, UpdateQuery);
					}
				}
			}
		}
	}
}

public void SQL_OnPollingTimerUpdate(Database db, DBResultSet results, const char[] error, any pData)
{
	//Not worrying about the result
}

public int NativeAddNotification(Handle plugin, int numParams)
{
	int written, ticket, receiver;
	char sMessage[1024], Escaped_Message[2049], InsertSQL[512];
	
	ticket = GetNativeCell(1);
	receiver = GetNativeCell(2);
	FormatNativeString(0, 3, 4, sizeof sMessage, written, sMessage);
	
	hDB.Escape(sMessage, Escaped_Message, sizeof Escaped_Message);
	
	Format(InsertSQL, sizeof InsertSQL, "INSERT INTO `Ticketron_Notifications` (`ticket_id`, `message`, `receiver`) VALUES ('%i', '%s', '%i')", ticket, Escaped_Message, receiver);
	
	hDB.Query(SQL_OnNativeAddNotification, InsertSQL);
	
	return IID;
}

public void SQL_OnNativeAddNotification(Database db, DBResultSet results, const char[] error, any pData)
{
	if (results == null)
		EL_LogPlugin(LOG_ERROR, "Unable to add notification: %s", error);
		
	IID = results.InsertId;
}

public void OnConvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == cPollingRate)
	{
		g_fPollingRate = cPollingRate.FloatValue;
		KillTimer(g_hPollingTimer);
		g_hPollingTimer = CreateTimer(g_fPollingRate, PollingTimer, _, TIMER_REPEAT);
	}
	if (convar == cBreed)
		cBreed.GetString(g_cBreed, sizeof g_cBreed);
	if (convar == cGroupID32)
		cGroupID32.GetString(g_cGroupID32, sizeof g_cGroupID32);
}

public int SteamWorks_SteamServersConnected()
{
	int octets[4];
	SteamWorks_GetPublicIP(octets);
	Format(g_cIP, sizeof(g_cIP), "%d.%d.%d.%d:%d", octets[0], octets[1], octets[2], octets[3], GetConVarInt(FindConVar("hostport")));
}

public void OnClientPostAdminCheck(int iClient)
{
	if (!StrEqual(g_cGroupID32, "0"))
	{
		SteamWorks_GetUserGroupStatus(iClient, StringToInt(g_cGroupID32));
	}
}

public int SteamWorks_OnClientGroupStatus(int authid, int groupid, bool isMember, bool isOfficer)
{
	
	if (groupid != StringToInt(g_cGroupID32))
		return;
	
	int iClient = GetUserFromAuthID(authid);	
	
	if (iClient == -1)
		return;
			
	if (isMember || isOfficer)
	{
		InGroup[iClient] = true;
		return;
	}
	
	return;
	
}

//In cases where Steamtools is also loaded and Steamworks fails to see the callback
public int Steam_GroupStatusResult(int client, int groupAccountID, bool groupMember, bool groupOfficer)
{
	
	if (groupAccountID != StringToInt(g_cGroupID32))
		return;	
	
	if (client == -1)
		return;
			
	if (groupMember || groupOfficer)
	{
		InGroup[client] = true;
		return;
	}
	
	return;
	
}

public Action VoidCmd(int client, int args)
{
	//Void
	return Plugin_Handled;
}

public int GetClientSeed(int client)
{
	if (CheckCommandAccess(client, "ticketron_donor", ADMFLAG_RESERVATION))
		return 2;
	if (InGroup[client])
		return 1;
		
	return 0;
}

public int GetUserFromAuthID(int authid)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i)) {
            char charauth[64];
            GetClientAuthId(i, AuthId_Steam3, charauth, sizeof(charauth));
               
            char charauth2[64];
            IntToString(authid, charauth2, sizeof(charauth2));
           
            if(StrContains(charauth, charauth2, false) > -1)
            {
                return i;
            }
        }
    }
    return -1;
}

stock bool Client_IsValid(int client, bool checkConnected=true)
{
	if (client > 4096) {
		client = EntRefToEntIndex(client);
	}

	if (client < 1 || client > MaxClients) {
		return false;
	}

	if (checkConnected && !IsClientConnected(client)) {
		return false;
	}

	return true;
}