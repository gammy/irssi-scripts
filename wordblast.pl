#!/usr/bin/perl -w
#
# Main TODO:
#
# Will require SQLite and the modules DBI, Class::DBI::SQLite and its
# dependencies. Install in cpan with 
# 'force install DBI' and 
# 'force install Class::DBI::SQLite'
#
use strict;
use DBI;
use Irssi;
use Irssi::Irc;
use Irssi qw(command_bind signal_add signal_add_first timeout_add timeout_add_once timeout_remove);
my $dbh = DBI->connect( "dbi:SQLite:$ENV{'HOME'}/.wordblast/wordblast.db" ) || die "Cannot connect: $DBI::errstr";
#my $dbh = DBI->connect( "dbi:SQLite:$ENV{'HOME'}/.irssi/scripts/wordblast.db" ) || die "Cannot connect: $DBI::errstr";
use vars qw($VERSION %IRSSI);
$VERSION = "0.3.6";
%IRSSI = (
    authors     => "gammy",
    contact     => "gam killer at pean dot org",
    name        => "wordblast",
    description => "Word game",
    license     => "GPLv2",
    url         => "http://www.pulia.nu",
    source      => "http://www.pulia.nu/code/junk/",
);

## Core
my $network	= "EFnet";
my $channel	= "#wordblast";
my $gamecall	= "!play";
my $gamecall2	= "!join";
my $delay	= 15 * 1000;
my $start_delay;
my @data;
my $gameId	= -1;

my @cheers = (
    "Nice one", "Good answer", "Excellent", "Perfect", "Grandiose",
    "Splendid", "Magnificent", "Outstanding", "Unstoppable",
    "INVINCIBLE", "Awesome", "Astounding", "Fabulous",  "Prodigious",
    "Phenomenal", "Incredible","Marvelous", "Miraculous", "Unbelievable", 
    "Wonderful", "Suitable", "Favourable", "Agreeable", "Pleasurable",
    "Pleasant", "Genial", "Appropriate", "Acceptable", "Befitting",
    "Classy", "Proper", "Expeditious"
);
my %scores;
my @players;
my %usedwords;
my $words;
my $timer;
my $playing;
my $currentplayer;
my $playerindex;
my $currentword;
my $winningword;
my $letter;
my %usedletters;
my $globalServer;
my $jumblecount = 10;
my $final = 0;
my $gameStart;
my $gameEnd;

## Wordlist
my $DB = "$ENV{'HOME'}/.wordblast/word_list.lst";
#my $DB = "$ENV{'HOME'}/.irssi/scripts/word_list.lst";
my @keys = ("a","b","c","d","e","f","g","h","i","j","k","l","m",
            "n","o","p","q","r","s","t","u","v", "w", "x","y","z");
my @rawlist;
our %wordlist;
my $found = 0;


## Subroutines
sub createAllTables{
    $dbh->do("CREATE TABLE IF NOT EXISTS tblGames (gameId INTEGER PRIMARY KEY AUTOINCREMENT, begDate INTEGER, endDate INTEGER, totalScore INTEGER, letter CHAR(1), winner VARCHAR(18), word VARCHAR(255), nicks TEXT)");
    $dbh->do("CREATE TABLE IF NOT EXISTS tblGamePlayers (gameId INTEGER, nick VARCHAR(18))");
    $dbh->do("CREATE TABLE IF NOT EXISTS tblPlayers (nick VARCHAR(18) PRIMARY KEY UNIQUE, wonGames INTEGER, score INTEGER)");
}

sub removeAllTables{
    $dbh->do("DROP TABLE tblGames");
    $dbh->do("DROP TABLE tblGamePlayers");
    $dbh->do("DROP TABLE tblPlayers");
}

sub addGame{
    my $winner = shift;
    my $nicks = "@_";
    my $totalscore = 0;
    foreach(values(%scores)){
	$totalscore += $_;
    }
    $dbh->do("INSERT INTO tblGames (begDate, endDate, totalScore, letter, winner, word, nicks) VALUES ($gameStart, $gameEnd, $totalscore, '$letter', '$winner', '$winningword', '$nicks')");
    my $res = $dbh->selectcol_arrayref("SELECT last_insert_rowid()");
    $gameId = $res->[0];
    updatePlayers($winner);
}

sub updatePlayers{
    while(my ($player, $score) = each(%scores)){
	if("$_[0]" eq "$player"){
	    updatePlayer($player, $score, 1);
	}else{
	    updatePlayer($player, $score, 0);
	}
    }
}

