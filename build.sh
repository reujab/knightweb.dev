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
	echo "  -w, --watch"
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

	trap cleanup EXIT
}

cleanup() {
	code=$?
	pkill --parent $$ || true
	exit $code
}

build-markdown() {
	local args template out
	args=("${pandoc_args[@]}" --resource-path="$(dirname "$1")" "$1")
	template=$(get-template "$1")
	args+=(--template="templates/$template")

	out=$(rename "$1" .md .html)
	pandoc "${args[@]}" |
	sed -r 's/<a href="#cb[0-9]+-[0-9]+" aria-hidden="true" tabindex="-1"><\/a>| id="cb[0-9]+(-[0-9]+)?"//g' |
	_minify --type html > "$out"
	if ((debug)); then wait; fi
}

get-template() {
	if [[ $force_template ]]; then echo "$force_template"; return; fi

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
	echo default
}

build-sass() {
	local out
	out=$(rename "$1" .sass .css)
	sassc -a "$1" | _minify --type css > "$out"
	if ((debug)); then wait; fi
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

watch() {
	local pid=
	while read -r; do
		if [[ $pid && -d /proc/$pid ]]; then
			if [[ $(ps -ho comm --ppid $pid) != sleep ]]; then
				echo Aborting
			fi
			kill -TERM "$pid"
		fi
		(
			sleep 0.5
			echo Recompiling...
			start=$EPOCHREALTIME
			$0 "$@" || {
				echo Exit code $? >&2
				exit 1
			}
			echo "Done in $(bc <<< "scale=2; ($EPOCHREALTIME - $start)/1")s"
		) & pid=$!
	done < <(inotifywait -mr -e{modify,close_write,move{,_self},delete{,_self}} filters src templates themes)
}

debug=0
force_template=
make_deb=0
minify=1
minify_args=()
opts=$(getopt -n "$0" -o xhdw -l deb-http-root:,debug,help,force-template:,make-deb,minify-args:,no-minify,pandoc-args:,watch -- "$@") || {
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
	-w|--watch)
		shift
		watch "$@"
		exit
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

for file in src/**/*.md; do
	build-markdown "$file" & jobs+=($!)
	if ((debug)); then wait; fi
done

for file in **/*.sass; do
	build-sass "$file" & jobs+=($!)
	if ((debug)); then wait; fi
done

build-highlighting-css

if ((!debug)); then wait "${jobs[@]}"; fi
if ((make_deb)); then make-deb; fi
