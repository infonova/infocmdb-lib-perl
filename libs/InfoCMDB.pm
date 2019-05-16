#!/usr/bin/perl
package InfoCMDB;

##########################
#
# Author: Christoph Mueller
# First Version: 10/2015
# Purpose: simplify usage of infoCMDB-API
#
##########################



use strict; 		# code tidy! 
use utf8; 			# use utf8 everywhere!!
use LWP::UserAgent; # make web calls
use Data::Dumper;	# for debugging
use YAML;			# read config files
use File::Spec;		# get path to X (configs, ...)
use URI::Escape;	# escape LWP request params
use Encode;			# encode notification params
use JSON;			# handle json response
use DateTime;		# date handler
use Date::Parse;    # parse date string to date object
use Log::Log4perl;  # logging utitly
use Scalar::Util qw(looks_like_number); # detect if id or name is given
use File::Basename; # Parse file paths into directory, filename and suffix. (Used for Attachment upload)
use File::Copy;		# Copy files or filehandles
use File::Path qw(make_path);

our $LOG_ERROR = 1;
our $LOG_OUT = 0;

# CREATE A NEW INSTANCE
# param 1: name of yaml-config located in etc/infoCMDB (without extension)
# return: self
#
# Example:
# my $cmdbname = InfoCMDB->new('configName');
sub new {
    my $class = shift;
	my $configName = $_[0];
	
	my ($volume, $directory, $file) = File::Spec->splitpath(__FILE__);
	
	my @info = caller(0);
	my $callerFilePath = $info[1];
	my ($callerVolume, $callerDirectory, $callerFile) = File::Spec->splitpath($callerFilePath);
	my $ua = LWP::UserAgent->new(
		keep_alive => 10,
	);

    my $self = {
		_file         => $callerFile,
		_logger       => undef,
		_etcPath      => $directory . '../etc/',
		_settings     => {
			'debug'               => 0,
			'CmdbBasePath'        => '',
			'logToConsole'        => 1,
			'logToFile'           => 1,
			'logfile'             => $directory . '../log/InfoCMDB.log',
			'logFormatConsole'    => '%d{ISO8601} | %6P | ' . $configName . ' | %5p | %m | %T %n',
			'logFormatFile'       => '%d{ISO8601} | %6P | ' . $configName . ' | %5p | %m | %T %n',
			'instanceName'        => $configName,
			'apikey'              => 0,
			'apiUser'             => undef,
			'apiPassword'         => undef,
			'apiUrl'              => '',
			'apiResponseFormat'   => 'json',
			'autoHistoryHandling' => 1
		},
		_ciHistoryIds => {},
		_ua           => $ua,
    };
    bless $self, $class;
	$self->loadConfig($configName.'.yml'); # overwrite settings
    return $self;
}


# LOGGER
# Utilty for logging messages to console or file depending on debug level
# return: instance of Log::Log4perl with initialized config depending on log settings
#
# Example:
# $cmdb->setDebug(1); # log only errors and warnings
# $cmdb->logger()->trace('My Trace Message');  # will be ignored
# $cmdb->logger()->debug('My Debug Message');  # will be ignored
# $cmdb->logger()->info('My Info Message');    # will be ignored
# $cmdb->logger()->warn('My Warning Message'); # will be logged
# $cmdb->logger()->error('My Error Message');  # will be logged
sub logger {
	my( $self, $params ) = @_;
	my %params;
	if($params ne undef) {
		%params = %{ $params };
	}

	if($self->{_logger} eq undef || $params{'forceInit'} eq 1) {
		my $logLevel;
		my $logCategory = 'InfoCMDB';

        if    ( $self->{_settings}{debug} eq 0 ) { $logLevel = 'ERROR'; }
        elsif ( $self->{_settings}{debug} eq 1 ) { $logLevel = 'WARN'; }
        elsif ( $self->{_settings}{debug} eq 2 ) { $logLevel = 'INFO'; }
        elsif ( $self->{_settings}{debug} eq 3 ) { $logLevel = 'DEBUG'; }
        elsif ( $self->{_settings}{debug} eq 4 ) { $logLevel = 'TRACE'; }
        else { $logLevel = 'ERROR'; }

		my %logOutputs;
		if($self->{_settings}{'logToConsole'} eq 1) {
			$logOutputs{$logCategory.'Screen'} = {
				'PerlModule' => 'Log::Log4perl::Appender::Screen',
				'options'    => {
					'stderr' => 0,
					'layout' => 'Log::Log4perl::Layout::PatternLayout',
					'layout.ConversionPattern' => $self->{_settings}{'logFormatConsole'}
				},
			};
		}

		if($self->{_settings}{'logToFile'} eq 1 && $self->{_settings}{'logfile'} ne '') {
			$logOutputs{$logCategory.'Logfile'} = {
				'PerlModule' => 'Log::Log4perl::Appender::File',
				'options'    => {
					'filename' => $self->{_settings}{'logfile'},
					'layout' => 'Log::Log4perl::Layout::PatternLayout',
					'layout.ConversionPattern' => $self->{_settings}{'logFormatFile'}
				},
			};
		}

		my $log4perlConf = "log4perl.category.".$logCategory." = ".$logLevel.", ".join(', ',keys(%logOutputs))."\n";

		foreach my $appenderName (keys(%logOutputs)) {
			$log4perlConf .= 'log4perl.appender.'.$appenderName.' = '. $logOutputs{$appenderName}{'PerlModule'} . "\n";

			foreach my $optionName (keys(%{ $logOutputs{$appenderName}{'options'} })) {
				$log4perlConf .= 'log4perl.appender.'.$appenderName.'.'.$optionName.' = '.$logOutputs{$appenderName}{'options'}{$optionName}."\n";
			}
		}

		Log::Log4perl::init( \$log4perlConf );

		$self->{_logger} = Log::Log4perl::get_logger($logCategory);

	}

	return $self->{_logger};
}


# GET ETC PATH
# return: String - absolute path of etc folder (configuration files for CMDB's)
#
# Example:
# my $etcPath = $cmdbname->getEtcPath();
sub getEtcPath {
    my( $self ) = @_;
    return $self->{_etcPath};
}


# LOAD CONFIG
# load config of file into object-property '_settings'
# return: self
sub loadConfig {
	my( $self, $configFile ) = @_;
	
	# step 1: open file
	open my $fh, '<', $self->getEtcPath() . $configFile 
	  or die "can't open config file '" . $self->getEtcPath() . $configFile . "': $!";

	# step 2: slurp file contents
	my $yml = do { local $/; <$fh> };

	# step 3: convert YAML 'stream' to perl hash ref
	my $config = Load($yml);
	
	$self->setSettings(%{ $config });
	#foreach my $conf (keys(%{ $config })) {
	#	$self->{_settings} = $config->{$conf};
	#}
	
	return $self;
}


# GET SETTINGS
# return: Hash - settings set by "setSettings"
#
# Example:
# my $settings = $cmdbname->getSettings();
sub getSettings {
	my( $self ) = @_;
	if(defined $self->{_settings}) {
		return $self->{_settings};
	}
	return {};
}


# SET SETTINGS
# set apikey and other settings which are needed for methods of this library
# return: self
#
# Example:
# $cmdbname->->setSettings('apikey' => 1234);
sub setSettings {
	my ( $self, %settings ) = @_;
	
	foreach my $settingName (keys(%{$self->{_settings}})) {
		if(defined $settings{$settingName} ) {
			$self->{_settings}{$settingName} = $settings{$settingName};
		}
	}

	$self->logger({'forceInit' => 1});
	
	return $self;
}


# GET DEBUG LEVEL
# return: integer - debugLevel
#
# Example:
# my $debugLevel = $cmdbname->getDebug();
sub getDebug {
	my( $self ) = @_;
	if(defined $self->{_settings}{debug}) {
		return $self->{_settings}{debug};
	}
	return {};
}


# SET DEBUG LEVEL
# choose the amount of data printed into console
# param 1: 
#   0 = no output 
#   1 = print minimal output
#   2 = print more output
#   3 = print even more output
#   4 ....
#
# return: self
#
# Example:
# $cmdbname->setDebug(1);
sub setDebug {
	my ( $self, $debugLevel ) = @_;
	if(defined $debugLevel and $debugLevel ne '') {
		$self->{_settings}{debug} = $debugLevel;
	} else {
		$self->{_settings}{debug} = 0;
	}

	$self->logger({'forceInit' => 1});

	return $self;
}


# LOG DEBUG
# print a message to the console if the debug level is high enough
# param 1: message to log
# param 2: log level of message
# param 3: boolean: is this an error?
# return: self
#
# Example:
# $cmdbname->logDebug('This is my message', 1);
sub logDebug {
	my ($self, $message, $logLevel, $isError) = @_;
	my $dLevel = $self->{_settings}{debug};
	my $today = DateTime->now(time_zone => 'local');

	if ($dLevel < $logLevel) {
		return;
	}

	my $logMessage = '';
	if ($dLevel eq 0) {
		$logMessage = $message . "\n";
	}
	elsif ($dLevel eq 1) {
		$logMessage = $today->dmy() . ' ' . $today->hms() . ': ' . $message . "\n";
	}
	else {
		$logMessage = $today->dmy() . ' ' . $today->hms() . ': ' . 'Function: ' . (caller(1))[3] . ' - ' . $message . "\n";
	}

	if($isError eq $LOG_ERROR) {
		print STDERR $logMessage;
	} else {
		print $logMessage;
	}

	return $self;
}


# GET FORMATTED DATE TIME
# returns date and time in readable format (e.g. 2015-11-22 12:02:11)
#
# Example:
# $cmdbname->getFormattedDateTime();
sub getFormattedDateTime {
	my $today = DateTime->now( time_zone=>'local' );
	return $today->ymd() . ' ' . $today->hms();
}


# GET SHORT DATE TIME
# returns date and time in short format (e.g. 20151122120211)
#
# Example:
# $cmdbname->getShortDateTime();
sub getShortDateTime {
	my $today = DateTime->now( time_zone=>'local' );
	return $today->year().$today->month().$today->day().$today->hour().$today->minute().$today->second();
}


# GET DATE OBJECT
# param 1: DateTime as string
# return DateTime Object
#
# Example:
# $cmdbname->getDateObject('2015-01-14 14:23:12');
# $cmdbname->getDateObject('2015-01-14');
sub getDateObject {
    my $self = $_[0];
    my $dateString = $_[1];
    
    my $epoch = str2time($dateString);
    my $datetime;
    if(defined $epoch) {
        $datetime = DateTime->from_epoch(time_zone => 'local', epoch => $epoch);
    } else {
        $datetime = DateTime->new(
            year      => 1970,
            month     => 1,
            day       => 1,
            hour      => 0,
            minute    => 0,
            second    => 0,
            time_zone => 'local',
        );
    }
    return $datetime;
}


