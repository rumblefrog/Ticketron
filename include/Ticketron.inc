#if defined _Ticketron_included
 #endinput
#endif
#define _Ticketron_included


/**
* Add a notification to database
* 
* @param ticket			Ticket ID
* @param receiver       False for reporter, True for handler
* @param format			Format
* @param ...			Any additional formating data
* @return				Last inserted ID, returns -1 if none
*/
native int Ticketron_AddNotification(int ticket, bool receiver, const char[] format, any ...);


public SharedPlugin __pl_Ticketron =
{
	name = "Ticketron",
	file = "Ticketron.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};


#if !defined REQUIRE_PLUGIN
public __pl_Ticketron_SetNTVOptional()
{
	MarkNativeAsOptional("Ticketron_AddNotification");
}
#endif