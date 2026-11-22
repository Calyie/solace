"""Build assets/practices/library_v1.json: the practice library.

guided practices are spoken by the voice step by step; each step is (text, seconds of silence after it), and "..."
inside a step is a short pause. interactive practices open a practice session in which the therapist guides the
person through the exercise, adapted to them. All wording is original; the techniques are standard ones.
"""
import json
from pathlib import Path

G, I = "guided", "interactive"

library = [
    # anxiety
    {"id": "longer-out-breath", "title": "Slow breathing with a longer out-breath", "category": "anxiety", "type": G,
     "when": "When anxiety or panic is rising, or before something stressful.",
     "versions": {
      "short": {"minutes": 3, "steps": [
        ("Let's slow things down together. You can keep your eyes open or close them, whatever feels better.", 3),
        ("Rest your feet on the floor... and let your shoulders drop a little.", 3),
        ("Breathe in through your nose for four... two... three... four.", 0),
        ("And out slowly through your mouth for six... two... three... four... five... six.", 2),
        ("Again. In for four... two... three... four.", 0),
        ("And out for six... two... three... four... five... six.", 2),
        ("Keep going at this pace on your own. The longer out-breath tells your body it is safe to settle.", 40),
        ("If your mind wanders, that's fine. Just come back to the count.", 40),
        ("Notice how you feel now compared with when we started... even a small change counts.", 5),
        ("You can use this any time, anywhere. Nobody needs to know you're doing it.", 0)]},
      "long": {"minutes": 8, "steps": [
        ("Let's spend a few minutes letting your body settle. Find a position that feels supported, sitting or lying down.", 4),
        ("Notice where your body touches the chair, the bed or the floor... and let it take your weight.", 5),
        ("Without changing anything yet, notice your breathing. Is it fast or slow, high in the chest or low in the belly?", 8),
        ("Now we'll lengthen the out-breath. Breathe in through your nose for four... two... three... four.", 0),
        ("And out through softly pursed lips for six... two... three... four... five... six.", 3),
        ("In for four... two... three... four. Out for six... two... three... four... five... six.", 3),
        ("Let your belly rise as you breathe in, and fall as you breathe out. Your hand can rest there if you like.", 5),
        ("Carry on with this rhythm on your own for a while.", 60),
        ("If thoughts pull you away, notice them kindly... and return to the next out-breath.", 60),
        ("Now let each out-breath soften one part of you: first your jaw...", 10),
        ("...then your shoulders...", 10),
        ("...then your hands.", 10),
        ("Keep breathing slowly.", 45),
        ("Let your breathing return to its own natural pace.", 10),
        ("Notice how you feel now. On a scale of 0 to 10, where is your anxiety compared with the start?", 5),
        ("Well done for giving yourself this time. This skill grows stronger every time you practise it.", 0)]}}},
    {"id": "grounding-54321", "title": "5-4-3-2-1 grounding", "category": "anxiety", "type": G,
     "when": "When you feel overwhelmed, flooded by a memory, or not quite present.",
     "versions": {"short": {"minutes": 3, "steps": [
        ("Let's bring you back to right here, right now. Keep your eyes open.", 2),
        ("Look around you and name five things you can see. Say them out loud or in your head.", 15),
        ("Now four things you can touch or feel. Your feet in your shoes... the chair under you... your clothes.", 15),
        ("Three things you can hear. Near sounds and far sounds.", 15),
        ("Two things you can smell, or two smells you like.", 12),
        ("And one thing you can taste, or one slow sip of water if you have some.", 10),
        ("Press your feet into the floor. Today is a new day, and you are here, in this room.", 4),
        ("How are you feeling now? You can repeat this as many times as you need.", 0)]}}},
    {"id": "worry-time", "title": "Worry time", "category": "anxiety", "type": G,
     "when": "When the same worries keep going round, especially in the evening.",
     "versions": {"short": {"minutes": 5, "steps": [
        ("This practice gives your worries a set time, so they don't take over your whole day.", 2),
        ("First, choose a worry time: fifteen minutes at the same time each day, not too close to bed.", 5),
        ("When a worry shows up outside that time, write it down in a few words. You can use the journal in the app.", 4),
        ("Then say to yourself: not now, I'll think about this at my worry time... and bring your attention back to what you were doing.", 5),
        ("It might come back. That's normal. Each time, note it and return. You are training your attention, not fighting your thoughts.", 5),
        ("At worry time, read your list. Some worries won't matter any more. For the ones that do, ask: is there something I can do about this?", 5),
        ("If there is, plan one small step. If there isn't, practise letting it be, and close the list until tomorrow.", 3),
        ("Shall we set your worry time now? You can choose it in the next screen.", 0)]}}},
    {"id": "surf-the-wave", "title": "Surfing a wave of panic", "category": "anxiety", "type": G,
     "when": "During a panic attack, or when panic is starting.",
     "versions": {"short": {"minutes": 4, "steps": [
        ("You're having a wave of panic. It feels awful, and it will pass. Panic always peaks and then falls.", 3),
        ("You don't need to fight it. Imagine it as a wave, and you are learning to ride it.", 3),
        ("Notice what your body is doing... a racing heart, tight chest, dizziness. These are uncomfortable, and they are not dangerous.", 4),
        ("Breathe out slowly, longer than you breathe in. Out for six... two... three... four... five... six.", 4),
        ("Rate the wave from 0 to 10 right now.", 6),
        ("Stay with it. Let it rise if it rises. You are still here, still breathing.", 20),
        ("Notice: is it the same, higher, or a little lower?", 10),
        ("Keep breathing out slowly. Feel your feet on the floor.", 30),
        ("Rate it again from 0 to 10. Even a small drop shows your body coming back down by itself.", 5),
        ("You rode it. Every time you stay with a wave instead of escaping it, the next one has less power.", 0)]}}},
    # meditation
    {"id": "body-scan", "title": "Body scan", "category": "meditation", "type": G,
     "when": "For tension, for rest, or to come back into your body.",
     "versions": {
      "short": {"minutes": 5, "steps": [
        ("Settle into a comfortable position. Let your eyes close, or rest them on one spot.", 4),
        ("Take one slow breath in... and a long breath out.", 4),
        ("Bring your attention to your feet. Notice whatever is there: warmth, coolness, tingling, or nothing at all. All of it is fine.", 15),
        ("Move your attention up through your legs... your knees... your thighs.", 15),
        ("Now your belly and your back. Notice the breath moving here.", 15),
        ("Your chest, your shoulders, your arms, down to your hands.", 15),
        ("Your neck, your jaw, your face. Let your forehead soften.", 15),
        ("Now feel your whole body at once, breathing.", 15),
        ("When you're ready, wriggle your fingers and toes, and open your eyes.", 0)]},
      "long": {"minutes": 15, "steps": [
        ("Welcome. For the next fifteen minutes, there is nothing to fix and nowhere to get to. Lie down or sit in a way that feels supported.", 5),
        ("If at any point this feels too much, open your eyes, look around the room, and feel your feet. You are in charge.", 4),
        ("Let your eyes close if that feels right. Take three slow breaths, letting each out-breath be a little longer.", 15),
        ("Bring your attention to the toes of your left foot. You don't need to move them. Just notice.", 20),
        ("Now the sole of the foot... the heel... the top of the foot... the ankle.", 25),
        ("Slowly move up through the left lower leg... the knee... the thigh. If you notice tension, breathe into it, and let it be as it is.", 30),
        ("Now move to the toes of your right foot... and slowly up the right foot and ankle.", 25),
        ("The right lower leg... the knee... the thigh.", 30),
        ("Notice your hips and pelvis, and the places where your body rests on the surface beneath you.", 25),
        ("Bring your attention to your belly. Feel it rise and fall with each breath.", 30),
        ("Your lower back... your upper back... your shoulder blades. Let the surface take your weight.", 30),
        ("Your chest, the heart beating, the lungs filling and emptying.", 25),
        ("Your shoulders. Many of us carry a lot here. See if they can drop, even a little.", 25),
        ("Down your arms... your elbows... your wrists... into your hands and each finger.", 30),
        ("Your neck and throat. Your jaw: let your teeth part slightly.", 20),
        ("Your face: your cheeks, around your eyes, your forehead, the top of your head.", 25),
        ("Now sense your whole body, from your toes to the top of your head, breathing as one.", 40),
        ("Rest here for a little while.", 60),
        ("Begin to deepen your breath. Move your fingers and toes. Stretch if you like.", 10),
        ("When you're ready, open your eyes. Take this calm with you into the rest of your day.", 0)]}}},
    {"id": "loving-kindness", "title": "Loving-kindness", "category": "meditation", "type": G,
     "when": "When you feel harsh towards yourself or others, lonely, or disconnected.",
     "versions": {
      "short": {"minutes": 5, "steps": [
        ("Sit comfortably and let your breathing settle.", 4),
        ("Bring to mind someone who makes you smile easily. A friend, a grandparent, even a pet.", 8),
        ("Silently offer them these wishes: may you be safe... may you be well... may you be at ease.", 15),
        ("Now turn the same wishes towards yourself, even if it feels strange: may I be safe... may I be well... may I be at ease.", 20),
        ("If it feels hard, that's okay. Imagine the person you love saying these words to you.", 15),
        ("Finally, widen the circle to everyone around you today: may you all be safe, well and at ease.", 15),
        ("Notice any warmth, softness or resistance, without judging it. Gently open your eyes.", 0)]},
      "long": {"minutes": 12, "steps": [
        ("Find a comfortable position and let your breathing find its own rhythm.", 6),
        ("You can put a hand on your heart if you like. Feel its warmth.", 8),
        ("Bring to mind someone who cares for you, or who you care for easily. Picture their face.", 12),
        ("Offer them these wishes, slowly, letting each one land: may you be safe.", 8),
        ("May you be well.", 8),
        ("May you be at ease.", 8),
        ("May you be happy.", 15),
        ("Now imagine this person turning and offering the same wishes to you. May you be safe. May you be well. May you be at ease. May you be happy.", 20),
        ("Let yourself receive them, as much as you can today.", 20),
        ("Now offer the wishes to yourself, in your own voice: may I be safe... may I be well... may I be at ease... may I be happy.", 30),
        ("If a voice says you don't deserve this, notice it kindly, and carry on anyway.", 20),
        ("Bring to mind someone neutral: a neighbour, someone at a shop. They also want to be happy. May you be safe, well and at ease.", 25),
        ("If you feel ready, bring to mind someone a little difficult. Not the hardest person. May you also be safe, well and at ease.", 25),
        ("Finally, let the wishes spread to everyone, everywhere: may all beings be safe, well, at ease and happy.", 25),
        ("Rest in whatever you feel now.", 30),
        ("When you're ready, take a slow breath, and open your eyes.", 0)]}}},
    {"id": "breath-awareness", "title": "Breath awareness", "category": "meditation", "type": G,
     "when": "For a calm, clear mind; a good daily practice.",
     "versions": {
      "short": {"minutes": 5, "steps": [
        ("Sit upright but relaxed, as if you are sitting with dignity.", 4),
        ("Let your breath be natural. Find where you feel it most clearly: the nose, the chest, or the belly.", 10),
        ("Rest your attention there, feeling each breath in and each breath out.", 30),
        ("Your mind will wander. That's what minds do. When you notice, simply come back to the breath. That moment of noticing is the practice.", 40),
        ("Keep resting with the breath.", 60),
        ("Now widen your attention to the whole body, sitting and breathing.", 15),
        ("Open your eyes when you're ready.", 0)]},
      "long": {"minutes": 15, "steps": [
        ("Sit upright but relaxed. Let your hands rest wherever is comfortable.", 5),
        ("Take a few deeper breaths, then let the breath return to its own pace.", 15),
        ("Choose one place to feel the breath: the cool air at the nose, the chest rising, or the belly moving.", 15),
        ("Rest your attention there.", 60),
        ("When your mind wanders, notice where it went... thinking, planning, remembering... and gently come back.", 60),
        ("You might count breaths from one to ten, then start again, if that helps you stay with it.", 90),
        ("If something in the body asks for attention, let it, then return to the breath.", 90),
        ("Keep sitting, just breathing.", 120),
        ("Let go of any effort. Let the breath breathe itself.", 90),
        ("Now widen your attention to sounds around you... and the whole body sitting here.", 30),
        ("Take a moment to thank yourself for this time. Open your eyes when you're ready.", 0)]}}},
    {"id": "sleep-wind-down", "title": "Winding down for sleep", "category": "sleep", "type": G,
     "when": "In bed, when your mind is busy.",
     "versions": {"long": {"minutes": 10, "steps": [
        ("Let yourself lie down comfortably. There's nothing you need to do now except rest.", 6),
        ("Breathe in gently... and let a long, slow breath out, like a sigh.", 8),
        ("Let your body sink into the bed. Feel how heavy your legs are... your arms... your head on the pillow.", 15),
        ("If thoughts about today or tomorrow come, imagine putting each one in a box by the bed. It will be there in the morning.", 20),
        ("Breathe in for four... and out for six... letting each out-breath carry you a little deeper.", 30),
        ("Soften your forehead... your eyes... your jaw.", 20),
        ("Picture a place where you feel calm and safe, real or imagined. Notice the light there, the sounds, the temperature.", 40),
        ("Let yourself rest in that place.", 60),
        ("There's no need to try to sleep. Rest is enough. Sleep will come when it's ready.", 60),
        ("I'll be quiet now. Goodnight.", 0)]}}},
    # mindfulness
    {"id": "rain", "title": "RAIN for a difficult feeling", "category": "mindfulness", "type": G,
     "when": "When a strong feeling like shame, fear or anger takes hold.",
     "versions": {"short": {"minutes": 8, "steps": [
        ("This practice helps you meet a difficult feeling instead of being swept away by it. It has four steps.", 3),
        ("R is for recognise. Notice what you're feeling right now and name it simply: this is fear, this is shame, this is sadness.", 15),
        ("A is for allow. Let the feeling be here, just for now. You don't have to like it. You might say: it's okay to feel this.", 20),
        ("I is for investigate, with kindness. Where do you feel it in your body? What is this feeling believing? What does it need?", 30),
        ("N is for nurture. Offer yourself what you need: a kind sentence, a hand on your heart, the words a good friend would say.", 30),
        ("Now just rest for a moment. Notice who you are, beyond this feeling: someone who can hold it with care.", 20),
        ("How is the feeling now? Often it softens a little, even if it's still there.", 0)]}}},
    {"id": "leaves-on-a-stream", "title": "Leaves on a stream", "category": "mindfulness", "type": G,
     "when": "When thoughts feel sticky or very convincing.",
     "versions": {"short": {"minutes": 6, "steps": [
        ("Close your eyes or rest them on one spot. Imagine sitting beside a gently flowing stream.", 6),
        ("Leaves are floating past on the water.", 6),
        ("For the next few minutes, each time a thought comes, place it on a leaf and watch it float away. Words, pictures, worries: all of them.", 10),
        ("If a thought is 'this isn't working', put that on a leaf too.", 40),
        ("If you get caught up in a thought, that's fine. Notice that you got hooked, and come back to the stream.", 45),
        ("The stream keeps flowing. You don't need to push the leaves or hold on to them.", 45),
        ("Now let the image fade, and come back to the room.", 5),
        ("Thoughts are things you have, not things you are. You can watch them without obeying them.", 0)]}}},
    {"id": "breathing-space", "title": "Three-minute breathing space", "category": "mindfulness", "type": G,
     "when": "A quick reset during a busy or difficult day.",
     "versions": {"short": {"minutes": 3, "steps": [
        ("Wherever you are, pause. Sit or stand a little taller.", 3),
        ("First minute: what's here right now? Notice your thoughts, your feelings, and your body, without trying to change them.", 50),
        ("Second minute: gather your attention onto your breathing. Follow each breath in and out.", 50),
        ("Third minute: widen your attention to your whole body, breathing, and the space around you.", 45),
        ("Now carry this steadiness into your next step.", 0)]}}},
    # self-compassion
    {"id": "self-compassion-break", "title": "Self-compassion break", "category": "self_compassion", "type": G,
     "when": "When you're being hard on yourself or going through something painful.",
     "versions": {"short": {"minutes": 4, "steps": [
        ("Think of a situation that is hurting you right now. Not the hardest one; something medium.", 10),
        ("Notice the pain of it. Say to yourself: this is a moment of difficulty. This hurts.", 12),
        ("Remind yourself that you are not alone in this: everyone struggles sometimes. Other people feel exactly this.", 12),
        ("Put a hand on your heart, or anywhere that feels soothing, and feel its warmth.", 8),
        ("Now say something kind to yourself, in your own words. For example: may I be gentle with myself... may I give myself what I need.", 20),
        ("If the words feel hard to believe, imagine saying them to a friend in the same situation, then let some of that warmth come back to you.", 20),
        ("Notice how you feel. Kindness to yourself is a skill, and it grows with practice.", 0)]}}},
    {"id": "compassionate-friend", "title": "The compassionate friend", "category": "self_compassion", "type": G,
     "when": "When the inner critic is loud.",
     "versions": {"short": {"minutes": 6, "steps": [
        ("Close your eyes and imagine a safe, comfortable place.", 8),
        ("Soon you'll have a visitor: someone wise and kind, who accepts you completely. They might be someone you know, a figure from your faith, or someone imagined.", 10),
        ("Picture them arriving. Notice how they look at you: warmly, without judgement.", 15),
        ("They know what you've been going through. Listen to what they say to you.", 30),
        ("What do they understand about you that you forget?", 25),
        ("Is there anything you want to say to them?", 25),
        ("They leave you with a small gift or a few words to keep. Notice what it is.", 15),
        ("Let the image fade, and come back to the room, bringing their kindness with you.", 0)]}}},
    # purpose and coaching (interactive: run by the therapist as a practice session)
    {"id": "wheel-of-life", "title": "Wheel of life", "category": "purpose", "type": I, "minutes": 10,
     "practice_name": "wheel of life",
     "when": "To see where your life feels balanced and where you'd like change.",
     "about": "You name your own life areas, rate each from 1 to 10, and choose one to raise. You'll see the wheel change month by month."},
    {"id": "ikigai", "title": "Ikigai: finding your reason for being", "category": "purpose", "type": I, "minutes": 15,
     "practice_name": "ikigai questions",
     "when": "When you're searching for direction or meaning.",
     "about": "Four questions, one at a time: what you love, what you're good at, what the world needs, and what can sustain you. Then one small experiment."},
    {"id": "values-compass", "title": "Values compass", "category": "purpose", "type": I, "minutes": 10,
     "practice_name": "values compass",
     "when": "When you feel stuck, or unsure what to do next.",
     "about": "Find what matters most to you in one area of life, and one action this week that moves towards it."},
    {"id": "best-possible-self", "title": "Your best possible self", "category": "purpose", "type": G,
     "when": "To lift your mood and clarify what you want.",
     "versions": {"short": {"minutes": 8, "steps": [
        ("Imagine yourself a few years from now, when things have gone as well as they realistically could.", 8),
        ("You've worked hard and reached the goals that matter to you. Where are you living? What does an ordinary day look like?", 30),
        ("Who is around you? How do you treat them, and how do they treat you?", 30),
        ("What are you doing with your time that feels meaningful?", 30),
        ("How do you feel about yourself in this future?", 25),
        ("Now come back to today. What is one small step, this week, in the direction of that person?", 15),
        ("You can write it down in your journal, and we can make it this week's homework if you like.", 0)]}}},
    {"id": "habit-design", "title": "Designing a habit", "category": "focus", "type": I, "minutes": 10,
     "practice_name": "habit design",
     "when": "To start a habit that lasts.",
     "about": "Start tiny, link it to something you already do, plan when and where, decide how to track it, and plan for the day you miss it."},
    # focus
    {"id": "focus-block", "title": "Starting a focus block", "category": "focus", "type": G,
     "when": "When you can't get started, or your attention keeps slipping.",
     "versions": {"short": {"minutes": 2, "steps": [
        ("Let's get you started. What's the one task for this block? Say it in a few words.", 8),
        ("What's the very smallest first step? Opening the file, writing one sentence, reading one page.", 8),
        ("Put your phone out of reach, or face down, and close anything you don't need.", 8),
        ("You'll work for twenty minutes, then take a five-minute break. You don't have to finish, only to start.", 3),
        ("Take one slow breath... and begin the first step now. I'll start the timer.", 0)]}}},
    {"id": "attention-anchor", "title": "One-minute attention reset", "category": "focus", "type": G,
     "when": "When you notice you've drifted, daydreamed, or scrolled.",
     "versions": {"short": {"minutes": 1, "steps": [
        ("Notice that you drifted. No blame; noticing is the skill.", 2),
        ("Feel your feet on the floor and take one slow breath out.", 6),
        ("Look at one object in front of you for a few seconds, really seeing it.", 8),
        ("Now name the task you are returning to, and the very next step.", 5),
        ("Off you go.", 0)]}}},
    # stabilisation (trauma)
    {"id": "calm-place", "title": "Calm place", "category": "stabilisation", "type": G,
     "when": "To build a feeling of safety you can return to, especially after hard memories.",
     "versions": {"short": {"minutes": 6, "steps": [
        ("Keep your eyes open or closed, whatever feels safer. You can stop at any time.", 4),
        ("Bring to mind a place where you feel calm and safe. It can be real, from a memory, or completely imagined.", 12),
        ("Look around this place. What do you see? Notice the colours and the light.", 20),
        ("What can you hear there?", 15),
        ("What does the air feel like on your skin? Is it warm or cool?", 15),
        ("Notice how your body feels in this calm place. Let that feeling grow a little.", 20),
        ("Choose a word that reminds you of this place.", 10),
        ("Whenever you need it, you can say the word and come back here, even for a few seconds.", 5),
        ("Now come back to the room. Feel your feet, and look around you.", 0)]}}},
    {"id": "container", "title": "The container", "category": "stabilisation", "type": G,
     "when": "When a memory or worry keeps intruding and now is not the time to deal with it.",
     "versions": {"short": {"minutes": 5, "steps": [
        ("This exercise helps you put something aside safely, until the right time to look at it.", 3),
        ("Imagine a strong container: a box, a safe, a chest. Make it as solid as you need.", 12),
        ("Picture placing the memory, feeling or worry inside. It might be an image, a word, or a colour.", 20),
        ("Close the container firmly. Lock it if you like.", 10),
        ("Put it somewhere safe, out of the way. It will be there when you choose to come back to it, perhaps in a session.", 12),
        ("Take a slow breath, feel your feet, and look around the room.", 0)]}}},
]

