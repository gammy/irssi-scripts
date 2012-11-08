#!/usr/bin/perl
# nofishow. A script which attempts to address the issue of not knowing who
# is using FiSH encryption on IRC.
#
# It simply looks for PRIVMSG messages -not- beginning with 
#   "+OK <arbitrary data>"
# in a specified list of channels/nicks and prepends a message to it.
#
# Explained:
# While FiSH can independently mark *encrypted* messages, it can't mark
# *unencrypted* ones. Also, it will do so on all channels unless they are
# in a static whitelist in blow.ini. This script only marks *unencrypted*
# messages that originate from a source supplied in nofish_check_sender.
#
# Settings:
#
# /set nofish_check_senders=<comma separated list of channels/nicks>
# /set nofish_hilight_mark=<string to prepend to non-encrypted messages>
#
# 
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
use warnings;
use strict;

use Irssi;
use Irssi::Irc;

use vars qw($VERSION %IRSSI);

## Global
our $VERSION = "0.4.1";

my %IRSSI = (
        authors => 'gammy',
        contact => 'gamAPPLEmy at pulappleia dot nu without fruits',
        name    => "noFiSH encryption hilighter",
        license => 'GPLv2',
        url     => 'http://www.pulia.nu',
);

our (@watch_list, $hilight);

sub help{
	Irssi::active_win->print("noFiSH v$VERSION");
	Irssi::active_win->print("SETTINGS");
	Irssi::active_win->print("nofish_check_senders");
	Irssi::active_win->print("  $_") for @watch_list;
	Irssi::active_win->print("nofish_hilight_mark");
	Irssi::active_win->print("  $hilight");
	Irssi::active_win->print("HELP");
	Irssi::active_win->print("/set nofish_check_senders #foo,#bar,bob");
	Irssi::active_win->print("/set nofish_hilight_mark foo");
	Irssi::active_win->print("HELP");
	Irssi::active_win->print("VERY IMPORTANT: Please remember that '$hilight' is only prepended to PRIVMSG data on channels and nicknames that are in your nofish_check_senders list(printed above)!");
}

sub load_settings{
    @watch_list = split(',', Irssi::settings_get_str('nofish_check_senders'));
    $hilight = Irssi::settings_get_str('nofish_hilight_mark');
    if($watch_list[0] eq 'PLEASE_SET_ME'){
        help();
    }
}

sub get_parts{
    my $data = shift;

    if($data=~/^:(.+?)\!.+?@.+?PRIVMSG\s(.+?)\s:(.+)$/){
        my ($nick, $recipient, $message) = ($1, $2, $3);
        if(index($recipient, '#') > -1){
            return ($recipient, $message);
        }else{
            return ($nick, $message);
        }
    }
}

sub handle_server_incoming{
    my ($server, $data) = @_;

    my ($sender, $message) = get_parts($data);

    if(defined($sender) && defined($message) && index($message, chr(1)) == -1){

        # Should we check it?
        my $check = 0;
        foreach my $entry (@watch_list){
            if("$sender" eq "$entry"){
                $check = 1;
                last;
            }
        }

        # Apparently.
        if($check && substr($message, 0, 4) ne '+OK ') { # Probably not encrypted
        
            my $offset = index($data, $message);
            substr($data, $offset, length($message), "$hilight $message");
        }

    }
        
    Irssi::signal_continue($server, $data);
}

    
## Defaults
Irssi::settings_add_str('misc', 'nofish_hilight_mark', chr(3)."4[u]".chr(3));
Irssi::settings_add_str('misc', 'nofish_check_senders', 'PLEASE_SET_ME');

## Load user settings
load_settings();

## Bindings
Irssi::command_bind('nofish', 'help');

## Signals
Irssi::signal_add_first('server incoming', \&handle_server_incoming);
Irssi::signal_add('setup changed', 'load_settings');
