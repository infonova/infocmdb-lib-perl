#!/usr/bin/perl
package InfoCMDB::MailImport;

##########################
#
# Author: Christoph Mueller
# First Version: 05/2016
# Purpose: Mail Handler Functions
#
##########################



use strict; 		# code tidy! 
use utf8; 			# use utf8 everywhere!!
use Data::Dumper;	# for debugging
use InfoCMDB;       # lib for handling InfoCMDB-API


sub InfoCMDB::getMailImportCi {
    my $cmdb = shift;
    my $ci_id = $_[0];
    my %element = (
        'name' => $cmdb->getAttributeValueTextFromCi($ci_id, 'mail_import_name'),
        'action' => $cmdb->getAttributeValueDefaultFromCi($ci_id, 'mail_import_action'),
        'status' => $cmdb->getAttributeValueDefaultFromCi($ci_id, 'mail_import_status'),
        'import_date' => $cmdb->getAttributeValueDateFromCi($ci_id, 'mail_import_date'),
        'files' => $cmdb->getAttributeValueTextFromCi($ci_id, 'mail_import_file', 'array_ref'),
    );
    
    for(my $i=1; $i <= 100; $i++) {
        my $attribute_exists = $cmdb->getAttributeIdByAttributeName('mail_import_data_'.$i.'_name', 0);
        if($attribute_exists eq '') {
            last;
        }
        
        my $data_name = $cmdb->getAttributeValueTextFromCi($ci_id, 'mail_import_data_'.$i.'_name');
        my $data_value = $cmdb->getAttributeValueTextFromCi($ci_id, 'mail_import_data_'.$i.'_value');
        
        if($data_name ne '') {
            $element{'data'}{$data_name} = $data_value;
        }
    }
    
    
    return \%element;
}

1;