# FORMAT FLOAT
# format to german human readable format: e.g. 2.11244335 --> 2,11
# param 1: float or integer or string with comma as decimal separator
# return string with comma as decimal separator and rounded to 2 decimal places
#
# Example:
# $cmdbname->formatFloat(2.144545); # 2,14
# $cmdbname->formatFloat(2); # 2,00
sub formatFloat {
    my $self = $_[0];
    my $value = $_[1];
    
    $value =~ s/,/\./g;
    $value = sprintf("%.2f", $value);
    
    $value =~ s/\./,/g;
    
    return $value;
}


# PRINT LOG
# print a message to the console or in a file
# param 1: message
# param 2: output "console" or file-path (if not given --> console)
# param 3: separator
# return: self
#
# Example:
# $cmdbname->printLog('This is my message', '/tmp/mylog.log');
# $cmdbname->printLog('This is my message', 'console';
sub printLog {
	my $self = $_[0];
	my $msg = $_[1];
	my $output = $_[2];
	my $separator = $_[3];

	# log this call also to our logfile
	my %settingsBackup = %{ $self->getSettings() };
	$self->setSettings('logToFile' => 1, 'logToConsole' => 0, 'debug' => 2);
	$self->logger()->info($msg);
	$self->setSettings(%settingsBackup);

	
	if($output eq '') {
		$output = 'console';
	}
	
	if($separator eq '') {
		$separator = '  |  ';
	}
	
	my $logLine = $self->getFormattedDateTime();
	
	if( lc(ref($msg)) eq 'array') {
		my $index = 0;
		foreach my $m ( @{ $msg } ) {
			$logLine .= $separator . $index . " => " . $m;
			$index++;
		}
		
	} elsif( lc(ref($msg)) eq 'hash') {
		my %msg = %{ $msg };
		foreach my $key (keys(%{ $msg })) {
			$logLine .= $separator . $key . " => " . $msg{$key};
		}
		
	} else {
		$logLine .= $separator . $msg;
	}
	$logLine .= "\n";
	
	if($output eq 'console') {
		print $logLine;
	} else {
		open(LOGF, ">> $output");
		print LOGF $logLine;
		close (LOGF);	
	}

}


# DEBUG CONTEXT
# get additional information of the current stacktrace (used for error messages)
# return: string - filename + line
#
# Example:
# $cmdbname->logDebug('My Message' . $cmdbname->debugContext(), 3 );
sub debugContext {
	return ' (' . (caller(1))[1] . ':' . (caller(1))[2] . ')';
}


# GET API KEY
# get apikey from object or request a new one
# return: string - apikey
#
# Example:
# $cmdbname->getApiKey();
sub getApiKey {
	my ( $self ) = @_;
	
	# get existing apikey
	if( defined($self->{_settings}->{apikey}) &&  $self->{_settings}->{apikey} ne '' &&  $self->{_settings}->{apikey} ne 0 ) {
		 return $self->{_settings}->{apikey}
	}
	
	# get a new apikey
	$self->logDebug('request new key for: '.$self->{_settings}->{instanceName}, 1);
	if( $self->{_settings}->{apiUser} ne '' ) {
		
		my $apiurl = $self->{_settings}->{apiUrl} . 'api/login' .
			'/username/' . $self->{_settings}->{apiUser} . 
			'/password/' . $self->{_settings}->{apiPassword} . 
			'/timout/21600' . # 6 hours
			'/method/json';

		my $ua = $self->{_ua};
		my $req = HTTP::Request->new(GET => $apiurl);
		my $res = $ua->request($req);
		
		if($res->status_line eq "202 Accepted" && $res->decoded_content =~ m/{"status":/ ) {
			my $resJSON = decode_json($res->decoded_content);
			$self->{_settings}->{apikey} = $resJSON->{'apikey'};
			$self->logDebug('new apikey: ' . $resJSON->{'apikey'}, 3);
			return $resJSON->{'apikey'};
		} else {
			$self->logDebug('error requesting new API key', 1);
			$self->logDebug($res->decoded_content, 2);
		}
	} else {
		$self->logDebug('no apiUsername given', 1);
	}
	
	return 0;
	
}


# CALL API
# make an api call to the configured CMDB
# param 1: url to call
# param 2: additonal parameter
# return: hash - response (errors, content, response)
sub callAPI {
	my ( $self, $url, $params ) = @_;
	my %params = %{ $params };
	my %response;
	my @errors = ();
	
	$self->logDebug('callAPI: '.$url, 3);
	$self->logDebug('Params: '. Dumper(\%params), 3);
	
	my $ua = $self->{_ua};
	my $res;
	my $req = HTTP::Request->new(POST => $url);

	my $content_string = '';
	while ( my ($key, $value) = each %params ) {
		if($key eq 'Recipients' && lc(ref($params{$key})) eq 'array') {
			$value = join(';', @{ $params{$key} });
		}
		if($url =~ /api\/notification/) { # cmdb notification api needs 'iso-8859-1' encoded params
			$content_string .= '&'.$key.'='.uri_escape(Encode::encode('iso-8859-1', $value));
		} else {
			$content_string .= '&'.$key.'='.uri_escape_utf8($value);
		}
	}
	$content_string =~ s/.//;#remove first &
	
	if($content_string ne '') {
		$req->header('Content-Type' => 'application/x-www-form-urlencoded');
		$req->content($content_string);
	}
	
	$res = $ua->request($req);#SEND!!!
	
	if($res->status_line ne "200 OK") {
		my $errMsg = sprintf('The webserver returned an error code: "%s" (URL: %s, Params: %s)', $res->status_line, $url, Dumper(\%params));
		$errMsg =~ s/\r?\n/ /g;
		push(@errors, $errMsg);
	}
	
	if($res->status_line eq "403 Forbidden") {
		push(@errors, 'invalid API-Key "' . $self->{_settings}{apikey} . '"');
	}
	
	$response{'response'} = $res;
	$response{'content'} = $res->decoded_content;
	$response{'errors'} = \@errors;
	
	$self->logDebug('Response: '. $response{'content'} , 4);
	
	return \%response;
}


# SEND NOTIFICATION
# param 1: name of notification in CMDB
# param 2: additional parameters
# return: Hash - response
#
# Example:
# my $cmdbname = InfoCMDB->new('cmdbname')->setSettings('apikey' => 1234);
# $cmdbname->sendNotification('server_notification_mail', {'Recipients' => ['firstname.lastname@example.com', 'firstname2.lastname2@example.com'], 'addParam' => 'CMDB'});
sub sendNotification {
	my ( $self, $name, $params ) = @_;
	
	$self->logDebug('sendNotification: ' . $name  . $self->debugContext(), 1);
	
	my $apiurl = $self->{_settings}->{apiUrl} . '/api/notification' .
			'/apikey/' . $self->getApiKey() . 
			'/notify/' . $name . 
			'/method/json';
	
	my $result = $self->callAPI($apiurl, $params);
	my @errors = @{ $result->{'errors'} };
	
	#print Dumper $result->{'content'};
	
	if( scalar(@errors) eq 0 ) {
		if( $result->{'content'} =~ m/{"status":/ ) {
			my $resJSON = decode_json($result->{'content'});
			
			if( $resJSON->{'status'} eq 'error' ) {
				push(@errors, $resJSON->{'message'});
			}
			
		} else {
			push(@errors, 'invalid JSON: "' . $result->{'content'} . '"');
		}
	}
	
	if( scalar(@errors) eq 0 ) {
		$result->{'status'} = 1;
	} else {
		$result->{'status'} = 0;
		$self->logDebug("sendNotification failed" . $self->debugContext() . ": \n    " . join("\n    ", @errors) , 0, $LOG_ERROR);
	}

	$result->{'errors'} = \@errors;

	return $result;
}


# CALL WEBSERVICE
# param 1: name of webservice in CMDB
# param 2: additional parameters
# param 3: array_ref of all signs that should be escaped. default:  ' (single quote)
# return: Hash - response
#
# Example:
# my $cmdbname = InfoCMDB->new('cmdbname')->setSettings('apikey' => 1234);
# $cmdbname->callWebservice('example_webservice', { 'argv1' => '192.168.1.1' })->{'content'};
sub callWebservice {
	my ( $self, $name, $params, $escape_signs ) = @_;
	
	$self->logDebug('callWebservice: ' . $name  . $self->debugContext(), 1);
	my $result = {};
	my @errors;
    
    
    my @signs_to_escape = ("'");
    if(defined $escape_signs) {
        @signs_to_escape = @{ $escape_signs };
    }
	
	my $apiurl = $self->{_settings}->{apiUrl} . '/api/adapter' .
			'/apikey/' . $self->getApiKey() . 
			'/query/' . $name . 
			'/method/' . $self->{_settings}->{apiResponseFormat};
			
	foreach my $key (keys(%{ $params })) {
		if($key !~ m/^argv/) {
			push(@errors, 'invalid webservice param "' . $key . '"');
		}
        foreach my $sign (@signs_to_escape) {
            $params->{$key} =~ s/$sign/\\$sign/g;
        }
	}
	
	if( scalar(@errors) eq 0 ) {
		$result = $self->callAPI($apiurl, $params);
		@errors = ( @errors, @{ $result->{'errors'} } );
		$result->{'untouchedContent'} = $result->{'content'};
		
	    if ( $self->{_settings}->{apiResponseFormat} eq 'json' ) {
	        if ( $result->{'content'} =~ m/^{"status":/ ) {
	            my $resJSON = decode_json( $result->{'content'} );
	            if ( $resJSON->{'status'} eq 'error' ) {
	                push( @errors, $resJSON->{'message'} );
	            }
	            $result->{'content'} = $resJSON->{'data'};
	        }
	        else {
	            push( @errors, 'invalid JSON: "' . $result->{'content'} . '"' );
	        }
	    }
	    elsif ( $self->{_settings}->{apiResponseFormat} eq 'xml' ) {
	        push( @errors,
	            'apiResponseFormat not yet implemented: "' . $self->{_settings}->{apiResponseFormat} . '"' );
	    }
	    elsif ( $self->{_settings}->{apiResponseFormat} eq 'plain' ) {
	        push( @errors,
	            'apiResponseFormat not yet implemented: "' . $self->{_settings}->{apiResponseFormat} . '"' );
	    }
	    else {
	        push( @errors, 'invalid  apiResponseFormat: "' . $self->{_settings}->{apiResponseFormat} . '"' );
	    }
	}

	
	if( scalar(@errors) eq 0 ) {
		$result->{'status'} = 1;
	} else {
		$result->{'status'} = 0;
		$self->logDebug("callWebservice failed" . $self->debugContext() . ": \n    " . join("\n    ", @errors) , 0, $LOG_ERROR);
	}

	$result->{'errors'} = \@errors;
	
	
	return $result;
}


# EXECUTE WORKFLOW
# param 1: name of workflow in CMDB
# param 2: additional parameters
# return: Hash - response
#
# Example:
# my $cmdbname = InfoCMDB->new('cmdbname')->setSettings('apikey' => 1234);
# $cmdbname->executeWorkflow('example_workflow', {})->{'content'};
sub executeWorkflow {
	my ( $self, $name, $params ) = @_;
	
	$self->logDebug('executeWorkflow: ' . $name  . $self->debugContext(), 1);
	
	my $apiurl = $self->{_settings}->{apiUrl} . '/api/adapter' .
			'/apikey/' . $self->getApiKey() . 
			'/workflow/' . $name . 
			'/method/json';
	
	my $result = $self->callAPI($apiurl, $params);
	my @errors = @{ $result->{'errors'} };
	
	if( $result->{'content'} =~ m/Workflow not found/ ) {
		push(@errors, 'Workflow with name "' . $name . '" not found!');
	}
	
	#print Dumper $result->{'content'};
	
	# currently always plain response
	# if( scalar(@errors) eq 0 ) {
		# if( $result->{'content'} =~ m/{"status":/ ) {
			# my $resJSON = decode_json($result->{'content'});
			
			# if( $resJSON->{'status'} eq 'error' ) {
				# push(@errors, $resJSON->{'message'});
			# }
			
		# } else {
			# push(@errors, 'invalid JSON: "' . $result->{'content'} . '"');
		# }
	# }
	
	if( scalar(@errors) eq 0 ) {
		$result->{'status'} = 1;
	} else {
		$result->{'status'} = 0;
		$self->logDebug("executeWorkflow failed" . $self->debugContext() . ": \n    " . join("\n    ", @errors) , 0, $LOG_ERROR);
	}

	$result->{'errors'} = \@errors;

	return $result;
}


# EXECUTE ATTRIBUTE SCRIPT
# param 1: name of attribute in CMDB
# param 2: additional parameters (ciid)
# return: Hash - response
#
# Example:
# my $cmdbname = InfoCMDB->new('cmdbname')->setSettings('apikey' => 1234);
# $cmdbname->executeAttributeScript('test_attribute', { 'ciid' => 12 })->{'content'};
sub executeAttributeScript {
	my ( $self, $name, $params ) = @_;
	
	$self->logDebug('executeAttributeScript: ' . $name  . $self->debugContext(), 1);
	my $result = {};
	my @errors;
	
	my $apiurl = $self->{_settings}->{apiUrl} . '/api/adapter' .
			'/apikey/' . $self->getApiKey() . 
			'/exec/' . $name . 
			'/method/json';
			
	
	$params->{'executable_attribute_name'} = $name;
	
	if(not defined($params->{'ciid'})) {
		push(@errors, 'parameter "ciid" is missing');
	}
	
	
	if( scalar(@errors) eq 0 ) {
		$result = $self->callAPI($apiurl, $params);
		@errors = ( @errors, @{ $result->{'errors'} } );
	
	}
	
	if( scalar(@errors) eq 0 ) {
		$result->{'status'} = 1;
	} else {
		$result->{'status'} = 0;
		$self->logDebug("executeAttributeScript failed" . $self->debugContext() . ": \n    " . join("\n    ", @errors) , 0, $LOG_ERROR);
	}

	$result->{'errors'} = \@errors;

	return $result;
}


# GET CI ID BY CI-ATTRIBUTE-ID
# param 1: ci_attribute-ID
# return response-hash
#
# Example:
# $cmdbname->getCiIdByCiAttributeId(232324);
sub getCiIdByCiAttributeId {
	my ( $self, $ci_attribute_id ) = @_;

    if( defined($ci_attribute_id) ) {
        my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
        my $result = '';
        
        my $response = $self->callWebservice('int_getCiIdByCiAttributeId', {'argv1' => $ci_attribute_id });
        
        if($response->{'status'} eq 1) {
            my @responseArray = @{ $response->{'content'} };
            if( scalar( @responseArray ) eq 1 ) {
                $result = $response->{'content'}->[0]->{'ci_id'};
            } else {
                $result = \@responseArray;
            }
        }
        
        $self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
        
        return $result;
    }
}


# GET CI ID BY CI-ATTRIBUTE VALUE-TEXT
# param 1: attribute (id or name)
# param 2: value in ci_attribute-table
# param 3: value_type (value_text/value_date/value_ci/value_default)
# param 4: return_always_array_ref (1 or 0, default: 0)
# return CI-ID or response-hash(multiple CI-ID's)
#
# Example:
# $cmdbname->getCiIdByCiAttributeValue('test_attribute', 'myvalue');
sub getCiIdByCiAttributeValue {
	my ( $self, $attribute, $value, $value_type, $return_always_array_ref ) = @_;
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	if(not defined($value_type)) {
		$value_type = 'value_text';
	}
    
    if(not defined($return_always_array_ref)) {
		$return_always_array_ref = 0;
	}

	my $result = '';
	
	my $response = $self->callWebservice('int_getCiIdByCiAttributeValue', {'argv1' => $attribute_id, 'argv2' => $value, 'argv3' => $value_type });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
        if($return_always_array_ref eq 1) {
            $result = \@responseArray;
        } else {
            if( scalar( @responseArray ) eq 1 ) {
                $result = $response->{'content'}->[0]->{'ci_id'};
            } elsif ( scalar( @responseArray ) eq 0 ) {
                $result = undef;
            }else {
                $result = \@responseArray;
            }
        }
	}	
	
	return $result;
}


# GET ATTRIBUTE ID BY ATTRIBUTE NAME
# param 1: name of attribute in CMDB
# param 2: print error if not found (1=print error, 0=no error)
# return: mixed - ID of attribute
#
# Example:
# $cmdbname->getAttributeIdByAttributeName('test_attribute');
sub getAttributeIdByAttributeName {
	my ( $self, $attribute_name, $showError) = @_;
	
	
	if( defined($self->{_attributeIds}{$attribute_name}) ) {
		return $self->{_attributeIds}{$attribute_name};
	}
	
	if(not defined($showError)) {
		$showError = 1;
	}
	
	$self->logDebug('get ID of attribute with name: ' . $attribute_name  . $self->debugContext(), 2);
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = "";
	my $response = $self->callWebservice('int_getAttributeIdByAttributeName', { 'argv1' => $attribute_name });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'id'};
		} else {
			$result = \@responseArray;
		}
	}
	
	if(scalar(@{$response->{'content'}}) eq 0) {
		if($showError eq 1) {
			$self->logDebug("attribute with name '".$attribute_name."' can't be found in CMDB!", 0);
		}
		$result = '';
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	$self->{_attributeIds}{$attribute_name} = $result;
	
	return $result;
	
}


