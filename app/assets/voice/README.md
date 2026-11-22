# Extra speech lexicons (OW-M2-2)

sherpa-onnx 2.x has no espeak-ng (its memory-safety bugs were finding OW-M2-2), so Kokoro speaks only words found in a
lexicon. The voice bundle's lexicons (misaki's dictionaries, Apache-2.0) hold base forms only ("make", not "makes";
no "that's"). These files add, for words seen in therapist replies, CACTUS counsellor lines and the app's practices:

- inflected forms derived from the base form's own phonemes with misaki's suffix rules (-s, -'s, -ed, -ing, -ly,
  n't, 'll, 've);
- other words and names from CMUdict (BSD-style licence, CMUDICT_LICENSE.txt), mapped from ARPAbet to Kokoro's phonemes.

Built by train/make_extra_lexicon.py (us or gb); every phoneme is one in the model's tokens.txt. On 13.5 million running
words of therapy dialogue, words missing from the lexicons fall from 3.4 % to 0.01 %.
