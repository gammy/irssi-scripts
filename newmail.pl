# Mail printer/counter loosely based on "Mail counter statusbar item" by 
# Timo Sirainen.
#
# Many thanks to phyber.
#
# To add a basic 'mail' statusbar, do
# /statusbar window ADD -alignment right mail
#
# in irssi.
#
# Format string arguments:
# %F = From
# %U = From (Without @domain)
# %S = Subject
# %C = Mail count
# %H = Size of mbox in Mebibytes 
#
# TODO:
# - Try to figure out why the item keeps clearing in weird ways.
# - A proper mbox parser should probably be used to read subjects in case
#   of the need for, among other things, iso conversion.
#   This is also useful for parsing out the soft name in the secondary
#   from-header and such. And time.. and so on and so on :)
#
# Author: gammy
#
use strict;
use Irssi;
use Irssi::TextUI;
use vars qw($VERSION %IRSSI);

$VERSION = "0.8";

%IRSSI = (
	authors     => "gammy",
	contact     => "gambananamy at pepeachan dot org(without fruits)",
	name        => "Check spool for new mail script",
	description => "",
	license     => "GPLv2",
	url         => "http://www.pulia.nu",
	source      => "http://www.pulia.nu/code/junk/",
);

my ($MailItem, $MailSizeOnly) = (0, 0); # Holds mail item after first read

my $debug = 1;

my $Timer = -1;
my $Noted = 0;
my $MailCount = 0;
my $OldMailCount = 0;

my $OldTextHack = ""; # Weird hack :(

my @InfoFormat = ('[%C]: %F: %S', '');

my ($FromLength, $SubjectLength) = (15, 10);
	
my %LatestMail = (
	'subject' => 'empty',
	'from'    => 'empty'
);

my %Mail = (
	'update'     => 30,
	'lastupdate' => 30,
	'current'    => 0,
	'last'       => 0
);
	
$Mail{'old_size'} = 0;

my $Spool;

sub writeItem{
	my ($Item, $SizeOnly, $Message) = @_;

	# Fill old buffer length with spaces. Odd hack :(
	$Item->default_handler($SizeOnly, $OldTextHack, undef, 1);

	dStatPrint("OldBuf/NewText:");
	dStatPrint("X" x length($OldTextHack));
	dStatPrint($Message);

	# Fill with new data
	$Item->default_handler($SizeOnly, $Message, undef, 1);
	
	$OldTextHack = (" "x length($Message));
}

sub dStatPrint{
	statPrint(@_) if $debug;
}

sub statPrint{
	Irssi::active_win->print(@_);
}

# Gets mailcount and last mail information
sub collectMailInfo{
	my $Offset = shift;

	$LatestMail{'from'} = "";
	$LatestMail{'subject'} = "";

	dStatPrint("collectMailInfo($Offset);");

	unless(open(MAILHANDLE, $Spool)){
		statPrint("Could not open \"$Spool\"!");
		return;
	}

	stopTimer();

	if($Offset){
		$MailCount = $OldMailCount;
		seek(MAILHANDLE, $Offset, 0);
	}else{
		$MailCount = 0;
	}

	while (<MAILHANDLE>) {
		if(/^From (.*?)\s/){
			$LatestMail{'from'} = $1;
			$MailCount++;
		}
		if(/^Subject: (.*)/i){
			if($1=~m/.*FOLDER INTERNAL DATA/){
				$MailCount--;
			}else{
				$LatestMail{'subject'} = $1;

			}
		}
	}
	close(MAILHANDLE);

	$OldMailCount = $MailCount;

	resetTimer();
}

sub mboxChanged{
	my @Stat = stat($Spool);
	$Mail{'size'}  = $Stat[7];
	$Mail{'mtime'} = $Stat[9];

	return 0 if $Mail{'size'} == $Mail{'last_size'} && $Mail{'mtime'} == $Mail{'last_mtime'};

	# Check if mbox got truncated.
	# This is probably because someone deleted
	# an e-mail. 
	if($Mail{'size'} < $Mail{'last_size'}){
		# It was. We have to rescan the mbox.
		dStatPrint("$Spool truncated.");
		$Mail{'old_size'} = $Mail{'last_size'} = 0;
		return 1;
	}

	$Mail{'old_size'} = $Mail{'last_size'};
	$Mail{'last_size'}  = $Mail{'size'};
	$Mail{'last_mtime'} = $Mail{'mtime'};

	return 1;
}

sub truncateString{
	my ($Input, $MaxLength) = @_;
	my $Length = length($Input);
	my $NewLength;
	my $Append = '';

	if($MaxLength == 0){
		$NewLength = $Length;
	}elsif($MaxLength > $Length){
		$NewLength = $Length;
	}else{
		$NewLength = $MaxLength;
		$Append = '..';
	}

	return substr($Input, 0, $NewLength) . $Append;
}