# GET ATTRIBUTE VALUE FROM CI
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: column of ci_attribute-table
# param 4: type of return (string or array_ref)
# return: mixed - hash or string of the response
#
# Example:
# $cmdbname->getAttributeValueFromCi(1234, 'test_attribute', 'value_text');
sub getAttributeValueFromCi {
	my ( $self, $ci_id, $attribute, $value_type, $return_type ) = @_;
	
	$self->logDebug('get '.$value_type.' of attribute CIID('.$ci_id.'), attribute( '.$attribute.')'  . $self->debugContext(), 2);
	
	if((not defined($return_type)) || $return_type eq '') {
		$return_type = 'string';
	}
		
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	if((not defined($attribute_id)) || $attribute_id eq '') {
		return '';
	}
	
	my $result = '';
	$self->{_settings}->{apiResponseFormat} = 'json';
	
	my $response = $self->callWebservice('int_getCiAttributeValue', {'argv1' => $ci_id, 'argv2' => $attribute_id, 'argv3' => $value_type});
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( $return_type eq 'string' ) {
			if(scalar( @responseArray ) > 0) {
				$result = $response->{'content'}->[0]->{'v'};
			} else {
				$result = '';
			}
		} elsif( $return_type eq 'array_ref' ) {
			$result = \@responseArray;
		}
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	return $result;
	
}


# GET ATTRIBUTE VALUE TEXT FROM CI
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: type of return (string or array_ref)
# return: mixed - hash or string of the response
#
# Example:
# $cmdbname->getAttributeValueTextFromCi(1234, 'test_attribute');
sub getAttributeValueTextFromCi {
	my ( $self, $ci_id, $attribute, $return_type ) = @_;

	return $self->getAttributeValueFromCi($ci_id, $attribute, 'value_text', $return_type);
}


# GET ATTRIBUTE VALUE CI FROM CI
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: type of return (string or array_ref)
# return: mixed - hash or string of the response
#
# Example:
# $cmdbname->getAttributeValueCiFromCi(1234, 'test_attribute');
sub getAttributeValueCiFromCi {
	my ( $self, $ci_id, $attribute, $return_type ) = @_;

	return $self->getAttributeValueFromCi($ci_id, $attribute, 'value_ci', $return_type);
}

# GET ATTRIBUTE VALUE CI FROM Multiselect CI
# param 1: ci_id
# param 2: attribute(id or name)
# return: hash  with key = CIID value = counter
#
# Example:
# $cmdbname->getAttributeValueMultiselectCiFromCi(1234, 'test_attribute');
sub getAttributeValueMultiselectCiFromCi {
	my ( $self, $ci_id, $attribute) = @_;

	my %result; 

	my $response =  $self->getAttributeValueFromCi($ci_id, $attribute, 'value_ci');
	my @valueCiIds = split(',\s?', $response);

	foreach my $valueCiId (@valueCiIds){
		$valueCiId =~ s/^\s+|\s+$//g;
		
		if ($valueCiId =~ /::/){
			my ($ciId, $counter) = (split /::/, $valueCiId);
			$result{$ciId} = $counter;
		}
		else{
			$result{$valueCiId} = 1;
		}
	}
	return \%result;
}


