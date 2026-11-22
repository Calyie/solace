# OW-M2-2 (owner, 2026-11-15: "Fix this too"): sherpa-onnx 2.x has no espeak-ng, so Kokoro speaks only words in its
# lexicon. The shipped lexicons (misaki's dictionaries) hold base forms: "make" but not "makes", "notice" but not
# "noticed", no "that's". This builds an extra lexicon of inflected forms from the base forms' own phonemes, with the
# suffix rules misaki (Kokoro's own G2P, Apache-2.0) uses: -s/-'s (s after p t k f θ; ᵻz/ɪz after sibilants; z else),
# -ed (t after voiceless; ᵻd/ɪd after d or t; d else), -ing (ɪŋ), -ly (l i). Only for words seen in the app's own text
# and in therapy dialogue (corpus files given), and only when the base form is in the shipped lexicon.
# Usage: python3 make_extra_lexicon.py us|gb LEXICON OUT corpus.txt...
import re, sys, collections
accent, lexpath, out, *corpus = sys.argv[1:]
gb = accent == 'gb'
lex = {}
for l in open(lexpath, encoding='utf-8'):
    w, _, ph = l.rstrip('\n').partition(' ')
    if w and ph and w.lower() not in lex:
        lex[w.lower()] = ph.split()
STRESS = {'ˈ', 'ˌ'}
def last(ph):
    for p in reversed(ph):
        if p not in STRESS: return p
    return ''
def s_(ph):
    e = last(ph)
    if not e: return None
    if e in 'ptkfθ': return ph + ['s']
    if e in 'szʃʒʧʤ': return ph + ['ɪ' if gb else 'ᵻ', 'z']
    return ph + ['z']
def ed_(ph):
    e = last(ph)
    if not e: return None
    if e in 'pkfθʃsʧ': return ph + ['t']
    if e in 'dt': return ph + ['ɪ' if gb else 'ᵻ', 'd']
    return ph + ['d']
def ing_(ph): return ph + ['ɪ', 'ŋ']
def ly_(ph): return ph + ['l', 'i']
def y_stem(w):  # worries -> worry, happiest -> happy
    return lex.get(w + 'y')
ARPA = {'AA': 'ɑ', 'AE': 'æ', 'AO': 'ɔ', 'AW': 'W', 'AY': 'I', 'EH': 'ɛ', 'EY': 'A', 'IH': 'ɪ', 'IY': 'i', 'OW': 'Q' if gb else 'O',
        'OY': 'Y', 'UH': 'ʊ', 'UW': 'u', 'B': 'b', 'CH': 'ʧ', 'D': 'd', 'DH': 'ð', 'F': 'f', 'G': 'ɡ', 'HH': 'h', 'JH': 'ʤ',
        'K': 'k', 'L': 'l', 'M': 'm', 'N': 'n', 'NG': 'ŋ', 'P': 'p', 'R': 'ɹ', 'S': 's', 'SH': 'ʃ', 'T': 't', 'TH': 'θ',
        'V': 'v', 'W': 'w', 'Y': 'j', 'Z': 'z', 'ZH': 'ʒ'}
cmu = {}
for l in open('cmudict.dict', encoding='utf-8', errors='ignore'):
    parts = l.split('#')[0].split()
    if len(parts) < 2 or '(' in parts[0]: continue
    pron = []
    for a in parts[1:]:
        base, st = a.rstrip('012'), a[len(a.rstrip('012')):]
        if base == 'AH': ph = ['ə'] if st == '0' else ['ʌ']
        elif base == 'ER': ph = ['ɚ'] if st == '0' else (['ɜ', 'ː'] if gb else ['ɜ', 'ɹ'])
        elif base in ARPA: ph = [ARPA[base]]
        else: pron = None; break
        if st == '1': pron.append('ˈ')
        elif st == '2': pron.append('ˌ')
        pron += ph
    if pron: cmu.setdefault(parts[0].lower(), pron)
def derive(w):
    cands = []
    if w.endswith("n't") and w[:-3] in lex: cands.append(lex[w[:-3]] + ['ə', 'n', 't'])  # isn't, wasn't
    if w.endswith("'ll") and w[:-3] in lex: cands.append(lex[w[:-3]] + ['l'])            # I'll, we'll
    if w.endswith("'ve") and w[:-3] in lex: cands.append(lex[w[:-3]] + ['v'])            # I've, they've
    if w.endswith("'s") and w[:-2] in lex: cands.append(s_(lex[w[:-2]]))
    if w.endswith("s'") and w[:-1] in lex: cands.append(lex[w[:-1]])
    if w.endswith('ies') and y_stem(w[:-3]): cands.append(s_(y_stem(w[:-3])))
    if w.endswith('es') and w[:-2] in lex and w[-3] in 'sxzh': cands.append(s_(lex[w[:-2]]))
    if w.endswith('s') and not w.endswith('ss') and w[:-1] in lex: cands.append(s_(lex[w[:-1]]))
    if w.endswith('ied') and y_stem(w[:-3]): cands.append(ed_(y_stem(w[:-3])))
    if w.endswith('ed'):
        if w[:-1] in lex: cands.append(ed_(lex[w[:-1]]))                      # noticed <- notice
        if w[:-2] in lex: cands.append(ed_(lex[w[:-2]]))                      # walked <- walk
        if len(w) > 4 and w[-3] == w[-4] and w[:-3] in lex: cands.append(ed_(lex[w[:-3]]))  # stopped <- stop
    if w.endswith('ing'):
        if w[:-3] in lex: cands.append(ing_(lex[w[:-3]]))
        if w[:-3] + 'e' in lex: cands.append(ing_(lex[w[:-3] + 'e']))         # making <- make
        if len(w) > 5 and w[-4] == w[-5] and w[:-4] in lex: cands.append(ing_(lex[w[:-4]]))  # stopping <- stop
    if w.endswith('ly') and w[:-2] in lex: cands.append(ly_(lex[w[:-2]]))
    if w.endswith('ily') and y_stem(w[:-3]): cands.append(y_stem(w[:-3])[:-1] + ['ə', 'l', 'i'])
    return next((c for c in cands if c), None) or cmu.get(w)
words = collections.Counter()
for f in corpus:
    for t in re.findall(r"[A-Za-z][A-Za-z']*[A-Za-z]|[A-Za-z]", open(f, encoding='utf-8', errors='ignore').read().replace('’', "'")):
        words[t.lower().replace('’', "'")] += 1
extra, still = {}, collections.Counter()
for w, n in words.items():
    if w in lex: continue
    ph = derive(w)
    if ph: extra[w] = ph
    else: still[w] = n
with open(out, 'w', encoding='utf-8') as f:
    for w in sorted(extra): f.write(w + ' ' + ' '.join(extra[w]) + '\n')
tot = sum(words.values()); miss_before = sum(n for w, n in words.items() if w not in lex)
miss_after = sum(still.values())
print(f'{accent}: {len(extra)} derived words; missing words {miss_before/tot:.2%} -> {miss_after/tot:.2%} of {tot} running words')
print('  still missing (most common):', still.most_common(40))
