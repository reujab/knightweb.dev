#!/bin/bash -eu
set -o pipefail

help() {
	echo "Usage: $0 [options]"
	echo
	echo "      --deb-http-root=/var/www/html"
	echo "  -x, --debug"
	echo "      --force-template=<template>"
	echo "  -h, --help"
	echo "  -d, --make-deb"
	echo "      --minify-args=<args>"
	echo "      --no-minify"
	echo "      --pandoc-args=<args>"
}

debug=0
make_deb=0
minify=1
minify_args=()
opts=$(getopt -n "$0" -o xhd -l deb-http-root:,debug,help,force-template:,make-deb,minify-args:,no-minify,pandoc-args: -- "$@") || {
	echo
	help
	exit 1
}
eval set -- "$opts"
while (($#)); do
	case "$1" in
	--deb-http-root)
	 	deb_http_root=$2
		shift
		;;
	-x|--debug)
		set -x
		debug=1
		;;
	--force-template)
	 	force_template=$2
		shift
		;;
	-h|--help)
		help
		exit
		;;
	-d|--make-deb)
	 	make_deb=1
		;;
	--minify-args)
		minify_args=($2)
		shift
		;;
	--no-minify)
	 	minify=0
		;;
	--pandoc-args)
		pandoc_args=($2)
		echo "${pandoc_args[@]}"
		shift
		;;
	--);;
	*)
		echo "Extra parameter: $1" >&2
		echo
		help
		exit 1
	esac
	shift
done

shopt -s globstar extglob # nullglob
pandoc_args+=(-C --toc=false --table-of-contents=false --wrap=none)
prev_wd=$PWD
cd "$(dirname "$0")"
website=$(basename "$(readlink -f .)")

rename() {
	dir=$(dirname "$1")
	base=$(basename "$1" "$2")
	renamed="$dir/$base$3"
	out=${renamed/src/dist}
	mkdir -p "$(dirname "$out")"
	echo "$out"
}

_minify() { if ((minify)); then minify "$@" "${minify_args[@]}"; else cat; fi }

rsync -a --delete --exclude={"*.bib","*.md","*.sass"} src/ dist/

for filter in filters/*.lua; do
	pandoc_args+=(--lua-filter="$filter")
done

for file in src/**/*.md; do
	args=("${pandoc_args[@]}" --resource-path="$(dirname "$file")" "$file")
	if [[ $file = src/articles/* ]]; then
		template=article
	else
		template=default
	fi
	template=${force_template:-$template}
	args+=(--template="templates/$template")

	out=$(rename "$file" .md .html)
	pandoc "${args[@]}" |
	sed -r 's/<a href="#cb[0-9]+-[0-9]+" aria-hidden="true" tabindex="-1"><\/a>| id="cb[0-9]+(-[0-9]+)?"//g' |
	_minify --type html > "$out" & jobs+=($!)
	((debug)) && wait
done

for file in **/*.sass; do
	out=$(rename "$file" .sass .css)
	sassc -a "$file" | _minify --type css > "$out" & jobs+=($!)
	((debug)) && wait
done

# Generate syntax highlighting CSS.
{
	args=(--template=templates/highlighting --metadata=title=- -fmarkdown)
	md=$'```sh\n```'
	pandoc "${args[@]}" <(echo "$md") |
	sed -e '/^pre\.numberSource.*$/,/^.*}.*/d' -e 's/^code span//'
	echo "@media (prefers-color-scheme: dark) {"
	pandoc "${args[@]}" --highlight-style=themes/dark.theme <(echo "$md") |
	grep "^code span" | sed 's/^code span//'
	echo "}"
} | _minify --type css > "dist/highlighting.css"

wait "${jobs[@]}"

if ((make_deb)); then
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	mkdir "$tmp/DEBIAN"
	cat > "$tmp/DEBIAN/control" << EOF
Package: $website
Version: $(date +%F)
Architecture: all
Maintainer: --
Description: $website
EOF
	out=$tmp${deb_http_root:-/var/www/html}
	mkdir -p "$out"
	cp -r dist/* "$out"
	dpkg-deb --build "$tmp" "$prev_wd"
fi
