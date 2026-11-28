#!/usr/bin/env bash
# Merges the per-platform digests of every image into one manifest list per image and tags it
# (.github/workflows/docker-images.yml, job `merge`; deploy/docker/README.md ▸ How a release is
# made).
#
#   merge-images.sh <images.json>
#
# <images.json>: {"<namespace>/<image>": ["sha256:…", …]}, one digest per platform.
# Environment:
#   NAMESPACE    the Docker Hub account (the namespace of every image), not a secret
#   HUB_TOKEN    its access token; empty = anonymous registry reads (a local check)
#   VERSION      the workspace version
#   TAGS         every tag of this run, the version among them ("0.1.0 0.1 latest")
#   PLATFORMS    the platforms every image must have ("linux/amd64 linux/arm64 …")
#   RETRY_WAITS  seconds to wait before each new try after a 429 (default "120 300 600 1200")
#   WAIT_BUDGET  seconds of such waits for the whole run (default 5400)
#
# Docker Hub counts every manifest GET as a pull, and a personal account has a pull limit:
# `imagetools create` GETs the per-platform manifests of its sources, so 26 images in one run
# can exceed it (issue #230). A HEAD is not counted, so the script:
#   - checks with a HEAD whether <image>:<version> exists and skips the image when it does: the
#     version tag is immutable (a re-run of a tag publishes the same version), and it is pushed
#     last, after <major>.<minor> and latest, so its presence means the whole tag set is there;
#     <major>.<minor> and latest are (re)pointed only for an image created in this run;
#   - merges wyrmd first, then the tools, the links, the simulators;
#   - on a 429 waits (2, 5, 10, 20 min) and tries again, within WAIT_BUDGET in all;
#   - checks a created image with a HEAD of its version tag, and the platform list of wyrmd
#     alone with one GET of its index;
#   - stops at the first image it cannot publish and names the images still missing: a re-run
#     skips the ones already published.
set -euo pipefail
shopt -s inherit_errexit

images="${1:?usage: merge-images.sh <images.json>}"
: "${NAMESPACE:?}" "${VERSION:?}" "${TAGS:?}" "${PLATFORMS:?}"
HUB_TOKEN="${HUB_TOKEN:-}"
read -r -a waits <<<"${RETRY_WAITS:-120 300 600 1200}"
budget="${WAIT_BUDGET:-5400}"
registry="https://registry-1.docker.io"
accept_index=(-H "Accept: application/vnd.oci.image.index.v1+json"
  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json")
work="$(mktemp -d)"
trap 'rm -f "$work"/*; rmdir "$work"' EXIT

# A pull token for one repository (<namespace>/<image>).
token() {
  local url="https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull"
  # the credentials reach curl on stdin, not on its command line
  if [ -n "$HUB_TOKEN" ]; then
    printf 'user = "%s:%s"\n' "$NAMESPACE" "$HUB_TOKEN" | curl -fsS --retry 3 -K - "$url"
  else
    curl -fsS --retry 3 "$url"
  fi | jq -er '.token // .access_token' || {
    echo "::error::no registry token for $1" >&2
    return 1
  }
}

# HEAD of <repo>:<tag>: prints the HTTP status; the headers stay in $work/head.
head_tag() {
  local t
  t="$(token "$1")"
  rm -f "$work/head"
  curl -sS --retry 3 -o /dev/null -I -D "$work/head" -w '%{http_code}' \
    -H "Authorization: Bearer $t" "${accept_index[@]}" "$registry/v2/$1/manifests/$2" || true
}

header() {
  [ -f "$work/head" ] || return 0
  tr -d '\r' <"$work/head" | awk -v h="$1" 'tolower($1) == tolower(h) ":" { print $2 }'
}

# wyrmd, the tools, the links, the simulators; by name within each.
order() {
  jq -r 'keys | sort_by((split("/") | last) as $b
           | [if $b == "wyrmd" then 0
              elif $b == "wyrm-tools" then 1
              elif ($b | startswith("wyrm-link-")) then 2
              elif ($b | startswith("wyrm-sim-")) then 3
              else 4 end, $b]) | .[]' "$images"
}

