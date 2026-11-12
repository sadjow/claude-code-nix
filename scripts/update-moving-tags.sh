#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:?Usage: update-moving-tags.sh VERSION}
if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 1
fi
MAJOR=${VERSION%%.*}
HEAD_COMMIT=$(git rev-parse HEAD)

# Record the remote values before changing anything. Explicit leases also
# protect against another writer updating either channel during this run.
REMOTE_TAGS=$(git ls-remote --refs origin refs/tags/latest "refs/tags/v$MAJOR")

remote_sha() {
  awk -v ref="refs/tags/$1" '$2 == ref { print $1 }' <<< "$REMOTE_TAGS"
}

tag_message() {
  case $1 in
    latest) echo "Latest release: v$VERSION" ;;
    *) echo "Latest $1 release: v$VERSION" ;;
  esac
}

# A rerun of an older build must not move a channel back behind a release
# that has already been published from a newer commit. An ancestry error is
# not a negative answer, so it fails closed instead of allowing the push.
newer_release_published() {
  local published_commit=$1 ancestry=0
  [[ $published_commit != "$HEAD_COMMIT" ]] || return 1
  git merge-base --is-ancestor HEAD "$published_commit" || ancestry=$?
  if (( ancestry > 1 )); then
    echo "Could not compare HEAD with the published commit $published_commit" >&2
    exit 1
  fi
  return "$ancestry"
}

LEASES=()
REFSPECS=()
for name in latest "v$MAJOR"; do
  published_sha=$(remote_sha "$name")
  if [[ -n $published_sha ]]; then
    # Compare against the published object, never a stale local tag; a failed
    # refresh aborts the run here.
    git fetch --quiet origin "+refs/tags/$name:refs/tags/$name"
    published_commit=$(git rev-parse "refs/tags/$name^{commit}")
    if newer_release_published "$published_commit"; then
      echo "$name already points to the newer commit $published_commit; leaving it unchanged"
      continue
    fi
  fi
  git tag -f -a "$name" -m "$(tag_message "$name")" HEAD
  LEASES+=("--force-with-lease=refs/tags/$name:$published_sha")
  REFSPECS+=("refs/tags/$name:refs/tags/$name")
done

if (( ${#REFSPECS[@]} == 0 )); then
  echo "leaving moving tags unchanged"
  exit 0
fi

# Never delete live channel refs. GitHub applies every update or none,
# including when one ref is rejected. Empty leases allow missing tags to be
# recreated, but only if they are still absent at push time.
git push --atomic "${LEASES[@]}" origin "${REFSPECS[@]}"
