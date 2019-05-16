#!/usr/bin/perl

##########################
#
# Author: Christoph Mueller
# First Version: 03/2016
# Purpose: Kitchen Sink - shows usage of InfoCMDB Perl Module
#
##########################

use strict; 		# code tidy! 
use utf8;           # use utf8 everywhere!!
use Data::Dumper;   # makes debugging easier
use lib "/app/perl/libs/";
use InfoCMDB;       # infoCMDB-API 

#initialize lib with config 'CMDB_Name'
# Configurations reside in:
# <infocmdb-lib-perl>/etc/<CMDB_Name>.yml
#
my $cmdb = InfoCMDB->new('CMDB_Name');


# # # # # # #
#  GENERAL  #
# # # # # # #

print Dumper $cmdb->printLog('This is my message', '/tmp/mylog.log'); # print to file
print Dumper $cmdb->printLog('This is my message'); # print to console

print Dumper $cmdb->formatFloat(2.144545); # 2,14
print Dumper $cmdb->formatFloat(2); # 2,00


# # # # # # # # # # #
#  ADVANCED LOGGING #
# # # # # # # # # # #

# The Debug Level defines how much should be logged
# Levels:
#   0 --> ERROR
#   1 --> WARN
#   2 --> INFO
#   3 --> DEBUG
#   4 --> TRACE
$cmdb->setDebug(3); # log errors, warnings, info-messages and debug-messages but no trace-messages
$cmdb->setDebug(1); # log only errors and warnings


$cmdb->setSettings({
	'logToConsole' => 1, # show messages in console if debug level is appropriate [default: 1]
	'logToFile'	   => 1, # log messages into a logfile if debug level is appropriate [default: 1]
	'logfile' 	   => 'pathToMylog.log', # write messages into given logfile [default: /opt/infoCMDB/perl/log/InfoCMDB.log]
});

# Example
$cmdb->setDebug(1); # log only errors and warnings
$cmdb->logger()->trace('My Trace Message');  # will be ignored
$cmdb->logger()->debug('My Debug Message');  # will be ignored
$cmdb->logger()->info('My Info Message');    # will be ignored
$cmdb->logger()->warn('My Warning Message'); # will be logged
$cmdb->logger()->error('My Error Message');  # will be logged

# Logfile /opt/infoCMDB/perl/log/InfoCMDB.log and console will show something like:
2016-09-27 10:56:13,290 | 13736 | cmdb | WARN | My Warning Message | at ./test.pl line 16. 
2016-09-27 10:56:13,291 | 13736 | cmdb | ERROR | My Error Message | at ./test.pl line 17. 


# # # # # # # # #
#  JSON         #
# # # # # # # # #

use JSON;
my $args = decode_json($ARGV[0]);
my $ci_id = $args->{'ciid'};
if($ci_id eq '') {
	$ci_id = $args->{':argv1:'};
}

# # # # # # # # #
#  DATE & TIME  #
# # # # # # # # #

print Dumper $cmdb->getFormattedDateTime(); # 2015-11-22 12:02:11
print Dumper $cmdb->getShortDateTime(); # 20151122120211
print Dumper $cmdb->getDateObject('2015-11-22 12:02:11'); # DateTime-Object
print Dumper $cmdb->getDateObject('2015-11-22'); # DateTime-Object


# # # # # # # # # 
#  INFOCMDB-API #
# # # # # # # # #

###### GETTING CI DETAILS ######
print Dumper $cmdb->getCi(1234); # retrieve everything for ciId 1234
print Dumper $cmdb->getCiDetails(1234); # retrieve basic ci details for ciId 1234
print Dumper $cmdb->getCiAttributes(1234); # retrieve all attributes for a ciId 1234

my @cis = (1234, 432, 2, 6);
print Dumper $cmdb->getCi(@cis); # retrieve everything for ciId 1234, 432, 2, 6 
print Dumper $cmdb->getCi(1234, 432, 2, 6); # retrieve everything for ciId 1234, 432, 2, 6 
print Dumper $cmdb->getCiDetails(1234, 432, 2, 6); # retrieve basic ci details for ciId 1234, 432, 2, 6
print Dumper $cmdb->getCiAttributes(1234, 432, 2, 6); # retrieve all attributes for a ciId 1234, 432, 2, 6

