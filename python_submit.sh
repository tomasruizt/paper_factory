#!/usr/bin/env bash
set -euo pipefail

# Submit a Python script (.py) as a local background job and return a job id.
# Mirrors the previous stata_submit.sh interface so callers do not need to
# change shape (submit, --status, --wait, --dry-run).
#
# Defaults to the interpreter on $PATH ("python3"). Override with $PYTHON_BIN
# to point at a uv/conda/virtualenv interpreter, e.g.:
#   PYTHON_BIN=/path/to/.venv/bin/python python_submit.sh code/01_build.py

FACTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_DIR="$FACTORY/run_state/python_jobs"
mkdir -p "$JOB_DIR"

PYTHON_BIN_DEFAULT="$(command -v python3 || command -v python || true)"

usage() {
    cat <<'EOF'
Usage:
  python_submit.sh code/filename.py
  python_submit.sh --time 04:00:00 code/file.py
  python_submit.sh --status <jobid>
  python_submit.sh --wait <jobid>
  python_submit.sh --dry-run code/file.py

Environment:
  PYTHON_BIN   Path to the Python interpreter (defaults to python3 on PATH)
EOF
}

job_meta() {
    echo "$JOB_DIR/$1.meta"
}

job_field() {
    local jobid="$1" key="$2"
    awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, "", $0); print $0; exit}' \
        "$(job_meta "$jobid")" 2>/dev/null || true
}

job_status() {
    local jobid="$1"
    local meta
    meta="$(job_meta "$jobid")"
    [[ -f "$meta" ]] || { echo "UNKNOWN"; return 1; }

    local pid log_file exit_file
    pid="$(job_field "$jobid" pid)"
    log_file="$(job_field "$jobid" log_file)"
    exit_file="$(job_field "$jobid" exit_file)"

    if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        echo "RUNNING"
        return 0
    fi

    if [[ -n "$exit_file" && -f "$exit_file" ]]; then
        local ec
        ec="$(cat "$exit_file" 2>/dev/null || echo 1)"
        if [[ "$ec" == "0" ]]; then
            echo "COMPLETED"
        else
            echo "FAILED"
        fi
        return 0
    fi

    if [[ -n "$log_file" && -f "$log_file" ]]; then
        if grep -Eq '^(Traceback|Error:)' "$log_file" 2>/dev/null; then
            echo "FAILED"
        else
            echo "EXITED"
        fi
    else
        echo "UNKNOWN"
    fi
}

TIME_OVERRIDE=""
DRY_RUN=false
STATUS_JOB=""
WAIT_JOB=""
PYFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --time)    TIME_OVERRIDE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --status)  STATUS_JOB="$2"; shift 2 ;;
        --wait)    WAIT_JOB="$2"; shift 2 ;;
        -*)        echo "Unknown option: $1" >&2; exit 1 ;;
        *)         PYFILE="$1"; shift ;;
    esac
done

if [[ -n "$STATUS_JOB" ]]; then
    job_status "$STATUS_JOB"
    exit 0
fi

if [[ -n "$WAIT_JOB" ]]; then
    while true; do
        state="$(job_status "$WAIT_JOB")"
        echo "$state"
        [[ "$state" == "RUNNING" ]] || break
        sleep 5
    done
    [[ "$state" != "FAILED" ]]
    exit $?
fi

if [[ -z "$PYFILE" ]]; then
    usage >&2
    exit 1
fi

if [[ ! "$PYFILE" = /* ]]; then
    PYFILE="$(pwd)/$PYFILE"
fi

if [[ ! -f "$PYFILE" ]]; then
    echo "ERROR: script not found: $PYFILE" >&2
    exit 1
fi

WORKDIR="$(cd "$(dirname "$PYFILE")" && pwd)"
if [[ "$(basename "$WORKDIR")" == "code" ]]; then
    WORKDIR="$(dirname "$WORKDIR")"
fi

PYFILE_BASE="$(basename "$PYFILE" .py)"
PRIMARY_LOG="$WORKDIR/logs/${PYFILE_BASE}.log"
EXIT_FILE="$WORKDIR/logs/${PYFILE_BASE}.exitcode"
JOBID="local_$(date +%Y%m%d%H%M%S)_$$"
META_FILE="$(job_meta "$JOBID")"

PYTHON_BIN="${PYTHON_BIN:-$PYTHON_BIN_DEFAULT}"
if [[ -z "$PYTHON_BIN" || ! -x "$PYTHON_BIN" ]]; then
    if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
        :
    else
        echo "ERROR: no Python interpreter found. Set PYTHON_BIN to an executable." >&2
        exit 1
    fi
fi

if $DRY_RUN; then
    printf 'TIME_OVERRIDE=%s\n' "${TIME_OVERRIDE:-none}"
    printf 'WORKDIR=%s\n' "$WORKDIR"
    printf 'PYTHON_BIN=%s\n' "$PYTHON_BIN"
    printf 'COMMAND=%q %q\n' "$PYTHON_BIN" "$PYFILE"
    exit 0
fi

mkdir -p "$WORKDIR/logs"

# Run in the background. The wrapper records the child's exit code to
# EXIT_FILE so --status / --wait can distinguish completed-cleanly from
# failed runs without re-parsing log heuristics.
(
    cd "$WORKDIR"
    (
        "$PYTHON_BIN" -u "$PYFILE" > "$PRIMARY_LOG" 2>&1 < /dev/null
        echo $? > "$EXIT_FILE"
    ) &
    pid=$!
    disown "$pid" 2>/dev/null || true
    {
        echo "pid=$pid"
        echo "script=$PYFILE"
        echo "workdir=$WORKDIR"
        echo "log_file=$PRIMARY_LOG"
        echo "exit_file=$EXIT_FILE"
        echo "python_bin=$PYTHON_BIN"
        echo "requested_time=${TIME_OVERRIDE:-}"
        echo "started=$(date +%s)"
    } > "$META_FILE"
)

echo "$JOBID"
