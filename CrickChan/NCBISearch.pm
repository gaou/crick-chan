package CrickChan::NCBISearch;

use G;
use strict;
use URI::Escape;
use HTML::Entities;
use Storable;
use base qw(Exporter);
use SelfLoader;
use JSON;

our @EXPORT = qw(
                 parsePage
                );


sub parsePage{
    my $body  = shift;
    my $ref1  = shift;
    my $ref2  = shift;
    my $ref3  = shift;
    my $ref4  = shift;
    my $linescore      = shift || 20.0;
    my $linescoredelta = shift || 0.1;
    my $skiptitle = shift;

    my %original = %{$ref1};
    my %expanded = %{$ref2};
    my %special  = %{$ref3};
    my %keyterm  = %{$ref4};

    my %sentences;
    my %verbs = %{retrieve("/home/gaou/crick-chan/verbs.hash.nstore")};

    $body =~ s/\n\n/end. /g;
    $body =~ s/\s*\n+/ /g;
    $body =~ s/<.*?>/ /g;
    $body =~ s/{\d+:(.*?)}/ $1/g;
    $body =~ s/\s*{[0-9.]+}//g;
    $body =~ s/\(\)//g;
    $body =~ s/ +/ /g;
    $body =~ s/\. ([A-Z])/\.  $1/g;
    $body =~ s/end\./\n\n/g;
    $body =~ s/Author information:.*?\n//g;
    $body =~ s/\n+/ /g;
    $body =~ s/\s+\./\./g;
    $body =~ s/\s+\,/\,/g;
    $body =~ s/SUMMARY: //g;
    $body =~ s/BACKGROUND: //g;
#    $body =~ s/\.([A-Z])/\.  $1/g;

    for my $stn (split(/\.  /, $body)){
	my $stn2 = $stn;
	my $symbols = $stn2 =~ tr/a-zA-Z0-9,."-' /a-zA-Z0-9,."-' /c;
	next if ($symbols > 10);

        my @words = split(/ /, $stn);
        next unless(scalar(@words) > 5);
        
        my %uniquewords;
        $uniquewords{lc($_)} ++ for (@words);
        
        my $flag = 0;
        my $score = 0;
        for (keys %uniquewords){
            $flag ++      if($verbs{lc($_)});
	    $score -= 2   if(lc($_) eq 'we');
	    $score -= 2   if(lc($_) eq 'our');
	    $score += 10  if($keyterm{lc($_)});
            $score += 5   if($special{lc($_)});
            $score += 1.2 if($original{lc($_)});
            $score += 0.8 if($expanded{lc($_)});
        }
        next unless($flag);
        next unless($score);
        
        next if($stn =~ /, [A-Z]., /);

        $stn =~ s/^\s+//g;
        substr($stn, -1, 1) = '' if (substr($stn, -1, 1) eq '.');
	if($linescore == 1 && length($skiptitle)){
	    $sentences{sprintf("S:%.1f LS:%.1f\n    ", $score, $linescore) . $stn} = $score;
	}else{
	    $sentences{sprintf("S:%.1f LS:%.1f\n    ", $score, $linescore) . $stn} = $score + $linescore;
	}
        $linescore -= $linescoredelta if($linescore > 0);
    }

    return %sentences;
}




1;
