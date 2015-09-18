package CrickChan::GenericSearch;

use G;
use strict;
use URI::Escape;
use HTML::Entities;
use Storable;
use base qw(Exporter);
use SelfLoader;
use JSON;

our @EXPORT = qw(
                searchBing
                searchBingForWikipedia
                searchBingForNCBIBookshelf
                parseHtml
                extractSentences
                extractParagraphs
                parseWiki
                );


sub searchBingForWikipedia {
    my $question = shift;
    $question =~ s/\s+/+/g;
    my $qencoded = uri_escape($question);
    print STDERR " searching Bing...\n";
    my @entries = readFile("lynx --dump \"http://www.bing.com/search?q=$qencoded+site%3Aen.wikipedia.org\" |grep http |grep http://en.wikipedia.org/ |grep -v '#'", 1);
    return (map{(split(" +"))[2]}@entries)[0..4];
}

sub searchBingForNCBIBookshelf {
    my $question = shift;
    $question =~ s/\s+/+/g;
    my $qencoded = uri_escape($question);
    print STDERR " searching Bing...\n";
    my @entries = readFile("lynx --dump \"http://www.bing.com/search?q=$qencoded+site%3Ahttp://www.ncbi.nlm.nih.gov/books\" |grep http |grep http://www.ncbi.nlm.nih.gov/books/NBK |grep -v '#'", 1);
    return (map{(split(" +"))[2]}@entries)[0..4];
}



sub searchBing {
    my $question = shift;
    $question =~ s/\s+/+/g;
    my $qencoded = uri_escape($question);
    print STDERR " searching Bing...\n";
    my @entries = readFile("lynx --dump \"http://www.bing.com/search?q=$qencoded\" |grep http |grep -v bing", 1);
    return (map{(split(" +"))[2]}@entries)[0..4];
}

sub parseHtml {
    my $url = shift;
    my $ref1 = shift;
    my $ref2 = shift;
    my $ref3 = shift;
    my $ref4 = shift;

    my %original = %{$ref1};
    my %expanded = %{$ref2};
    my %special  = %{$ref3};
    my %keyterms = %{$ref4};

    my @text = readFile("lynx --dump \"$url\" |grep -v http", 1, -format=>"command");

    my %verbs = %{retrieve("/home/gaou/crick-chan/verbs.hash.nstore")};

    my %sentences;

    my $linescore = 20.0;
    my $linescoredelta = 0.05;

    foreach my $par (extractParagraphs(@text)) {
        foreach my $stn (extractSentences($par)) {
	    my $stn2 = $stn;
	    my $symbols = $stn2 =~ tr/a-zA-Z0-9,."-' /a-zA-Z0-9,."-' /c;
	    next if ($symbols > 10);
            my @words = map{lc $_}split(/ /, $stn);
            my %uniquewords;
            for(@words) {
                $_ =~ s/^[^\w]//g;
                $_ =~ s/[^\w]$//g;
                $uniquewords{lc $_} ++;
            }

            my $flag = 0;
            my $score = 0;
            for (keys %uniquewords){
                $flag ++ if($verbs{$_});
                $score -= 2   if(lc($_) eq 'we');
                $score += 5   if($keyterms{lc $_});
                $score += 2   if($special{lc $_});
                $score += 1.2 if($original{lc $_});
                $score += 0.8 if($expanded{lc $_});
            }

	    $sentences{sprintf("S:%.1f LS:%.1f\n    ", $score, $linescore) . $stn} = $score + $linescore if($flag * $score);
            $linescoredelta -= 0.1;
        }
    }
    return %sentences;
}

sub extractSentences {
    my $paragraph = shift;
    my @sentence;
    my @sentences;
    foreach my $block (split(/ /, $paragraph)) {
        if($block =~ s/[\.\!\?]+$//) {
            push @sentence, $block;
            my $stn = join " ", @sentence;
            push @sentences, "$stn";
            @sentence = ();
        } else {
            push @sentence, $block;
        }
    }

    if(@sentence) {
        my $stn = join " ", @sentence;
        push @sentences, "$stn";
        @sentence = ();
    }

    return @sentences;
}