# GET ATTRIBUTE VALUE DATE FROM CI
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: type of return (string or array_ref)
# return: mixed - hash or string of the response
#
# Example:
# $cmdbname->getAttributeValueCiFromCi(1234, 'test_attribute');
sub getAttributeValueDateFromCi {
	my ( $self, $ci_id, $attribute, $return_type ) = @_;

	return $self->getAttributeValueFromCi($ci_id, $attribute, 'value_date', $return_type);
}


# GET ATTRIBUTE VALUE DEFAULT FROM CI
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: value/id - return value or id of option (default: "value")
# param 4: type of return (string or array_ref)
# return: mixed - hash or string of the response
#
# Example:
# $cmdbname->getAttributeValueDefaultFromCi(1234, 'test_attribute', 'value');
sub getAttributeValueDefaultFromCi {
	my ( $self, $ci_id, $attribute, $resolve_type, $return_type ) = @_;
	if((not defined($resolve_type)) || $resolve_type eq 'value') {
		$return_type = 'string'; # force "string" if resolove_type "value" is given
		$resolve_type = 'value';
	}
	
	my $default_id = $self->getAttributeValueFromCi($ci_id, $attribute, 'value_default', $return_type);
	
	if($resolve_type eq 'value') {
		return $self->getAttributeDefaultOption($default_id);
	} else {
		return $default_id;
	}
	
}


# GET ATTRIBUTE DEFAULT OPTION
# param 1: option-ID of attribute_default_options
# return: mixed - hash or string of the response
#
# Example:
# $cmdbname->getAttributeDefaultOption(12);
sub getAttributeDefaultOption {
	my ( $self, $option_id ) = @_;
	
	if($option_id eq '' || (not defined($option_id)) || ref($option_id) eq 'ARRAY') {
		return '';
	}

    if( defined($self->{_attributeDefaultOptionValues}{$option_id}) ) {
        return $self->{_attributeDefaultOptionValues}{$option_id};
    }
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = '';
	
	my $response = $self->callWebservice('int_getAttributeDefaultOption', {'argv1' => $option_id});
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'v'};
            $self->{_attributeDefaultOptionValues}{$option_id} = $result;
		} else {
			$result = \@responseArray;
		}
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	return $result;
}


sub getAttributeDefaultOptionId {
	my ( $self, $attribute, $value ) = @_;
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = '';
	
	my $response = $self->callWebservice('int_getAttributeDefaultOptionId', {'argv1' => $attribute_id, 'argv2' => $value });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'id'};
		} else {
			$result = \@responseArray;
		}
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	return $result;
	
}


# GET NUMBER OF CI ATTRIBUTES
# get number of ci_attributes-rows for a specific ci and attribute
# param 1: ci_id
# param 2: attribute(id or name)
# return: integer - count
#
# Example:
# $cmdbname->getNumberOfCiAttributes(1234, 'test_attribute');
sub getNumberOfCiAttributes {
	my ( $self, $ci_id, $attribute ) = @_;
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = '';
	
	my $response = $self->callWebservice('int_getNumberOfCiAttributes', {'argv1' => $ci_id, 'argv2' => $attribute_id });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'v'};
		} else {
			$result = \@responseArray;
		}
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	return $result;
}


# CREATE HISTORY
# create a history id
# param 1: message for history-entry
# param 2: user_id for history
# return: integer - id of history entry
#
# Example:
# $cmdbname->createHistory('creating new history to combine', 23);
sub createHistory {
	my ( $self, $message, $user_id ) = @_;
	
	if(not defined($message)) {
		$message = 'Process ' . $self->{_file};
	}
	
	if(not defined($user_id)) {
		$user_id = 0;
	}
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = "";
	my $response = $self->callWebservice('int_createHistory', { 'argv1' => $user_id, 'argv2' => $message });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'v'};
		} else {
			$result = \@responseArray;
		}
	}
	
	if(scalar(@{$response->{'content'}}) eq 0) {
		$self->logDebug("creating History-ID failed!", 0);
		$result = '';
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	return $result;
}


# GET HISTORY ID FOR CI
# get the cached history id for a specific CI ( or create a new history id if 'autoHistoryHandling' is set to 1 )
# param 1: ci_id
# return: integer - id of history entry
#
# Example:
# $cmdbname->getHistoryIdForCi(1234);
sub getHistoryIdForCi {
	my ( $self, $ci_id ) = @_;
	
	if( defined($self->{_ciHistoryIds}{$ci_id}) ) {
		return $self->{_ciHistoryIds}{$ci_id};
	}
	
	# only generate history id if hisotry-handling is enabled
	if($self->{_settings}{'autoHistoryHandling'} ne 1) {
		return 0;
	}
	
	# create history id
	my $historyId = $self->createHistory();
	$self->{_ciHistoryIds}{$ci_id} = $historyId;
	
	return $historyId;
}


# SET HISTORY ID FOR CI
# set the cached history id for a specific CI
# param 1: ci_id
# param 2: history_id
# return self
#
# Example:
# $cmdbname->setHistoryIdForCi(1234, 332320);
sub setHistoryIdForCi {
	my ( $self, $ci_id, $historyId ) = @_;
	
	$self->{_ciHistoryIds}{$ci_id} = $historyId;

	return $self;
}

# CREATE CI ATTRIBUTE
# param 1: ci_id
# param 2: attribute(id or name)
# return ci_attribute - id
#
# Example:
# $cmdbname->createCiAttribute(1234, 'test_attribute');
sub createCiAttribute {
	my ( $self, $ci_id, $attribute, $history_id ) = @_;
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	if(not defined($history_id)) {
		$history_id = $self->getHistoryIdForCi($ci_id);
	}
	
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = '';
	
	my $response = $self->callWebservice('int_createCiAttribute', {'argv1' => $ci_id, 'argv2' => $attribute_id, 'argv3' => $history_id });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'v'};
		} else {
			$result = \@responseArray;
		}
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	return $result;
	
}

# GET Ci with all details and attributes
# param 1: ci_id
# return
# {
# 	id: 1,
# 	ci_type:
# 	ci_type_id:
# 	project: ["general",...],
# 	project_id: [1,...],
# 	attributes: {
# 		attribute_name: { # duplicted ci_attribute entries for attribute
# 			att_type: "value_text",
#			ci_attribute_ids: {
# 				ci_attribute_id: {
#					value(s): [],
#					modified_at:
#				},
# 				ci_attribute_id: {
#					value(s): [],
#					modified_at:
#				}
#	 		},
#		}
# 		attribute_name2: { # only 1 ci_attribute entry
# 			attribute_type: "value_text",
#			value: "text",
#			modified_at:
# 		}
# 	}
# 	attributeIdNames: {
# 		1: attribute_name,
# 		2: attribute_name2,
# 	},
#	created_at,
#	modified_at
# }
#
# Example:
# $cmdbname->getCi(1234);
sub getCi {
    my ( $self, @ci_id ) = @_;

    my $result           = $self->getCiDetails(@ci_id) or return;
    my %resultAttributes = $self->getCiAttributes(@ci_id);

    for my $ci (keys %{$result}) {
	        $result->{$ci}{'attributes'}        = $resultAttributes{'attributes'}{$ci};
	        $result->{$ci}{'attributesIdNames'} = $resultAttributes{'attributesIdNames'}{$ci};
    }
    if(scalar @ci_id eq 1) {
    	return $result->{$ci_id[0]};
    }

    return $result;
}

# GET Ci Basic Details
# param 1: ci_id
# return
# {
# 	id: 1,
# 	ci_type:
# 	ci_type_id:
# 	project: ["general",...],
# 	project_id: [1,...],
#	created_at,
#	modified_at
# }
#
# Example:
# $cmdbname->getCiDetails(1234);
sub getCiDetails {
    my ( $self, @ci_id ) = @_;
    # my %result_ci;
    my %result;

    my $response = $self->callWebservice( 'int_getCi', { 'argv1' => join( ',', @ci_id ) } );

    if ( $response->{'status'} eq 1 ) {
        my @responseArray = @{ $response->{'content'} };

        # can only have 1 return
        if ( scalar(@responseArray) gt 0 ) {
            for my $response (@responseArray) {
                my %result_ci = %{ $response };
                my $ci_id      = $result_ci{ci_id};
                my @projects   = split( /,/, $result_ci{'project'} );
                my @projectIds = split( /,/, $result_ci{'project_id'} );
                my %projectsHash;
                my %projectIdsHash;

                for ( 0 .. scalar @projects - 1 ) {
                    $projectIdsHash{ $projectIds[$_] } = $projects[$_];
                    $projectsHash{ $projects[$_] }     = $projectIds[$_];
                }

                $result_ci{project}    = \%projectsHash;
                $result_ci{projectIds} = \%projectIdsHash;
                $result{$ci_id} = \%result_ci;
            }
        }

        else {
            return '';
        }
    }

    return \%result;
}



# GET all Attributes for given Ci
# param 1: ci_id
# return
# {
# 	attributes: {
# 		attribute_name: { # duplicted ci_attribute entries for attribute
# 			att_type: "value_text",
#			ci_attribute_ids: {
# 				ci_attribute_id: {
#					value(s): [],
#					modified_at:
#				},
# 				ci_attribute_id: {
#					value(s): [],
#					modified_at:
#				}
#	 		},
#		}
# 		attribute_name2: { # only 1 ci_attribute entry
# 			attribute_type: "value_text",
#			value: "text",
#			modified_at:
# 		}
# 	}
# 	attributeIdNames: {
# 		1: attribute_name,
# 		2: attribute_name2,
# 	},
# }
#
# Example:
# $cmdbname->getCiAttributes(1234);
sub getCiAttributes {
    my ( $self, @ci_id ) = @_;

    my %result_Attributes;
    my %result_AttributeIdNames;

    my $response = $self->callWebservice( 'int_getCiAttributes', { 'argv1' => join(',', @ci_id) } );

    if ( $response->{'status'} eq 1 ) {
        my @responseArray = @{ $response->{'content'} };

        if ( scalar(@responseArray) gt 0 ) {
            for my $attribute (@responseArray) {

                $result_AttributeIdNames{$attribute->{'ci_id'}}{ $attribute->{'attribute_id'} } = $attribute;
                if ( !$result_Attributes{$attribute->{'ci_id'}}{ $attribute->{'attribute_name'} }
                    || ref $result_Attributes{$attribute->{'ci_id'}}{ $attribute->{'attribute_name'} } ne 'ARRAY' )
                {
                    $result_Attributes{$attribute->{'ci_id'}}{ $attribute->{'attribute_name'} } = [];
                }
                push @{ $result_Attributes{$attribute->{'ci_id'}}{ $attribute->{'attribute_name'} } }, $result_AttributeIdNames{$attribute->{'ci_id'}}{ $attribute->{'attribute_id'} };
            }

            # clean up arrays if only 1 value in hash

            #   'otrs_user_firstname' => [
            #                              {
            #                                'attribute_type' => 'input',
            #                                'attribute_name' => 'otrs_user_firstname',
            #                                'ci_attribute_id' => '5',
            #                                'value' => 'Test2',
            #                                'modified_at' => '2016-07-19 08:32:29',
            #                                'attribute_id' => '9'
            #                              }
            #                            ]
            # },
            #
            # <<<< becomes >>>>
            #
            #   'otrs_user_firstname' => {
            #                              'attribute_type' => 'input',
            #                              'attribute_name' => 'otrs_user_firstname',
            #                              'ci_attribute_id' => '5',
            #                              'value' => 'Test2',
            #                              'modified_at' => '2016-07-19 08:32:29',
            #                              'attribute_id' => '9'
            #                            }

            for my $ci ( @ci_id ) {
                for my $attributeGroup ( keys %{$result_Attributes{$ci}} ) {
                    if (   ref $result_Attributes{$ci}{$attributeGroup} eq 'ARRAY' 
                    	&& scalar( @{ $result_Attributes{$ci}{$attributeGroup} } ) eq 1 ) {
                        $result_Attributes{$ci}{$attributeGroup} = @{ $result_Attributes{$ci}{$attributeGroup} }[0];
                    }
                }
            }
        } else {
            return '';
        }
    }

    return (
        'attributes'        => \%result_Attributes,
        'attributesIdNames' => \%result_AttributeIdNames,
    );
}

