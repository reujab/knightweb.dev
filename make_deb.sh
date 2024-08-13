#!/bin/bash -eux
set -o pipefail
shopt -s globstar

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
rm "$public/404.html"
mv "$tmp"/*.xml "$public"
for file in "$public"/**/*.{css,html,xml}; do minify --svg-keep-comments "$file" -o "$file"; done
echo "Sitemap: https://$website/sitemap.xml" >> "$public/robots.txt"
dpkg-deb --build "$deb" "$prev_wd"
