#!/bin/bash -eux
set -o pipefail

prev_wd=$PWD
cd "$(dirname "$0")"
website=$(basename "$PWD")
tmp=$(mktemp -d)
mkdir "$tmp/DEBIAN"
mkdir -p "$tmp/var/www"
cat > "$tmp/DEBIAN/control" << EOF
Package: $website
Version: $(date +%F)
Architecture: all
Maintainer: --
Description: $website
EOF

zola build
rm public/404.html
minify public/atom.xml -o public/atom.xml
cp -a public "$tmp/var/www/html"
dpkg-deb --build "$tmp" "$prev_wd"
