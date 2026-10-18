#!/usr/bin/env bash

# the daily run: updates this clone to main, runs every package for real,
# audits the keys, posts approved drafts, has an ai triage the results (without
# the nsec), reruns what it marks transient, and opens a "daily run" issue with
# its summary. see the readme to set it up, and daily_run.md for the ai's part.

ai_harness="${AI_HARNESS:-claude}"
ai_model="${AI_MODEL:-}"
ai_timeout_minutes="${AI_TIMEOUT_MINUTES:-60}"
ai_max_budget_usd="${AI_MAX_BUDGET_USD:-}"
github_user="${DAILY_RUN_GITHUB_USER:-tinfoilhash}"
github_repo="${DAILY_RUN_GITHUB_REPO:-tinfoilhash/verify-from-gpg}"
log_root="${DAILY_RUN_LOG_DIR:-$HOME/Library/Logs/verify-from-gpg}"
keep_days="${DAILY_RUN_KEEP_DAYS:-30}"

repo_dir=$(dirname -- "$(realpath "$0")")
cd "$repo_dir" || exit 1

# the run resets this clone to main, so only run in a clone set up for it.
check_clone() {
  if [ "$(git config --bool verify-from-gpg.dailyRun)" != true ]; then
    echo 'not a daily run clone (see the readme), exiting'
    exit 1
  fi
}

# a stale lock from a run that was killed is taken over, and so is this run's
# own lock after update_clone runs it again (exec keeps the pid).
take_lock() {
  mkdir -p "$log_root" || exit 1

  local lock_dir="$log_root/.lock"

  if ! mkdir "$lock_dir" 2> /dev/null; then
    local pid
    pid=$(cat "$lock_dir/pid" 2> /dev/null)

    if [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -0 "$pid" 2> /dev/null; then
      echo "another daily run is in progress (pid $pid), exiting"
      exit 1
    fi
  fi

  echo "$$" > "$lock_dir/pid" || exit 1
  trap 'rm -rf "$log_root/.lock"' EXIT
}

# resets to origin's main, then runs that version of this script.
update_clone() {
  git fetch -q origin || exit 1
  git checkout -q -f main || exit 1
  git reset -q --hard origin/main || exit 1

  DAILY_RUN_UPDATED=1 exec "$repo_dir/daily_run.sh"
}

# keeps an old run while it has drafts waiting for approval.
delete_old_runs() {
  local old_run_dir
  while IFS= read -r old_run_dir <&3; do
    if [ -z "$(pending_drafts "$old_run_dir/drafts")" ]; then
      rm -rf "$old_run_dir"
    fi
  done 3< <(
    find "$log_root" -mindepth 1 -maxdepth 1 -type d -name '20*' \
      -mtime +"$keep_days"
  )
}

# imports new packages' keys into the real keyring, then audits the keys in a
# throwaway one, so a stale copy at a key's url isn't hidden by a newer one.
check_keys() {
  ./check_keys.sh --import > "$run_dir/keys-import.log" 2>&1

  local home
  home=$(mktemp -d /tmp/verify-from-gpg-audit.XXXXXX) || exit 1
  GNUPGHOME="$home" ./check_keys.sh --import > "$run_dir/keys-audit.log" 2>&1
  GNUPGHOME="$home" gpgconf --kill gpg-agent 2> /dev/null
  rm -rf "$home"
}

open_daily_issues() {
  gh issue list --repo "$github_repo" --author "$github_user" --state open \
    --search 'in:title "daily run"' --limit 100 --json number,body \
    | jaq -r '
      .[]
      | (try (.body | capture("<!-- run: (?<id>[0-9-]+) -->") | .id)) as $id
      | "\(.number) \($id // "")"
    '
}

# drafts are <n>.json in a run's drafts folder, marked done by <n>.posted or
# <n>.skipped next to them.
pending_drafts() {
  local drafts_dir="$1"

  local draft
  for draft in "$drafts_dir"/*.json; do
    [ -f "$draft" ] || continue
    local base="${draft%.json}"
    if [ ! -f "$base.posted" ] && [ ! -f "$base.skipped" ]; then
      echo "${base##*/}"
    fi
  done
}

post_draft() {
  local draft="$1"

  local repo issue title
  repo=$(jaq -r '.repo // ""' "$draft") || return 1
  issue=$(jaq -r '.issue // ""' "$draft") || return 1
  title=$(jaq -r '.title // ""' "$draft") || return 1

  if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "invalid repo: $repo"
    return 1
  fi

  local body_file="${draft%.json}.body.md"
  jaq -r '.body' "$draft" > "$body_file" || return 1

  if [[ "$issue" =~ ^[0-9]+$ ]]; then
    gh issue comment "$issue" --repo "$repo" --body-file "$body_file"
  elif [ -n "$title" ]; then
    gh issue create --repo "$repo" --title "$title" --body-file "$body_file"
  else
    echo 'draft has neither an issue nor a title'
    return 1
  fi
}

