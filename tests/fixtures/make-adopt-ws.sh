#!/bin/sh
# Build a synthetic, in-progress workspace for testing ADOPT mode.
# Fictional project: Northwind Freight integration (a carrier API -> a warehouse system).
# Usage: sh make-adopt-ws.sh <target-dir>   (target must not exist)
set -eu
T=${1:?target dir}
[ -e "$T" ] && { echo "exists: $T" >&2; exit 1; }
mkdir -p "$T"
cd "$T"

commit() { # commit <date> <message>
  GIT_AUTHOR_DATE="$1T10:00:00+0000" GIT_COMMITTER_DATE="$1T10:00:00+0000" \
    git -c user.name="${AUTHOR:-Dana Kim}" -c user.email="dana@example.com" -c commit.gpgsign=false \
    commit -q -m "$2"
}

# --- repo 1: carrier-sync (Python service) -----------------------------------------------------
mkdir carrier-sync && cd carrier-sync
git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
cat > README.md <<'EOF'
# carrier-sync

Pulls shipment events from the RoadRunner Carrier API and pushes them to the Northwind warehouse
system (WMS). Runs every 5 minutes.

- `sync.py`: main loop
- Config via environment: CARRIER_API_URL, WMS_URL, and tokens from the secrets manager.
EOF
printf 'import time\n\ndef run():\n    pass\n' > sync.py
git add . && commit 2026-07-20 "Initial service skeleton"
printf 'def map_event(e):\n    return {"id": e["shipment_id"], "status": e["status"]}\n' > mapping.py
git add . && commit 2026-08-05 "Map carrier events to WMS status codes"
printf '\ndef retry(fn, n=3):\n    return fn()\n' >> sync.py
AUTHOR="Luis Ortega" && git add . && commit 2026-08-28 "Add retry on WMS 503"
AUTHOR="Dana Kim"
printf '# statuses\nIN_TRANSIT = "T"\nDELIVERED = "D"\nEXCEPTION = "X"\n' > statuses.py
git add . && commit 2026-09-15 "Handle EXCEPTION status (per 2026-09-10 status call)"
cd ..

# --- repo 2: wms-adapter (small TypeScript lib) ------------------------------------------------
mkdir wms-adapter && cd wms-adapter
git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
printf '# wms-adapter\n\nTyped client for the Northwind WMS REST API (v2).\n' > README.md
printf 'export const version = "0.1.0";\n' > index.ts
git add . && commit 2026-07-25 "Client skeleton for WMS v2"
printf 'export async function postStatus() {}\n' >> index.ts
git add . && commit 2026-09-01 "postStatus endpoint"
cd ..

# --- notes and docs (not a repo) ---------------------------------------------------------------
mkdir -p notes/meetings docs
cat > notes/meetings/2026-07-14-kickoff.md <<'EOF'
# Kickoff, 2026-07-14

Attendees: Priya Nair (Northwind, ops director), Dana Kim (contractor), Luis Ortega (Northwind IT)

- Goal: carrier shipment events show up in the WMS within 10 minutes.
- Go-live target: 2026-10-01.
- Luis owns WMS access and the staging environment.
- Decision: we use the carrier's REST API, not their SFTP batch files.
EOF
cat > notes/meetings/2026-08-02-sync.md <<'EOF'
# Sync, 2026-08-02

- Carrier API rate limit is 60 requests/minute. Polling every 5 minutes is fine.
- Priya asked for an exceptions report (damaged, lost) as a daily email. Not in original scope: to be quoted.
- Luis: staging WMS available from 2026-08-10.
EOF
cat > notes/meetings/2026-09-10-status.md <<'EOF'
# Status call, 2026-09-10

- Go-live moved to 2026-10-15 because the WMS v2 upgrade on Northwind's side slipped.
- Decision: EXCEPTION status maps to WMS code "X" and raises an alert.
- Exceptions report: approved, fixed fee, deliver after go-live.
- Open: who monitors alerts on weekends? Priya to confirm.
EOF
cat > notes/todo.txt <<'EOF'
- ask Luis for prod WMS credentials process
- write runbook for on-call
- quote exceptions report  (done 2026-09-12)
EOF
cat > docs/architecture.md <<'EOF'
# Architecture

RoadRunner Carrier API --(poll 5 min)--> carrier-sync --(REST)--> wms-adapter --> Northwind WMS v2
Alerts: carrier-sync posts to the #freight-alerts channel on EXCEPTION.
EOF

# --- the workspace's own instructions ----------------------------------------------------------
cat > CLAUDE.md <<'EOF'
# Northwind integration workspace

- Python code lives in carrier-sync/, TypeScript in wms-adapter/.
- Run tests with `pytest` in carrier-sync.
- Never commit secrets. Tokens come from the secrets manager.
EOF
echo "built: $T"