# GET CI-ATTRIBUTE ID
# param 1: ci_id
# param 2: attribute(id or name)
# return ci_attribute - id
#
# Example:
# $cmdbname->getCiAttributeId(1234, 'test_attribute');
sub getCiAttributeId {
	my ( $self, $ci_id, $attribute ) = @_;
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = '';
	
	my $response = $self->callWebservice('int_getCiAttributeId', {'argv1' => $ci_id, 'argv2' => $attribute_id });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'id'};
		} else {
			$result = \@responseArray;
		}
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	return $result;
}


# UPDATE CI ATTRIBUTE
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: column of ci_attribute table
# param 4: value to set
# param 5: history_id for update
# param 6: ci_attribute-ID in the case there are multiple values with the same attribute_id
# return ci_attribute - id
#
# Example:
# $cmdbname->updateCiAttribute(1234, 'test_attribute', 'value_text', 'TEST');
sub updateCiAttribute {
	my ( $self, $ci_id, $attribute, $value_type, $value, $history_id, $ci_attribute_id ) = @_;
	
	if( not defined($ci_attribute_id) ) {
		my $attribute_id;
		if(looks_like_number($attribute)) {
			$attribute_id = $attribute; 
		} else {
			$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
		}
		$ci_attribute_id = $self->getCiAttributeId($ci_id, $attribute_id);
	}

	if((not defined($ci_attribute_id)) || ref($ci_attribute_id) eq 'ARRAY') {
		return undef;
	}
	
	if( not defined($history_id) ) {
		$history_id = $self->getHistoryIdForCi($ci_id);
	}
	
	my $response = $self->callWebservice('int_updateCiAttribute', {'argv1' => $ci_attribute_id, 'argv2' => $value_type, 'argv3' => $value, 'argv4' => $history_id });
	
	return $ci_attribute_id;
}


# SET CI ATTRIBUTE
# create OR update the value of an attribute for a ci (if an entry exists in the database)
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: column of ci_attribute table
# param 4: value to set
# param 5: history_id for update
# param 6: ci_attribute-ID in the case there are multiple values with the same attribute_id
# return ci_attribute - id
#
# Example:
# $cmdbname->updateCiAttribute(1234, 'test_attribute', 'value_text', 'TEST');
sub setCiAttributeValue {
	my ($self, $ci_id, $attribute, $value_type, $value, $history_id, $ci_attribute_id) = @_;

	my $attribute_id;
	if (looks_like_number($attribute)) {
		$attribute_id = $attribute;
	}
	else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute);
	}

	# fetch ci_attribute id (if exists)
	if (not defined($ci_attribute_id)) {
		my $result = $self->getCiAttributeId($ci_id, $attribute_id);
		if(ref($result) eq 'ARRAY') {
			my @ids = @{ $result };
			# skip if there exists more than one attribute
			if(scalar(@ids) > 0) {
				return;
			} else {
				$result = undef;
			}
		}

		# create ci_attribute - row if it does not exist
		if (not defined($result)) {
			$ci_attribute_id = $self->createCiAttribute($ci_id, $attribute_id);
		}
	}

	# update value
	return $self->updateCiAttribute($ci_id, $attribute_id, $value_type, $value, $history_id, $ci_attribute_id);
}


# SET CI ATTRIBUTE VALUE TEXT
# create OR update the value of an value_text-attribute for a ci (if an entry exists in the database)
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: value to set
# param 4: history_id for update
# param 5: ci_attribute-ID in the case there are multiple values with the same attribute_id
# return ci_attribute - id
#
# Example:
# $cmdbname->setCiAttributeValueText(1234, 'test_attribute', 'TEST');
sub setCiAttributeValueText {
	my ( $self, $ci_id, $attribute, $value, $history_id, $ci_attribute_id ) = @_;
	
	return $self->setCiAttributeValue($ci_id, $attribute, 'value_text', $value, $history_id, $ci_attribute_id);
}


# SET CI ATTRIBUTE VALUE DEFAULT
# create OR update the value of an value_default-attribute for a ci (if an entry exists in the database)
# param 1: ci_id
# param 2: attribute (id or name)
# param 3: value to set (option-id or text)
# param 4: history_id for update
# param 5: ci_attribute-ID in the case there are multiple values with the same attribute_id
# param 6: is value (param 3) an option-id --> default: 0
# return ci_attribute - id
#
# Example:
# $cmdbname->setCiAttributeValueDefault(1234, 'test_attribute', 'option 1');
sub setCiAttributeValueDefault {
	my ( $self, $ci_id, $attribute, $value, $history_id, $ci_attribute_id, $value_is_id ) = @_;
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	my $default_id;
	if( $value_is_id eq 1) {
		$default_id = $value;
	} else {
		$default_id = $self->getAttributeDefaultOptionId($attribute_id, $value);
	}
	
	return $self->setCiAttributeValue($ci_id, $attribute_id, 'value_default', $default_id, $history_id, $ci_attribute_id);
}


# SET CI ATTRIBUTE VALUE CI
# create OR update the value of an value_ci-attribute for a ci (if an entry exists in the database)
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: value to set
# param 4: history_id for update
# param 5: ci_attribute-ID in the case there are multiple values with the same attribute_id
# return ci_attribute - id
#
# Example:
# $cmdbname->setCiAttributeValueCi(1234, 'test_attribute', 5678);
sub setCiAttributeValueCi {
	my ( $self, $ci_id, $attribute, $value, $history_id, $ci_attribute_id ) = @_;
	
	return $self->setCiAttributeValue($ci_id, $attribute, 'value_ci', $value, $history_id, $ci_attribute_id);
}


# SET CI ATTRIBUTE VALUE DATE
# create OR update the value of an value_date-attribute for a ci (if an entry exists in the database)
# param 1: ci_id
# param 2: attribute(id or name)
# param 3: value to set
# param 4: history_id for update
# param 5: ci_attribute-ID in the case there are multiple values with the same attribute_id
# return ci_attribute - id
#
# Example:
# $cmdbname->setCiAttributeValueDate(1234, 'test_attribute', '2015-10-20 01:20:07');
sub setCiAttributeValueDate {
	my ( $self, $ci_id, $attribute, $value, $history_id, $ci_attribute_id ) = @_;
	
	return $self->setCiAttributeValue($ci_id, $attribute, 'value_date', $value, $history_id, $ci_attribute_id);
}


# DELETE CI ATTRIBUTE
# param 1: ci_attribute-ID
# param 2: history_id for delete
# return response-hash
#
# Example:
# $cmdbname->deleteCiAttribute(232324);
sub deleteCiAttribute {
	my ( $self, $ci_attribute_id, $history_id ) = @_;
    
    # if ci_attribute_id is scalar
    if(defined($ci_attribute_id) && ref($ci_attribute_id) eq '') {
        if( not defined($history_id) ) {
            my $ci_id = $self->getCiIdByCiAttributeId($ci_attribute_id);
            $history_id = $self->getHistoryIdForCi($ci_id);
        }
        
        my $response = $self->callWebservice('int_deleteCiAttribute', {'argv1' => $ci_attribute_id, 'argv2' => $history_id });
        
        return $response;
    }
    
    return 0;
}


# GET CI-TYPE ID BY CI-TYPE NAME
# param 1: name of ci-type in CMDB
# param 2: print error if not found (1=print error, 0=no error)
# return: mixed - ID of citype
#
# Example:
# $cmdbname->getCiTypeIdByCiTypeName('test_citype');
sub getCiTypeIdByCiTypeName {
	my ( $self, $citype_name, $showError) = @_;
	
	
	if( defined($self->{_ciTypeIds}{$citype_name}) ) {
		return $self->{_ciTypeIds}{$citype_name};
	}
	
	if( not defined ($showError) ) {
		$showError = 1;
	}
	
	$self->logDebug('get ID of citype with name: ' . $citype_name  . $self->debugContext(), 2);
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = "";
	my $response = $self->callWebservice('int_getCiTypeIdByCiTypeName', { 'argv1' => $citype_name });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'id'};
		} else {
			$result = \@responseArray;
		}
	}
	
	if(scalar(@{$response->{'content'}}) eq 0) {
		if($showError eq 1) {
			$self->logDebug("citype with name '".$citype_name."' can't be found in CMDB!", 0);
		}
		$result = '';
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	$self->{_ciTypeIds}{$citype_name} = $result;
	
	return $result;
	
}


# SET CI-TYPE OF CI
# param 1: ci_id
# param 2: citype(id or name)
# param 3: history_id for update (optional)
# return self
#
# Example:
# $cmdbname->setCiTypeOfCi(1234, 'test_citype');
sub setCiTypeOfCi {
	my ( $self, $ci_id, $ci_type, $history_id ) = @_;

	my $ci_type_id;
	if(looks_like_number($ci_type)) {
		$ci_type_id = $ci_type; 
	} else {
		$ci_type_id = $self->getCiTypeIdByCiTypeName($ci_type); 
	}
	
	if( not defined($history_id) ) {
		$history_id = $self->getHistoryIdForCi($ci_id);
	}
	
	my $response = $self->callWebservice('int_setCiTypeOfCi', {'argv1' => $ci_id, 'argv2' => $ci_type_id, 'argv3' => $history_id });
	
	return $self;
}


