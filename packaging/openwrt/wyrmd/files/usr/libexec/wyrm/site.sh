#!/bin/sh
# The site of a broker's configuration: the text of the key `site` of a `wyrmd.json5`.
#
#   site.sh <wyrmd.json5>      prints the site; exit 1 when the file names none the device
#                              takes
#   site.sh --name <name>      exit 0 when the name is one the device takes
#
# JSON5 is read as tokens, without a parser: a comment and the content of a string never
# count, and only a key of the outermost object does (an upstream or a link has a `site`
# of its own). A site written with an escape is not taken.
#
# The device takes a site of 1 to SITE_MAX characters of SITE_CHARS that does not start
# with `.`: it names a directory of the data partition (`.replaced-<site>-<n>`), and the
# broker takes every such name. The crate wyrm-image has the same rule (`plain_site`,
# `SITE_MAX`, `SITE_EXTRA`), and its tests read these lines.

SITE_MAX=64
SITE_CHARS='A-Za-z0-9_.-'

plain() {
    case $1 in
    '' | .* | *[!$SITE_CHARS]*) return 1 ;;
    esac
    [ "${#1}" -le "$SITE_MAX" ]
}

if [ $# -eq 2 ] && [ "$1" = --name ]; then
    plain "$2"
    exit
fi
[ $# -eq 1 ] && [ -f "$1" ] || exit 1

site=$(awk '
BEGIN { depth = 0; state = 0; want = 0; tok = ""; inword = 0; found = 0 }
{
    line = $0 "\n"
    n = length(line)
    for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        d = substr(line, i + 1, 1)
        if (state == 1) { if (c == "\n") state = 0; continue }
        if (state == 2) { if (c == "*" && d == "/") { state = 0; i++ } continue }
        if (state == 3) {
            if (c == "\\") { esc = 1; i++; continue }
            if (c != q) { str = str c; continue }
            state = 0
            if (depth != 1) continue
            if (want) {
                if (key == "site" && !esc && index(str, "\n") == 0) { print str; found = 1; exit }
                want = 0
            } else {
                tok = esc ? "" : str
            }
            continue
        }
        isword = (c ~ /[A-Za-z0-9_$]/)
        if (!isword) inword = 0
        if (c == "/" && d == "/") { state = 1; i++; continue }
        if (c == "/" && d == "*") { state = 2; i++; continue }
        if (c == "\"" || c == "\047") { state = 3; q = c; str = ""; esc = 0; continue }
        if (c == "{" || c == "[") { if (depth == 1) want = 0; depth++; tok = ""; continue }
        if (c == "}" || c == "]") { depth--; continue }
        if (depth != 1) continue
        if (c == ":") { key = tok; want = 1; tok = ""; continue }
        if (c == ",") { want = 0; tok = ""; continue }
        if (isword) {
            # a value that is no string (a number, true) is no site
            if (want) { want = 0; key = "" }
            tok = inword ? tok c : c
            inword = 1
        }
    }
}
END { exit !found }
' "$1") || exit 1
plain "$site" || exit 1
printf '%s\n' "$site"
