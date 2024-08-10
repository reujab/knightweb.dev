#!/bin/bash -eu
set -o pipefail
shopt -s globstar nullglob

help() {
	echo "Usage: $0 [options]"
	echo
	echo "      --deb-http-root=/var/www/html"
	echo "      --force-template=<template>"
	echo "      --get-metadata"
	echo "  -h, --help"
	echo "  -d, --make-deb"
	echo "      --minify-args=<args>"
	echo "      --no-dark-theme"
	echo "      --no-minify"
	echo "      --pandoc-args=<args>"
	echo "  -w, --watch"
}

_minify() { if ((minify)); then minify "$@" "${minify_args[@]}"; else cat; fi; }

rename() {
	local dir base renamed out
	dir=$(dirname "$1")
	base=$(basename "$1" "${2:-}")
	renamed="$dir/$base${3:-}"
	out=$(sed -E 's/\/[0-9]{6}-/\//g' <<< "${renamed/src/dist}")
	mkdir -p "$(dirname "$out")"
	echo "$out"
}

init() {
	start=$EPOCHREALTIME
	prev_wd=$PWD
	cd "$(dirname "$0")"

	# get-metadata
	# exit 0
	# metadata=$(get-metadata)
	get-metadata > /tmp/meta.json

	process-filters
	rm -r dist
	mkdir dist
}

process-filters() {
	for filter in filters/*.lua; do
		pandoc_args+=(--lua-filter="$filter")
	done
}

build-highlighting-css() {
	get-highlighting-css | _minify --type css > dist/highlighting.css
}

get-highlighting-css() {
	args=(--template=templates/highlighting --metadata=title=- -fmarkdown)
	md=$'```sh\n```'
	pandoc "${args[@]}" <(echo "$md") |
	sed -e '/^pre\.numberSource.*$/,/^.*}.*/d' -e 's/^code span//'
	if ((dark_theme)); then
		echo "@media (prefers-color-scheme: dark) {"
		pandoc "${args[@]}" --highlight-style=themes/dark.theme <(echo "$md") |
		grep '^code span\.' | sed 's/^code span//'
		echo "}"
	fi
}

traverse() {
	local out
	for file in "$1"/*; do
		if [[ -d $file ]]; then
			traverse "$file"
		elif [[ $file = *.md ]]; then
			build-markdown "$file" & jobs+=($!)
		elif [[ $file = *.sass ]]; then
			build-sass "$file" & jobs+=($!)
		elif [[ $file =~ \.(bib)$ ]]; then
			:
		else
			out=$(rename "$file")
			cp -a "$file" "$out"
		fi
	done
}

get-metadata() {
	echo "{"
	get-metadata-for-dir src 1
	echo "}"
}

get-metadata-for-dir() {
	local first=1 key files file dir href
	key=$(get-key "$1")
	if ((!$2)); then echo ,; fi
	echo "\"$key\":{"
	files=("$1"/*)
	for i in "${!files[@]}"; do
		file="${files[$i]}"
		if [[ -d $file ]]; then
			get-metadata-for-dir "$file" "$first"
			first=0
		elif [[ $file = *.md ]]; then
			if ((!first)); then echo ,; fi
			first=0

			key=$(get-key "$file")
			if [[ $file = */index.md ]]; then
				dir=$(rename "$1")
				href=$(basename "$dir")/
			else
				# FIXME
				href=$(rename "$1" .md .html)
			fi

			echo "\"$key\":"
			sed -n '/^---$/,/^---$/ { /^---$/d; p }' "$file" |
			yaml2json | head -c-1
			echo ",\"href\":\"$href\""
			echo ",\"preview\":"
head -n20 "$file" | pandoc | tr -d '\n' >&2
			jq -Rn --arg preview "$(head -n20 "$file" | pandoc --wrap=none | tr -d '\n')" '$preview'
			echo "}"
		fi
	done
	echo "}"
}

get-key() {
	local out base
	out=$(rename "$1")
	out=${out/dist/src}
	base=$(basename "$out")
	echo "${base//./_}"
	# basename "$out" | sed 's/[-.]//g'
}

build-markdown() {
	local args template out
	args=("${pandoc_args[@]}" --resource-path="$(dirname "$1")" "$1")
	template=$(get-template "$1")
	args+=(--template="templates/$template")

	out=$(rename "$1" .md .html)
	# pandoc "${args[@]}" --metadata-file=<(echo "$metadata") |
	pandoc "${args[@]}" --metadata-file=/tmp/meta.json |
	# This removes unused code block line number references.
	sed -r 's/<a href="#cb[0-9]+-[0-9]+" aria-hidden="true" tabindex="-1"><\/a>| id="cb[0-9]+(-[0-9]+)?"//g' |
	# htmlq -r ".preview br" |
	_minify --type html > "$out"
}

get-template() {
	if [[ $force_template ]]; then echo "$force_template"; return; fi

	local file base
	file=$1
	while [[ $file != . ]]; do
		base=$(basename "$file" .md)
		dir=$(dirname "$file")
		dir_base=$(basename "$dir")
		paths=("$dir_base.$base" "$base")
		for path in "${paths[@]}"; do
			if [[ -f templates/$path.html ]]; then
				echo "$path.html"
				return
			fi
		done
		file=$(dirname "$file")
	done
	echo default.html5
}

build-sass() {
	local out
	out=$(rename "$1" .sass .css)
	sassc -a "$1" | _minify --type css > "$out"
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
	$0 "$@"

	miniserve -q --index=index.html dist &

	local pid=
	while read -r; do
		if [[ $pid && -d /proc/$pid ]]; then kill $pid; fi
		(
			# Typically, when a file is modified, several events are triggered.
			# This prevents a bunch of "Recompiling..." messages for a single change.
			sleep 0.1
			echo Recompiling...
			exec $0 "$@"
		) & pid=$!
	done < <(inotifywait -mr -e{modify,close_write,move{,_self},delete{,_self}} filters src static templates themes)
}

cleanup() {
	code=$?
	local jobs
	jobs=$(jobs > /dev/null; jobs -p)
	if [[ $jobs ]]; then kill $jobs; fi
	exit $code
}
trap cleanup EXIT

dark_theme=1
force_template=
make_deb=0
minify=1
minify_args=()
pandoc_args=(-C --toc=false --table-of-contents=false --wrap=none)
opts=$(getopt -n "$0" -o xhdw -l deb-http-root:,get-metadata,help,force-template:,make-deb,minify-args:,no-dark-theme,no-minify,pandoc-args:,watch -- "$@") || {
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
	--force-template)
	 	force_template=$2
		shift
		;;
	--get-metadata)
		get-metadata
		get-metadata | jq
		exit
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
	--no-dark-theme)
		dark_theme=0
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
		watch --no-minify "$@"
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

build-highlighting-css & jobs+=($!)

traverse src

for job in "${jobs[@]}"; do wait "$job"; done
if ((make_deb)); then make-deb; fi

echo "Done in $(bc <<< "scale=2; ($EPOCHREALTIME - $start)/1")s"
