#!/usr/bin/env bash
# Run with: bash tests/test-update-moving-tags.sh [path/to/update-moving-tags.sh]
# All pushes go to temporary local bare repositories; no network is used.
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT=${1:-"$ROOT_DIR/scripts/update-moving-tags.sh"}
if [[ ! -f "$SCRIPT" ]]; then
    printf 'Missing script under test: %s\n' "$SCRIPT" >&2
    exit 1
fi
SCRIPT=$(cd -- "$(dirname -- "$SCRIPT")" && pwd)/$(basename -- "$SCRIPT")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/moving-tags-tests.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Ignore host configuration (including signing, hooks, and URL rewrites), and
# disallow every Git transport except the local filesystem used by these tests.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_ALLOW_PROTOCOL=file
export GIT_TERMINAL_PROMPT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    if [[ -f "${RUN_LOG:-}" ]]; then
        printf '\nScript output:\n' >&2
        cat "$RUN_LOG" >&2
    fi
    exit 1
}

assert_equal() {
    [[ "$1" == "$2" ]] || fail "$3 (expected '$1', got '$2')"
}

remote_git() {
    git --git-dir="$REMOTE" "$@"
}

local_git() {
    git -C "$WORK" "$@"
}

make_fixture() {
    FIXTURE=$(mktemp -d "$TEST_ROOT/case.XXXXXX")
    REMOTE="$FIXTURE/origin.git"
    WORK="$FIXTURE/work tree"
    RUN_LOG="$FIXTURE/script.log"
    RECEIVE_LOG="$REMOTE/receive-transactions.log"

    git init --quiet --bare "$REMOTE"
    git init --quiet --initial-branch=main "$WORK"
    local_git config user.name 'Moving Tag Tests'
    local_git config user.email 'moving-tags@example.invalid'
    local_git config commit.gpgSign false
    local_git config tag.gpgSign false
    remote_git config receive.advertiseAtomic true
    local_git remote add origin "$REMOTE"
    local_git commit --quiet --allow-empty -m 'Initial release'
    INITIAL_COMMIT=$(local_git rev-parse HEAD)
    local_git tag -a v1.9.0 -m 'Immutable older release'
    local_git tag -a v2.1.0 -m 'Immutable current release'
    IMMUTABLE_V1=$(local_git rev-parse refs/tags/v1.9.0)
    IMMUTABLE_V2=$(local_git rev-parse refs/tags/v2.1.0)
    local_git push --quiet origin refs/heads/main refs/tags/v1.9.0 refs/tags/v2.1.0

    # This local-only tag must never be published by an overbroad --tags push.
    local_git tag -a unrelated-local-tag -m 'Do not publish this tag'
    cat > "$REMOTE/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'BEGIN\n'
    cat
} >> "$GIT_DIR/receive-transactions.log"
HOOK
    chmod +x "$REMOTE/hooks/pre-receive"
}

advance_head() {
    local_git commit --quiet --allow-empty -m 'Next release'
    TARGET_COMMIT=$(local_git rev-parse HEAD)
}

run_script() {
    (cd -- "$WORK" && bash "$SCRIPT" "$@") > "$RUN_LOG" 2>&1
}

run_successfully() {
    : > "$RECEIVE_LOG"
    run_script "$@" || fail 'moving-tag update unexpectedly failed'
}

assert_immutable_refs() {
    assert_equal "$IMMUTABLE_V1" "$(remote_git rev-parse refs/tags/v1.9.0)" 'older remote release tag changed'
    assert_equal "$IMMUTABLE_V2" "$(remote_git rev-parse refs/tags/v2.1.0)" 'current remote release tag changed'
    assert_equal "$IMMUTABLE_V1" "$(local_git rev-parse refs/tags/v1.9.0)" 'older local release tag changed'
    assert_equal "$IMMUTABLE_V2" "$(local_git rev-parse refs/tags/v2.1.0)" 'current local release tag changed'
    assert_equal "$INITIAL_COMMIT" "$(remote_git rev-parse refs/heads/main)" 'remote branch changed'
    if remote_git show-ref --verify --quiet refs/tags/unrelated-local-tag; then
        fail 'unrelated local tag was published'
    fi
}

