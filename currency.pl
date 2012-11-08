#!/usr/bin/perl 
# A simple currency converter using Locale::Object::Currency::Converter.
# For irssi :)
#
# A word of warning:
# If you have a packaging system, PLEASE USE IT to install the required 
# modules. Loading this into irssi without all required modules might
# result in erratic behaviour.
#
# If you're going to use cpan, something like this should suffice:
#
# cpan> force install Locale::Object::Currency
# cpan> force install Locale::Object::Currency::Converter
# cpan> force install Finance::Currency::Convert::Yahoo
#
# TODO:
# - Allow users in a channel to query? Or? Hm.
# - the $Public printing crap is really stupid.
#
# Settings:
#
# /set currency_allow_external=<0 or 1> [not yet used of course]
# /set currency_convert_internally=<0 or 1> (1 is faster)
# /set currency_converter=<Yahoo or XE> (Yahoo is better)
#
# 
# Forking code heavily inspired by dns.pl v2.1.1 by inch <inch@stmpd.net>
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
#
# Changes:
# 0.3:
# - Added granularity cutoff
# - Workaround (suggested by mauke) for suppressing carp warnings in
#   Locale::Object::Currency in order to avoid ugly console output requiring
#   a /redraw.
# - Placed most Currency conversion code in an eval BLOCK in case
#   Locale::Object::Currency screws up (it's somewhat flaky) - 
#   if a dependency is missing we only find out in realtime..
#   This also catches common errors such as invalid currency codes.
# - Added check to verify that the exchange rate is numeric
#   (Locale::Object::Currency just returns an arbitrary error string
#   if it fails here)
#
use warnings;
use strict;

use constant {
    'VERSION' => '0.3', # Small doesn't mean bad!
    'GRANULARITY' => 6
};

use POSIX;
use Irssi;
use Irssi::Irc;

use Locale::Object::Currency;
use Locale::Object::Currency::Converter;

## Global
use vars qw(%IRSSI);

# Dirty dirty
our ($InternalConvert, $AllowExternal, $ConverterSite)  = (1, 0, 'Yahoo');
our ($Converter, $PipeTag);
our ($Public, $Waiting) = (0, 0);
our ($WindowItem, $Server);

my %IRSSI = (
        authors => 'gammy',
        contact => 'gamAPPLEmy at pulappleia dot nu without fruits',
        name    => "Simple currency converter",
        license => 'GPLv2',
        url     => 'http://www.pulia.nu',
);

## Functions

# This is really stupid :(
sub pPrint{
    my $Text = shift;

    $Public = 0 if index $Text, 'Failure' != -1;

    if($Public){
        if("$WindowItem" eq '0'){
            Irssi::active_win->print("Your active window is not public; printing locally.");
            Irssi::active_win->print($Text);
            return;
        }
        my $WindowType = $WindowItem->{'type'};
        if($WindowItem && ($WindowType eq 'CHANNEL' || $WindowType eq 'QUERY')){
            $WindowItem->command('MSG ' . $WindowItem->{'name'} . ' ' . $Text);
        }else{
            Irssi::active_win->print("Can't post to window type $WindowType!");
            Irssi::active_win->print($Text);
        }
    }else{
        Irssi::active_win->print($Text);
    }
}

sub initConverter{

    undef($Converter);
    # I am using Yahoo because I noticed that XE only give .2 in accuracy
    # on the rate, resulting in quite a disrepency if you want to calculate
    # the rate on your own based on its result. Yahoo is much more accurate.
    our $Converter = 
        Locale::Object::Currency::Converter->new(service => $ConverterSite);

}

sub help{

    $Public = 0;

    pPrint 'Simple currency converter v' . VERSION;
    pPrint 'SETTINGS';
    pPrint 'currency_allow_external     = ' . $AllowExternal;
    pPrint 'currency_convert_internally = ' . $InternalConvert;
    pPrint 'currency_converter          = ' . $ConverterSite;
    pPrint 'HELP';
    pPrint '/set currency_allow_external=<0/1> (1 allows external queries)';
    pPrint '/set currency_convert_internally=<0/1> (1 is faster)';
    pPrint '/set currency_converter=<Yahoo/XE> (Yahoo is better)';
    pPrint '-o: Send output to active channel/query';
    pPrint 'USAGE';
    pPrint '/currency [-o] 100[ ]USD [to|in] EUR';
    pPrint 'EXAMPLES';
    pPrint '/currency 100usd in eur';
    pPrint '/currency -o 100 USD to EUR';
    pPrint '/currency 100.203USD in EUR';
    pPrint '.. and so on';

}

sub loadSettings{

    $AllowExternal   = Irssi::settings_get_bool('currency_allow_external');
    $InternalConvert = Irssi::settings_get_bool('currency_convert_internally');
    $ConverterSite   = Irssi::settings_get_str('currency_converter');

    initConverter();

}

