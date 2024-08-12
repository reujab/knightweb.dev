#!/bin/bash -eu
set -o pipefail

cd "$(dirname "$0")"
zola build
miniserve -q --index=index.html public
