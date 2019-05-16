#!/usr/bin/perl
package AdvancedHashCache;

##########################
#
# Author: Christoph Mueller <christoph.mueller@infonova.com>
# First Version: 06/2017
# Purpose: Cache and Preload Data in memory
#
##########################


# EXAMPLE

#	use AdvancedHashCache;
#	use Data::Dumper;
#
#   my %baseModelPerson = (
#   	'firstname'	=> '',
#   	'lastname'	=> '',
#   	'email'		=> '',
#   );
#   
#   my $cache = AdvancedHashCache->new();
#   $cache->setDefaultNamespace('Namespace' => 'person');
#   $cache->setNamespaceBaseModel('Namespace' => 'person', 'BaseModel' => \%baseModelPerson);
#   $cache->setNamespaceValidation('Namespace' => 'person', 'Validation' => sub {
#   	my $value = $_[0];
#   
#   	my %return = (
#   		'result' 	=> 1,
#   		'message'	=> 'valid',
#   		'value'		=> $value,
#   	);
#   	
#   	if(!exists($value->{'email'}) or $value->{'email'} eq '') {
#   		%return = (
#   			'result' 	=> 0,
#   			'message'	=> 'Email needs to be set!',
#   			'value'		=> $value,
#   		);
#   	}
#   
#   	return \%return;
#   });
#   
#   # no error, data directly set
#   $cache->set('Key' => 1, 'Value' => {
#   	'firstname' => 'John',
#   	'lastname' 	=> 'Doe',
#   	'email' 	=> 'john.doe@example.com',
#   });
#   
#   # no error, firstname will be inherited from BaseModel
#   $cache->set('Key' => 1, 'Value' => {
#   	'lastname' 	=> 'Doe',
#   	'email' 	=> 'john.doe@example.com',
#   });
#   
#   # error, validation fails (email not set) and value will be not set
#   $cache->set('Key' => 1, 'Value' => {
#   	'firstname' => 'John',
#   	'lastname' 	=> 'Doe',
#   	'email' 	=> '',
#   });
#   
#   
#   # get stored value from cache
#   my $result = $cache->get('Key' => 1);
#   print Dumper $result;

#   # preload multiple values at once
#	my $persons = {
#		1	=> {
#			'firstname' => 'John',
#			'lastname'	=> 'Doe',
#			'email'		=> 'john.doe@example.com',
#		},
#		2	=> {
#			'firstname' => 'Max',
#			'lastname'	=> 'Mustermann',
#			'email'		=> 'max.mustermann@example.com',
#		},
#		3	=> {
#			'firstname' => 'Test',
#			'lastname'	=> 'AdvancedHashCache',
#			'email'		=> 'advanced@example.com',
#		},
#	};
#	
#	$cache->preload('Data' => $persons);
#	
#	my $persons = $cache->getNamespaceCache('Namespace' => 'person');
#	print Dumper $persons;



use strict; 				# code tidy! 
use utf8; 					# use utf8 everywhere!!
use Storable qw(dclone);	# clone hashes without references
use Data::Dumper;			# for debugging



sub new {
    my $class = shift;
		
    my $Self = {
		_cache     				=> {}, 			# store data --> _cache->{ namespace-name }{ key-name } = value
		_alias					=> {},			# store one or more alias for a cache key
		_default_namespace 		=> 'default',	# default namespace
		_namespace_base_model	=> {}, 			# base model for every value in namespace
		_namespace_validation 	=> {}, 			# validation functions for namespace values
    };
    bless $Self, $class;

    return $Self;
}

sub get {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Key');
	my @optionalParams = ('Namespace');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);

	my $namespace = $Self->{_default_namespace};
	if(exists($Params{'Namespace'})) {
		$namespace = $Params{'Namespace'};
	}

	if(exists($Self->{_cache}{ $namespace }{ $Params{'Key'} })) {
		return dclone($Self->{_cache}{ $namespace }{ $Params{'Key'} });
	}

	if(exists($Self->{_alias}{ $namespace }{ $Params{'Key'} })) {
		my $keyAlias = $Self->{_alias}{ $namespace }{ $Params{'Key'} };
		return dclone($Self->{_cache}{ $namespace }{ $keyAlias });
	}

	return undef;
}