# GET CI-TYPE OF CI
# param 1: ci_id
# param 2: type of return value (id or name)
# return name of ci_type
#
# Example:
# $cmdbname->getCiTypeOfCi(1234);
sub getCiTypeOfCi {
	my ( $self, $ci_id, $return_type ) = @_;

    if( not defined($return_type) ) {
        $return_type = 'name';
    }
	
	my $response = $self->callWebservice('int_getCiTypeOfCi', {'argv1' => $ci_id, 'argv2' => $return_type });
    
    my $result = '';
    
    if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{$return_type};
		}
	}
	
	return $result;
}


# GET LIST OF CI-ID's OF CI-TYPE
# param 1: ci-type (name or ID)
# return: array - list of CI-ID's
#
# Example:
# $cmdbname->getListOfCiIdsOfCiType(3);
sub getListOfCiIdsOfCiType {
	my ( $self, $ci_type ) = @_;
	
	my $ci_type_id;
	if(looks_like_number($ci_type)) {
		$ci_type_id = $ci_type; 
	} else {
		$ci_type_id = $self->getCiTypeIdByCiTypeName($ci_type); 
	}
	
	my $response = $self->callWebservice('int_getListOfCiIdsOfCiType', {'argv1' => $ci_type_id });
	my @responseArray = @{ $response->{'content'} };
	
	my @ids;
	foreach my $res (@responseArray) {
		push(@ids, $res->{'ciid'});
	}
	
	return \@ids;
}


# GET LIST OF CI-ID's BY CI RELATION
# param 1: ci_id
# param 2: relation-type (id or name)
# param 3: mode (optional): all, directed_from, directed_to, bidirectional, omnidirectional
#
# Example: 
# $cmdbname->getListOfCiIdsByCiRelation(1234, 'relation_name');
# $cmdbname->getListOfCiIdsByCiRelation(1234, 'relation_name', 'directed_from'); # (ci_id_1 = 1234 and direction = 1) OR (ci_id_2 = 1234 and direction = 2) 
# $cmdbname->getListOfCiIdsByCiRelation(1234, 'relation_name', 'directed_to');   # (ci_id_2 = 1234 and direction = 1) OR (ci_id_1 = 1234 and direction = 2) 
sub getListOfCiIdsByCiRelation {
    my ($self, $ci_id, $ci_relation_type, $mode) = @_;

    my $ci_relation_type_id;
    if(looks_like_number($ci_relation_type)) {
        $ci_relation_type_id = $ci_relation_type;
    } else {
        $ci_relation_type_id = $self->getCiRelationTypeIdByRelationTypeName($ci_relation_type);
    }
    
    if( not defined($mode) ) {
        $mode = 'all';
    }
    
    my $response;
    my @responseArray = ();

    if ( $mode eq 'all' ) {
        $response = $self->callWebservice(
            "int_getListOfCiIdsByCiRelation_directionList",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id,
                'argv3' => '0,1,2,3,4'
            }
        );
    }
    elsif ( $mode eq 'directed_from' ) {
        $response = $self->callWebservice(
            "int_getListOfCiIdsByCiRelation_directedFrom",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id
            }
        );
    }
    elsif ( $mode eq 'directed_to' ) {
        $response = $self->callWebservice(
            "int_getListOfCiIdsByCiRelation_directedTo",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id
            }
        );
    }
    elsif ( $mode eq 'bidirectional' ) {
        $response = $self->callWebservice(
            "int_getListOfCiIdsByCiRelation_directionList",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id,
                'argv3' => '3'
            }
        );
    }
    elsif ( $mode eq 'omnidirectional' ) {
        $response = $self->callWebservice(
            "int_getListOfCiIdsByCiRelation_directionList",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id,
                'argv3' => '0,4'
            }
        );
    }
    else {
        $self->logDebug( "getListOfCiIdsByCiRelation failed: invalid mode '" . $mode . "'!", 0 );
        return \@responseArray;
    }

    
    @responseArray = @{ $response->{'content'} };
    
    my @ids;
	foreach my $res (@responseArray) {
		push(@ids, $res->{'ci_id'});
	}
	
	return \@ids;
}


# CREATE CI
# param 1: ci-type (name or ID)
# param 2: array reference of projects (name's or id's)
# param 3: history_id for insert
# param 4: icon
# return: hash with columns of new ci-row
#
# Example:
# $cmdbname->createCi('test_citype', ['test_project_1', 'test_project_2']);
sub createCi {
	my ( $self, $ci_type, $projects, $history_id, $icon ) = @_;
	
	my $ci_type_id;
	if(looks_like_number($ci_type)) {
		$ci_type_id = $ci_type; 
	} else {
		$ci_type_id = $self->getCiTypeIdByCiTypeName($ci_type); 
	}
	
	# only generate history id if history_id is not defined and hisotry-handling is enabled
	# if(not defined ($history_id) ) {
		# if($self->{_settings}{'autoHistoryHandling'} ne 1) {
			# create history id
			# $history_id = $self->createHistory();
		# } else {
			# $history_id = 0;
		# }
	# }
	$history_id = 0; # no history handling for "insert ci"
	
	if( not defined ($icon) ) {
		$icon = '';
	}
	
	my $response = $self->callWebservice('int_createCi', {'argv1' => $ci_type_id, 'argv2' => $icon, 'argv3' => $history_id })->{'content'}->[0];
	my $ci_id;
	if( defined($response) ) {
		$ci_id = $response->{'id'};
	}
	
	if( defined($ci_id) ) {
		foreach my $project (@{ $projects }) {
			$self->addCiProjectMapping($ci_id, $project);
		}
	}
	
	return $response;

}


# GET PROJECT-ID BY PROJECT NAME
# param 1: name of project in CMDB
# param 2: print error if not found (1=print error, 0=no error)
# return: mixed - ID of project
#
# Example:
# $cmdbname->getProjectIdByProjectName('test_project');
sub getProjectIdByProjectName {
	my ( $self, $project_name, $showError) = @_;
	
	
	if( defined($self->{_projectIds}{$project_name}) ) {
		return $self->{_projectIds}{$project_name};
	}
	
	if( not defined($showError) ) {
		$showError = 1;
	}
	
	$self->logDebug('get ID of project with name: ' . $project_name  . $self->debugContext(), 2);
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = "";
	my $response = $self->callWebservice('int_getProjectIdByProjectName', { 'argv1' => $project_name });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'id'};
		} else {
			$result = \@responseArray;
		}
	}
	
	if(scalar(@{$response->{'content'}}) eq 0) {
		if($showError eq 1) {
			$self->logDebug("project with name '".$project_name."' can't be found in CMDB!", 0);
		}
		$result = '';
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
	
	$self->{_projectIds}{$project_name} = $result;
	
	return $result;
	
}

# get Projects
# get project rows
# return: response-array
#
# Example:
# $cmdbname->getProjects();
sub getProjects {
    my ( $self ) = @_;

    my $response = $self->callWebservice('int_getProjects');
    my %ProjectsHash;
    foreach ( @{ $response->{'content'} } ) {
        $ProjectsHash{ $_->{id} } = $_->{name};
        $ProjectsHash{byName}{ $_->{name} } = $_->{id};
    }
    return %ProjectsHash;
}

# get CI-PROJECT MAPPING
# get ci-project rows
# param 1: ci_id
# param 2: [projectIds]
# param 3: optional [preserve projectIds] (won't be removed, but also not explizitly set)
# return: response-array
#
# Example:
# $cmdbname->setCiProjectMappings(1234, [2,'project_a'], ['general',3]);
sub setCiProjectMappings {
    my ( $self, $ci_id, $projectsToSet, $projectsToPreserve ) = @_;

    my %cmdbProjects           = $self->getProjects();
    my %projectsToSetHash      = map { $_ => $cmdbProjects{byName}->{$_} || $_ } @{$projectsToSet};
    my %projectsToPreserveHash = map { $_ => $cmdbProjects{byName}->{$_} || $_ } @{$projectsToPreserve};
    my %projectsKeepHash       = ( keys %projectsToSetHash, keys %projectsToPreserveHash );

    my $response = $self->callWebservice( 'int_getCiProjectMappings', { 'argv1' => $ci_id } );

    my %currentCiProjectsHash;
    foreach ( @{ $response->{'content'} } ) {
        $currentCiProjectsHash{ $_->{id} } = $_->{name};
        $currentCiProjectsHash{byName}{ $_->{name} } = $_->{id};
    }

    my %currentCiProjectIds = map { $_ => $_ } values( %{ $currentCiProjectsHash{byName} } );
    my @deleteProjects = keys %currentCiProjectIds;
    foreach ( grep( /\d+/, keys %currentCiProjectIds ) ) {
        if ( !$projectsKeepHash{$_} ) {
            $self->removeCiProjectMapping( $ci_id, $_ );
            delete $currentCiProjectIds{$_};
        }

        delete $projectsToSetHash{$_};
    }

    foreach ( keys %projectsToSetHash ) {
        $self->addCiProjectMapping( $ci_id, $_ );
    }

    return %currentCiProjectsHash;
}

# get CI-PROJECT MAPPING
# get ci-project rows
# param 1: ci_id
# return: response-array
#
# Example:
# $cmdbname->getCiProjectIdMappings(1234);
sub getCiProjectMappings {
    my ( $self, $ci_id ) = @_;

    my $response = $self->callWebservice( 'int_getCiProjectMappings', { 'argv1' => $ci_id } );
    my @responseArray = @{ $response->{'content'} };

    return @responseArray;
}

# ADD CI-PROJECT MAPPING
# add ci-project row if not already exists
# param 1: ci_id
# param 2: project (id or name)
# return: response-hash
#
# Example:
# $cmdbname->addCiProjectMapping(1234, 'test_project');
sub addCiProjectMapping {
	my ( $self, $ci_id, $project, $history_id ) = @_;
	
	my $project_id;
	if(looks_like_number($project)) {
		$project_id = $project; 
	} else {
		$project_id = $self->getProjectIdByProjectName($project); 
	}
	
	if( not defined($history_id) ) {
		$history_id = $self->getHistoryIdForCi($ci_id);
	}
	
	my $response = $self->callWebservice('int_addCiProjectMapping', {'argv1' => $ci_id, 'argv2' => $project_id, 'argv3' => $history_id })->{'content'};
	
	return $response;
}


