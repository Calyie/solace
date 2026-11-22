#!/usr/bin/env bash
# The chosen phone file for one trained model. Round 1 measured the choice (tests/compare_quants.sh, PROGRESS
# 2026-11-06): Q4_K_M with an importance matrix drifts least from the full model (mean KLD E4B 0.144, E2B 0.159;
# plain Q4_0 0.236 and 0.327), and N3 asks for at most 0.16. After train/export.sh, which keeps the trained bf16 file:
#   1. held-out text from the people SFT never saw (train/sft.py's own split) and calibration text from the others
#   2. the bf16 model's token distributions on the held-out text, the reference for the drift
#   3. an importance matrix from the calibration text, and the Q4_K_M file quantised with it:
#      therapist-NAME-Q4_K_M-imat.gguf, its SHA-256 added to therapist-NAME.sha256 (the app loads only listed files)
#   4. its drift against the bf16 model (N3: mean KLD at most 0.16), then the bf16 file and the reference removed
#   5. (2026-11-13) the same for Q5_K_M with the same importance matrix: on round 2's held-out text E2B's Q4_K_M
#      drifted 0.231, its Q5_K_M 0.079 for 6 percent more file (tests/quant_compare_r2.sh); the probes decide which ships
# The reference keeps every token's full distribution (262k entries for Gemma 4), about 0.5 GB per 1,000 tokens, so 20
# chunks (about 11 GB, round 1 used 40) and deleted at once.
# Usage (pod): bash train/phone_file.sh NAME SFT_JSONL
set -uo pipefail
W=${W:-/workspace}; A=${A:-$W/therapist-app}; L=$W/llama.cpp/build/bin; OUT=$W/export; Q=$W/quants
PY=${PY:-$W/venv-vllm/bin/python}; M=$1; SFT=$2; mkdir -p $Q
B=$OUT/therapist-$M-bf16.gguf; F=$OUT/therapist-$M-Q4_K_M-imat.gguf
# made early (pod/early_phone.sh): its result lines again, nothing made twice
[ -s $OUT/therapist-$M.early ] && [ -s $F ] && { cat $OUT/therapist-$M.early; exit 0; }
[ -s $B ] || { echo "no bf16 file for $M"; exit 1; }
$PY -I - "$A/train" "$SFT" "$Q" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
from sft import split_by_profile  # the same held-out people as the training run (its default share and seed)
rows = [json.loads(l) for l in open(sys.argv[2])]
train, held = split_by_profile(rows, 0.05, 3407)
text = lambda rs: "\n\n".join("\n".join(m["content"] for m in r["messages"]) for r in rs)
open(f"{sys.argv[3]}/heldout.txt", "w").write(text(held)[:400000])
open(f"{sys.argv[3]}/calib.txt", "w").write(text(train[:400])[:400000])
print(f"held-out text from {len({r['id'].split('#')[0].rstrip('LR') for r in held})} people")
PY
$L/llama-perplexity -m $B -f $Q/heldout.txt -ngl 99 -c 2048 --chunks 20 --kl-divergence-base $Q/$M-base.kld \
    > $Q/$M-bf16.log 2>&1 || { echo "the bf16 reference failed for $M"; exit 1; }
$L/llama-imatrix -m $B -f $Q/calib.txt -ngl 99 -c 2048 --chunks 60 -o $Q/$M.imatrix > $Q/$M-imatrix.log 2>&1 \
    || { echo "the importance matrix failed for $M"; exit 1; }
$L/llama-quantize --imatrix $Q/$M.imatrix $B $F Q4_K_M > $Q/$M-quantize.log 2>&1 || { echo "quantize failed for $M"; exit 1; }
(cd $OUT && sha256sum $(basename $F)) >> $OUT/therapist-$M.sha256
$L/llama-perplexity -m $F -ngl 99 -c 2048 --chunks 20 --kl-divergence-base $Q/$M-base.kld --kl-divergence \
    > $Q/$M-imat.kl.log 2>&1
echo "$M phone file $(basename $F): $(grep -E 'Mean +KLD' $Q/$M-imat.kl.log | head -1) | $(grep -E '^Same top p' $Q/$M-imat.kl.log | head -1) (N3: mean KLD at most 0.16)"
F5=$OUT/therapist-$M-Q5_K_M-imat.gguf
if $L/llama-quantize --imatrix $Q/$M.imatrix $B $F5 Q5_K_M > $Q/$M-quantize5.log 2>&1; then
  (cd $OUT && sha256sum $(basename $F5)) >> $OUT/therapist-$M.sha256
  $L/llama-perplexity -m $F5 -ngl 99 -c 2048 --chunks 20 --kl-divergence-base $Q/$M-base.kld --kl-divergence \
      > $Q/$M-imat5.kl.log 2>&1
  echo "$M phone file $(basename $F5): $(grep -E 'Mean +KLD' $Q/$M-imat5.kl.log | head -1) | $(grep -E '^Same top p' $Q/$M-imat5.kl.log | head -1)"
else echo "Q5_K_M quantize failed for $M"; fi
rm -f $B $Q/$M-base.kld
