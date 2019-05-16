#!/bin/sh
set -e

REPO_DIR=$(git rev-parse --show-toplevel)

sudo chmod -R 775 $REPO_DIR
sudo chown -R apache:apache $REPO_DIR