# REMOVE CI-PROJECT MAPPING
# add ci-project row if not already exists
# param 1: ci_id
# param 2: project (id or name)
# return: response-hash
#
# Example:
# $cmdbname->addCiProjectMapping(1234, 'test_project');
sub removeCiProjectMapping {
	my ( $self, $ci_id, $project ) = @_;
	
	my $project_id;
	if(looks_like_number($project)) {
		$project_id = $project; 
	} else {
		$project_id = $self->getProjectIdByProjectName($project); 
	}
	
	my $response = $self->callWebservice('int_removeCiProjectMapping', {'argv1' => $ci_id, 'argv2' => $project_id})->{'content'};
	
	return $response;
}


# DELETE CI
# delete a CI with all dependencies
# param 1: ci_id
# param 2: history-message
# param 3: user (id or name)
# return: response-hash
#
# Example:
# $cmdbname->deleteCi(1234);
sub deleteCi {
    my ( $self, $ci_id, $message, $user ) = @_;
    
    if( not defined ($message) ) {
        $message = 'ci deleted';
    }
    
    $message = 'Process ' . $self->{_file} . ': ' . $message;
     
    my $user_id;
    if( not defined($user) ) {
        $user_id = $self->getUserIdByUsername($self->{_settings}->{apiUser});
    } else {
        if(looks_like_number($user)) {
            $user_id = $user; 
        } else {
            $user_id = $self->getUserIdByUsername($user); 
        }
    }
    
    my $response = $self->callWebservice('int_deleteCi', {'argv1' => $ci_id, 'argv2' => $user_id, 'argv3' => $message})->{'content'};
    
    return $response;
}


# GET USER-ID BY USERNAME
# param 1: username
# return: id of user
#
# Example:
# $cmdbname->getUserIdByUsername('username');
sub getUserIdByUsername {
    my ( $self, $username ) = @_;
    
    my $response = $self->callWebservice('int_getUserIdByUsername', {'argv1' => $username})->{'content'}->[0];
	my $user_id = 0;
	if(defined($response)) {
		$user_id = $response->{'id'};
	}
    
    return $user_id;
}


# CHECK IF CI RELATION EXISTS
# param 1: first  ci_id
# param 2: second ci_id
# param 3: relation-type (id or name)
#
# Example:
# $cmdbname->checkIfCiRelationExists(1234, 5678, 'relation_name');
sub checkIfCiRelationExists {
    my ( $self, $ci_id_1, $ci_id_2, $ci_relation_type) = @_;

    my $ci_relation_type_id;
    if(looks_like_number($ci_relation_type)) {
        $ci_relation_type_id = $ci_relation_type;
    } else {
        $ci_relation_type_id = $self->getCiRelationTypeIdByRelationTypeName($ci_relation_type);
    }
    
    my $relation_count = $self->callWebservice('int_getCiRelationCount', { 'argv1' => $ci_id_1, 'argv2' => $ci_id_2, 'argv3' => $ci_relation_type_id } )->{'content'}->[0]->{'c'};
    
    if($relation_count ne 0) {
        return 1;
    } else {
        return 0;
    }
}


# CREATE CI RELATION
# param 1: ci_id_1
# param 2: ci_id_2
# param 3: relation-type (id or name)
# param 4: direction: 1 = directed (ci_id_1 -> ci_id_2), 2 = directed (ci_id_2 -> ci_id_1), 3 = bidirectional, 4 = omnidirectional
#
# Example:
# $cmdbname->createCiRelation(1234, 5678, 'relation_name', 2);
sub createCiRelation {
	my ($self, $ci_id_1, $ci_id_2, $ci_relation_type, $direction) = @_;
	
    my $ci_relation_type_id;
    if(looks_like_number($ci_relation_type)) {
        $ci_relation_type_id = $ci_relation_type;
    } else	{
        $ci_relation_type_id = $self->getCiRelationTypeIdByRelationTypeName($ci_relation_type);
    }

    if( not defined ($direction) ) {
        $direction = 4;
    }
	
	if ($self->checkIfCiRelationExists($ci_id_1, $ci_id_2, $ci_relation_type_id) eq 0)	{
		my $response = $self->callWebservice('int_createCiRelation', { 'argv1' => $ci_id_1, 'argv2' => $ci_id_2, 'argv3' => $ci_relation_type_id, 'argv4' => $direction} );
		return $response;
	}
    
	return 0;
}

# DELETE CI RELATION
# param 1: ci_id_1
# param 2: ci_id_2
# param 3: relation-type (id or name)
#
# Example:
# $cmdbname->deleteCiRelation(1234, 5678, 'relation_name');
sub deleteCiRelation {
	my ($self, $ci_id_1, $ci_id_2, $ci_relation_type) = @_;
	
	my $ci_relation_type_id;
	
    if(looks_like_number($ci_relation_type)) {
        $ci_relation_type_id = $ci_relation_type;
    } else {
        $ci_relation_type_id = $self->getCiRelationTypeIdByRelationTypeName($ci_relation_type);
    }
	
    my $response = $self->callWebservice('int_deleteCiRelation', { 'argv1' => $ci_id_1, 'argv2' => $ci_id_2, 'argv3' => $ci_relation_type_id});
    
    return $response;
}

# DELETE CI RELATIONS BY CI RELATION TYPE
# delete all ci-relations with a specific relation-type of a specific CI
# param 1: ci_id
# param 2: relation-type (id or name)
# param 3: mode (optional): all, directed_from, directed_to, bidirectional, omnidirectional
#
# Example: 
# $cmdbname->deleteCiRelationsByCiRelationType(1234, 'relation_name');
# $cmdbname->deleteCiRelationsByCiRelationType(1234, 'relation_name', 'directed_from'); # (ci_id_1 = 1234 and direction = 1) OR (ci_id_2 = 1234 and direction = 2) 
# $cmdbname->deleteCiRelationsByCiRelationType(1234, 'relation_name', 'directed_to');   # (ci_id_2 = 1234 and direction = 1) OR (ci_id_1 = 1234 and direction = 2) 
sub deleteCiRelationsByCiRelationType {
    my ($self, $ci_id, $ci_relation_type, $mode) = @_;

    my $ci_relation_type_id;
    if(looks_like_number($ci_relation_type)) {
        $ci_relation_type_id = $ci_relation_type;
    } else {
        $ci_relation_type_id = $self->getCiRelationTypeIdByRelationTypeName($ci_relation_type);
    }
    
    if( not defined ($mode) ) {
        $mode = 'all';
    }
    
    my $response = 0;
    if ( $mode eq 'all' ) {
        $response = $self->callWebservice(
            "int_deleteCiRelationsByCiRelationType_directionList",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id,
                'argv3' => '0,1,2,3,4'
            }
        );
    }
    elsif ( $mode eq 'directed_from' ) {
        $response = $self->callWebservice(
            "int_deleteCiRelationsByCiRelationType_directedFrom",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id
            }
        );
    }
    elsif ( $mode eq 'directed_to' ) {
        $response = $self->callWebservice(
            "int_deleteCiRelationsByCiRelationType_directedTo",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id
            }
        );
    }
    elsif ( $mode eq 'bidirectional' ) {
        $response = $self->callWebservice(
            "int_deleteCiRelationsByCiRelationType_directionList",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id,
                'argv3' => '3'
            }
        );
    }
    elsif ( $mode eq 'omnidirectional' ) {
        $response = $self->callWebservice(
            "int_deleteCiRelationsByCiRelationType_directionList",
            {   'argv1' => $ci_id,
                'argv2' => $ci_relation_type_id,
                'argv3' => '0,4'
            }
        );
    }
    else {
        $self->logDebug( "deleteCiRelationsByCiRelationType failed: invalid mode '" . $mode . "'!",
            0 );
    }

    return $response;
}


# GET CI RELATION ID BY RELATION TYPE NAME
# param 1: relation-type name
# param 2: print error if not found (1=print error, 0=no error)
#
# Example:
# $cmdbname->getCiRelationTypeIdByRelationTypeName('relation_name');
sub getCiRelationTypeIdByRelationTypeName {
    my ($self, $relation_type_name, $showError) = @_;
    
    if( defined($self->{_ciRelationTypeIds}{$relation_type_name}) ) {
		return $self->{_ciRelationTypeIds}{$relation_type_name};
	}
     
	if( not defined ($showError) ) {
		$showError = 1;
	}
	
	$self->logDebug('get ID of ci-relation-type with name: ' . $relation_type_name  . $self->debugContext(), 2);
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = "";
	my $response = $self->callWebservice('int_getCiRelationTypeIdByRelationTypeName', { 'argv1' => $relation_type_name });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'id'};
		} else {
			$result = \@responseArray;
		}
	}
	
	if(scalar(@{$response->{'content'}}) eq 0) {
		if($showError eq 1) {
			$self->logDebug("ci-relation-type with name '".$relation_type_name."' can't be found in CMDB!", 0);
		}
		$result = '';
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
    
    $self->{_ciRelationTypeIds}{$relation_type_name} = $result;
	
	return $result;
}


# CREATE ATTRIBUTE-GROUP IF NOT EXISTS
# param 1: columns of attribute-group table as hash
# return: mixed - ID of attribute-group
#
# Example:
# $cmdbname->createAttributeGroupIfNotExists({ 
#     name => 'test_attribute_group, 
#     description => 'attribute description', 
#     order_number => 10
# });
sub createAttributeGroupIfNotExists {
	my $self = $_[0];
	my %Param = %{ $_[1] };
	
	my $attribute_group_id = $self->getAttributeGroupIdByAttributeGroupName($Param{'name'});
	
	if($attribute_group_id ne '') {
		return $attribute_group_id;
	}
	
	my %attributeGroup = (
		'name' => '',
		'description' => '',
		'note' => '',
		'order_number' => 0,
		'parent_attribute_group_id' => 0,
		'is_duplicate_allow' => '0',
		'is_active' => '1',
		'user_id' => 0
	);
	
	foreach my $key (keys(%attributeGroup)) {
		if( defined($Param{ $key }) ) {
			$attributeGroup{$key} = $Param{ $key };
		}
	}
	
	my $response = $self->callWebservice('int_createAttributeGroup', {
		'argv1' => join(', ', keys(%attributeGroup) ) ,
		'argv2' => "'".join("', '", values(%attributeGroup) )."'"
	}, []);
	
	if( defined($response->{'content'}->[0]) ) {
		return $response->{'content'}->[0]->{'id'};
	}
	return '';
	
}