sub formatOutput{
	my $OutputFormat = shift;
	my $Output = $OutputFormat;


	my $From = $LatestMail{'from'};
	my $User = substr($From, 0, index($From, '@'));
	my $Subject = $LatestMail{'subject'};
	my $MboxSize = int($Mail{'size'} / 1024 / 1024);
	
	dStatPrint("formatOutput: from=\"$From\", subject=\"$Subject\"");

	# Truncate output strings if needed
	$User = truncateString($User, $FromLength);
	$From = truncateString($From, $FromLength);
	$Subject = truncateString($Subject, $SubjectLength);

	# %F = From
	# %U = From (Without @domain)
	# %S = Subject
	# %C = Mail count
	# %H = Size of mbox in Mebibytes 
	
	$OutputFormat =~s/%F/$From/g;
	$OutputFormat =~s/%U/$User/g;
	$OutputFormat =~s/%S/$Subject/g;
	$OutputFormat =~s/%C/$MailCount/g;
	$OutputFormat =~s/%H/$MboxSize/g;

	return $OutputFormat;
}

sub checkMail{
	($MailItem, $MailSizeOnly) = @_;
	
	#dStatPrint("checkMail();");

	my $StatusChange = mboxChanged();

	if($StatusChange){
		dStatPrint("$Spool has changed.");
		collectMailInfo($Mail{'old_size'});
		$Noted = 0;
	}
	
	# Update item
	writeItem($MailItem, $MailSizeOnly, formatOutput($InfoFormat[$Noted]));
}

sub stopTimer{
	Irssi::timeout_remove($Timer) if $Timer != -1;
}

sub resetTimer{
	#dStatPrint("Reset timer $Timer.");
	stopTimer();
	$Timer = Irssi::timeout_add(($Mail{'update'} * 1000), 'updateItem', undef);
}

sub updateItem{
	Irssi::statusbar_items_redraw('mail');
	#dStatPrint("Updated Status (redrew).");
}

sub loadSettings{

	$Spool         = Irssi::settings_get_str('mail_spool');
	$InfoFormat[0] = Irssi::settings_get_str('mail_info_format');
	$InfoFormat[1] = Irssi::settings_get_str('mail_info_format_noted');
	$FromLength    = Irssi::settings_get_int('mbox_max_sender_length');
	$SubjectLength = Irssi::settings_get_int('mbox_max_subject_length');
	$Mail{'update'} = Irssi::settings_get_int('mbox_refresh_time');

	return if $Mail{'update'} == $Mail{'lastupdate'};

	$Mail{'lastupdate'} = $Mail{'update'};

	resetTimer();
	dStatPrint("Loaded settings and reset timer.");
}

sub handleArgs{
	my $Argument = lc($_[0]);
	my $EscapedInfoFormat = $InfoFormat[0];
	my $EscapedInfoNotedFormat = $InfoFormat[1];
	$EscapedInfoFormat=~s/%/%%/g;
	$EscapedInfoNotedFormat=~s/%/%%/g;

	if("$Argument" eq "" || "$Argument" eq "help"){
		statPrint("");
		statPrint("IRSSI environment variables:");
		statPrint("  mail_spool              = $Spool");
		statPrint("  mail_info_format        = $EscapedInfoFormat");
		statPrint("  mail_info_format_noted  = $EscapedInfoNotedFormat");
		statPrint("  mbox_refresh_time       = $Mail{'update'}");
		statPrint("  mbox_max_sender_length  = $FromLength");
		statPrint("  mbox_max_subject_length = $SubjectLength");
		statPrint("");
		statPrint("Commands:");
		statPrint("  /mbox noted    - Clear mbox statusbar");
		statPrint("  /mbox update   - Force update");
		statPrint("  /mbox help     - This text");
	}elsif("$Argument" eq "noted"){ # FIXME ugly
		$Noted = 1;
		writeItem($MailItem, $MailSizeOnly, formatOutput($InfoFormat[$Noted]));
	}elsif("$Argument" eq "update"){
		checkMail($MailItem, $MailSizeOnly);
	}else{
		statPrint("\"$Argument\" not understood.");
	}
}
	
# Initial defaults
Irssi::settings_add_str('misc', 'mail_spool', $ENV{'MAIL'});
Irssi::settings_add_str('misc', 'mail_info_format', $InfoFormat[0]);
Irssi::settings_add_str('misc', 'mail_info_format_noted', $InfoFormat[1]);
Irssi::settings_add_int('misc', 'mbox_refresh_time', $Mail{'update'});
Irssi::settings_add_int('misc', 'mbox_max_sender_length', $FromLength);
Irssi::settings_add_int('misc', 'mbox_max_subject_length', $SubjectLength);

# Load settings and start timer
loadSettings();

# Bindings and signals
Irssi::command_bind("mbox", 'handleArgs');
Irssi::signal_add('setup changed', 'loadSettings');

mboxChanged();
collectMailInfo();

# New statusbar
Irssi::statusbar_item_register('mail', '{sb $0}', 'checkMail');

statPrint("Mailcheck v$VERSION.");
statPrint("Please note several options in misc-settings.");
updateItem();