out = Path(__file__).resolve().parent.parent / "assets" / "practices" / "library_v1.json"
out.parent.mkdir(parents=True, exist_ok=True)
WPM = 140                      # a slow, calm speaking pace
NATURAL_PACE = {"worry-time", "focus-block", "attention-anchor", "grounding-54321"}  # instructions: never stretched


def timed(pid: str, minutes: int, steps: list) -> dict:
    """Stretch the silences (not the words) towards the intended length, at most 120 s per pause; then label the
    practice with its real length, so the minutes shown in the app are always true."""
    spoken = sum(len(t.split()) for t, _ in steps) * 60 / WPM
    silence = sum(x for _, x in steps)
    factor = 1.0
    if pid not in NATURAL_PACE and silence and spoken + silence < minutes * 60:
        factor = (minutes * 60 - spoken) / silence
    out = [{"text": t, "pause": min(120, round(x * factor))} for t, x in steps]
    real = (spoken + sum(x["pause"] for x in out)) / 60
    return {"minutes": max(1, round(real)), "steps": out}


rows = []
for p in library:
    p = dict(p)
    if p["type"] == G:
        p["versions"] = {k: timed(p["id"], v["minutes"], v["steps"]) for k, v in p["versions"].items()}
    rows.append(p)
out.write_text(json.dumps(rows, ensure_ascii=False, indent=1))
cats = {}
for p in rows:
    cats[p["category"]] = cats.get(p["category"], 0) + 1
words = sum(len(s["text"].split()) for p in rows if p["type"] == G for v in p["versions"].values() for s in v["steps"])
print(f"{len(rows)} practices ({sum(p['type'] == G for p in rows)} guided, {sum(p['type'] == I for p in rows)} interactive),"
      f" {words} spoken words; by category: {cats}")
