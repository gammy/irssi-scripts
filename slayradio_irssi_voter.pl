#!/usr/bin/perl
# Slay information and voting script for irssi
# Requires LWP plus write access to COOKIE_FILE(RTFS)
#
# Last updated: Thu Jun 24 16:36:54 BST 2010
#
# If you don't have LWP, get it from cpan with something like
#
# 'force install LWP'
#
# This script utilises Slaygons web voting system on slayradio.org.
#
# Author: gammy
# TODO (wishlist?): 
# - forking code (background the task)
# 
# NOTES:
# - The data coming from slayradio.org is encoded as iso-8859-1,
#   but since I don't know which locale you're using on /your/
#   side, I can't [without making assumptions] recode it. 
#
#0.8.1:
# - Added support for backwards-compatible multi-word responses with a 
#   default delimiter set to "_" (RESPONSE_DELIMITER).
#0.8:
# - Added response check for 'deprecated'
# - Rewrote most of the script.
#   Thanks Alexander Monakov for informing me that it needed updates!
# - Added environment variables (slay_http_timeout, slay_identifier)

use warnings;
use strict;
#use encoding 'iso-8859-1';
use POSIX;
use LWP::UserAgent;
use Irssi;
use Irssi::Irc;
use Irssi qw(command_bind signal_add signal_add_first timeout_add timeout_add_once timeout_remove);

use constant {
	DEBUG			=> 0,
	RESPONSE_DELIMITER 	=> '_',
	VERSION			=> '0.8.1',
	COOKIE_FILE		=> $ENV{HOME} . '/.slaycookie',
	BASE_ADDRESS		=> 'http://www.slayradio.org',
};

# XXX only defaults. Change in irssi with /set slay_
my %slay_env = (
	"http_timeout"       => "10",
	"identifier"         => "slay"
	);

my $UA;

use vars qw($VERSION %IRSSI);
        $VERSION = VERSION;
        %IRSSI = (
                authors     => "gammy",
                contact     => "gabananammy at papplean dot org, without fruits",
                name        => "SLAY Radio information and voting script",
                description => "An information output and voting script for SLAY Radio",
                license     => "GPLv2",
                url         => "http://www.pulia.nu",
                source      => "http://www.pulia.nu/code/junk/",
        );

sub debug_print{
        stat_print(@_) if DEBUG;
}

sub stat_print{
        Irssi::active_win->print(@_);
}

sub load_lwp {

	undef $UA;

	if(! -f COOKIE_FILE){
		# Touch.
		open FILE, '>', COOKIE_FILE;
		close FILE;
	}

	$UA = LWP::UserAgent->new(
		agent => "SLAY Radio information and voting script v" . VERSION,
		timeout => $slay_env{timeout},
		'cookie_jar' => {
			file            => COOKIE_FILE,
			autosave        => 1
		}
	);
}

sub get_settings {

	for my $key (keys(%slay_env)) {
		$slay_env{$key} = Irssi::settings_get_str('slay_' . $key);
		debug_print("LOAD slay_$key = $slay_env{$key}");
	}

	load_lwp();

	debug_print("Loaded settings.");
}

sub get_page {

    my $req = HTTP::Request->new(GET => @_);
    my $res = $UA->request($req);

    unless($res->is_success) {
	    stat_print("Error: Request for '@_' failed:" . $res->status_line);
	    return;
    }

    return $res->content;

}

sub display_help {

	my $call = $slay_env{identifier};

	stat_print("SLAY Radio information and voting script v" . VERSION);
	stat_print("/$call      - Get and print SLAY Radio information");
	stat_print("/$call 1-4  - Where 1 is bad and 4 is good");

}

sub slayradio{

	my $arg = shift;
	my $page;


	if("$arg" eq "help"){
		display_help();
		return;
	}

	my @response = split "\n", get_page(BASE_ADDRESS . '/wp.php');
	if(@response < 7) { # Something went wrong.
		return;
	}
	chop @response;
	my ($listeners, $rating, $votes, $type, $requester, $tune, $tuneid) = @response;

	if($arg eq '') {

		my $ratestring = "None.";
		my $requeststring = "None.";

		stat_print("$listeners listeners ($type stream)");
		debug_print("[tuneid = $tuneid]");
		stat_print("Tune     : $tune");

		if($type ne "live") {
			$ratestring = "$rating% ($votes votes)" unless "$votes" eq "0";
			$requeststring = "$requester" if "$requester" ne "";
			stat_print("Rating   : $ratestring");
			stat_print("Requester: $requeststring");
	   	}

		return;
	}

	if(! isdigit $arg || $arg < 1 || $arg > 4) {
		display_help();
		return;
	}

	if($type eq "live"){
	    stat_print("You can't vote when show is live.");
	    return;
	}
	
				    
	stat_print("Voting $arg for $tune...");

	# Init cookies
	$page = get_page(BASE_ADDRESS . "/wp_init.php");
	# Actual request
	#$page = get_page(BASE_ADDRESS . "/playing_vote_new.php/$tuneid/$arg");
	$page = get_page(BASE_ADDRESS . "/wp_vote.php/$tuneid/$arg");
	debug_print("PAGE: " . $page);

	my @codes = split RESPONSE_DELIMITER, lc $page;
	my $code = shift @codes;

	if($code eq "registered"){

		if(@codes > 0) { # New response

			my $voted = shift @codes;

			if(! isdigit $voted) {
				stat_print("Unexpected: '$voted'");
				return;
			}elsif($voted != $arg) {
				stat_print("Voted $arg but server thinks we voted $voted.");
				return;
			}

		}

		stat_print("ok.");

	}else{
		if(@codes > 0) { # XXX
			stat_print(@codes . " unimplemented responses: @codes");
		}

		if($code eq "onevote"){
			stat_print("You have already voted.");
		}elsif($code eq "cookies"){
			stat_print("Cookies are required.");
		}elsif($code eq "live"){ # Shouldn't happen
			print "Can't vote when show is live.\n";
		}elsif($code eq "notplaying"){
			stat_print("Vote id is not currently playing.");
		}elsif($code eq "unknown"){
			stat_print("Unknown error; contact Slaygon!");
		}elsif($code eq "deprecated"){ # New
			stat_print("This method of voting has been deprecated. Please contact Slaygon.");
		}else{
			stat_print("Unknown response! Dump:");
			stat_print($page);
		}
	}

}    

# Set default settings (is only done if they do not exist)
for my $key (keys(%slay_env)) {
	Irssi::settings_add_str('misc', "slay_$key", $slay_env{$key});
}
get_settings();

Irssi::signal_add('setup changed', 'get_settings');
Irssi::command_bind($slay_env{identifier}, 'slayradio');

stat_print("Loaded SLAY Radio information and voting script v" .
	   VERSION);
