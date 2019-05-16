#!/usr/bin/perl
package CommonCmdbFunctions;

use LWP;
use LWP::Simple;
use LWP::UserAgent; 
use HTTP::Request;
use URI::Escape;
use XML::Simple;
use XML::XPath;
use HTML::Entities();
use DBI;
use JSON;
use utf8;
use Encode;
use Try::Tiny;
use Data::Dumper;
use strict;
use warnings;
use Exporter;
use POSIX qw(strftime);
use Scalar::Util qw(looks_like_number);
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ( #functions which will be imported into the main namespace
	"printError",
	"checkRequiredParams",
	"callWebservice",
	"datestamp",
	"getAttributeValueTextFromCi",
	"getAttributeValueDefaultFromCi",
	"getAttributeValueCiFromCi",
	"countAttributesOfCi",
	"updateAttributeValueTextOfCi",
	"createRelation",
	"deleteRelation",
	"dateTimeStamp",
	"convertDecisionToGerman",
	"UnixTimeToDateTime"
);

our $apikey;

sub setSettings {
	my %Param = @_;
	
	if(defined $Param{apikey} ) {
		$apikey = $Param{apikey};
	}
}

sub getSettings {
	return {apikey => $apikey};
}

sub getFunctionName {
	my $functionLevel = shift;
	if(!$functionLevel) {
		$functionLevel = 0;
	}
	
	return (( caller($functionLevel) )[3]);
}

sub printError {
	my $msg = shift;
	my $functionLevel = shift;
	
	print getFunctionName($functionLevel) . " -- " . $msg . "\n";
}

sub checkRequiredParams {
	my %givenParams = %{ $_[0] };
	my @requiredParams = @{$_[1]};
	my $error = 0;
	
	foreach (@requiredParams) {
		#print $_.": ".$givenParams{$_}."\n";
		if (!$givenParams{$_}) {
			printError($_." is a required param!", 3);
			$error++;
		}
	}
	if($error gt 0) {
		return;
	}
	#print "\n";
	
	return 1;
}



############################################
#               FUNCTIONS                  #
############################################

### sending mail via cmdb ###
# param1: name of template
# param2: hash of properties --> Subject | From | FromName | Recipients | RecipientsCC | RecipientsBCC | Attachments + custom Params
# EXAMPLE:
# my %params = (
	# Recipients => 'example@example.com'
	# body => 'TEST' # --> custom param
# );
#callWebservice("notify", "test", \%params);#send mail template "test" to "example@example.com"

### call webservice ###
# my %params = (
	# 'argv1' => '11111'
# );	
# print callWebservice("query", "test",\%params);#call query "test" with argv1 = 11111

### execute workflow ###
# my %params = (
	# 'argv1' => '11111'
# );	
# callWebservice("workflow", "test",\%params);#execute workflow "test" with first parameter = 11111

### execute executable ###
# my %params = (
	# 'executable_attribute_name' => 'test',
	# 'ciid' => '234'
# );	
# callWebservice("exec", "test",\%params);#execute executable of attribute with name "test" for ci_id = 234

sub callWebservice {
	my $type = shift; #workflow | notify | query | exec
	my $name = shift;
	my %params =  %{shift()};
	my $method = "plain";
	my $apiurl;
	my $ua = LWP::UserAgent->new;  # we create a global UserAgent object
	if($type eq "notify") {
		$apiurl = "http://itocmdb.infonova.at/api/notification/apikey/".$apikey."/".$type."/".$name;
	}elsif($type eq "exec") {
		$apiurl = "http://itocmdb.infonova.at/api/adapter/apikey/".$apikey."/";
	} else {
		$apiurl = "http://itocmdb.infonova.at/api/adapter/apikey/".$apikey."/".$type."/".$name."/method/".$method;
	}
	my $res;
	my $req = HTTP::Request->new(POST => $apiurl);
	$req->header('Content-Type' => 'application/x-www-form-urlencoded');

	my $content_string = '';
	while ( my ($key, $value) = each %params ) {
		if($key eq 'Recipients' && ref($value) eq 'Array') {
			$value = join(';', $value);
		}
		$content_string .= '&'.$key.'='.uri_escape_utf8($value);
	}
	$content_string =~ s/.//;#remove first &
	
	$req->content($content_string);
	
	$res = $ua->request($req);#SEND!!!
	
	if($res->status_line ne "200 OK") {
		print $res->status_line."\n";
		return 0;#error
	}
	
	$res = $res->decoded_content if $res->is_success;
	return $res;
}

