#!/bin/bash -eux
set -o pipefail

prev_wd=$PWD
cd "$(dirname "$0")"
website=$(basename "$PWD")
deb=$(mktemp -d)
public=$deb/var/www/html
tmp=$(mktemp -d)
trap 'rm -rf "$deb" "$tmp"' EXIT
mkdir "$deb/DEBIAN"
cat > "$deb/DEBIAN/control" << EOF
Package: $website
Version: $(date +%F)
Architecture: all
Maintainer: --
Description: $website
EOF

zola build -fu "https://$website" -o "$tmp"
zola build -o "$public"
rm "$public"/{404.html,highlighting.css}
mv "$tmp"/*.xml "$public"
for file in "$public"/*.{css,xml}; do minify "$file" -o "$file"; done
echo "Sitemap: https://$website/sitemap.xml" >> "$public/robots.txt"
dpkg-deb --build "$deb" "$prev_wd"