sub set {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Key', 'Value');
	my %optionalParams = ('Namespace');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);

	my $namespace = $Self->{_default_namespace};
	if(exists($Params{'Namespace'})) {
		$namespace = $Params{'Namespace'};
	}

	my %value;
	if(exists($Self->{_namespace_base_model}{ $namespace })) {
		%value = %{ dclone($Self->{_namespace_base_model}{ $namespace }) };

		foreach my $key (keys(%{ $Params{'Value'} })) {
			$value{ $key } = $Params{'Value'}->{$key};
		}

	} else {
		%value = %{ dclone($Params{'Value'}) };
	}


	if(exists($Self->{_namespace_validation}{ $namespace })) {

		my $validation = $Self->{_namespace_validation}{ $namespace }->(\%value);

		if($validation->{'result'} eq 1) {
			$Self->{_cache}{ $namespace }{ $Params{'Key'} } = \%value;	
		} else {
			return $validation;
		}

	} else {
		$Self->{_cache}{ $namespace }{ $Params{'Key'} } = \%value;
	}

	return 1;

}

sub remove {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Key');
	my %optionalParams = ('Namespace');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);

	my $namespace = $Self->{_default_namespace};
	if(exists($Params{'Namespace'})) {
		$namespace = $Params{'Namespace'};
	}

	delete($Self->{_cache}{ $namespace }{ $Params{'Key'} });

	return 1;
}

sub setAlias {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Key', 'KeyAlias');
	my %optionalParams = ('Namespace');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);

	my $namespace = $Self->{_default_namespace};
	if(exists($Params{'Namespace'})) {
		$namespace = $Params{'Namespace'};
	}

	$Self->{_alias}{ $namespace }{ $Params{'KeyAlias'} } 		= $Params{'Key'};

	return 1;
}

sub unsetAlias {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('KeyAlias');
	my %optionalParams = ('Namespace');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);

	my $namespace = $Self->{_default_namespace};
	if(exists($Params{'Namespace'})) {
		$namespace = $Params{'Namespace'};
	}

	delete($Self->{_alias}{ $namespace }{ $Params{'KeyAlias'} });

	return 1;
}

sub setDefaultNamespace {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Namespace');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);	

	$Self->{_default_namespace} = $Params{'Namespace'};
}

sub setNamespaceBaseModel {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Namespace', 'BaseModel');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);	

	$Self->{_namespace_base_model}{ $Params{'Namespace'} } = $Params{'BaseModel'};
}

sub setNamespaceValidation {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Namespace', 'Validation');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);	

	$Self->{_namespace_validation}{ $Params{'Namespace'} } = $Params{'Validation'};
}

sub clear {
	my ( $Self, %Params ) = @_;

	$Self->{_cache} = {};

	return 1;
}

sub getNamespaces {
	my ( $Self, %Params ) = @_;

	return keys(%{ $Self->{_cache} });
}

sub getNamespaceModels {
	my ( $Self, %Params ) = @_;

	return $Self->{_namespace_base_model};
}

sub getNamespaceCache {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Namespace');

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);	

	return $Self->{_cache}{ $Params{'Namespace'} };	
}

sub preload {
	my ( $Self, %Params ) = @_;
	my @requiredParams = ('Data');
	my %optionalParams = ('Namespace');

	my %return = (
		'result'	=> 1,
	);
	my %detailedResult;

	$Self->hasRequiredParams(RequiredParams => \@requiredParams, Params => \%Params);

	my $namespace = $Self->{_default_namespace};
	if(exists($Params{'Namespace'})) {
		$namespace = $Params{'Namespace'};
	}

	my %data = %{ $Params{'Data'} };

	foreach my $key (keys(%data)) {
		my $detail = $Self->set('Key' => $key, 'Value' => $data{ $key });
		if($detail ne 1) {
			$return{ 'result' } = 0;
		}
		$detailedResult{ $key } = $detail;
	}

	$return{ 'detail' } = \%detailedResult;

	return \%return;
}


sub hasRequiredParams {
	my ( $Self, %Params ) = @_;	

	my @requiredParams 	= @{ $Params{'RequiredParams'} };
	my %givenParams 	= %{ $Params{'Params'} };

	for my $needed (@requiredParams) {
        if ( !defined $givenParams{ $needed } ) {
            die( getSubName(2).': Missing required param: "' . $needed . '"' );
        }
    }

    return 1;
}


sub getSubName {
	my $level = $_[0];
	if($level eq undef) {
		$level = 1;
	}

	my $sub = (caller($level))[3];
	$sub =~ s/^.*?:://g;

	if($sub eq undef) {
		$sub = '';
	}

	return $sub;
}


1;