# approvals are tinfoil hash's comments on a daily run issue that are exactly
# `post all`, `skip all`, or `post`/`skip` with draft numbers, like `post 1, 3`.
# they're parsed here, not by the ai, so text from anyone else can't approve.
process_approvals() {
  : > "$run_dir/approvals.txt"

  local number run_id
  while read -r number run_id <&3; do
    [ -n "$run_id" ] || continue

    local drafts_dir="$log_root/$run_id/drafts"
    [ -d "$drafts_dir" ] || continue

    local comments
    comments=$(
      gh issue view "$number" --repo "$github_repo" --json comments \
        | jaq -r --arg user "$github_user" \
          '.comments[] | select(.author.login == $user) | .body'
    ) || continue

    local line
    while IFS= read -r line <&4; do
      [[ "$line" =~ ^(post|skip)\ (all|[0-9]+(,\ ?[0-9]+)*)$ ]] || continue
      local action="${BASH_REMATCH[1]}"
      local which="${BASH_REMATCH[2]}"

      local n
      for n in $(pending_drafts "$drafts_dir"); do
        if [ "$which" != all ] && ! grep -Eq "(^|, ?)$n(,|$)" <<< "$which"; then
          continue
        fi

        local draft="$drafts_dir/$n.json"

        if [ "$action" = skip ]; then
          : > "$drafts_dir/$n.skipped"
          echo "#$number draft $n: skipped" >> "$run_dir/approvals.txt"
          continue
        fi

        local url
        if url=$(post_draft "$draft" 2>&1); then
          echo "$url" > "$drafts_dir/$n.posted"
          echo "#$number draft $n: posted $url" >> "$run_dir/approvals.txt"
          gh issue comment "$number" --repo "$github_repo" \
            --body "posted draft $n: $url" > /dev/null
        else
          echo "#$number draft $n: failed to post: $url" \
            >> "$run_dir/approvals.txt"
        fi
      done
    done 4<<< "$comments"
  done 3< <(open_daily_issues)
}

# lists the drafts still waiting for approval, so the ai doesn't redraft them.
write_pending_drafts() {
  : > "$run_dir/pending-drafts.txt"

  local number run_id
  while read -r number run_id <&3; do
    [ -n "$run_id" ] || continue

    local n
    for n in $(pending_drafts "$log_root/$run_id/drafts"); do
      echo "#$number draft $n: $log_root/$run_id/drafts/$n.json" \
        >> "$run_dir/pending-drafts.txt"
    done
  done 3< <(open_daily_issues)
}

# the commands the ai may run with claude. the others limit it with their own
# settings below.
claude_allowed_tools=(
  'Read' 'Grep' 'Glob' 'Edit' 'Write' 'WebFetch'
  'Bash(gh issue list:*)' 'Bash(gh issue view:*)' 'Bash(gh pr list:*)'
  'Bash(gh pr view:*)' 'Bash(gh pr checks:*)' 'Bash(gh pr create:*)'
  'Bash(gh search issues:*)'
  'Bash(gh search prs:*)' 'Bash(gh release list:*)' 'Bash(gh release view:*)'
  'Bash(gh release download:*)' 'Bash(git status:*)' 'Bash(git diff:*)'
  'Bash(git log:*)' 'Bash(git show:*)' 'Bash(git switch main)'
  'Bash(git switch -c daily-run/:*)' 'Bash(git add:*)' 'Bash(git commit:*)'
  'Bash(git push -u origin daily-run/:*)' 'Bash(gpg --list-packets:*)'
  'Bash(gpg --show-keys:*)' 'Bash(gpg --verify:*)' 'Bash(./check_keys.sh:*)'
  'Bash(./packages/:*)' 'Bash(bats:*)' 'Bash(shfmt:*)' 'Bash(shellcheck:*)'
  'Bash(actionlint:*)'
)

# opencode's equivalent, as a config file it merges with the user's.
write_opencode_config() {
  cat > "$run_dir/opencode.json" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit": "allow",
    "webfetch": "allow",
    "bash": {
      "*": "deny",
      "gh issue list *": "allow",
      "gh issue view *": "allow",
      "gh pr list *": "allow",
      "gh pr view *": "allow",
      "gh pr checks *": "allow",
      "gh pr create *": "allow",
      "gh search *": "allow",
      "gh release list *": "allow",
      "gh release view *": "allow",
      "gh release download *": "allow",
      "git status*": "allow",
      "git diff*": "allow",
      "git log*": "allow",
      "git show *": "allow",
      "git switch main": "allow",
      "git switch -c daily-run/*": "allow",
      "git add *": "allow",
      "git commit *": "allow",
      "git push -u origin daily-run/*": "allow",
      "gpg --list-packets *": "allow",
      "gpg --show-keys *": "allow",
      "gpg --verify *": "allow",
      "./check_keys.sh*": "allow",
      "./packages/*": "allow",
      "bats *": "allow",
      "shfmt *": "allow",
      "shellcheck *": "allow",
      "actionlint*": "allow"
    }
  }
}
EOF
}

