#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.01"

#include <sourcemod>
#include <morecolors_store>
#undef REQUIRE_EXTENSIONS
#include <SteamWorks>


#pragma newdecls required

#define Divider_Left "▬▬ι═══════ﺤ(̲̅ ̲̅(̲̅"
#define Divider_Right ") ̲̅)-═══════ι▬▬";

#define Divider_Success "{grey}▬▬ι═══════ﺤ{lightseagreen}(̲̅ ̲̅(̲̅Success) ̲̅){grey}-═══════ι▬▬"
#define Divider_Failure "{grey}▬▬ι═══════ﺤ{lightseagreen}(̲̅ ̲̅(̲̅Failure) ̲̅){grey}-═══════ι▬▬"

//<!-- Main -->
Database hDB;

char g_cIP[64];
char g_cHostname[128];
char g_cBreed[32];

float g_fPollingRate = 10.0;

Handle g_hPollingTimer;

//<!--- ConVars --->
ConVar cPollingRate;
ConVar cBreed;

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
	char TicketsCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Ticketron_Tickets` ( `id` INT NOT NULL AUTO_INCREMENT , `host` VARBINARY(16) NOT NULL , `hostname` VARCHAR(64) NOT NULL , `breed` VARCHAR(32) NOT NULL , `target_name` VARCHAR(32) NULL DEFAULT NULL , `target_steamid` VARCHAR(32) NULL DEFAULT NULL , `target_ip` VARBINARY(16) NULL DEFAULT NULL, `reporter_name` VARCHAR(32) NOT NULL , `reporter_steamid` VARCHAR(32) NOT NULL , `reporter_ip` VARBINARY(16) NOT NULL, `reason` TEXT NOT NULL , `handler_name` VARCHAR(32) NULL DEFAULT NULL , `handler_steamid` VARCHAR(32) NULL DEFAULT NULL , `handled` TINYINT(1) NOT NULL DEFAULT '0' , `insignia` VARCHAR(32) NULL DEFAULT NULL , `time_reported` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , `time_handled` TIMESTAMP NULL DEFAULT NULL , `time_closed` TIMESTAMP NULL DEFAULT NULL , `closed` TINYINT(1) NOT NULL DEFAULT '0' , PRIMARY KEY (`id`), INDEX (`breed`), INDEX (`handler_steamid`), INDEX (`handled`), INDEX (`target_steamid`), INDEX (`target_ip`), INDEX (`reporter_steamid`), INDEX (`reporter_ip`), INDEX (`insignia`), INDEX (`closed`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	char RepliesCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Ticketron_Replies` ( `id` INT NOT NULL AUTO_INCREMENT , `ticket_id` INT NOT NULL , `replier_name` VARCHAR(32) NOT NULL , `replier_steamid` VARCHAR(32) NOT NULL , `message` LONGTEXT NOT NULL , `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , PRIMARY KEY (`id`), INDEX (`ticket_id`), INDEX (`replier_steamid`), FOREIGN KEY (`ticket_id`) REFERENCES `Ticketron_Tickets` (`id` )) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	char NotificationsCreateSQL[] = "CREATE TABLE `Ticketron_Notifications` ( `id` INT NOT NULL AUTO_INCREMENT , `ticket_id` INT NOT NULL , `message` TEXT NOT NULL , `internal_handled` TINYINT(1) NOT NULL DEFAULT '0' , `external_handled` TINYINT(1) NOT NULL DEFAULT '0' , `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , PRIMARY KEY (`id`), INDEX (`ticket_id`), INDEX (`internal_handled`), INDEX (`external_handled`), FOREIGN KEY (`ticket_id`) REFERENCES `Ticketron_Tickets` (`id` )) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	
	SQL_SetCharset(hDB, "utf8mb4");
	
	if(!SQL_FastQuery(hDB, TicketsCreateSQL))
		return APLRes_Failure;
		
	if(!SQL_FastQuery(hDB, RepliesCreateSQL))
		return APLRes_Failure;
		
	if(!SQL_FastQuery(hDB, NotificationsCreateSQL))
		return APLRes_Failure;
	
	RegPluginLibrary("Ticketron");
	//TODO: Create Native
	//CreateNative("Ticketron_ReplyMessage", NativeLogPlugin);
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_ticketron_version", PLUGIN_VERSION, "Ticketron Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	cPollingRate = CreateConVar("sm_ticketron_rate", "10", "Ticketron Notification Polling Rate", FCVAR_NONE, true, 1.0, false);
	cBreed = CreateConVar("sm_ticketron_breed", "global", "Ticketron External Breed Identifier", FCVAR_NONE);
	
	AutoExecConfig(true, "ticketron");
	
	RegAdminCmd("sm_ticket", CreateTicketCmd, 0, "Creates ticket");
	RegAdminCmd("sm_handle", HandleTicketCmd, ADMFLAG_GENERIC, "Handles ticket");
	
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
	
	//TODO: Implement using IN clause
	g_hPollingTimer = CreateTimer(g_fPollingRate, PollingTimer, _, TIMER_REPEAT);
}