assert_moving_tags() {
    local name major=${1:-v2}
    for name in latest "$major"; do
        assert_equal tag "$(remote_git cat-file -t "refs/tags/$name")" "$name remote tag is not annotated"
        assert_equal "$TARGET_COMMIT" "$(remote_git rev-parse "refs/tags/$name^{}")" "$name remote tag does not point to HEAD"
        assert_equal tag "$(local_git cat-file -t "refs/tags/$name")" "$name local tag is not annotated"
        assert_equal "$(local_git rev-parse "refs/tags/$name")" "$(remote_git rev-parse "refs/tags/$name")" "$name local and remote tag objects differ"
    done
    assert_immutable_refs
}

assert_single_two_tag_transaction() {
    local major=${1:-v2}
    [[ -f "$RECEIVE_LOG" ]] || fail 'remote received no push'
    assert_equal 1 "$(grep -c '^BEGIN$' "$RECEIVE_LOG")" 'expected exactly one push transaction'
    assert_equal 2 "$(awk 'NF == 3 { count++ } END { print count+0 }' "$RECEIVE_LOG")" 'expected exactly two pushed refs'
    assert_equal "$(printf 'refs/tags/latest\nrefs/tags/%s\n' "$major" | LC_ALL=C sort)" "$(awk 'NF == 3 { print $3 }' "$RECEIVE_LOG" | LC_ALL=C sort)" 'push touched unexpected refs'
    if awk 'NF == 3 && $2 ~ /^0+$/ { deleted=1 } END { exit !deleted }' "$RECEIVE_LOG"; then
        fail 'moving tags were deleted remotely instead of force-updated'
    fi
}

seed_moving_tags() {
    TARGET_COMMIT=$INITIAL_COMMIT
    run_successfully 2.1.0
    assert_moving_tags
    assert_single_two_tag_transaction
}

test_initial_creation() {
    make_fixture
    advance_head
    run_successfully 2.1.0
    assert_moving_tags
    assert_single_two_tag_transaction
}

test_existing_tags() {
    make_fixture
    seed_moving_tags
    advance_head
    run_successfully 2.2.0
    assert_moving_tags
    assert_single_two_tag_transaction
}

test_new_major_version() {
    make_fixture
    seed_moving_tags
    local old_major
    old_major=$(remote_git rev-parse refs/tags/v2)
    advance_head
    run_successfully 12.0.0
    assert_moving_tags v12
    assert_single_two_tag_transaction v12
    assert_equal "$old_major" "$(remote_git rev-parse refs/tags/v2)" 'previous major release channel changed'
}

test_atomic_rejection() {
    make_fixture
    seed_moving_tags
    local old_latest old_major
    old_latest=$(remote_git rev-parse refs/tags/latest)
    old_major=$(remote_git rev-parse refs/tags/v2)
    advance_head
    cat > "$REMOTE/hooks/update" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == refs/tags/v2 ]]; then
    printf 'Deliberately rejecting v2\n' >&2
    exit 1
fi
HOOK
    chmod +x "$REMOTE/hooks/update"
    : > "$RECEIVE_LOG"
    if run_script 2.2.0; then
        fail 'script reported success after the remote rejected v2'
    fi
    grep -q 'Deliberately rejecting v2' "$RUN_LOG" || fail 'rejection test did not reach the update hook'
    assert_equal "$old_latest" "$(remote_git rev-parse refs/tags/latest)" 'latest changed despite atomic push rejection'
    assert_equal "$old_major" "$(remote_git rev-parse refs/tags/v2)" 'v2 changed despite atomic push rejection'
    assert_immutable_refs
    assert_single_two_tag_transaction

    # Failed publication may leave updated local tags. A retry must recover.
    rm -- "$REMOTE/hooks/update"
    run_successfully 2.2.0
    assert_moving_tags
    assert_single_two_tag_transaction
}

test_missing_tag_restoration() {
    local missing
    for missing in latest v2; do
        make_fixture
        seed_moving_tags
        remote_git update-ref -d "refs/tags/$missing"
        local_git tag -d "$missing" >/dev/null
        advance_head
        run_successfully 2.2.0
        assert_moving_tags
        assert_single_two_tag_transaction
    done
}