# runs the chosen harness's cli without the nsec, so the ai can't publish, and
# with DRY_RUN and the npub, so the package scripts it runs are dry runs.
run_ai() {
  local prompt="follow daily_run.md in this repo for the daily run in $run_dir."

  local command=()
  case "$ai_harness" in
    claude)
      command=(claude -p "$prompt" --permission-mode dontAsk
        --add-dir "$run_dir" --no-session-persistence
        --allowedTools "${claude_allowed_tools[@]}")
      [ -n "$ai_model" ] && command+=(--model "$ai_model")
      [ -n "$ai_max_budget_usd" ] \
        && command+=(--max-budget-usd "$ai_max_budget_usd")
      ;;
    codex)
      # codex limits commands with its sandbox, not an allowlist, so it can
      # write only in this clone and the run directory.
      command=(codex exec --full-auto --skip-git-repo-check
        --add-dir "$run_dir" -c sandbox_workspace_write.network_access=true)
      [ -n "$ai_model" ] && command+=(--model "$ai_model")
      command+=("$prompt")
      ;;
    opencode)
      write_opencode_config
      command=(env OPENCODE_CONFIG="$run_dir/opencode.json" opencode run --auto)
      [ -n "$ai_model" ] && command+=(--model "$ai_model")
      command+=("$prompt")
      ;;
    *)
      echo "unknown AI_HARNESS: $ai_harness"
      return 1
      ;;
  esac

  local npub
  npub=$(nak encode npub "$(nak key public "$NSEC" < /dev/null)" < /dev/null)

  # perl's alarm stops a hung cli, and works on macos and linux, unlike
  # `timeout`.
  env -u NSEC DRY_RUN=1 NPUB="$npub" perl -e \
    'alarm shift; exec @ARGV or die "exec failed: $!\n"' \
    "$((ai_timeout_minutes * 60))" "${command[@]}" \
    < /dev/null > "$run_dir/ai.log" 2>&1
}

# undoes anything the ai changed in the clone (commits, edits, new files), so
# reruns run origin's code, not code the ai could have written.
restore_clone() {
  git fetch -q origin \
    && git checkout -q -f main \
    && git reset -q --hard origin/main \
    && git clean -q -fd
}

# reruns, for real, the packages the ai marked transient (like a relay
# timeout). names must be packages in this repo.
rerun_transient() {
  [ -f "$run_dir/transient.txt" ] || return

  if ! restore_clone; then
    echo 'restoring the clone failed, so nothing was rerun' \
      > "$run_dir/reruns-skipped.txt"
    return
  fi

  local package_name
  while IFS= read -r package_name <&3; do
    [[ "$package_name" =~ ^[a-z0-9_]+$ ]] || continue
    [ -x "packages/$package_name/verify.sh" ] || continue

    mkdir -p "$run_dir/reruns"
    "packages/$package_name/verify.sh" < /dev/null \
      > "$run_dir/reruns/$package_name.log" 2>&1
    echo "$package_name $?" >> "$run_dir/reruns/status.txt"
  done 3< "$run_dir/transient.txt"
}

# lists each package that stopped, with the line it stopped on, for when the ai
# didn't write a summary.
stopped_packages() {
  local package_name package_status
  while read -r package_name package_status; do
    [ "$package_status" -eq 0 ] && continue

    local log="$run_dir/packages/$package_name.log"
    local reason
    reason=$(grep -a -E 'exiting$|failed' "$log" | tail -n 1)
    reason="${reason:-no reason logged}"
    echo "- **$package_name** (exit $package_status): $reason"
  done < "$1"
}