sub pipeInput{
    my $ReadHandle = shift;

    my $Text = <$ReadHandle>;

    close($ReadHandle);
    Irssi::input_remove($PipeTag);

    $PipeTag = -1;

    pPrint($Text); # FIXME

    $Waiting = 0;
}

sub getConversion{
    my ($Amount, $OrigCurrency, $DestCurrency) = @_;

    my ($ReadHandle, $WriteHandle);
    pipe($ReadHandle, $WriteHandle);

    my $PID = fork();

    if(! defined($PID)){
        $Public = 0;
        pPrint("fork() failed!");
        close($ReadHandle);
        close($WriteHandle);
        return;
    }

    $Waiting = 1;

    if($PID > 0){ # Parent
        close($WriteHandle); # No write needed
        
        Irssi::pidwait_add($PID);

        $PipeTag = Irssi::input_add(
            fileno($ReadHandle), 
            INPUT_READ,
            \&pipeInput,
            $ReadHandle
        );

        return;
    }
        
    # Child
    my $Text;

    eval{
        local $SIG{__WARN__} = sub {}; # Workaround hack to suppress internal
                                       # carp warnings - they ruin the curses
                                       # window...

        my $FromCurrency = Locale::Object::Currency->new(code=>$OrigCurrency);
        die "'$OrigCurrency': invalid currency" if  ! $FromCurrency;

        my $ToCurrency = Locale::Object::Currency->new(code=>$DestCurrency);
        die "'$DestCurrency': invalid currency" if  ! $DestCurrency;

        $Converter->from($FromCurrency);
        $Converter->to($ToCurrency);

        my $ResultAmount = -1;
        my $Rate = $Converter->rate;
        unless($Rate=~/^\d*(\.\d*|)$/){
            die 'Conversion rate variable is not numeric - ' .
                'you might be missing a few modules.';
        }

        if(! $InternalConvert){
            $ResultAmount = $Converter->convert($Amount), 
        }else{
            $ResultAmount = ($Amount * $Rate);
        }

        # Adjust granularity a bit
        my $AdjustAmount = sprintf('%.'.GRANULARITY.'f', $ResultAmount);
        $ResultAmount = '~'.$AdjustAmount if "$ResultAmount" ne $AdjustAmount;

        undef($FromCurrency);
        undef($ToCurrency);
    
        my ($YY,$MM,$DD) = (localtime($Converter->timestamp))[5,4,3];
        my $HumanDate = sprintf("%02d%02d%02d", (1900+$YY)-2000, ++$MM, $DD);

        $Text = "$Amount $OrigCurrency = $ResultAmount $DestCurrency | Rate: $Rate ($HumanDate)";


    };

    if($@){
        $Text = "Failure: $@";
    }

    eval {
       print $WriteHandle $Text;
       close($WriteHandle);
   };

   POSIX::_exit(1);
}



# Won't catch errors if input is in the style of '100sek usd ass'..meh
sub parseInput{

    my $Input = uc shift;
    $Input =~tr/,/./;
    $Input =~s/IN//;
    $Input =~s/TO//;
    $Input =~s/\s+/ /g;

    my ($Amount, $From, $To);
    my @Segments = split / /, $Input;

    return -1 if @Segments != 2 && @Segments != 3;

    $To = pop @Segments; # Output currency should always be last

    if(@Segments == 1){ # presuming Amount and Input currency are grouped
        if($Segments[0] =~m/^([^a-z]*?)([a-z]+)/i){
            ($Amount, $From) = ($1, $2);
        }else{
            return -1;
        }
    }else{ 
        ($Amount, $From) = @Segments;
    }


    return ($Amount, $From, $To);
}

sub handleInput{
    my $Input = shift;
    ($Server, $WindowItem) = @_;

    if($Waiting > 0){
        $Public = 0;
        pPrint("Previous request not yet finished. Please wait.");
        $Public = 1;
        return;
    }

    my $Opt = substr($Input, 0, 3);
    if("$Opt" eq '-o '){
        $Public = 1;
        substr($Input, 0, 3, '');
    }else{
        $Public = 0;
    }
    
    my @Info = parseInput($Input);

    if(@Info != 3){
        help();
    }else{
        getConversion(@Info);
    }
    
}

## Init

# Defaults
Irssi::settings_add_bool('misc', 'currency_allow_external'    , 0);
Irssi::settings_add_bool('misc', 'currency_convert_internally', 1);
Irssi::settings_add_str( 'misc', 'currency_converter'         , 'Yahoo');

# Load user settings
loadSettings();

# Bindings
Irssi::command_bind('currency', 'handleInput');

# Signals
#Irssi::signal_add_first('server incoming', \&handleIncoming);
Irssi::signal_add('setup changed', 'loadSettings');

help();
