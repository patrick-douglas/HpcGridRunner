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

# Backup do arquivo de comandos
cp -f "$CMDS_FILE" "${CMDS_FILE}.bak"

python3 - "$CMDS_FILE" <<'PY'
import re, sys, pathlib

cmds = pathlib.Path(sys.argv[1])
bak  = cmds.with_suffix(cmds.suffix + ".bak")

# CPU que respeita cpuset/afinidade (melhor que nproc no cluster)
cpu_expr = r"$(getconf _NPROCESSORS_ONLN)"

# RAM: 90% do total (em GB), arredondado pra baixo (mais seguro contra OOM)
# Usando bash process substitution (<(...)) porque os scripts J*.sh rodam em shell
mem_expr = r"$(awk '/^Mem:/ {printf \"%d\", $2*0.90}' <(free -g))G"

cpu_re = re.compile(r'(--CPU)\s+\d+')
mem_re = re.compile(r'(--max_memory)\s+\d+G')

# Log 1x por job (sentinel via variável de ambiente)
prefix_once = (
    'if [[ -z "${__NODECHECK_DONE:-}" ]]; then '
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
    'echo "free -g:"; free -g; '
    'echo "uptime:"; uptime; '
    'echo "======================"; '
    'fi; '
)

out_lines = []
with bak.open("r", errors="replace") as fh:
    for line in fh:
        # substitui CPU e MEM (mantendo $(...) literal para expandir no node)
        line = cpu_re.sub(rf"\1 {cpu_expr}", line)
        line = mem_re.sub(rf"\1 {mem_expr}", line)

        # log 1x por job + comando
        out_lines.append(prefix_once + line)

cmds.write_text("".join(out_lines))
PY

echo ">> grid_exec_wrap: edited $CMDS_FILE (CPU->\$(getconf _NPROCESSORS_ONLN), MEM->90% of RAM) and removed cache" >&2

exec "$GRIDRUNNER" "$@"
