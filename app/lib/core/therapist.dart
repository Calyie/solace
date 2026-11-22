// The therapist people choose (owner, 2026-11-05): a portrait for calls and a voice. The portraits are fictional
// women made with an open image model (Qwen-Image-2512); none is based on a real person. The voices are Kokoro's
// Heart and Bella, the two the owner rated highest in a blind test, and both run on every device; Heart is the
// default since 2026-11-13 (owner: "Heart is way better than Bella").
// Three women and three men (owner, 2026-11-16: "we only need 3 women and 3 men portraits"; the South Asian woman,
// p4, was removed, and a setting that named her falls back to p1 in Settings.fromJson).
const portraits = <String, String>{
  'p1': 'assets/therapist/portrait_1.jpg', // African American
  'p2': 'assets/therapist/portrait_2.jpg', // white
  'p3': 'assets/therapist/portrait_3.jpg', // East Asian
  // three fictional men in their forties (owner, 2026-11-14), same model and recipe (media/male_portraits_modal.py)
  'p5': 'assets/therapist/portrait_5.jpg', // mixed Indian heritage
  'p6': 'assets/therapist/portrait_6.jpg', // African American
  'p7': 'assets/therapist/portrait_7.jpg', // white
};

String portraitFor(String id) => portraits[id] ?? portraits['p1']!;

/// The therapist's name for each portrait (owner, 2026-11-19: "give the model a name and personality"). The model
/// reads it in its instructions (prompt v5, {therapist_name}) and introduces itself by it; training used many names,
/// so any of these works.
const therapistNames = <String, String>{
  'p1': 'Maya', 'p2': 'Claire', 'p3': 'Mei', 'p5': 'Arjun', 'p6': 'Daniel', 'p7': 'Keith',
};

String therapistNameFor(String portrait) => therapistNames[portrait] ?? therapistNames['p1']!;
