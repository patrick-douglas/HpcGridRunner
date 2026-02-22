#!/usr/bin/env bash
set -euo pipefail

GRIDRUNNER="/home/me/HpcGridRunner/hpc_cmds_GridRunner.pl"

# Trinity passa o arquivo de comandos como ÚLTIMO argumento
CMDS_FILE="${@: -1}"

if [[ ! -f "$CMDS_FILE" ]]; then
  echo "ERROR: último argumento não é um arquivo de comandos: $CMDS_FILE" >&2
  echo "ARGS: $*" >&2
  exit 1
fi

# Evita reuso de cache do GridRunner
rm -f "${CMDS_FILE}.hpc-cache_success" 2>/dev/null || true

# Backup
cp -f "$CMDS_FILE" "${CMDS_FILE}.bak"

python3 - "$CMDS_FILE" <<'PY'
import re, sys, pathlib

cmds = pathlib.Path(sys.argv[1])
bak  = cmds.with_suffix(cmds.suffix + ".bak")

# CPU cpuset-aware
cpu_expr = r"$(getconf _NPROCESSORS_ONLN)"

# RAM: 90% do total via /proc/meminfo (kB -> GB), mínimo 1G
# IMPORTANTE: sem \" dentro do awk, pq o awk está em aspas simples no shell
mem_expr = r"$(awk '/^MemTotal:/ {v=int(($2/1024/1024)*0.90); if(v<1)v=1; printf \"%s\", v}' /proc/meminfo)G"

# A linha acima ainda tem \"%s\" porque estamos em string Python; vamos trocar para "%s" literal no output
mem_expr = mem_expr.replace('\\"', '"')

cpu_re = re.compile(r'(--CPU)\s+\d+')
mem_re = re.compile(r'(--max_memory)\s+\d+G')

# Log 1x por job (POSIX sh)
prefix_once = (
    'if [ -z "${__NODECHECK_DONE:-}" ]; then '
    'export __NODECHECK_DONE=1; '
    'echo "===== NODE CHECK ====="; '
    'echo "HOST=$(hostname)"; '
    'echo "PWD=$(pwd)"; '
    'echo "DATE=$(date)"; '
    'echo "nproc=$(nproc)"; '
    'echo "_NPROCESSORS_ONLN=$(getconf _NPROCESSORS_ONLN)"; '
    'echo "cpuinfo_processors=$(grep -c ^processor /proc/cpuinfo)"; '
    'echo "Cpus_allowed_list=$(grep Cpus_allowed_list /proc/self/status | awk \'{print $2}\')"; '
    'echo "taskset=$(taskset -pc $$ 2>/dev/null || true)"; '
    'echo "MemTotal_kB=$(awk \'/^MemTotal:/ {print $2}\' /proc/meminfo)"; '
    f'echo "Mem_90pct_GB={mem_expr}"; '
    'echo "uptime:"; uptime; '
    'echo "======================"; '
    'fi; '
)

out_lines = []
with bak.open("r", errors="replace") as fh:
    for line in fh:
        line = cpu_re.sub(rf"\1 {cpu_expr}", line)
        line = mem_re.sub(rf"\1 {mem_expr}", line)
        out_lines.append(prefix_once + line)

cmds.write_text("".join(out_lines))
PY

echo ">> grid_exec_wrap: edited $CMDS_FILE (CPU->\$(getconf _NPROCESSORS_ONLN), MEM->90% via /proc/meminfo) and removed cache" >&2
exec "$GRIDRUNNER" "$@"
