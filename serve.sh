#!/bin/bash -eu
set -o pipefail

cd "$(dirname "$0")"
qrencode -tansiutf8 <<< "http://$(hostname -i):1111"
zola serve -i0.0.0.0 -u/