sub updatePlayer{
    my ($nick, $score, $winner) = @_;
    my $totalscore = $score;
    my @list = $dbh->selectrow_array("SELECT wonGames, score FROM tblPlayers WHERE nick = '$nick'");

    if(@list != 0){
        $winner += $list[0];
        $totalscore += $list[1];
    }
    $dbh->do("INSERT OR REPLACE INTO tblPlayers (nick, wonGames, score) VALUES ('$nick', $winner, $totalscore)");
    $dbh->do("INSERT INTO tblGamePlayers (gameId, nick) VALUES ($gameId, '$nick')");
}

sub newLetter{
    $letter = chr(int(rand(26)+97));
    %usedletters = () if keys(%usedletters) == $jumblecount;
    newLetter() if defined $usedletters{$letter};
    $usedletters{$letter} = 1;
}
		
sub iprint{
    Irssi::active_win->print("@_");
}

sub loadlist{
    iprint("Please wait, loading ($DB)..");

    open(FILE, "<$DB") or die "Can't load \"$DB\"!";
    @rawlist = <FILE>;
    close(FILE);
    chomp(@rawlist);

    $words = @rawlist;
    iprint("ok. loaded $words words.");
    iprint("Categorising by letter.");
    
    # This could be done MUCH faster.
    foreach my $key (@keys){
	foreach my $word (@rawlist){
	    if(substr($word, 0, 1) eq "$key"){
		push(@{$wordlist{$key}}, $word);
		# Reserved for optimisations
	    }
	}
	iprint("$key..." . @{$wordlist{$key}} . " words.");
    }
    undef(@rawlist);

    iprint("Ready for challenges.");
}

sub wordExists{
    my $word = $_[0];
    my $key = substr($word, 0, 1);
    return 0 if ord($key) != ord($letter) or ord($key) <  97 or ord($key) > 122;
    for(my $i = 0; $i < @{$wordlist{$key}}; $i++){
	return 1 if $wordlist{$key}[$i] eq "$word";
    }
    return 0;						    
}

sub serverpost{
    my ($server, $msg, $target) = @_;
    $server->command('msg '.$target.' '.$msg);
}

sub cyclePlayer{
    if($currentplayer < $#players){
	$currentplayer++;
    }else{
	$currentplayer = 0;
	
    }
}

sub removePlayer{
    splice(@players, $_[0], 1);
    $currentplayer--;
}

