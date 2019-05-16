#!/usr/bin/perl

package Database::Sybase;
use base Database;
use DBI;
use Data::Dumper;

##########################
#
# Author: Andreas Lohnauer
# First Version: 04/2019
# Purpose: centralize database logic
#
##########################

sub new {
    shift->SUPER::new(@_)
}

sub getConnection {
	my( $self ) = @_;
	if($self->{DBConnection} eq undef) {
	    my $dbDriver 	= $self->{_settings}{'database.driver'};
		my $dbHost 		= $self->{_settings}{'database.hostname'};
		my $dbUser 		= $self->{_settings}{'database.user'};
		my $dbPass 		= $self->{_settings}{'database.pass'};
		my $dbName 		= $self->{_settings}{'database.name'}; 
		my $charset     = $self->{_settings}{'database.charset'};
		
		my $connect_params = 'DBI:' . $dbDriver . ':server=' . $dbHost;
		if ($charset ne ''){
    		 $connect_params .= ';charset=' . $charset;
		}
		
		$self->{DBConnection} = DBI->connect($connect_params, $dbUser, $dbPass) or die "Unable to connect: $DBI::errstr\n";
		
		if ($dbName ne ''){
			$self->{DBConnection}->do("use $dbName");
		}
	}
	return $self->{DBConnection};
}

1;