# GET ATTRIBUTE-GROUP-ID BY ATTRIBUTE-GROUP-NAME
# param 1: attribute-group-name
# return: mixed - ID of attribute-group
#
# Example:
# $cmdbname->getAttributeGroupIdByAttributeGroupName('test_attribute_group');
sub getAttributeGroupIdByAttributeGroupName {
	my ( $self, $attribute_group_name ) = @_;
	
	my $response = $self->callWebservice('int_getAttributeGroupIdByAttributeGroupName', {'argv1' => $attribute_group_name });
	
	if( defined($response->{'content'}->[0]) ) {
		return $response->{'content'}->[0]->{'id'};
	}
	return '';
}


# CREATE ATTRIBUTE IF NOT EXISTS
# param 1: columns of attribute table as hash
# return: mixed - ID of attribute
#
# Example:
# $cmdbname->createAttributeIfNotExists({
#     'name' => 'test_attribute',
#     'description' => 'my attribute description',
#     'note' => 'my attribute note',
#     'attribute_type_id' => 1, #input text
#     'attribute_group_id' => 1,
#     'order_number' => 10
# });
sub createAttributeIfNotExists {
	my $self = $_[0];
	my %Param = %{ $_[1] };
	
	my $attribute_id = $self->getAttributeIdByAttributeName($Param{'name'}, 0);
	
	if($attribute_id ne '') {
		return $attribute_id;
	}
	
	my %attribute = (
		'name' => '',
		'description' => '',
		'note' => '',
		'hint' => '',
		'attribute_type_id' => 1,
		'attribute_group_id' => '',
		'order_number' => 0,
		'column' => 1,
		'is_unique' => '0',
		'is_numeric' => '0',
		'is_bold' => '0',
		'is_event' => '0',
		'is_unique_check' => '0',
		'is_autocomplete' => '0',
		'is_multiselect' => '0',
		'is_project_restricted' => '0',
		'regex' => '',
		'script_name' => '',
		'input_maxlength' => '',
		'textarea_cols' => '',
		'textarea_rows' => '',
		'is_active' => '1',
		'user_id' => 0,
		'historicize' => '1'
	);
	
	foreach my $key (keys(%attribute)) {
		if( defined($Param{ $key }) ) {
			$attribute{$key} = $Param{ $key };
		}
	}
	
	my $response = $self->callWebservice('int_createAttribute', {
		'argv1' => '`'.join('`, `', keys(%attribute) ) .'`',
		'argv2' => "'".join("', '", values(%attribute) )."'"
	}, []);
	
	if( defined($response->{'content'}->[0]) ) {
		my $attribute_id = $response->{'content'}->[0]->{'id'};
		$self->{_attributeIds}{ $attribute{'name'} } = $attribute_id;
		return $attribute_id;
	}
	return '';
	
}


# CREATE CI Type IF NOT EXISTS
# param 1: columns of attribute table as hash
# return: mixed - ID of attribute
#
# Example:
# $cmdbname->createCITypeIfNotExists({
#     'name' => 'test_ci_type',
#     'description' => 'my ci_type description',
#     'note' => 'my ci_type note',
#     'parent_ci_type_id' => 1
# });
sub createCITypeIfNotExists {
	my $self = $_[0];
	my %Param = %{ $_[1] };
	
	my $ci_type_id = $self->getCiTypeIdByCiTypeName($Param{'name'}, 0);
	
	if($ci_type_id ne '') {
		return $ci_type_id;
	}
	
	my %ci_type = (
		'name' => '',
		'description' => '',
		'note' => '',
		'parent_ci_type_id' => 0,
		'order_number' => 0,
		'create_button_description' => '',
		'icon' => '',
		'query' => "",
		'default_project_id' => '',
		'default_attribute_id' => 0,
		'default_sort_attribute_id' => 0,
		'is_default_sort_asc' => 0,
		'is_ci_attach' => 0,
		'is_attribute_attach' => 0,
		'tag' => '',
		'is_tab_enabled' => 0,
		'is_event_enabled' => 0,
		'is_active' => 1,
		'user_id' => 0
	);
	
	foreach my $key (keys(%ci_type)) {
		if( defined($Param{ $key }) ) {
			$ci_type{$key} = $Param{ $key };
		}
	}
	my @escape_sings = ();
	my $response = $self->callWebservice('int_createCIType', {
		'argv1' => '`'.join('`, `', keys(%ci_type) ) .'`',
		'argv2' => "'".join("', '", values(%ci_type) )."'"
	}, []);
	

	if( defined($response->{'content'}->[0]) ) {
		my $ci_type_id = $response->{'content'}->[0]->{'id'};
		$self->{_ciTypeIds}{ $ci_type{'name'} } = $ci_type_id;
		return $ci_type_id;
	}
	return '';
	
}

# UPDATE CI Type
# param 1: id or name of ci_type
# param 2: hash of fields => values to update
# return: success
#
# Example:
# $cmdbname->updateCIType(
# 		'name',
# 		{
# 			'query' => 'select 1 from;',
# 		}
# );

# $cmdbname->updateCIType(
# 		2,
#	 	{
#     		'query' => 'select 1 from;',
# 		}
# );
sub updateCIType {
	my $self = $_[0];
	my $ci_type_id =  $_[1];
	my %Param = %{ $_[2] };

	if(!looks_like_number($ci_type_id)){
		$ci_type_id = $self->getCiTypeIdByCiTypeName($Param{'name'}, 0);
	}

	if($ci_type_id eq '') {
		return 0;
	}

	my @updatePair;
	for my $p (keys(%Param)) {
		push @updatePair, sprintf('%s = "%s"', $p, $Param{$p});
	}
	my $response = $self->callWebservice('int_updateCiType', {
		'argv1' => $ci_type_id,
		'argv2' => join(", \n", @updatePair )
	}, []);

    return $response->{'status'};
}



# SET ATTRIBUTE ROLE
# param 1: attribute (id or name)
# param 2: role (id or name)
# param 3: permission      x -> no access    r ->  read access    r/w -> read and write access
# return: undef
#
# Example:
# $cmdbname->setAttributeRole('test_attribute', 'test_role', 'r/w');
sub setAttributeRole {
	my ( $self, $attribute, $role, $permission ) = @_;
	
	my $attribute_id;
	if(looks_like_number($attribute)) {
		$attribute_id = $attribute; 
	} else {
		$attribute_id = $self->getAttributeIdByAttributeName($attribute); 
	}
	
	my $role_id;
	if(looks_like_number($role)) {
		$role_id = $role; 
	} else {
		$role_id = $self->getRoleIdByRoleName($role); 
	}
	
	my $permission_read = 0;
	my $permission_write = 0;
	
	if($permission eq 'r') {
		$permission_read = 1;
		$permission_write = 0;
	} elsif($permission eq 'r/w' || $permission eq 'w') {
		$permission_read = 1;
		$permission_write = 1;
	}
	
	
	my $response = $self->callWebservice('int_setAttributeRole', { 'argv1' => $attribute_id, 'argv2' => $role_id, 'argv3' => $permission_read, 'argv4' => $permission_write });
	
}


# GET ROLE ID BY ROLE NAME
# param 1: name of role in CMDB
# param 2: print error if not found (1=print error, 0=no error)
# return: mixed - ID of role
#
# Example:
# $cmdbname->getRoleIdByRoleName('test_role');
sub getRoleIdByRoleName {
	my ( $self, $role_name, $showError) = @_;
    
    if( defined($self->{_roleIds}{$role_name}) ) {
		return $self->{_roleIds}{$role_name};
	}
	
	if( not defined ($showError) ) {
		$showError = 1;
	}
	
	$self->logDebug('get ID of role with name: ' . $role_name  . $self->debugContext(), 2);
	
	my $backupResponseFormat = $self->{_settings}->{apiResponseFormat};
	my $result = "";
	my $response = $self->callWebservice('int_getRoleIdByRoleName', { 'argv1' => $role_name });
	
	if($response->{'status'} eq 1) {
		my @responseArray = @{ $response->{'content'} };
		if( scalar( @responseArray ) eq 1 ) {
			$result = $response->{'content'}->[0]->{'id'};
		} else {
			$result = \@responseArray;
		}
	}
	
	if(scalar(@{$response->{'content'}}) eq 0) {
		if($showError eq 1) {
			$self->logDebug("role with name '".$role_name."' can't be found in CMDB!", 0);
		}
		$result = '';
	}
	
	$self->{_settings}->{apiResponseFormat} = $backupResponseFormat;
    
    $self->{_roleIds}{$role_name} = $result;
	
	return $result;
	
}

# SET ATTRIBUTE ATTACHMENT
# param 1: ci id
# param 2: attribute (id or name)
# param 3: filepath
# return: undef
#
# Example:
# $cmdbname->setCiAttributeAttachment(123, 'test_attribute', '/path/file');
sub setCiAttributeAttachment {
    my ( $self, $ciid, $attribute, $sourcefile ) = @_;

    my $attachmentpath   = $self->{_settings}->{CmdbBasePath} . '/public/_uploads/attachment';
    my $attachmentpathCi = $attachmentpath . '/' . $ciid;
    my $filename         = basename($sourcefile);
    my $destfile         = $attachmentpathCi . '/' . $filename;


    if ( !-e $sourcefile ) {
        $self->logDebug( 'Sourcefile doesn\'t exist! ' . $sourcefile . ' ' . $self->debugContext(), 0 );
        return 0;
    }

    if ( $self->{_settings}->{CmdbBasePath} =~ /^\s*$/ || !-d $self->{_settings}->{CmdbBasePath} ) {
        $self->logDebug( 'CmdbBasePath is not set! ' . $self->debugContext(), 0 );
        return 0;
    }

    if ( !-d $attachmentpath ) {
        $self->logDebug( 'Attachment Path doesn\'t exist! ' . $attachmentpath . ' ' . $self->debugContext(), 0 );
        return 0;
    }

    if ( $self->setCiAttributeValueText( $ciid, $attribute, $filename ) ) {
        # move file after attribute has been created
        make_path( $attachmentpathCi, { chmod => 0777 } );
        return move( $sourcefile, $destfile );
    }
    else {
        # handle attribute create error
        $self->logDebug(
            "failed to update attachment attribute [CiID: "
                . $ciid
                . ", Attribute: "
                . $attribute . '] '
                . $self->debugContext(),
            0
        );
        return 0;
    }

    return 1;
}




1;