#!/bin/bash -e
set -o pipefail

deb_out=$PWD
deb=$(mktemp -d)
trap 'rm -rf "$deb"' EXIT
http_root=$deb/var/www/data
cd "$(dirname "$0")"
shopt -s globstar extglob

rename() {
	dir=$(dirname "$1")
	base=$(basename "$1" "$2")
	renamed="$dir/$base$3"
	out=${renamed/src/$http_root}
	mkdir -p "$(dirname "$out")"
	echo "$out"
}

mkdir -p "$http_root"
rsync -a --exclude={"*.bib","*.md","*.sass"} src/ "$http_root/"
cp -a DEBIAN "$deb"

for file in **/*.sass; do
	out=$(rename "$file" .sass .css)
	sassc -a "$file" | minify --type css -o "$out" & jobs+=($!)
done

pandoc_args=(-C)
for filter in filters/*.lua; do
	pandoc_args+=(--lua-filter="$filter")
done
for file in src/**/*.md; do
	args=("${pandoc_args[@]}" --resource-path="$(dirname "$file")")
	if [[ $file = src/articles/* ]]; then
		template=article
	else
		template=default
	fi
	args+=(--template="templates/$template" "$file")

	out=$(rename "$file" .md .html)
	pandoc "${args[@]}" | minify --type html -o "$out" & jobs+=($!)
done

wait "${jobs[@]}"
rsync -a --delete "$http_root/" dist/
dpkg-deb --build "$deb" "$deb_out"