sub datestamp { 
        my @time_now = localtime(time);
    my $datestamp = sprintf "%d%02d%02d%02d%02d%02d" ,
    $time_now[5]+1900,$time_now[4]+1,$time_now[3],$time_now[2],$time_now[1],$time_now[0];
        return $datestamp;
}

sub getAttributeValueTextFromCi {
	my $ci_id = $_[0];
	my $attribute_name = $_[1];
	my %params = (	
		'argv1' => 'value_text',
		'argv2' => $ci_id,
		'argv3' => $attribute_name
		);	
	my $value = callWebservice("query", "select_value_from_ci_attribute_name", \%params);
	
	return $value;
}

sub getAttributeValueDefaultFromCi {
	my $ci_id = $_[0];
	my $attribute_name = $_[1];
	my %params = (	
		'argv1' => 'value_default',
		'argv2' => $ci_id,
		'argv3' => $attribute_name
		);	
	my $value = callWebservice("query", "select_value_from_ci_attribute_name", \%params);
	
	return $value;
}

sub getAttributeValueCiFromCi {
	my $ci_id = $_[0];
	my $attribute_name = $_[1];
	my %params = (	
		'argv1' => 'value_ci',
		'argv2' => $ci_id,
		'argv3' => $attribute_name
		);	
	my $value = callWebservice("query", "select_value_from_ci_attribute_name", \%params);
	
	return $value;
}

sub countAttributesOfCi {
	my $ci_id = $_[0];
	my $attribute = $_[1];
	my $attribute_id;
	
	#if number --> ID is given, otherwise the name is given
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute;
	} else {
		$attribute_id = callWebservice("query", "select_id_of_attribute_per_name", { 'argv1' => $attribute } );
	}
	
	my $count = callWebservice("query", "count_ci_attributes", { 'argv1' => $ci_id, 'argv2' => $attribute_id } );
	
	return $count;
}

sub updateAttributeValueTextOfCi {
	my $ci_id = $_[0];
	my $attribute = $_[1];
	my $value = $_[2];
	my $attribute_id;
	my %params;
	
	#if number --> ID is given, otherwise the name is given
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute;
	} else {
		$attribute_id = callWebservice("query", "select_id_of_attribute_per_name", { 'argv1' => $attribute } );
	}
	
	my $attribute_count = countAttributesOfCi($ci_id, $attribute_id);
	
	if($attribute_count eq 0) { #INSERT
		%params = (	
			'argv1' => $ci_id,
			'argv2' => $attribute_id,
			'argv3' => $value,
			);	
		callWebservice("query", "insert_into_ci_attribute", \%params);
	} else { #UPDATE
		%params = (	
			'argv1' => $ci_id,
			'argv2' => $attribute_id,
			'argv3' => $value,
			);	
		callWebservice("query", "update_ci_attribute_value_text", \%params);
	}
	
}

sub createRelation {
	my $relation_type = $_[0];
	my $ci_id_1 = $_[1];
	my $ci_id_2 = $_[2];

	#my $relation_type_id = callWebservice("query", "select_relation_type_id", { 'argv1' => $relation_type } );
	
	my $relation_count = callWebservice("query", "get_count_of_specific_relation", { 'argv1' => $ci_id_1, 'argv2' => $ci_id_2, 'argv3' => $relation_type } );
	
	if($relation_count eq 0) {
		callWebservice("query", "insert_relation", { 'argv1' => $ci_id_1, 'argv2' => $ci_id_2, 'argv3' => $relation_type } );
	}
	
}

sub deleteRelation {
	my $relation_type = $_[0];
	my $ci_id_1 = $_[1];
	my $ci_id_2 = $_[2];

	callWebservice("query", "delete_single_relation", { 'argv1' => $ci_id_1, 'argv2' => $ci_id_2, 'argv3' => $relation_type } );
	
}

sub dateTimeStamp {
    my ($sec, $min, $hr, $day, $mon, $year) = localtime;
	my $stringDateTime = sprintf("%04d%02d%02d%02d%02d%02d", 1900 + $year, $mon + 1, $day, $hr, $min, $sec);
    return $stringDateTime;
}

sub UnixTimeToDateTime {
	my ( $UnixTimeStamp ) = @_;
	if(! $UnixTimeStamp ) {
		return;
	}

    return strftime('%F %H:%M:%S', localtime($UnixTimeStamp));
}

sub convertDecisionToGerman {
	my $value = $_[0];
	$value =~ s/Yes/Ja/gi;
	$value =~ s/No/Nein/gi;
	return $value;
}


1;