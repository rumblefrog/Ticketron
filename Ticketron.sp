#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "0.01"

#include <sourcemod>

#pragma newdecls required


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
	char TicketsCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Ticketron_Tickets` ( `id` INT NOT NULL AUTO_INCREMENT , `host` VARBINARY(16) NOT NULL , `hostname` VARCHAR(64) NOT NULL , `breed` VARCHAR(32) NOT NULL , `target_name` VARCHAR(32) NOT NULL , `target_steamid` VARCHAR(32) NOT NULL , `target_ip` VARBINARY(16) NOT NULL, `reporter_name` VARCHAR(32) NOT NULL , `reporter_steamid` VARCHAR(32) NOT NULL , `reporter_ip` VARBINARY(16) NOT NULL, `reason` TEXT NOT NULL , `handler_name` VARCHAR(32) NULL DEFAULT NULL , `handler_steamid` VARCHAR(32) NULL DEFAULT NULL , `handled` TINYINT(1) NOT NULL DEFAULT '0' , `insignia` VARCHAR(32) NULL DEFAULT NULL , `time_reported` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , `time_handled` TIMESTAMP NULL DEFAULT NULL , `time_closed` TIMESTAMP NULL DEFAULT NULL , `closed` TINYINT(1) NOT NULL DEFAULT '0' , PRIMARY KEY (`id`), INDEX (`breed`), INDEX (`handler_steamid`), INDEX (`handled`), INDEX (`target_steamid`), INDEX (`target_ip`), INDEX (`reporter_steamid`), INDEX (`reporter_ip`), INDEX (`insignia`), INDEX (`closed`)) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	char RepliesCreateSQL[] = "CREATE TABLE IF NOT EXISTS `Ticketron_Replies` ( `id` INT NOT NULL AUTO_INCREMENT , `ticket_id` INT NOT NULL , `replier_name` VARCHAR(32) NOT NULL , `replier_steamid` VARCHAR(32) NOT NULL , `message` LONGTEXT NOT NULL , `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , PRIMARY KEY (`id`), INDEX (`ticket_id`), INDEX (`replier_steamid`), FOREIGN KEY (`ticket_id`) REFERENCES `Ticketron_Tickets` (`id` )) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	char NotificationsCreateSQL[] = "CREATE TABLE `Ticketron_Notifications` ( `id` INT NOT NULL AUTO_INCREMENT , `ticket_id` INT NOT NULL , `message` TEXT NOT NULL , `internal_handled` TINYINT(1) NOT NULL DEFAULT '0' , `external_handled` TINYINT(1) NOT NULL DEFAULT '0' , `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP , PRIMARY KEY (`id`), INDEX (`ticket_id`), INDEX (`internal_handled`), INDEX (`external_handled`), FOREIGN KEY (`ticket_id`) REFERENCES `Ticketron_Tickets` (`id` )) ENGINE = InnoDB CHARSET=utf8mb4 COLLATE utf8mb4_general_ci";
	
	SQL_SetCharset(hDB, "utf8mb4");
	
	SQL_TQuery(hDB, OnTableCreate, ChatLogSQL);
	SQL_TQuery(hDB, OnTableCreate, PluginLogSQL);
	
	if(!SQL_FastQuery(hHD, TicketsCreateSQL))
		return APLRes_Failure;
		
	if(!SQL_FastQuery(hHD, RepliesCreateSQL))
		return APLRes_Failure;
		
	if(!SQL_FastQuery(hHD, NotificationsCreateSQL))
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
}
