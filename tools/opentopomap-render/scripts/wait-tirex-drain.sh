#!/bin/bash
# Block until the Tirex render queue inside the container drains, i.e. the
# cumulative count of successful z<ZOOM> renders in jobs.log stops growing.
# Used by the Makefile `render` target after `tirex-batch`.
#
# Usage: wait-tirex-drain.sh [CONTAINER] [ZOOM] [POLL_SECONDS] [STABLE_CHECKS]
set -u
C="${1:-alaskarouter-otm}"
Z="${2:-11}"
POLL="${3:-60}"
NEED="${4:-4}"
prev=-1
stable=0
while [ "${stable}" -lt "${NEED}" ]; do
  cnt=$(docker exec "${C}" sh -c "grep -c 'z=${Z}.*success=1' /var/log/tirex/jobs.log 2>/dev/null" 2>/dev/null)
  cnt="${cnt:-0}"
  if [ "${cnt}" = "${prev}" ]; then
    stable=$((stable + 1))
  else
    stable=0
    echo "  [$(date +%T)] z${Z} successes=${cnt}"
  fi
  prev="${cnt}"
  [ "${stable}" -lt "${NEED}" ] && sleep "${POLL}"
done
echo "render drained: z${Z} cumulative successes=${prev}"
