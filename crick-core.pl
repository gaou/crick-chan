use G;
use lib '/home/gaou/crick-chan/lib';
#use warnings;
use strict;
use Storable;
use URI::Escape;
use HTML::Entities;
use CrickChan::NCBISearch;
use CrickChan::QueryExpansion;
use CrickChan::GenericSearch;

my $checkenju = readFile("ps auxw | grep enju |grep genia");
die("Cannot find Enju CGI") unless($checkenju =~ /cgi/);


my $question = $ARGV[0] || "How does bacteria repair DNA damage?"; #"what is the symptom of Alzheimer's disease?"; #

print STDERR "QUESTION: $question\n";
$question =~ s/\?//g;
my $qencoded = uri_escape($question);

print STDERR " query expansion with Bing...\n";
my %special  = filterSpecialTerm($question);
my %expanded = queryExpansion($question);
my %original = queryPrepFilter($question);
my %keyterms = filterObjectiveTerm($question);
print STDERR "SpecialTerm:  ", join(",", keys %special), "\n";
print STDERR "ExpandedTerm: ", join(",", keys %expanded), "\n";
print STDERR "OriginalTerm: ", join(",", keys %original), "\n";
print STDERR "KeyTerm:      ", join(",", keys %keyterms), "\n";

my $keyword = join(" ", keys %special, keys %expanded, keys %original, keys %keyterms);
my (%answers, $count, $page, @pages, @entries, $rankscore, $rankdelta, $search);

