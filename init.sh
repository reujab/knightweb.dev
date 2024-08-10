#!/bin/bash -eux
set -o pipefail

cd "$(dirname "$0")"
sed -i 's/^compile_sass = true$/compile_sass = false/' config.toml
zola build
for file in static/highlighting*.css; do minify "$file" -o "$file"; done
sed -i 's/^compile_sass = false$/compile_sass = true/' config.toml
zola build
