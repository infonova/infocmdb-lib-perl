# InfoCMDB API Wrapper for PERL

To simplify the creation of workflows for the InfoCMDB API we created this module to abstract interactions.

## Installation

## Structure


## Configuration

YAML configurations are used to define the credentials for the API.

> /etc/<cmdb_name>.yml
```yaml
apiUrl: http://<hostname>/
apiUser: ext_webservice
apiPassword: xyz
autoHistoryHandling: 1
CmdbBasePath: /app/
```
## Example

```perl
#!/usr/bin/perl
use strict 
use utf8
use Data::Dumper
use lib "/app/perl/libs/";
use InfoCMDB;

my $cmdb = InfoCMDB->new('CMDB_Name');


```