if(isBio()){
    print STDERR "Topic is BIOLOGY\n";

    print STDERR " querying PubMedCentral...\n";
    @entries = map{s/<.*?>//g; $_} grep {/<Id>/} readFile("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pmc&sort=relevance&retmax=5&term=" . $qencoded, 1);
    
    $rankscore = 2.0;
    $rankdelta = 0.2;
    
    $count = 0;
    $page = readFile('http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?retmode=text&db=pmc&id=' . join(',', @entries));
    $page =~ s/\n+/ /g;
    $page =~ s/<ref-list>.*?<\/ref-list>//g;
    @pages = split(/<\/article>/, $page);
    
    for my $acc (@entries){
	my $url = 'http://www.ncbi.nlm.nih.gov/pmc/articles/PMC' . $acc;
	
	my $body = '';
	$pages[$count] =~ s/^.*<body>//g;
	while($pages[$count] =~ /<p>(.*?)<\/p>/g){
	    $body .= $1 . "\n";
	}
	
	my %sentences = parsePage($pages[$count], \%original, \%expanded, \%special, \%keyterms, 10.0, 0.5);
	
	for my $key (keys %sentences){
	    $answers{"RS:$rankscore " . $key . ". (URL: $url)"} = $sentences{$key} + $rankscore - 8 - 2;
	}
	$rankscore -= $rankdelta;    
	$count ++;
	last if ($count == 9);
    }

    

    
    print STDERR " querying PubMed...\n";
    @entries = map{s/<.*?>//g; $_} grep {/<Id>/} readFile("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&sort=relevance&retmax=10&term=" . $qencoded, 1);
    
    $rankscore = 1.0;
    $rankdelta = 0.1;
    
    $count = 0;
    $page = readFile('http://www.ncbi.nlm.nih.gov/pubmed/' . join(',', @entries) . '?report=abstract&format=text');
    @pages = split(/PMID: /, $page);
    
    for my $acc (@entries){
	my $url = 'http://www.ncbi.nlm.nih.gov/pubmed/' . $acc;
	
	my %sentences = parsePage($pages[$count], \%original, \%expanded, \%special, \%keyterms, 1.0, 0.05, "pubmed");
	
	for my $key (keys %sentences){
	    $answers{"RS:$rankscore " . $key . ". (URL: $url)"} = $sentences{$key} + $rankscore;
	}
	$rankscore -= $rankdelta;    
	$count ++;
	last if ($count == 9);
    }
    

    
    
    print STDERR " querying OMIM...\n";
    my $apikey = "30CE8AF42397828EDFF7992DCCA70A7453ADD9A6";
    @entries = map{s/<.*?>//g; $_} grep {/<mimNumber>/}  readFile("http://api.omim.org/api/entry/search?search=" . $qencoded . "&start=0&limit=10&apiKey=" . $apikey, 1);
    @entries = () if ($question =~ /bacteria/ || $question =~ /microb/);
    
    $rankscore = 10;
    $rankdelta = 1;
    
    my $omim = readFile("http://api.omim.org/api/entry?mimNumber=" . join(",", @entries) . "&include=text&apiKey=" . $apikey);
    
    $count = 1;
    my %texts;
    for my $entry (split(/<\/entry>/, $omim)){
	my $acc;
	if ($entry =~ /<mimNumber>(\d+)<\/mimNumber>/){
	    $acc = $1;
	    next unless(length($acc));
	    $texts{$acc} = $entry;
	}
    }
    
    $rankscore += 5 if($keyword =~ /disease/ || $keyword =~ /human/ || $keyword =~ /symptom/ || $keyword =~ /sapiens/);
    
    for my $acc (@entries){
	my $body;
	$texts{$acc} =~ s/\&lt\;Subhead\&gt\; .*?\n\n//g;
	$texts{$acc} =~ s/\n+/ /g;
	while ($texts{$acc} =~ /<textSectionContent>.*?<\/textSectionContent>/g){
	    $body .= $&;
	}
	
	my %sentences = parsePage(decode_entities($body), \%original, \%expanded, \%special, \%keyterms, 20, 0.1);
	
	for my $key (keys %sentences){
	    $answers{sprintf("RS:%.1f ", $rankscore) . $key . ". (URL: http://www.omim.org/entry/$acc)"} = $sentences{$key} + $rankscore - 8 - 18;
	}
    $rankscore -= $rankdelta;    
	
	$count ++;
	last if ($count == 10);
    }


    my @key = sort{$answers{$b} <=> $answers{$a}} keys %answers;
    my $base = (10 * scalar(keys %keyterms)) + (5 * scalar(keys %special)) + 10;
    my $confidence = $answers{$key[0]} / $base * 100;
    
    if($confidence < 90){

	$rankscore = 2.0;
	$rankdelta = 0.1;
	print STDERR " querying NCBI Bookshelf...\n";
	
	my @urls = searchBingForNCBIBookshelf($question);
	@entries = map{(split("/"))[-1]}@urls;
	
	for my $acc (@entries[0..5]){
	    my $url = 'http://www.ncbi.nlm.nih.gov/books/' . $acc;
	    
	    my $body;
	    my $page = readFile("lynx --source $url");
	    $page =~ s/<div .*? class=\"table\">.*?<\/div>//g;
	    while($page =~ /<p>(.*?)<\/p>/g){
		$body .= $1 . "\n";
	    }
	    
	    my %sentences = parsePage($body, \%original, \%expanded, \%special, \%keyterms, 2.0, 0.1);
	    
	    for my $key (keys %sentences){
		$answers{"RS:$rankscore " . $key . ". (URL: $url)"} = $sentences{$key} + $rankscore;
	    }
	    $rankscore -= $rankdelta;    
	    $count ++;
	    last if ($count == 9);
	}
    }
    
}else{
    print STDERR "Topic is GENERIC\n";
}

my @key = sort{$answers{$b} <=> $answers{$a}} keys %answers;
my $base = (10 * scalar(keys %keyterms)) + (5 * scalar(keys %special)) + 10;
my $confidence = $answers{$key[0]} / $base * 100;

if($confidence < 90){
    my @urls = searchBingForWikipedia($question);
    my @topics = map{(split("/"))[-1]}@urls;
    
    print STDERR "  retrieving sentences from Wikipedia entry...\n";
    $rankscore = 5.0;
    $rankdelta = 1.0;
    
    for my $topic (@topics) {
	next if ($topic =~ /Talk:/);
	my %sentences = parseWiki($topic, \%original, \%expanded, \%special, \%keyterms);
	
	foreach my $sentence (keys %sentences) {
	    $answers{sprintf("RS:%.1f ", $rankscore) . $sentence} = $sentences{$sentence} + $rankscore - 15;
	}
	$rankscore -= $rankdelta;
    }


    @urls = searchBing($question);
    print STDERR "  retrieving sentences from Web pages...\n";
    $rankscore = isBio() ? 5.0 : 7.0;
    $rankdelta = 0.1;
    my %web;
    for my $url (@urls) {
	next if ($url =~ /youtube/ || $url =~ /wikipedia/);
	my %sentences = parseHtml($url, \%original, \%expanded, \%special, \%keyterms);
	foreach my $sentence (keys %sentences) {
	    $web{sprintf("RS:%.1f ", $rankscore) . $sentence . ". (URL: $url) [Web]"} = $sentences{$sentence} + $rankscore - 20;
	}
	$rankscore -= $rankdelta;
    }
    my @tmpkey = sort{$web{$b} <=> $web{$a}} keys %web;
    $answers{$tmpkey[$_]} = $web{$tmpkey[$_]} for (0..5);
}

@key = sort{$answers{$b} <=> $answers{$a}} keys %answers;
$base = (10 * scalar(keys %keyterms)) + (5 * scalar(keys %special)) + 10;
$confidence = $answers{$key[0]} / $base * 100;
#say sprintf("CONFIDENCE: %.1f\%", $confidence * 1.0);

say sprintf("Confidence: %.2f\% Score: %.1f: %s\n",  $answers{$key[$_]} / $base * 100, $answers{$key[$_]}, $key[$_]) for (0..5);

