#!/usr/bin/env bash
set -euo pipefail

CODEXBARCTL="${CODEXBARCTL:-$HOME/.local/bin/codexbarctl}"
CODEX_BIN="${CODEX_BIN:-codex}"
PROMPT="只回复：你好"
SWITCH_TIMEOUT=120
LIMIT=0
DRY_RUN=0
RESTORE_ACTIVE=1
INCLUDE_EXCEEDED=0
LOG_DIR="$HOME/.codex/codexbar/warmups"

usage() {
  cat <<'EOF'
Usage:
  codexbar-warmup.sh [options]

Warm up Codex accounts one by one so each healthy account starts its 5h window early.

Options:
  --prompt TEXT          Warmup prompt. Default: 只回复：你好
  --timeout SECONDS      Switch wait timeout per account. Default: 120
  --limit N              Warm up at most N accounts. Default: all eligible accounts
  --include-exceeded     Also include exceeded accounts
  --no-restore-active    Leave the last warmed account active
  --dry-run              Print the plan only
  -h, --help             Show this help

Environment:
  CODEXBARCTL            Path to codexbarctl. Default: ~/.local/bin/codexbarctl
  CODEX_BIN              Path to codex. Default: codex
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      PROMPT="${2:?missing value for --prompt}"
      shift 2
      ;;
    --timeout)
      SWITCH_TIMEOUT="${2:?missing value for --timeout}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:?missing value for --limit}"
      shift 2
      ;;
    --include-exceeded)
      INCLUDE_EXCEEDED=1
      shift
      ;;
    --no-restore-active)
      RESTORE_ACTIVE=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -x "$CODEXBARCTL" ]]; then
  echo "codexbarctl is not executable: $CODEXBARCTL" >&2
  exit 1
fi

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  echo "codex command not found: $CODEX_BIN" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
run_id="$(date +%Y%m%d-%H%M%S)"
log_file="$LOG_DIR/$run_id.jsonl"

status_json="$("$CODEXBARCTL" status --json)"
accounts_json="$("$CODEXBARCTL" accounts --json)"

original_identity="$(
  python3 - "$status_json" <<'PY'
import json, sys
status = json.loads(sys.argv[1])
print(status.get("activeIdentityKey") or "")
PY
)"

plan_file="$(mktemp)"
python3 - "$accounts_json" "$INCLUDE_EXCEEDED" "$LIMIT" > "$plan_file" <<'PY'
import json, sys

accounts = json.loads(sys.argv[1])
include_exceeded = sys.argv[2] == "1"
limit = int(sys.argv[3])

eligible = []
for account in accounts:
    if account.get("isSuspended") or account.get("tokenExpired"):
        continue
    status = account.get("usageStatus", "")
    if status in {"ok", "warning"} or (include_exceeded and status == "exceeded"):
        eligible.append(account)

if limit > 0:
    eligible = eligible[:limit]

for account in eligible:
    print(
        "\t".join([
            account.get("identityKey", ""),
            account.get("email", ""),
            account.get("workspace", ""),
            account.get("usageStatus", ""),
        ])
    )
PY

account_count="$(wc -l < "$plan_file" | tr -d ' ')"
echo "warmup_accounts=$account_count"
echo "log_file=$log_file"

if [[ "$account_count" == "0" ]]; then
  rm -f "$plan_file"
  exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
  sed 's/^/DRY_RUN\t/' "$plan_file"
  rm -f "$plan_file"
  exit 0
fi

while IFS=$'\t' read -r identity email workspace usage_status; do
  [[ -z "$identity" ]] && continue
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "warming $email [$workspace] usage=$usage_status"

  if "$CODEXBARCTL" switch-auto "$identity" --wait --timeout "$SWITCH_TIMEOUT"; then
    output_file="$(mktemp)"
    if "$CODEX_BIN" exec \
        --ephemeral \
        --ignore-rules \
        --skip-git-repo-check \
        -s read-only \
        -C /tmp \
        -o "$output_file" \
        "$PROMPT" >/dev/null 2>&1; then
      result_status="success"
      result_message="$(tr '\n' ' ' < "$output_file" | sed 's/[[:space:]]\{1,\}/ /g' | cut -c 1-240)"
    else
      result_status="codex_failed"
      result_message="$(tr '\n' ' ' < "$output_file" 2>/dev/null | sed 's/[[:space:]]\{1,\}/ /g' | cut -c 1-240)"
    fi
    rm -f "$output_file"
  else
    result_status="switch_failed"
    result_message="failed to switch account"
  fi

  python3 - "$log_file" "$started_at" "$identity" "$email" "$workspace" "$usage_status" "$result_status" "$result_message" <<'PY'
import json, sys
from datetime import datetime, timezone

path, started_at, identity, email, workspace, usage_status, status, message = sys.argv[1:]
entry = {
    "started_at": started_at,
    "finished_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "identityKey": identity,
    "email": email,
    "workspace": workspace,
    "usageStatusBefore": usage_status,
    "status": status,
    "message": message,
}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY

  echo "warmup_result $email $result_status"
done < "$plan_file"

rm -f "$plan_file"

if [[ "$RESTORE_ACTIVE" == "1" && -n "$original_identity" ]]; then
  echo "restoring_active=$original_identity"
  "$CODEXBARCTL" switch-auto "$original_identity" --wait --timeout "$SWITCH_TIMEOUT" || true
fi

"$CODEXBARCTL" refresh || true
echo "done"
