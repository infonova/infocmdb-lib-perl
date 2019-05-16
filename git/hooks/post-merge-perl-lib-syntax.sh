#!/bin/bash
set -e

REPO_DIR=$(git rev-parse --show-toplevel)

FOUND_ERRORS=$(find -name "*.pm" | xargs -i perl -c -I ./libs/ {} 2>&1 | grep -v 'syntax OK')

if [  ! -z  "$FOUND_ERRORS" ] ; then
	echo $FOUND_ERRORS
	exit 1
fi
