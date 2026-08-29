#!/usr/bin/env bash
# End-to-end manual verification of fix/orca-composite-worktree-id.
#
# Reproduces what an operator actually does: an Orca-backed ship task exists,
# its state/<id>.meta carries the worktree id EXACTLY as the live Orca CLI
# records it ("<pty-id>::<absolute-worktree-path>"), and the operator runs
#   bin/fm-teardown.sh <task-id>
# to finish the task. A fake `orca` on PATH stands in for the real CLI and logs
# every argv it is invoked with, so the transcript shows the id that actually
# reached Orca.
#
# Usage: orca-composite-teardown-demo.sh <label>
set -u
ROOT_REPO=${FM_DEMO_ROOT:?set FM_DEMO_ROOT to the firstmate checkout}
LABEL=$1
. "$ROOT_REPO/tests/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-orca-composite-demo)
ID=orcacompositedemo
PROJ="$TMP_ROOT/project"; WT="$TMP_ROOT/worktree"
DATA="$TMP_ROOT/data"; STATE="$TMP_ROOT/state"; CONFIG="$TMP_ROOT/config"
LOG="$TMP_ROOT/orca-cli.log"; RESP="$TMP_ROOT/responses"; FB="$TMP_ROOT/fakebin"

fm_git_worktree "$PROJ" "$WT" "fm/$ID"
mkdir -p "$DATA/$ID" "$STATE" "$CONFIG" "$RESP" "$FB"
touch "$STATE/.last-watcher-beat"

# The real recorded shape, straight out of `orca worktree create --json`.
WTID="c3bcc5b7-c52e-415c-97d4-99b0e08024df::$WT"

cat > "$FB/orca" <<'SH'
#!/usr/bin/env bash
set -u
{ printf 'orca'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$FM_ORCA_LOG"
[ "${1:-}" = status ] && { printf '{"ok":true,"result":{"runtime":{"reachable":true,"state":"ready"}}}\n'; exit 0; }
# A real `orca worktree rm` removes the checkout; do the same so the end state is honest.
if [ "${1:-}" = worktree ] && [ "${2:-}" = rm ]; then
  for a in "$@"; do case "$a" in id:*::/*) rm -rf "${a#*::}" ;; esac; done
fi
n=$(( $(cat "$FM_ORCA_RESPONSES/.count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FM_ORCA_RESPONSES/.count"
[ -f "$FM_ORCA_RESPONSES/$n.out" ] && cat "$FM_ORCA_RESPONSES/$n.out"
exit 0
SH
chmod +x "$FB/orca"
# `orca worktree show` resolves the id back to its path.
printf '{"ok":true,"result":{"worktree":{"id":"%s","path":"%s"}}}\n' "$WTID" "$WT" > "$RESP/1.out"

fm_write_meta "$STATE/$ID.meta" \
  "window=fm-$ID" "endpoint_task_id=$ID" "terminal=term-composite-demo" \
  "worktree=$WT" "project=$PROJ" "harness=claude" "kind=ship" \
  "mode=local-only" "yolo=off" "backend=orca" "orca_worktree_id=$WTID"

NEUTRAL="$TMP_ROOT/neutral-root"; mkdir -p "$NEUTRAL/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$NEUTRAL/bin/fm-guard.sh"; chmod +x "$NEUTRAL/bin/fm-guard.sh"

echo "########## $LABEL ##########"
echo
echo "\$ cat state/$ID.meta"
sed "s#$TMP_ROOT#<tmp>#g" "$STATE/$ID.meta"
echo
echo "\$ fm-teardown.sh $ID"
set +e
OUT=$( PATH="$FB:$PATH" FM_ORCA_LOG="$LOG" FM_ORCA_RESPONSES="$RESP" \
  FM_ROOT_OVERRIDE="$NEUTRAL" FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" \
  FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT_REPO/bin/fm-teardown.sh" "$ID" 2>&1 )
RC=$?
set -e
printf '%s\n' "$OUT" | sed "s#$TMP_ROOT#<tmp>#g"
echo "exit status: $RC"
echo
echo "-- what firstmate actually asked the Orca CLI to do --"
if [ -s "$LOG" ]; then sed "s#$TMP_ROOT#<tmp>#g" "$LOG"; else echo "(the Orca CLI was never invoked)"; fi
echo
echo "-- operator-visible end state --"
if [ -e "$STATE/$ID.meta" ]; then
  echo "state/$ID.meta: STILL PRESENT (task not torn down)"
else
  echo "state/$ID.meta: removed (task torn down)"
fi
if [ -e "$WT" ]; then echo "worktree <tmp>/worktree: STILL ON DISK"; else echo "worktree <tmp>/worktree: removed"; fi
echo
