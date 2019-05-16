#!/usr/bin/perl
package Database;

##########################
#
# Author: Christoph Mueller
# First Version: 03/2017
# Purpose: centralize database logic
#
##########################


use strict; 		# code tidy! 
use utf8; 			# use utf8 everywhere!!
use Data::Dumper;	# for debugging
use YAML;			# read config files
use File::Spec;		# get path to X (configs, ...)



# CREATE A NEW INSTANCE
# param 1: name of yaml-config located in etc (without extension)
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
	
    my $self = {
		_file     => $callerFile,
		_etcPath  => $directory.'../etc/',
		_settings => {
			'instance_name' 	=> $configName,
			'database.driver'	=> undef,
			'database.port'		=> undef,
			'database.hostname'	=> undef,
			'database.user'		=> undef,
			'database.pass'		=> undef,
			'database.name'		=> undef,
			'database.sid'		=> undef,
			'database.charset'  => undef
		},
		DBConnection => undef,
    };
    bless $self, $class;
	$self->loadConfig($configName.'.yml'); # overwrite settings
    return $self;
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
	
	return $self;
}


sub getConnection {
	my( $self ) = @_;

	return undef;
}


1;