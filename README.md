# Ticketron [![Build Status](https://travis-ci.com/RumbleFrog/Ticketron.svg?token=fzDwLamkGxdhu8zz3Bvs&branch=master)](https://travis-ci.com/RumbleFrog/Ticketron)
A fully-featured ticket support system

# Convars

**sm_ticketron_rate** Ticketron rate at which it fetches for new notifcations [Default: **10.0**] (Min: 1.0)

**sm_ticketron_breed** Ticketron external breed identifier [Default: **global**]

**sm_ticketron_groupid32** Steam Group 32-Bit ID (Used for ticket priority) [Default: **0

# Commands

- !TicketQueue Page# (Returns a list of unhandled & open tickets)
- !Handle #Ticket (Handles or self-assign a ticket)
- !Unhandle #Ticket (Unhandle or unself-assign a ticket)
- !CloseTicket #Ticket (Closes a ticket that you handle)
- !ReplyTicket #Ticket Message (Replies to a ticket that you handle)
- !TagPlayer #Ticket (Tag a target as part of of the ticket. Ex: A Hacker/Offender)
- !MyTickets Page# (Returns a list of tickets you created)
- !ViewTicket #Ticket (View details about a specific ticket)
- !Ticket Message (Creates a ticket with message)
- !MyQueue Page# (Returns a list of tickets being handled by you & still open)

# Installation

1. Extract **Ticketron.smx** to **/addons/sourcemod/plugins**
2. Create **ticketron** entry in your database.cfg

# Prerequisites

- [EventLogs](https://github.com/RumbleFrog/EventLogs/releases)
- [SteamWorks Extension](https://users.alliedmods.net/~kyles/builds/SteamWorks/)

# Native

- [Include File](https://github.com/RumbleFrog/Ticketron/blob/master/include/Ticketron.inc)

# Download 

Download the latest version from the [release](https://github.com/RumbleFrog/Ticketron/releases) page

# License

MIT