# Called when player's time is up or 
# A word was entered correctly
sub checkAnswer{
    if("$currentword" ne ""){ # Player replied
	if(wordExists($currentword)){
	    timeout_remove($timer);
	    my $notyetused = 1;
	    foreach(keys(%usedwords)){
		if("$_" eq "$currentword"){
		    $notyetused = 0;
		    last;
		}
	    }
	    if($notyetused){
		serverpost($globalServer, 
		    $cheers[int(rand($#cheers))] . ", " . 
		    $players[$currentplayer] . "!", $channel);
		$usedwords{$currentword} = $players[$currentplayer];
		$scores{$players[$currentplayer]}++; #Add score
		$winningword = $currentword;
		cyclePlayer();
		initPlayer();
	    }else{ # It has already been used!	
		if("$players[$currentplayer]" eq "$usedwords{$currentword}"){
		    serverpost($globalServer, "$players[$currentplayer]: You already used $currentword! You're out!", $channel);
		}else{
		    serverpost($globalServer, "$players[$currentplayer]: $currentword has already been used by $usedwords{$currentword}! You're out!", $channel);
		}
		timeout_remove($timer);
		$final = 1 if $currentplayer < $#players;
		removePlayer($currentplayer);
		cyclePlayer();
		initPlayer();
	    }
	}else{ # It wasn't a word
	    #serverpost($globalServer, "$players[$currentplayer]: $currentword isn't a word!", $channel);
	    $currentword = "";
	}
    }else{ # Player didn't reply.
	timeout_remove($timer);
	$final = 1 if $currentplayer < $#players;
	serverpost($globalServer, "$players[$currentplayer]: You didn't reply in time! You're out!", $channel);
	removePlayer($currentplayer);
	cyclePlayer();
	initPlayer();
    }
    
}

sub gameOver{
    my $endtext;
    my %sortedscores = ();
    my $winner;
    my @scorelist;

    $gameEnd = time();
    $endtext = "Game ended in ". ($gameEnd - $gameStart) ."s with ";
    while(my ($player, $score) = each(%scores) ){
	push(@scorelist, [$score, $player]);
    }
    @scorelist = reverse sort {$a->[0] <=> $b->[0]} @scorelist;
    if($scorelist[0][0] == $scorelist[1][0]){
	$endtext .= "a tie";
    }else{
	$winner = $scorelist[0][1];
	$endtext .= "$winner as the winner";
    }
    $endtext .= "! Scores: ";
    for(my $i = 0; $i < @scorelist; $i ++){
	$endtext .= "$scorelist[$i][1]\[$scorelist[$i][0]\] ";
    }
    undef @scorelist;

    serverpost($globalServer, "$endtext", $channel);
    addGame("$winner", sort(keys(%scores)));
    $playing = 0;
    %scores = ();
    %usedwords = ();
    $currentplayer = 0;
    @players = ();
    return 0;
}

sub initPlayer{
    if(@players == 1 && $final == 0){
	gameOver();
	return 0;
    }
    if(@players == 0){
	gameOver();
	return 0;
    }
    $currentword = "";
    $final = 0 if $final == 1;
    serverpost($globalServer, "$players[$currentplayer]: Give me a word beginning with $letter.", $channel);
    $timer = timeout_add($delay, 'checkAnswer', undef);
}

# Initialise scores, wordlists, etc
sub initGame{
    my $playerlist;

    $playing = 1;
    %usedwords = (); # FIXME should NOT be here!
    foreach(@players){
	$scores{$_} = 0;
    }
	
    $playerlist = join(", ", @players[0 .. $#players-1]) . " and $players[-1]";
	
    serverpost($_[0], 
	"INFO: wordblast v$VERSION. $words words in memory (~" . int($words / @players) . " words per player)", $channel);
    serverpost($_[0], 
	"Game started! " . 
	@players . " players: $playerlist. Time per word is ".
	$delay / 1000 . "s.", $channel);

    $currentplayer = 0;
    $currentword = "";
    newLetter();
    $gameStart = time();
    initPlayer();

}

# Game starts here, or is canceled.
sub startgame{
    my ($server, $msg, $nick, $address, $target) = @data;
    timeout_remove($timer);
    if(@players > 1){
	initGame($server);
    }else{
	serverpost($server, "Nobody wants to play with $players[0].", $channel);
	@players = (); # FIXME: Hack!
	$playing = 0;
    }
}

sub getquery{
    my ($server, $msg, $nick, $address, $target) = @_;
    return 0 if "$target" ne "$channel";
    my @calls = split(" ", $msg);
    my $call = lc(shift(@calls));
    $globalServer = $server; #FIXME: hack
    
    # Check if game is active. If so, check if called
    # is on the list. If not, return an error to him. If so,
    # take his request as a response of a query.
    #my $isaplayer = 0;
    if($playing){
	if("$nick" eq "$players[$currentplayer]"){
	    $currentword = $call;
	    checkAnswer();
	}
    }else{ # If we are not playing,
	if("$call" eq "$gamecall" or "$call" eq "$gamecall2"){ #And the call is right,
	    if(@players == 0){# Start a game.
		$start_delay = 20 * 1000;
		if(@calls > 0 && $calls[0] =~ /^-?\d/ && $calls[0] >= 0){
		    $calls[0] = 60 if $calls[0] > 60;
		    $start_delay = $calls[0] * 1000;
		}
		#$start_delay = $calls[0] * 1000 if @calls > 0 && $calls[0] =~ /^-?\d/ && $calls[0] >= 0 && $calls[0] <= 60;
		@players = ("$nick");
		$currentplayer = 0;
		$final = 0;
		serverpost($server, 
		    "$nick wants to start a game. " .
		    "Type \"$gamecall\" to join! " .
		    "Game starts in " . $start_delay / 1000 . " seconds.",
		    $channel);
		@data = ($server, $msg, $nick, $address, $target);
		$timer = timeout_add($start_delay, 'startgame', undef);
	    }else{
		# Check if nick already joined the game
		foreach(@players){
		    return 0 if "$_" eq "$nick";
		}
		push(@players, $nick);
		serverpost($server, "$nick joins the game.", $channel);
	    }
	}
    }
}

## Start
iprint("Loaded wordblast $VERSION.");
loadlist();
createAllTables();
signal_add('message public', 'getquery');
