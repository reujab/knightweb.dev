#!/bin/bash -eux
set -o pipefail

replace() { sed -i "s/^compile_sass = $1$/compile_sass = $2/" config.toml; }

cd "$(dirname "$0")"
rm -f static/highlighting*.css
replace true false
zola build
for file in static/highlighting*.css; do minify "$file" -o "$file"; done
replace false true
zola build
