#!/usr/bin/env bash
# Downloads the test corpus into corpus/files, from pinned commits of projects
# whose test files are published under a permissive license.
set -euo pipefail

cd "$(dirname "$0")"
dest=files
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { # name url commit paths...
	local name=$1 url=$2 commit=$3
	shift 3
	echo "$name@${commit:0:12}"
	git -C "$tmp" init -q "$name"
	git -C "$tmp/$name" remote add origin "$url"
	git -C "$tmp/$name" sparse-checkout set --no-cone "$@"
	git -C "$tmp/$name" fetch -q --depth 1 --filter=blob:none origin "$commit"
	git -C "$tmp/$name" checkout -q FETCH_HEAD
	mkdir -p "$dest/$name"
	# flattened; a name met twice takes its directory as prefix
	find "$tmp/$name" -path "$tmp/$name/.git" -prune -o -type f -print0 | sort -z |
		while IFS= read -r -d '' f; do
			out="$dest/$name/$(basename "$f")"
			[ -e "$out" ] && out="$dest/$name/$(basename "$(dirname "$f")")-$(basename "$f")"
			cp "$f" "$out"
		done
}

rm -rf "$dest"
# Apache License 2.0
fetch poi https://github.com/apache/poi.git 942d95d85b15d0dfdb3bc9ba1b4f273f277757c8 \
	'/test-data/document/*' '/test-data/spreadsheet/*' '/test-data/slideshow/*'
# MIT
fetch python-docx https://github.com/python-openxml/python-docx.git e45454602b53e8e572b179ccf1c91093ec9f4ed7 \
	'*.docx'
# Mozilla Public License 2.0: documents from the bug reports of Writer,
# Impress and Calc
fetch libreoffice https://github.com/LibreOffice/core.git 2a6ccbc40b060848a6eba2b2d27db43a625ded9a \
	'/sw/qa/**/*.docx' '/sd/qa/**/*.pptx' '/sd/qa/**/*.pptm' '/sd/qa/**/*.potx' '/sd/qa/**/*.ppsx' \
	'/sc/qa/**/*.xlsx' '/sc/qa/**/*.xlsm' '/sc/qa/**/*.csv'
# MIT
fetch python-pptx https://github.com/scanny/python-pptx.git 278b47b1dedd5b46ee84c286e77cdfb0bf4594be \
	'*.pptx' '*.pptm' '*.xlsx'
find "$dest" -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -12
