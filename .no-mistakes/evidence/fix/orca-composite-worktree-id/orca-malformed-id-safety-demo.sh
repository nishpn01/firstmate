#!/usr/bin/env bash
# Companion to orca-composite-teardown-demo.sh: the composite id is now accepted,
# so show that loosening the endpoint validator did NOT widen what teardown will
# destroy. Each malformed orca_worktree_id is driven through the same operator
# command, bin/fm-teardown.sh <task-id>.
set -u
ROOT_REPO=${FM_DEMO_ROOT:?set FM_DEMO_ROOT to the firstmate checkout}
. "$ROOT_REPO/tests/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-orca-malformed-demo)
PTY=c3bcc5b7-c52e-415c-97d4-99b0e08024df

run_case() {  # <description> <orca_worktree_id>
  local desc=$1 wtid=$2 id=orcamalformeddemo out rc
  local proj="$TMP_ROOT/$3-project" wt="$TMP_ROOT/$3-worktree"
  local data="$TMP_ROOT/$3-data" state="$TMP_ROOT/$3-state" config="$TMP_ROOT/$3-config"
  local log="$TMP_ROOT/$3-orca.log" resp="$TMP_ROOT/$3-resp" fb="$TMP_ROOT/$3-fakebin"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  mkdir -p "$data/$id" "$state" "$config" "$resp" "$fb"; touch "$state/.last-watcher-beat"
  printf '#!/usr/bin/env bash\nset -u\n{ printf "orca"; for a in "$@"; do printf " %%s" "$a"; done; printf "\\n"; } >> "$FM_ORCA_LOG"\nprintf %s\n "{\\"ok\\":true,\\"result\\":{\\"runtime\\":{\\"reachable\\":true,\\"state\\":\\"ready\\"}}}"\n' > "$fb/orca"
  chmod +x "$fb/orca"; : > "$log"
  local neutral="$TMP_ROOT/$3-neutral"; mkdir -p "$neutral/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$neutral/bin/fm-guard.sh"; chmod +x "$neutral/bin/fm-guard.sh"
  fm_write_meta "$state/$id.meta" \
    "window=fm-$id" "endpoint_task_id=$id" "terminal=term-demo" "worktree=$wt" \
    "project=$proj" "harness=claude" "kind=ship" "mode=local-only" "yolo=off" \
    "backend=orca" "orca_worktree_id=$wtid"
  set +e
  out=$( PATH="$fb:$PATH" FM_ORCA_LOG="$log" FM_ORCA_RESPONSES="$resp" \
    FM_ROOT_OVERRIDE="$neutral" FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" \
    FM_CONFIG_OVERRIDE="$config" "$ROOT_REPO/bin/fm-teardown.sh" "$id" 2>&1 )
  rc=$?
  set -e
  echo "--- $desc"
  echo "    orca_worktree_id=$(printf '%s' "$wtid" | sed "s#$TMP_ROOT#<tmp>#g" | cat -v)"
  echo "    \$ fm-teardown.sh $id"
  printf '%s\n' "$out" | sed "s#$TMP_ROOT#<tmp>#g" | sed 's/^/    /'
  echo "    exit status: $rc"
  [ -s "$log" ] && echo "    orca CLI invoked: $(wc -l < "$log" | tr -d ' ') call(s) -- UNEXPECTED" \
                || echo "    orca CLI invoked: never (refused before any runtime call)"
  [ -e "$state/$id.meta" ] && echo "    state/$id.meta: preserved" || echo "    state/$id.meta: REMOVED -- UNEXPECTED"
  [ -e "$wt" ] && echo "    worktree: intact" || echo "    worktree: REMOVED -- UNEXPECTED"
  echo
}

echo "########## malformed Orca worktree ids still fail closed (@ $(git -C "$ROOT_REPO" rev-parse --short HEAD)) ##########"
echo
run_case "empty pty-id half"          "::$TMP_ROOT/a-worktree"            a
run_case "relative path half"         "$PTY::relative/worktree"           b
run_case "path traversal"             "$PTY::$TMP_ROOT/c-worktree/../elsewhere" c
run_case "embedded control character" "$PTY::$TMP_ROOT/d-worktree"$'\t'"trailing" d