sub extractParagraphs {
    my @lines = @_;
    my @paragraph;
    my @paragraphs;

    foreach my $line (@lines) {
        chomp($line);
        last if $line =~ /^参照/;
        if($line =~ /^\s*$/) {
            my $par = join(" ", @paragraph);
            $par =~ s/^ +//g;
            $par =~ s/ +/ /g;
            $par =~ s/\[.+?\]\(.+?\)//g;
            $par =~ s/\[.+?\]//g;
            push @paragraphs, $par if scalar(split(/ /, $par)) > 5;
            @paragraph = ();
        } else {
            push @paragraph, $line if $line !~ /^ +\[/;
        }
    }

    return @paragraphs;
}

sub parseWiki {
    my $topic = shift;
    my $ref1 = shift;
    my $ref2 = shift;
    my $ref3 = shift;
    my $ref4 = shift;

    $topic =~ s/ /_/g;
    
    my %original = %{$ref1};
    my %expanded = %{$ref2};
    my %special  = %{$ref3};
    my %keyterms = %{$ref4};

    my $url = "https://en.wikipedia.org/w/api.php?action=query&titles=$topic&prop=revisions&rvprop=content&format=json";
    my $json = readFile($url, -format=>"url");
    my $obj = from_json($json);
    my @pages = keys %{$obj->{query}->{pages}};

    my %verbs = %{retrieve("/home/gaou/crick-chan/verbs.hash.nstore")};

    my %sentences; # Return variable;

    foreach my $page (@pages) {
        my @title = map{lc $_}split(/ /, $obj->{query}->{pages}->{$page}->{title});

        foreach my $revision (@{$obj->{query}->{pages}->{$page}->{revisions}}) {
            my $content = $revision->{"*"};

            if($content =~ /^#REDIRECT \[\[([^#]+)\]\]$/) {
                return parseWiki($1, $ref1, $ref2, $ref3, $ref4);
            }

            $content =~ s/<ref.+\/ref>//g;
	    $content =~ s/<.*?>//g;

            my $linescore = 20.0;
            my $linescoredelta = 0.3;
            foreach my $line (split(/\n/, $content)) {
                chomp($line);
                my @sentence;
                my @words = split(/ /, $line);
                foreach my $word (@words) {
                    if($word =~ s/\.$//g) {
                        push @sentence, $word;
                        next unless scalar(@sentence) > 5;

                        my $stn = join(" ", @sentence) . ".";

                        $stn =~ s/{{.+?}}//g;

                        while($stn =~ /\[\[(.+?)\]\]/) {
                            my $link = $1;
                            $link =~ s/.+\|(.+)/$1/g;
                            $stn =~ s/\[\[.+?\]\]/$link/;
                        }

                        $stn =~ s/'+/'/g;

                        my %uniquewords;
                        for(@sentence, @title) {
                            $_ =~ s/^[^\w]//g;
                            $_ =~ s/[^\w]$//g;
                            $uniquewords{lc $_} ++;
                        }

			next unless(scalar(keys %uniquewords) > 5);

                        my $flag = 0;
                        my $score = 0;
                        for (keys %uniquewords){
                            $flag ++ if($verbs{$_});
			    $score += 5   if($keyterms{lc $_});
                            $score += 2   if($special{lc $_});
                            $score += 1.2 if($original{lc $_});
                            $score += 0.8 if($expanded{lc $_});
                        }
			$stn =~ s/\[http:\S+ (.*?)\]/$1/eg;
			my $title = $obj->{query}->{pages}->{$page}->{title};
			$title =~ s/ /_/g;
                        $sentences{sprintf("LS:%.1f S:%.1f\n     ", $linescore, $score) . decode_entities($stn) . " [".$obj->{query}->{pages}->{$page}->{title}."]" . ". (URL: https://en.wikipedia.org/wiki/$title)"} = $score + $linescore if $flag * $score;
                        @sentence = ();
                    } else {
                        push @sentence, $word;
                    }
                }
                $linescore -= $linescoredelta if $linescore - $linescoredelta >= 0 and $line =~ /^==.+==$/;
		$linescore -= 0.001;
            }
        }
    }

    return %sentences;
}