###### GETTING VALUES ######
print Dumper $cmdb->getCiIdByCiAttributeValue('test_attribute', 'myvalue'); # returns ID of CI where the value of 'test_attribute' is 'myvalue'
print Dumper $cmdb->getNumberOfCiAttributes(1234, 'test_attribute'); # returns how often 'test_attribute' is set for CI with ID 1234

print Dumper $cmdb->getAttributeValueTextFromCi(1234, 'test_attribute'); # return value of 'test_attribute' of CI with ID 1234 if the value-type is text (Input, Textarea, ...)
print Dumper $cmdb->getAttributeValueCiFromCi(1234, 'test_attribute'); # return value of 'test_attribute' of CI with ID 1234 if the value-type is a CIID (Dropdown CI-Type, ...)
print Dumper $cmdb->getAttributeValueDateFromCi(1234, 'test_attribute'); # return value of 'test_attribute' of CI with ID 1234 if the value-type is date (Date, Date and Time)
print Dumper $cmdb->getAttributeValueDefaultFromCi(1234, 'test_attribute'); # return value of 'test_attribute' of CI with ID 1234 if the value-type is default-values (Dropdown with static values, ...)

print Dumper $cmdb->getCiTypeOfCi(1234); # get the name of the current CI-Type

print Dumper $cmdb->getListOfCiIdsOfCiType('test_citype'); # retruns a list of all CI-ID's with the CI-Type 'test_citype'

###### SETTING VALUES ######
print Dumper $cmdb->setCiAttributeValueText(1234, 'test_attribute', 'TEST'); # set value of 'test_attribute' to value 'TEST' for CIID 1234 (text-values)
print Dumper $cmdb->setCiAttributeValueDefault(1234, 'test_attribute', 'option 1'); # set value of 'test_attribute' to option 'option 1' for CIID 1234 (default-values)
print Dumper $cmdb->setCiAttributeValueCi(1234, 'test_attribute', 5678); # set value of 'test_attribute' to CI with ID '5678' for CIID 1234 (ci-values)
print Dumper $cmdb->setCiAttributeValueDate(1234, 'test_attribute', '2015-10-20 01:20:07'); # set value of 'test_attribute' to value '2015-10-20 01:20:07' for CIID 1234 (date-values)

print Dumper $cmdb->setCiTypeOfCi(1234, 'test_citype'); # move CI with id 1234 to CI-Type with name 'test_citype'

###### AUTOMATISATION ######

# send notification template with name "my_template" to Recipients and replace ":placeholder_in_template:" with "myvalue" in mailtext
# possible parameters:
#	* 	subject -> if set, subject will be replaced with this
#	* 	meetingrequest -> if set to 1, a meeting invitation will be created
#	* 	Organizername -> name of the organizer of the meeting
#	* 	Organizermail -> mail address of the organizer of the meeting
#	* 	Meetingstart -> start of the meeting in format d.m.Y H:i
#	* 	Meetingduration -> duration of the meeting in seconds
#	* 	Meetinglocation -> location of the meeting
#	* 	From -> mail address of sender
#	* 	FromName -> description of sender(e.g. firstname and lastname)
#	* 	Recipients -> recipients of the mail, separated by the ";" sign
#	* 	RecipientsCC -> cc-recipients of the mail, separated by the ";" sign
#	*	RecipientsBCC -> bcc-recipients of the mail, separated by the ";" sign
#	* 	Attachments -> path to a file on server that should be attached to the mail
print Dumper $cmdb->sendNotification('my_template', {'Recipients' => ['firstname.lastname@example.com', 'firstname2.lastname2@example.com'], 'placeholder_in_tempalte' => 'myvalue'});

# call webservice with name "my_webservice" and replace ":argv1:" with "first_param". On success: return result (content) of query.
print Dumper $cmdb->callWebservice('my_webservice', { 'argv1' => 'first_param' })->{'content'};

# execute worklfow with name "my_workflow" and passing "first_param" as first parameter. On success: return output (content) of workflow.
print Dumper $cmdb->executeWorkflow('my_workflow', {'argv1' => 'first_param'})->{'content'};

# simulate a click on the link of attribute "my_attribute" of ci with ID 12. On success: return last line of output (content) of script.
print Dumper $cmdb->executeAttributeScript('my_attribute', { 'ciid' => 12 })->{'content'};