write_issue_body() {
  local ai_status="$1"
  local body="$run_dir/issue.md"

  if [ "$ai_status" -eq 0 ] && [ -s "$run_dir/summary.md" ]; then
    cat "$run_dir/summary.md" > "$body"
  else
    {
      echo "the ai step failed (exit $ai_status), so this is the plain summary."
      echo "see \`ai.log\` in the run's logs."
      echo
      echo '### stopped'
      echo
      stopped_packages "$run_dir/packages/status.txt"
      echo
      echo '### key audit'
      echo
      grep -E '^  (problem|warning):' "$run_dir/keys-audit.log" \
        || echo 'no problems or warnings'
    } > "$body"
  fi

  # check_keys.sh ends with its counts, so a log without them means the audit
  # itself failed.
  if ! grep -q -- '^--- [0-9]* problems, [0-9]* warnings$' \
    "$run_dir/keys-audit.log"; then
    {
      echo
      echo '### key audit failed'
      echo
      echo "the audit didn't finish. see \`keys-audit.log\` in the run's logs."
    } >> "$body"
  fi

  write_drafts_section >> "$body"

  if [ -f "$run_dir/reruns-skipped.txt" ]; then
    {
      echo
      cat "$run_dir/reruns-skipped.txt"
    } >> "$body"
  fi

  if [ -f "$run_dir/reruns/status.txt" ]; then
    {
      echo
      echo '### reruns'
      echo
      local package_name package_status
      while read -r package_name package_status; do
        echo "- $package_name: exit $package_status"
      done < "$run_dir/reruns/status.txt"
    } >> "$body"
  fi

  if [ -s "$run_dir/approvals.txt" ]; then
    {
      echo
      echo '### approvals'
      echo
      sed 's/^/- /' "$run_dir/approvals.txt"
    } >> "$body"
  fi

  {
    echo
    echo "harness: $ai_harness${ai_model:+ ($ai_model)} · logs: \`$run_dir\`"
    echo
    echo "<!-- run: $run_id -->"
  } >> "$body"
}

# lists this run's drafts from their json, the text that's posted on approval,
# rather than the ai's description of them.
write_drafts_section() {
  local drafts
  drafts=$(pending_drafts "$run_dir/drafts")
  [ -n "$drafts" ] || return

  echo
  echo '### drafts for approval'

  local n
  for n in $drafts; do
    local draft="$run_dir/drafts/$n.json"
    local target
    target=$(jaq -r '
      if .issue then "comment on \(.repo)#\(.issue)"
      else "new issue on \(.repo): \(.title)" end
    ' "$draft") || target='unreadable draft'

    echo
    echo "**$n.** $target"
    echo
    echo '<details><summary>body</summary>'
    echo
    jaq -r '.body // ""' "$draft"
    echo
    echo '</details>'
  done

  echo
  echo 'reply `post 1` (or `post all`, `post 1, 3`, `skip 1`) to approve.'
}

# closes earlier daily run issues that have no drafts waiting for approval.
close_finished_issues() {
  local new_number="$1"

  local number issue_run_id
  while read -r number issue_run_id <&3; do
    [ "$number" = "$new_number" ] && continue

    if [ -n "$issue_run_id" ] \
      && [ -n "$(pending_drafts "$log_root/$issue_run_id/drafts")" ]; then
      continue
    fi

    local comment=()
    if [ -n "$new_number" ]; then
      comment=(--comment "superseded by #$new_number")
    fi

    gh issue close "$number" --repo "$github_repo" "${comment[@]}" > /dev/null
  done 3< <(open_daily_issues)
}

open_issue() {
  local ai_status="$1"

  # the ai marks a day with nothing new to say as quiet.
  if [ "$ai_status" -eq 0 ] && [ -f "$run_dir/quiet" ] \
    && ! grep -qv ' 0$' "$run_dir/reruns/status.txt" 2> /dev/null; then
    echo 'quiet day, no issue'
    close_finished_issues ''
    return
  fi

  write_issue_body "$ai_status"
  restore_clone

  local url
  url=$(gh issue create --repo "$github_repo" --title "daily run $run_date" \
    --body-file "$run_dir/issue.md") || exit 1
  echo "opened $url"

  close_finished_issues "${url##*/}"
}

main() {
  check_clone

  # launchd runs this in a login shell, so the nsec comes from ~/.zshenv.
  if [ -z "${NSEC:-}" ]; then
    echo '$NSEC not set, exiting'
    exit 1
  fi

  take_lock

  if [ -z "${DAILY_RUN_UPDATED:-}" ]; then
    update_clone
  fi

  # keep the mac awake until the run ends.
  if command -v caffeinate > /dev/null; then
    caffeinate -i -w "$$" &
  fi

  # always post as tinfoil hash, whichever account gh has active.
  GH_TOKEN=$(gh auth token --user "$github_user") || exit 1
  export GH_TOKEN

  run_date=$(date +%Y-%m-%d)
  run_id=$(date +%Y-%m-%d-%H%M%S)
  run_dir="$log_root/$run_id"
  mkdir -p "$run_dir/drafts" || exit 1

  delete_old_runs
  check_keys
  LOG_DIR="$run_dir/packages" ./verify_all.sh
  process_approvals
  write_pending_drafts

  local ai_status=0
  run_ai || ai_status=$?

  rerun_transient
  open_issue "$ai_status"
}

# in braces, so bash has read it all before update_clone replaces this file.
{
  main "$@"
  exit
}