test_concurrent_publication() {
    local state name old_sha competing_sha before_other other_name
    local real_git
    real_git=$(command -v git)
    for state in existing missing; do
        for name in latest v2; do
            make_fixture
            seed_moving_tags
            advance_head
            other_name=latest
            [[ "$name" == latest ]] && other_name=v2
            before_other=$(remote_git rev-parse "refs/tags/$other_name")
            if [[ "$state" == missing ]]; then
                remote_git update-ref -d "refs/tags/$name"
                old_sha=
            else
                old_sha=$(remote_git rev-parse "refs/tags/$name")
            fi
            competing_sha=$(printf 'object %s\ntype commit\ntag %s\ntagger Concurrent Publisher <concurrent@example.invalid> 1700000000 +0000\n\nConcurrent release\n' \
                "$INITIAL_COMMIT" "$name" | remote_git mktag)

            # A delegating Git wrapper changes one remote ref immediately after
            # ls-remote returns its snapshot, before the script can push. Git's
            # real local transport and real lease enforcement handle the rest.
            mkdir -p "$FIXTURE/bin"
            touch "$FIXTURE/race-pending"
            cat > "$FIXTURE/bin/git" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == ls-remote && -f "$RACE_PENDING" ]]; then
    "$REAL_GIT" "$@"
    "$REAL_GIT" --git-dir="$RACE_REMOTE" update-ref "$RACE_REF" "$RACE_SHA" "$RACE_OLD_SHA"
    rm -- "$RACE_PENDING"
else
    exec "$REAL_GIT" "$@"
fi
SHIM
            chmod +x "$FIXTURE/bin/git"
            : > "$RECEIVE_LOG"
            if PATH="$FIXTURE/bin:$PATH" REAL_GIT="$real_git" \
                RACE_PENDING="$FIXTURE/race-pending" RACE_REMOTE="$REMOTE" \
                RACE_REF="refs/tags/$name" RACE_SHA="$competing_sha" \
                RACE_OLD_SHA="$old_sha" run_script 2.2.0; then
                fail "concurrent change to $state $name unexpectedly succeeded"
            fi
            [[ ! -f "$FIXTURE/race-pending" ]] || fail 'concurrent-publisher test did not trigger the race'
            assert_equal "$competing_sha" "$(remote_git rev-parse "refs/tags/$name")" "concurrent writer's $name update was overwritten"
            assert_equal "$before_other" "$(remote_git rev-parse "refs/tags/$other_name")" "$other_name changed despite a failed lease on $name"
            assert_immutable_refs
        done
    done
}

test_invalid_versions() {
    make_fixture
    seed_moving_tags
    advance_head
    local before_local before_remote version
    before_local=$(local_git show-ref)
    before_remote=$(remote_git show-ref)
    for version in '' 'not-a-version' '2' 'v2.1.0' '2.1.0/branch'; do
        : > "$RECEIVE_LOG"
        if run_script "$version"; then
            fail "invalid version '$version' unexpectedly succeeded"
        fi
        assert_equal "$before_local" "$(local_git show-ref)" "invalid version '$version' changed local refs"
        assert_equal "$before_remote" "$(remote_git show-ref)" "invalid version '$version' changed remote refs"
        [[ ! -s "$RECEIVE_LOG" ]] || fail "invalid version '$version' attempted a push"
    done
}

run_test() {
    local label=$1
    shift
    printf 'TEST: %s\n' "$label"
    ("$@")
    printf 'PASS: %s\n' "$label"
}

run_test 'creates both annotated moving tags when absent' test_initial_creation
run_test 'force-updates both existing moving tags in one push' test_existing_tags
run_test 'derives a multi-digit major without changing older release channels' test_new_major_version
run_test 'rejecting one tag leaves both remote tags unchanged; retry succeeds' test_atomic_rejection
run_test 'restores either missing moving tag' test_missing_tag_restoration
run_test 'concurrent changes to existing or missing tags are preserved by leases' test_concurrent_publication
run_test 'invalid versions change no refs and attempt no push' test_invalid_versions
printf '\nAll moving-tag regression tests passed.\n'