public Action CreateTicketCmd(int client, int args)
{
	char buffer[2048];
	
	GetCmdArg(1, buffer, sizeof buffer);
	
	int response = CreateTicket(client, buffer);
	
	if (response == -1)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "");
		CReplyToCommand(client, "{lightseagreen}Error when creating the ticket. Please try again later.");
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "");
	} else
	{
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "");
		CReplyToCommand(client, "{lightseagreen}Your Ticket ID: {chartreuse}%i{grey}.", response);
		CReplyToCommand(client, "{lightseagreen}View Your Ticket Using {chartreuse}!ViewTicket #{grey}.");
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "");
	}
	
	return Plugin_Handled;
}

public Action HandleTicketCmd(int client, int args)
{
	char buffer[16];
	int ticket;
	
	GetCmdArg(1, buffer, sizeof buffer);
	ticket = StringToInt(buffer);
	
	bool response = HandleTicket(client, ticket);
	
	if (!response)
	{
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "");
		CReplyToCommand(client, "{lightseagreen}Error when assigning the ticket. Please try again later.");
		CReplyToCommand(client, "%s", Divider_Failure);
		CReplyToCommand(client, "");
	} else
	{
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "");
		CReplyToCommand(client, "{lightseagreen}Now Handling Ticket ID: {chartreuse}%i{grey}.", response);
		CReplyToCommand(client, "{lightseagreen}Unhandle The Ticket Using {chartreuse}!UnhandleTicket #{grey}.");
		CReplyToCommand(client, "{lightseagreen}View The Ticket Using {chartreuse}!ViewTicket #{grey}.");
		CReplyToCommand(client, "%s", Divider_Success);
		CReplyToCommand(client, "");
	}
	
	return Plugin_Handled;

}

int CreateTicket(int client, const char[] reason)
{
	DBStatement Insert;
	
	char error[255], Client_Name[MAX_NAME_LENGTH], Client_SteamID64[32], Client_IP[45];
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	GetClientIP(client, Client_IP, sizeof Client_IP);
	
	
	Insert = SQL_PrepareQuery(hDB, "INSERT INTO `Ticketron_Tickets` (`host`, `hostname`, `breed`, `reporter_name`, `reporter_steamid`, `reporter_ip`, `reason`) VALUES (?, ?, ?, ?, ?, ?, ?)", error, sizeof error);
	
	Insert.BindString(0, g_cIP, false);
	Insert.BindString(1, g_cHostname, false);
	Insert.BindString(2, g_cBreed, false);
	Insert.BindString(3, Client_Name, false);
	Insert.BindString(4, Client_SteamID64, false);
	Insert.BindString(5, Client_IP, false);
	Insert.BindString(6, reason, false);
	
	if (!SQL_Execute(Insert))
		return -1;
	else
		return SQL_GetInsertId(Insert);
}

bool HandleTicket(int client, int ticket)
{
	DBStatement Update, Select;
	
	char error[255], Client_Name[MAX_NAME_LENGTH], Client_SteamID64[32];
	
	Select = SQL_PrepareQuery(hDB, "SELECT * FROM `Ticketron_Tickets` WHERE `id` = ?", error, sizeof error);
	Select.BindInt(0, ticket, false);
	
	if(!SQL_Execute(Select))
		return false;
	else
	{
		SQL_FetchRow(Select);
		
		int handled = SQL_FetchInt(Select, 13);
		
		if (handled == 1)
			return false;
	}
	
	GetClientName(client, Client_Name, sizeof Client_Name);
	GetClientAuthId(client, AuthId_SteamID64, Client_SteamID64, sizeof Client_SteamID64);
	
	Update = SQL_PrepareQuery(hDB, "UPDATE `Ticketron_Tickets` SET `handler_name` = ?, `handler_steamid` = ?, `handled` = 1 WHERE `id` = ?", error, sizeof error);
	
	Update.BindString(0, Client_Name, false);
	Update.BindString(1, Client_SteamID64, false);
	Update.BindInt(2, ticket, false);
	
	return SQL_Execute(Update);
}

public Action PollingTimer(Handle timer)
{

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
}

public int SteamWorks_SteamServersConnected()
{
	int octets[4];
	SteamWorks_GetPublicIP(octets);
	Format(g_cIP, sizeof(g_cIP), "%d.%d.%d.%d:%d", octets[0], octets[1], octets[2], octets[3], GetConVarInt(FindConVar("hostport")));
}