# Every image has one digest per platform before anything is pushed.
expected="$(wc -w <<<"$PLATFORMS" | tr -d ' ')"
bad="$(jq -r --argjson n "$expected" 'to_entries[] | select(.value | length != $n)
          | "\(.key): \(.value | length) of \($n) platforms"' "$images")"
if [ -n "$bad" ]; then
  while read -r line; do echo "::error::$line"; done <<<"$bad"
  exit 1
fi

# The version tag last: see above.
extra=()
for t in $TAGS; do [ "$t" = "$VERSION" ] || extra+=("$t"); done

# One image: imagetools create with the waits after a 429. 0 = created, 1 = not.
create() {
  local name="$1" try=0 args=() d t
  for t in "${extra[@]}" "$VERSION"; do args+=(-t "$name:$t"); done
  for d in $(jq -r --arg n "$name" '.[$n][]' "$images"); do args+=("$name@$d"); done
  while :; do
    if docker buildx imagetools create "${args[@]}" 2>&1 | tee "$work/create"; then
      return 0
    fi
    if ! grep -qE 'toomanyrequests|429 Too Many Requests|status 429' "$work/create"; then
      echo "::error::$name: imagetools create failed (not a rate limit)"
      return 1
    fi
    if [ "$try" -ge "${#waits[@]}" ]; then
      echo "::error::$name: Docker Hub pull rate limit (429) after $((try + 1)) tries"
      return 1
    fi
    local pause="${waits[$try]}"
    if [ "$pause" -gt "$budget" ]; then
      echo "::error::$name: Docker Hub pull rate limit (429); the next wait (${pause} s) exceeds what is left of this run's waits (${budget} s)"
      return 1
    fi
    try=$((try + 1))
    budget=$((budget - pause))
    echo "::warning::$name: Docker Hub pull rate limit (429); waiting $((pause / 60)) min $((pause % 60)) s before try $((try + 1)) of $((${#waits[@]} + 1))"
    sleep "$pause"
  done
}

# wyrmd's manifest list has exactly the platforms of this run (attestations aside).
check_platforms() {
  local name="$1" t got want
  t="$(token "$name")"
  got="$(curl -fsS --retry 3 -H "Authorization: Bearer $t" "${accept_index[@]}" \
    "$registry/v2/$name/manifests/$VERSION" |
    jq -r '.manifests[].platform | select(.os != "unknown")
             | [.os, .architecture] + (if .variant and .variant != "v8" then [.variant] else [] end)
             | join("/")' | sort | tr '\n' ' ')"
  want="$(tr ' ' '\n' <<<"$PLATFORMS" | grep . | sort | tr '\n' ' ')"
  if [ "$got" != "$want" ]; then
    echo "::error::$name:$VERSION has platforms [$got], expected [$want]"
    return 1
  fi
  echo "$name:$VERSION platforms: $got"
}

mapfile -t names < <(order)
done_count=0
skipped=()
for i in "${!names[@]}"; do
  name="${names[$i]}"
  status="$(head_tag "$name" "$VERSION")"
  left="$(header ratelimit-remaining)"
  case "$status" in
    200)
      echo "$name:$VERSION exists ($(header docker-content-digest)): skipped, tags left as they are"
      skipped+=("$name")
      continue
      ;;
    404 | 401) ;; # no such tag, or no such repository yet
    *) echo "::warning::$name:$VERSION: HEAD answered $status; creating it" ;;
  esac
  echo "::group::$name (pull limit left: ${left:-unknown})"
  if ! create "$name"; then
    echo "::endgroup::"
    rest=("${names[@]:$((i + 1))}")
    echo "::error::stopped at $name; not reached: ${rest[*]:-none}. Re-run the job later: an image whose $VERSION tag exists is skipped"
    exit 1
  fi
  status="$(head_tag "$name" "$VERSION")"
  if [ "$status" != 200 ]; then
    echo "::endgroup::"
    echo "::error::$name:$VERSION: HEAD answered $status after the create"
    exit 1
  fi
  echo "$name:$VERSION = $(header docker-content-digest)"
  if [ "${name##*/}" = wyrmd ]; then check_platforms "$name"; fi
  echo "::endgroup::"
  done_count=$((done_count + 1))
done
echo "created $done_count, skipped ${#skipped[@]} (version tag already there) of ${#names[@]} images"
