#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG (ajuste aqui) ======
# Onde está o executável que gera/submete os jobs por FASTA
HPC_FASTA_GR="/home/me/HpcGridRunner/BioIfx/hpc_FASTA_GridRunner.pl"

# Grid conf (Slurm)
GRIDCONF="/home/me/HpcGridRunner/hpc_conf/SLURM.blast.conf"

# DB do DIAMOND (prefix do .dmnd, sem extensão)
DIAMOND_DB="/blastdb/sprot/uniprot_sprot.fasta"

# Parâmetros do DIAMOND
EVALUE="1e-3"
MAX_TARGETS="1"
OUTFMT="6"
SENS="--more-sensitive"

# threads por task (vai ser o --threads dentro do diamond)
THREADS="20"

# Split do FASTA (seqs por bin)
SEQS_PER_BIN="100"

# Percentuais pra rodar
PCTS=(1)

# Se quiser re-run quando output já existe:
FORCE=1
# ==================================

# Checagens básicas
[[ -x "$HPC_FASTA_GR" ]] || { echo "ERRO: não achei executável $HPC_FASTA_GR"; exit 1; }
[[ -f "$GRIDCONF" ]]     || { echo "ERRO: não achei $GRIDCONF"; exit 1; }

for pct in "${PCTS[@]}"; do
  dir="${pct}"
  trinity_fa="reads_${pct}pct.trinity_out.Trinity.fasta"
  out_prefix="blast_${pct}pct_swissprot"
  out_file="${out_prefix}.outfmt6"

  echo
  echo "=============================="
  echo ">> DIAMOND ${pct}% (pasta: ${dir})"
  echo "=============================="

  [[ -d "$dir" ]] || { echo "AVISO: pasta '$dir' não existe, pulando"; continue; }

  pushd "$dir" >/dev/null

  if [[ ! -f "$trinity_fa" ]]; then
    echo "AVISO: não achei $dir/$trinity_fa, pulando"
    popd >/dev/null
    continue
  fi

  if [[ -f "$out_file" && "$FORCE" -eq 0 ]]; then
    echo "AVISO: output '$dir/$out_file' já existe. (FORCE=0) Pulando."
    popd >/dev/null
    continue
  fi

  if [[ -f "$out_file" && "$FORCE" -eq 1 ]]; then
    echo "FORCE=1: removendo output antigo $dir/$out_file"
    rm -rf "$out_file"
    rm -rf farmit* *.cmds *.cache_success
  fi

  # Template (usa __QUERY_FILE__ que o hpc_FASTA_GridRunner substitui)
  cmd_template="diamond blastx \
    -d ${DIAMOND_DB} \
    -q __QUERY_FILE__ \
    --evalue ${EVALUE} \
    --max-target-seqs ${MAX_TARGETS} \
    --outfmt ${OUTFMT} \
    --threads \$(getconf _NPROCESSORS_ONLN) \
    ${SENS}"

  # Submete via GridRunner
  "$HPC_FASTA_GR" \
    --cmd_template "$cmd_template" \
    --query_fasta "$trinity_fa" \
    --grid_conf "$GRIDCONF" \
    --parafly \
    -N "$SEQS_PER_BIN" \
    -O "$out_file"

  popd >/dev/null
done

echo
echo "✅ Done. DIAMOND blastx submetido para os percentuais definidos."
