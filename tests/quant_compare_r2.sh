#!/usr/bin/env bash
# 2026-11-13: E2B's chosen phone file (Q4_K_M with an importance matrix, train/phone_file.sh) drifted 0.231 from the
# trained model on round 2's held-out people (N3 asks at most 0.16; round 1 measured 0.159 on its own text). Before
# E4B's phone file is made the same way, two questions on the same text against the same kind of reference:
#   1. is it the text or the training? the model before DPO (SFT only) through the same steps
#   2. which file meets N3? Q5_K_M and Q6_K with the same importance matrix
# The first line re-measures the shipped file against a fresh reference, so it must repeat 0.231.
# Usage (pod, after train/phone_file.sh e2b): bash tests/quant_compare_r2.sh e2b
set -uo pipefail
W=/workspace; L=$W/llama.cpp/build/bin; Q=$W/quants; R=$Q/cmp; OUT=$W/export; M=${1:-e2b}; mkdir -p $R
CV="$W/venv-convert/bin/python $W/llama.cpp/convert_hf_to_gguf.py"
kl() {  # FILE REFERENCE: drift of one file from its full model
  local n=$(basename $1 .gguf); $L/llama-perplexity -m $1 -ngl 99 -c 2048 --chunks 20 --kl-divergence-base $2 \
      --kl-divergence > $R/$n.kl.log 2>&1
  echo "$n $(du -m $1 | cut -f1) MB | $(grep -E '^Mean +KLD' $R/$n.kl.log) | $(grep -E '^Same top p' $R/$n.kl.log)"; }
ref() {  # NAME MERGED: the bf16 file and its token distributions on the held-out text
  $CV $2 --outtype bf16 --outfile $R/$1-bf16.gguf > $R/$1-convert.log 2>&1 || { echo "CONVERT FAILED $1"; return 1; }
  $L/llama-perplexity -m $R/$1-bf16.gguf -f $Q/heldout.txt -ngl 99 -c 2048 --chunks 20 --kl-divergence-base $R/$1.kld \
      > $R/$1-bf16.log 2>&1 || { echo "REFERENCE FAILED $1"; return 1; }; }
echo "=== $M after DPO $(date +%T)"
ref $M $W/runs/$M-dpo/merged || exit 1
for q in Q5_K_M Q6_K; do $L/llama-quantize --imatrix $Q/$M.imatrix $R/$M-bf16.gguf $R/$M-$q-imat.gguf $q > /dev/null 2>&1; done
for f in $OUT/therapist-$M-Q4_K_M-imat.gguf $OUT/therapist-$M-Q4_K_M.gguf $R/$M-Q5_K_M-imat.gguf $R/$M-Q6_K-imat.gguf; do
  kl $f $R/$M.kld; done
rm -f $R/$M-bf16.gguf $R/$M.kld
echo "=== $M before DPO (SFT only) $(date +%T)"
ref $M-sft $W/runs/$M-sft/merged || exit 1
$L/llama-imatrix -m $R/$M-sft-bf16.gguf -f $Q/calib.txt -ngl 99 -c 2048 --chunks 60 -o $R/$M-sft.imatrix \
    > $R/$M-sft-imatrix.log 2>&1 || { echo "IMATRIX FAILED $M-sft"; exit 1; }
$L/llama-quantize --imatrix $R/$M-sft.imatrix $R/$M-sft-bf16.gguf $R/$M-sft-Q4_K_M-imat.gguf Q4_K_M > /dev/null 2>&1
kl $R/$M-sft-Q4_K_M-imat.gguf $R/$M-sft.kld
rm -f $R/$M-sft-bf16.gguf $R/$M-sft.kld $R/$M-sft-Q4_K_M-imat.gguf
echo "=== compare done $(date +%T)"
