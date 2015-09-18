package CrickChan::QueryExpansion;

use G;
use strict;
use URI::Escape;
use HTML::Entities;
use Storable;
use base qw(Exporter);
use SelfLoader;

our @EXPORT = qw(
                 queryExpansion
                 queryPrepFilter
                 filterSpecialTerm
                 filterObjectiveTerm
                 isBio
                 isCompleteSentence
                 recentBing
                );

our $recentbing;

sub recentBing{
    return $recentbing;
}

sub isBio{
    if($recentbing =~ /nih\.gov\//){
	return 1;
    }else{
	return 0;
    }
}

sub queryExpansion{
    my $string = shift;
    my $escaped = uri_escape($string);
#    my $url = 'http://www.google.co.jp/search?rls=en&q=' . $escaped . '&as_qdr=all&complete=0&num=100';
    my $url = 'http://www.bing.com/search?q=' . $escaped . '&count=20';
    my %words;
#say $url;

    my $page = readFile($url);
    $recentbing = $page;
#say $page;
    for my $key ($page =~ /<strong>.*?<\/strong>/g){
	$key =~ s/<.*?\>//g;
	my $decoded = decode_entities($key);
	$decoded =~ s/://g;
	$decoded =~ s/;//g;
	
	for (split(/\s+/, $decoded)){
	    $words{$_}++ if(/[a-zA-Z]/ && length($_) > 3);
	}
    }

    my %preps = %{retrieve("/home/gaou/crick-chan/prepositions.hash.nstore")};
    $preps{$_}++ for (qw/is are was were be have has had which how what when who where/);
    my %return;

    my %original = queryPrepFilter($string);

    for (keys %words){
#	next if (/[^a-zA-Z'-]/);
	next if ($original{lc($_)});
	$return{lc($_)}++ unless($preps{lc($_)});
    }

    return %return;
}


sub queryPrepFilter{
    my $string = shift;

    my %preps = %{retrieve("/home/gaou/crick-chan/prepositions.hash.nstore")};
    $preps{$_}++ for (qw/is are was were be have has had which how what when who where/);
    my %return;

    for (split(/\s+/, $string)){
#	next if (/[^a-zA-Z'-]/);
	$return{lc($_)}++ unless($preps{lc($_)});
    }

    return %return;
}

sub filterSpecialTerm{
    my $string = shift;

    my %words = %{retrieve("/home/gaou/crick-chan/linux.words")};
    my %return;

    for (split(/\s+/, $string)){
#	next if (/[^a-zA-Z'-]/);
	$return{lc($_)}++ unless($words{lc($_)});
    }

    return %return;
}



sub filterObjectiveTerm{
    my $question = shift;
    my $qencoded = uri_escape($question);

    my $enju = readFile("http://localhost:8080/cgi-lilfes/enju?sentence=$qencoded");
    my %return;
    for my $tags (split(/</, $enju)){
	if($tags =~ /^tok .*? pos=\"(.*?)\" .*? pred=\"(.*?)\".*>(.+)/){
	    my ($pos, $pred, $word) = ($1, $2, $3);
	    $return{lc($word)} ++ if ($pos =~ /NN/);
	}
    }

    return %return;

}

sub isCompleteSentence{
    my $question = shift;
    my $qencoded = uri_escape($question);

    my $enju = readFile("http://localhost:8080/cgi-lilfes/enju?sentence=$qencoded");

    my $result = 0;
    for my $tags (split(/</, $enju)){
	if($tags =~ /^tok .*? pos=\"(.*?)\" .*? pred=\"(.*?)\".*>(.+)/){
	    if($1 =~ /VB/){
		$result = 1;
	    }
	}
    }
    return $result;
}


=head

 previous script using LODQA

    my $page = readFile("http://lodqa.org/analysis?query=" . $qencoded . "&preset=qald-biomed&endpoint_url=http%3A%2F%2Frdf.pubannotation.org%2Fsparql&graph_uri=&dictionary_url=http%3A%2F%2Fpubdictionaries.org%3A80%2Fdictionaries%2Fid_mapping%3Fdictionaries%3D%255B%2522qald-drugbank%2522%252C%2522qald-diseasome%2522%252C%2522qald-sider%2522%255D%26output_format%3Dsimple%26threshold%3D0.5%26top_n%3D0&parser_url=http%3A%2F%2Fbionlp.dbcls.jp%2Fenju&ignore_predicates=&sortal_predicates=http%3A%2F%2Fwww.w3.org%2F1999%2F02%2F22-rdf-syntax-ns%23type%0D%0Ahttp%3A%2F%2Fwww.w3.org%2F2000%2F01%2Frdf-schema%23subClassOf&max_hop=3&config=");

    my %return;
    if($page =~ /<div id=\"lodqa-pgp\">{(.*?)}<\/div>/){
	my $mappings = $1;
	while($mappings =~ /\"head\":\d+,\"text\":\"(.*?)\"}/g){
	    for (split(/\s+/, $1)){
		$return{lc($_)}++;
	    }
	}
    }
    
    return %return;

=cut

1;
