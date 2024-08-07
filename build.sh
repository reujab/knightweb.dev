#!/bin/bash -eu
set -o pipefail
shopt -s globstar extglob # nullglob

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

_minify() { if ((minify)); then minify "$@" "${minify_args[@]}"; else cat; fi }

rename() {
	local dir base renamed out
	dir=$(dirname "$1")
	base=$(basename "$1" "$2")
	renamed="$dir/$base$3"
	out=${renamed/src/dist}
	mkdir -p "$(dirname "$out")"
	echo "$out"
}

init() {
	pandoc_args+=(-C --toc=false --table-of-contents=false --wrap=none)
	for filter in filters/*.lua; do
		pandoc_args+=(--lua-filter="$filter")
	done

	prev_wd=$PWD
	cd "$(dirname "$0")"
	website=

	rsync -a --delete --exclude={"*.bib","*.md","*.sass"} src/ dist/
}

build-markdown() {
	local file args template out
	for file in src/**/*.md; do
		args=("${pandoc_args[@]}" --resource-path="$(dirname "$file")" "$file")
		template=$(get-template "$file")
		args+=(--template="templates/$template")

		out=$(rename "$file" .md .html)
		pandoc "${args[@]}" |
		sed -r 's/<a href="#cb[0-9]+-[0-9]+" aria-hidden="true" tabindex="-1"><\/a>| id="cb[0-9]+(-[0-9]+)?"//g' |
		_minify --type html > "$out" & jobs+=($!)
		((debug)) && wait
	done
}

get-template() {
	[[ $force_template ]] && return "$force_template"

	local file base
	file=$(readlink -f "$1")
	while [[ $file != / ]]; do
		base=$(basename "$file" .md)
		if [[ -f templates/$base.html ]]; then
			echo "$base"
			return
		fi

		file=$(dirname "$file")
	done
	echo "Warning: template not found for $1" >&2
	echo default
}

build-sass() {
	local file out
	for file in **/*.sass; do
		out=$(rename "$file" .sass .css)
		sassc -a "$file" | _minify --type css > "$out" & jobs+=($!)
		((debug)) && wait
	done
}

build-highlighting-css() {
	get-highlighting-css | _minify --type css > "dist/highlighting.css"
}

get-highlighting-css() {
	args=(--template=templates/highlighting --metadata=title=- -fmarkdown)
	md=$'```sh\n```'
	pandoc "${args[@]}" <(echo "$md") |
	sed -e '/^pre\.numberSource.*$/,/^.*}.*/d' -e 's/^code span//'
	echo "@media (prefers-color-scheme: dark) {"
	pandoc "${args[@]}" --highlight-style=themes/dark.theme <(echo "$md") |
	grep "^code span" | sed 's/^code span//'
	echo "}"
}

make-deb() {
	local website tmp out
	website=$(basename "$(readlink -f .)")
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
}

debug=0
force_template=
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

init
build-markdown
build-sass
build-highlighting-css

((!debug)) && wait "${jobs[@]}"

((make_deb)) && make-deb
exit 0
