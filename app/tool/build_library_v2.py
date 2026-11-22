"""Build assets/practices/library_v2.json: the Meditate library (listen-only) plus tools and in-the-moment helpers.

Owner's direction (2026-10-29): meditation must be effortless (press play, nothing to fill in) yet work better than the
usual app meditations. Built on three routes with evidence: the body (breathing patterns), imagery (compassion,
future self, savouring), and deep relaxation (hypnosis-style, deep rest). Each one is quietly personalised from the
app's memory with {slot|fallback} fields the app fills in (value, goal, today_focus, struggle, good_moment,
kind_phrase, calm_word); nothing is asked of the person. All wording is original.

Step = (text, seconds of silence after it[, "pacer"]) - "pacer" shows and sounds the breathing guide in the silence.
"""
import json
from pathlib import Path

M, T, I = "meditation", "tool", "interactive"
CYCLIC = [["in", 2], ["and in again", 1], ["slowly out", 6]]
SIX = [["in", 5], ["out", 5]]

library = [
    # Calm the body, fast
    {"id": "cyclic-sighing", "title": "Five-minute sigh", "category": "calm", "type": M, "pacer": CYCLIC,
     "evidence": "Strong for a short practice: five minutes a day for a month lifted mood and lowered breathing rate "
                 "more than mindfulness meditation in a 2023 Stanford trial (Balban and others).",
     "when": "Any time you want to feel calmer, or every day to build the habit.",
     "versions": {"short": {"minutes": 5, "steps": [
        ("This is one of the quickest ways to calm your body, and all you do is breathe. You breathe in twice through "
         "your nose, and then out slowly through your mouth, for longer.", 3),
        ("Let's do one together. Breathe in through your nose... then a second, smaller sip of air on top... and "
         "now let it all go, slowly, through your mouth.", 4),
        ("That second sip opens your lungs a little more, and the long breath out tells your body it is safe to "
         "settle. Now keep going at this pace. The circle and the soft tones will guide you.", 60, "pacer"),
        ("If you feel light-headed, slow down, or breathe normally for a few breaths. There is no right way to feel.", 60, "pacer"),
        ("Let each long breath out soften something: your jaw... your shoulders... your hands.", 60, "pacer"),
        ("A little longer. You're doing nothing wrong if your mind wanders. The breath brings you back.", 60, "pacer"),
        ("Now let your breathing find its own pace again... and notice how you feel, compared with five minutes "
         "ago.", 8),
        ("Even on good days, these five minutes teach your body the way back to calm, so it finds it faster when you "
         "need it.", 0)]}}},
    {"id": "six-breaths", "title": "Slow breathing at six a minute", "category": "calm", "type": M, "pacer": SIX,
     "evidence": "Strong: slow breathing near six breaths a minute (resonance breathing) reduced stress and anxiety "
                 "across many trials (meta-analysis, Goessl and others, 2017).",
     "when": "For stress, anxiety, or before something hard. Ten minutes, mostly in calm silence.",
     "versions": {"short": {"minutes": 10, "steps": [
        ("For the next ten minutes, you'll breathe at about six breaths a minute: in for five, out for five. At this "
         "pace, your heart and your breathing fall into a steady rhythm together, and your body settles.", 3),
        ("The rising tone means breathe in, the falling tone means breathe out. Breathe gently, through your nose if "
         "you can, into your belly. Not too deep.", 2),
        ("Just follow.", 120, "pacer"),
        ("If your mind wanders, that's fine. The tones bring you back.", 120, "pacer"),
        ("Let the breath be soft and quiet, as if you were breathing next to someone asleep.", 120, "pacer"),
        ("Stay with the rhythm.", 120, "pacer"),
        ("Last minute.", 60, "pacer"),
        ("Now let go of the rhythm, and breathe however your body wants to... Notice the steadiness that's here. "
         "It's yours, and it comes back more easily each time.", 0)]}}},
    {"id": "surf-the-wave", "title": "Riding a wave of panic", "category": "calm", "type": T, "pacer": CYCLIC,
     "evidence": "Well established: panic peaks and passes; staying with it rather than escaping weakens it, and "
                 "long out-breaths calm the body.",
     "when": "During a panic attack, or when panic is starting.",
     "versions": {"short": {"minutes": 4, "steps": [
        ("You're having a wave of panic. It feels awful, and it will pass. Panic always rises, peaks and falls.", 3),
        ("Your racing heart and tight chest are uncomfortable, and they are not dangerous. Your body is doing an "
         "alarm drill. You don't need to fight it.", 3),
        ("Breathe in twice through your nose, then out slowly through your mouth. Follow the circle.", 40, "pacer"),
        ("Feel your feet on the floor. You are still here, still breathing.", 40, "pacer"),
        ("Notice: is the wave the same, higher, or a little lower now?", 30, "pacer"),
        ("Every time you ride a wave instead of running from it, the next one has less power.", 0)]}}},
    {"id": "grounding-54321", "title": "5-4-3-2-1: back to the present", "category": "calm", "type": T,
     "evidence": "A standard grounding skill used in trauma and anxiety care.",
     "when": "When you feel overwhelmed, flooded by a memory, or not quite here.",
     "versions": {"short": {"minutes": 2, "steps": [
        ("Let's bring you back to right here, right now. Keep your eyes open.", 2),
        ("Look around and find five things you can see.", 15),
        ("Four things you can feel: your feet in your shoes, the chair under you, your clothes.", 15),
        ("Three things you can hear.", 15),
        ("Two things you can smell, or two smells you like.", 12),
        ("One thing you can taste.", 10),
        ("Press your feet into the floor. Today is a new day, and you are here.", 0)]}}},
    # Start the day
    {"id": "morning-lift", "title": "Morning lift", "category": "morning", "type": M, "pacer": CYCLIC,
     "evidence": "Combines a breathing pattern with strong evidence and vivid rehearsal of a real moment today; just "
                 "listen. Your focus for the day comes from what you have told the app.",
     "when": "Each morning, before the day takes over. Nothing to do but listen.",
     "versions": {"short": {"minutes": 5, "steps": [
        ("Good morning. Before the day starts, let's give your body and mind a good beginning. There's nothing to do "
         "but listen.", 3),
        ("Three slow sighs together: in through the nose, a second sip on top, and a long breath out.", 30, "pacer"),
        ("Feel the day ahead without rushing into it yet. Whatever it holds, you can meet it one moment at a time.", 6),
        ("Today, let this guide you: {value|what matters most to you}.", 6),
        ("Picture one moment later today when you act from that. It can be small. See where you are... who's "
         "there... what you do... and how it feels in your body to do it.", 30),
        ("If there's one thing to move forward today, let it be this: {today_focus|one small step towards the life "
         "you want}. Imagine the first minute of doing it... how simple that first minute is.", 25),
        ("And whatever the day brings, here are words to carry with you: {kind_phrase|I'm doing my best, and that is "
         "enough for today}.", 8),
        ("One more long breath out... and go gently into your day.", 0)]}}},
    # Kindness to yourself
    {"id": "compassionate-companion", "title": "The compassionate companion", "category": "kindness", "type": M,
     "evidence": "Moderate: compassion-focused imagery and related practices reduce self-criticism, shame and low "
                 "mood (meta-analysis, Kirby and others, 2017).",
     "when": "When the inner critic is loud, or you feel not good enough.",
     "versions": {"short": {"minutes": 10, "steps": [
        ("Sit or lie comfortably. Let your breathing slow down a little, just slightly slower than usual, soothing "
         "and even.", 20),
        ("Let your face soften into a gentle, friendly expression, the way you'd look at someone you're fond of.", 10),
        ("Now imagine a presence coming to be with you. A compassionate companion: wise, strong, warm, and completely "
         "on your side. It doesn't have to be a person. It can be a figure, a light, an animal, whatever feels right.", 20),
        ("Notice how they look at you. There's no judgement in their eyes. Only understanding, and a deep wish for "
         "you to be well.", 20),
        ("They know about {struggle|what has been hard for you lately}. They know how hard you've been trying, "
         "including the parts nobody sees.", 20),
        ("Let them come a little closer. Notice their voice, calm and kind. Listen to what they want to say to you.", 40),
        ("They say: {kind_phrase|You don't have to be perfect to deserve kindness}. Let the words land, even if part "
         "of you doesn't believe them yet.", 25),
        ("They remind you that your care about {value|the things that matter to you} is not a weakness. It's one of "
         "the best things about you.", 20),
        ("Breathe in their warmth. Breathe out anything you've been carrying alone.", 40),
        ("This companion isn't really outside you. It's a part of you that you're learning to hear. You can come "
         "back to it any time.", 10),
        ("Let the image fade, take a slow breath, and come back to the room.", 0)]}}},
    {"id": "loving-kindness", "title": "Loving-kindness", "category": "kindness", "type": M,
     "evidence": "Moderate: increases warm, positive feelings towards yourself and others across trials.",
     "when": "When you feel harsh, lonely or disconnected.",
     "versions": {"short": {"minutes": 6, "steps": [
        ("Sit comfortably, and let your breathing settle. You might put a hand on your heart.", 10),
        ("Bring to mind someone who makes you smile easily: a friend, a grandparent, even a pet.", 12),
        ("Offer them these wishes: may you be safe... may you be well... may you be at ease.", 25),
        ("Now imagine them offering the same wishes back to you: may you be safe... may you be well... may you be at "
         "ease.", 30),
        ("And offer them to yourself, in your own voice. If it feels strange, that's all right. Say them anyway.", 40),
        ("Finally, let the wishes spread to everyone you'll meet today.", 30),
        ("Gently open your eyes.", 0)]}}},
    # Direction
    {"id": "future-self", "title": "A visit from your future self", "category": "direction", "type": M,
     "evidence": "Moderate: vividly imagining your future self strengthens motivation and wiser choices today, and "
                 "imagining a best possible future lifts mood (Peters and others, 2010).",
     "when": "When you feel lost, stuck, or unsure what to do next.",
     "versions": {"short": {"minutes": 8, "steps": [
        ("Close your eyes or rest them on one spot, and take a slow breath.", 6),
        ("Imagine a door opening, and through it walks you... a year from now. This is the you who has spent the "
         "year living a little more by {value|what matters most to you}, week by week.", 20),
        ("Notice how they stand. Their face. Their eyes. There's something settled about them.", 20),
        ("They have moved towards {goal|the life you want}. Not perfectly, but really.", 15),
        ("They look at you with real understanding. They remember exactly how today feels, because they were you.", 20),
        ("Ask them: what helped you get here? Then listen.", 40),
        ("Ask them: what's one thing I could do today? Listen again. It's probably simpler than you expect.", 40),
        ("Before they go, they give you something small to remember this by: a word, an object, a gesture. Notice "
         "what it is.", 20),
        ("They leave, and the door closes softly. They're not a stranger. They're who you're becoming.", 8),
        ("Take a breath, and come back.", 0)]}}},
    # Let go
    {"id": "letting-go-bridge", "title": "Letting go: the bridge", "category": "let_go", "type": M,
     "evidence": "Moderate: learning to step back from thoughts (defusion, from ACT) reduces their grip, and "
                 "acceptance reduces the struggle that keeps them going.",
     "when": "When the same thoughts keep going round, or you're stuck in the past.",
     "versions": {"short": {"minutes": 8, "steps": [
        ("Let your body settle. Feel what's supporting you, the chair, the bed, the floor.", 10),
        ("Imagine you're standing on a bridge over a slow, wide river. The air is fresh. You lean on the railing.", 15),
        ("Below you, things are floating past on the water: leaves, small boats, branches.", 10),
        ("As thoughts come, imagine each one placed on something floating by. Words, pictures, memories, worries. "
         "Even the old loop about {struggle|what's been weighing on you}.", 20),
        ("You don't need to push them along, or pull them out. You simply watch them pass beneath you.", 40),
        ("If you find yourself in the water, caught up in a thought, that's fine. Notice it, and climb back onto the "
         "bridge.", 40),
        ("Letting go isn't forgetting, and it isn't pretending it didn't matter. It's loosening your grip, so your "
         "hands are free for what's in front of you.", 30),
        ("Breathe out slowly, and let your shoulders drop.", 20),
        ("Now turn away from the river and look at the path ahead. Somewhere along it is {value|what matters to you}.", 15),
        ("Take a breath, and come back to the room.", 0)]}}},
    {"id": "rain", "title": "RAIN for a difficult feeling", "category": "let_go", "type": M,
     "evidence": "A widely used mindfulness approach to strong feelings; early but encouraging evidence.",
     "when": "When a strong feeling like shame, fear or anger takes hold.",
     "versions": {"short": {"minutes": 7, "steps": [
        ("This practice helps you meet a difficult feeling instead of being swept away by it.", 3),
        ("Recognise: notice what you're feeling, and name it simply. This is fear. This is shame. This is sadness.", 20),
        ("Allow: let it be here, just for now. You don't have to like it. It's okay to feel this.", 30),
        ("Investigate, kindly: where do you feel it in your body? What does this feeling believe? What does it need?", 40),
        ("Nurture: offer yourself what you need. A hand on your heart. The words a good friend would say.", 40),
        ("Rest for a moment as someone who can hold this feeling with care.", 30),
        ("Notice how the feeling is now. It often softens a little, even if it's still there.", 0)]}}},
    # Deep calm
    {"id": "calm-body-hypnosis", "title": "Deep calm (guided hypnosis)", "category": "deep", "type": M,
     "evidence": "Good: hypnosis reduced anxiety substantially compared with control conditions across studies "
                 "(meta-analysis, Valentine and others, 2019). Works through deep relaxation, imagery and suggestion. "
                 "Not if you have psychosis or often lose touch with your surroundings. Never while driving.",
     "when": "For anxiety and tension, when you have fifteen undisturbed minutes.",
     "versions": {"long": {"minutes": 15, "steps": [
        ("Find a position where your body is fully supported. Make sure you won't be disturbed. You'll stay aware "
         "the whole time, and you can open your eyes whenever you like.", 6),
        ("Look at one spot slightly above eye level. Keep looking... and notice your eyelids becoming heavier... and "
         "when they want to close, let them.", 20),
        ("Take a deep breath in... and as you breathe out, let a wave of relaxation flow down from the top of your "
         "head.", 10),
        ("Down over your forehead... your eyes... your cheeks and jaw... down your neck... and across your shoulders, "
         "which grow heavy and loose.", 20),
        ("Down your arms, to your hands... down through your chest and belly... your back... your hips... your legs, "
         "all the way down to your feet.", 25),
        ("Now I'll count down from ten to one. With each number, you drift twice as deep into calm. Ten... nine... "
         "eight...", 10),
        ("Seven... six... five... deeper and calmer...", 10),
        ("Four... three... two... one. Deeply relaxed, and safe.", 20),
        ("In this calm state, your mind is open to helpful ideas. Each breath out reminds your body how to be "
         "calm.", 20),
        ("And you may notice that in the moments that used to wind you up, especially {struggle_situation|the "
         "situations that make you tense}, a quiet steadiness begins to appear. Not forced. It simply shows up, a "
         "little more each time.", 25),
        ("You can feel more at ease in your body... more confident in yourself... more able to meet things as they "
         "come. These changes grow on their own, day by day.", 25),
        ("Now, gently press your thumb and first finger together, and silently say your calm word: {calm_word|steady}. "
         "Feel this calm, and link it to that touch and that word.", 20),
        ("From now on, whenever you press your thumb and finger together and say {calm_word|steady}, some of this "
         "calm will come back. The more you practise, the stronger the link.", 15),
        ("In a moment, I'll count from one to five. At five, you'll open your eyes, feeling refreshed, alert and "
         "calm. One... two... energy coming back into your body...", 6),
        ("Three... four... feeling awake and clear... five. Eyes open, fully alert, and calm.", 0)]}}},
    {"id": "deep-rest", "title": "Deep rest", "category": "deep", "type": M,
     "evidence": "Early but encouraging: guided deep-rest practices (yoga nidra) improve sleep, stress and fatigue.",
     "when": "When you're drained, or for an afternoon reset. Lie down.",
     "versions": {"long": {"minutes": 15, "steps": [
        ("Lie down on your back if you can, arms by your sides, and let your body be heavy. There's nothing to do and "
         "nowhere to be.", 10),
        ("Bring to mind a simple intention, in a few words, as if it's already true. For example: {intention|I am "
         "safe, and I am enough}. Say it to yourself three times.", 20),
        ("Now your attention will move quickly through the body. Just let it be where I say. Right hand thumb... "
         "first finger... middle finger... ring finger... little finger... palm... wrist...", 6),
        ("Right elbow... shoulder... right side of the waist... hip... knee... ankle... the sole of the right foot...", 6),
        ("Left hand thumb... first finger... middle finger... ring finger... little finger... palm... wrist... elbow... "
         "shoulder... waist... hip... knee... ankle... the sole of the left foot...", 8),
        ("The back of the head... the whole back... the forehead... the eyes... the cheeks... the lips... the "
         "chest... the belly... the whole body, all at once.", 15),
        ("Now count your breaths backwards from twenty-seven, silently. Twenty-seven, breathing in and out... "
         "twenty-six... If you lose count, start again at twenty-seven.", 90),
        ("Let the counting go. Feel your body becoming heavy... heavy as stone, sinking into the ground...", 20),
        ("And now light... light as a feather, as if you could float.", 20),
        ("Feel warmth, like sun on your skin...", 15),
        ("And coolness, like a breeze...", 15),
        ("Now just rest, aware, in deep quiet.", 120),
        ("Bring back your intention, and say it to yourself three times: {intention|I am safe, and I am enough}.", 20),
        ("Slowly come back. Move your fingers and toes. Stretch. When you're ready, roll to one side, and sit up.", 0)]}}},
    # Sleep
    {"id": "sleep-shuffle", "title": "Drifting to sleep", "category": "sleep", "type": M,
     "evidence": "Early evidence: imagining a stream of unrelated, peaceful images (the cognitive shuffle) mimics "
                 "how the mind drifts at sleep onset and crowds out worry.",
     "when": "In bed, when your mind won't stop.",
     "versions": {"long": {"minutes": 12, "steps": [
        ("Lie comfortably and let your body be heavy. You don't need to try to sleep. Just rest, and picture what I "
         "say, one thing at a time.", 10),
        ("A lemon... bright yellow, cool in your hand.", 10),
        ("A lighthouse... on a calm evening.", 10),
        ("A wooden ladder... leaning against a wall.", 10),
        ("A lamb... in soft grass.", 10),
        ("A lantern... glowing warm.", 10),
        ("A leaf... floating on a pond.", 12),
        ("A blue cup... with steam rising.", 12),
        ("A bicycle... resting by a gate.", 12),
        ("A blanket... folded on a chair.", 12),
        ("A bird... on a quiet branch.", 14),
        ("A boat... still on the water.", 14),
        ("A candle... flickering slowly.", 16),
        ("A cloud... drifting.", 18),
        ("A cat... curled up asleep.", 20),
        ("A cushion... soft and deep.", 20),
        ("A path... through a garden.", 25),
        ("A pebble... smooth and grey.", 25),
        ("A pillow... and you sinking into it.", 30),
        ("Keep picturing simple, peaceful things of your own, one after another, letting each one fade.", 120),
        ("I'll be quiet now. Goodnight.", 0)]}}},
    {"id": "body-scan", "title": "Body scan", "category": "sleep", "type": M,
     "evidence": "Moderate: part of mindfulness programmes with good evidence for stress and preventing relapse in "
                 "depression.",
     "when": "For tension, rest, or before sleep.",
     "versions": {"long": {"minutes": 12, "steps": [
        ("Lie or sit comfortably. If anything feels too much at any point, open your eyes and look around the room.", 6),
        ("Take three slow breaths, letting each out-breath be a little longer.", 20),
        ("Bring your attention to your feet. Notice whatever is there: warmth, coolness, tingling, or nothing. All of "
         "it is fine.", 40),
        ("Slowly up through your lower legs... your knees... your thighs. If you find tension, breathe into it, and "
         "let it be.", 50),
        ("Your hips... your belly, rising and falling... your lower back... your upper back.", 50),
        ("Your chest... your shoulders... down your arms to your hands and fingers.", 50),
        ("Your neck... your jaw, letting your teeth part slightly... your face... the top of your head.", 50),
        ("Now feel your whole body at once, breathing.", 60),
        ("Rest here.", 60),
        ("When you're ready, wriggle your fingers and toes, and open your eyes. Or let yourself drift into sleep.", 0)]}}},
    # Feel good
    {"id": "savouring", "title": "Savouring a good moment", "category": "feel_good", "type": M,
     "evidence": "Moderate: recalling a good memory in detail lifts mood and reduced the stress response in lab "
                 "studies (Speer and Delgado, 2017).",
     "when": "When the day feels grey, or you want to end it well.",
     "versions": {"short": {"minutes": 6, "steps": [
        ("Settle in, and let your breathing slow a little.", 8),
        ("Bring to mind a moment that went well recently: {good_moment|a moment when you felt at ease, or proud, or "
         "close to someone}.", 15),
        ("Step back into it. Where are you? What can you see around you... the light, the colours?", 25),
        ("What can you hear? Who's there?", 20),
        ("What were you feeling in your body at that moment? Let that feeling come back now.", 25),
        ("Stay with the good feeling for a few breaths. Let it grow a little, and spread through your chest.", 30),
        ("Notice your part in this moment. It happened partly because of you.", 20),
        ("Keep a little of this feeling with you as you come back.", 0)]}}},
    # Feeling safe (stabilisation)
    {"id": "calm-place", "title": "Your calm place", "category": "safe", "type": M,
     "evidence": "A standard stabilising practice in trauma care: building a feeling of safety you can return to.",
     "when": "To build a sense of safety, especially after hard memories.",
     "versions": {"short": {"minutes": 6, "steps": [
        ("Keep your eyes open or closed, whatever feels safer. You can stop at any time.", 4),
        ("Bring to mind a place where you feel calm and safe. Real, remembered, or imagined.", 15),
        ("Look around. Notice the colours and the light.", 25),
        ("What can you hear there?", 20),
        ("What does the air feel like on your skin?", 20),
        ("Notice how your body feels here. Let that feeling grow a little.", 30),
        ("Choose a word that brings you back here. Whenever you need it, say the word and return, even for a few "
         "seconds.", 15),
        ("Now come back to the room. Feel your feet, and look around you.", 0)]}}},
    {"id": "container", "title": "The container", "category": "safe", "type": T,
     "evidence": "A standard stabilising skill in trauma care for putting intrusive memories aside until the right time.",
     "when": "When a memory or worry keeps intruding and now is not the time.",
     "versions": {"short": {"minutes": 5, "steps": [
        ("This helps you put something aside safely, until the right time to look at it.", 3),
        ("Imagine a strong container: a box, a safe, a chest. As solid as you need.", 20),
        ("Place the memory, feeling or worry inside. As an image, a word, or a colour.", 30),
        ("Close it firmly. Lock it if you like.", 15),
        ("Put it somewhere safe and out of the way. It will be there when you choose to come back to it.", 20),
        ("Take a slow breath, feel your feet, and look around the room.", 0)]}}},
    # Added after the owner asked what research-backed techniques were missing (2026-10-29)
    {"id": "muscle-relaxation", "title": "Progressive muscle relaxation", "category": "deep", "type": M,
     "evidence": "Strong: tensing and releasing muscle groups reduces anxiety and improves sleep across many trials. "
                 "It teaches your body the difference between tension and letting go.",
     "when": "For tension, anxiety, or trouble sleeping. Skip any area that is injured or painful.",
     "versions": {"long": {"minutes": 12, "steps": [
        ("Sit or lie comfortably. You'll gently tense one part of your body for about five seconds, then let go and "
         "notice the difference. Tense to about half your strength, never to the point of pain.", 4),
        ("Start with your hands and arms. Make fists and tighten your arms... hold... and let go. Feel the warmth and "
         "heaviness flowing in.", 20),
        ("Now your face. Scrunch it up: eyes, nose, forehead... hold... and release. Let your jaw hang loose.", 20),
        ("Your neck and shoulders. Lift your shoulders up towards your ears... hold... and let them drop.", 20),
        ("Your chest and back. Take a breath and gently squeeze your shoulder blades together... hold... and let "
         "go as you breathe out.", 20),
        ("Your belly. Tighten your stomach muscles... hold... and let them soften completely.", 20),
        ("Your legs. Press your knees together and tighten your thighs... hold... and release.", 20),
        ("Your feet. Curl your toes downwards... hold... and let go.", 20),
        ("Now let your attention travel from your feet to your head, and wherever you find a little tension left, "
         "breathe out and let it melt.", 30),
        ("Rest in this heaviness. Your body knows how to let go now, and it gets easier each time you practise.", 30),
        ("Take your time to come back, or let yourself drift towards sleep.", 0)]}}},
    {"id": "urge-surfing", "title": "Urge surfing", "category": "urges", "type": M,
     "evidence": "Good: from mindfulness-based relapse prevention, which reduced relapse in trials (Bowen and others, "
                 "2014). Urges rise, peak and fall like waves; riding one without acting weakens the next.",
     "when": "When you feel the pull to drink, check, scroll, smoke, ask for reassurance, or anything you want to do "
             "less.",
     "versions": {"short": {"minutes": 6, "steps": [
        ("You're feeling an urge. You don't have to act on it, and you don't have to fight it. For the next few "
         "minutes, we'll just watch it, like watching a wave.", 3),
        ("Notice where you feel the urge in your body. Your chest? Your hands? Your mouth? Your stomach?", 15),
        ("Describe it to yourself: is it tight, warm, buzzing, pulling? How strong is it, from 0 to 10?", 15),
        ("Now breathe with it. As you breathe in, notice the urge. As you breathe out, make a little space around "
         "it.", 30),
        ("Urges are like waves. They build, they peak, and they fall. You're on your board, riding it.", 30),
        ("If it gets stronger, that's the wave rising. Stay with your breath. You don't need to do anything.", 30),
        ("Notice it now. Has it changed shape, moved, or eased a little?", 20),
        ("Each time you ride a wave without acting on it, the next one is a little smaller. That's how habits loosen.", 10),
        ("Now choose one small thing to do instead, something kind to yourself, and do it now.", 0)]}}},
    {"id": "breathing-space", "title": "Three-minute breathing space", "category": "calm", "type": M,
     "evidence": "Strong for the programme it comes from: mindfulness-based cognitive therapy reduces the risk of "
                 "depression coming back (meta-analysis, Kuyken and others, 2016).",
     "when": "A quick reset in a busy or difficult moment. Use it often.",
     "versions": {"short": {"minutes": 3, "steps": [
        ("Wherever you are, pause. Sit or stand a little taller, in a way that feels dignified and awake.", 3),
        ("First, what's here right now? Notice your thoughts... your feelings... the sensations in your body. "
         "Just notice them, without trying to change anything.", 45),
        ("Now gather your attention onto the breath, low in your belly. Feel each breath in and each breath out.", 45),
        ("Now let your attention widen to your whole body, breathing. Your posture, your face, the space around you.", 40),
        ("Take this steadiness with you into the next moment.", 0)]}}},
    {"id": "sounds-and-thoughts", "title": "Sounds and thoughts", "category": "let_go", "type": M,
     "evidence": "From mindfulness-based cognitive therapy (strong evidence for keeping depression from returning): "
                 "learning to see thoughts as passing events, not facts.",
     "when": "When thoughts feel loud, convincing, or stuck on repeat.",
     "versions": {"short": {"minutes": 10, "steps": [
        ("Sit comfortably, and let your eyes close or rest on one spot.", 6),
        ("Start by listening. Let sounds come to you: near sounds, far sounds, loud and quiet ones. You don't need to "
         "name them or like them. Just notice them arriving... and passing.", 60),
        ("Notice the gaps between sounds too. Sounds come and go on their own.", 45),
        ("Now, in the same way, turn your attention to your thoughts. Notice them arriving, like sounds in the mind... "
         "staying a while... and passing.", 45),
        ("You might picture thoughts as clouds moving across the sky, or as words on a screen. You don't need to "
         "follow them or push them away.", 60),
        ("Sometimes you'll be carried off by a thought. That's what minds do. When you notice, gently come back to "
         "watching.", 60),
        ("Thoughts are events in the mind, not facts about you or the world. Even the loud ones.", 30),
        ("Let go of the practice, take a breath, and open your eyes.", 0)]}}},
    {"id": "name-it", "title": "Name it to tame it", "category": "let_go", "type": M,
     "evidence": "Good: putting a feeling into words calms the brain's alarm response (Lieberman and others, 2007); "
                 "noting practice turns that into a habit.",
     "when": "When a strong feeling takes over: anxiety, anger, shame, sadness.",
     "versions": {"short": {"minutes": 8, "steps": [
        ("Settle into a comfortable position, and take one slow breath out.", 6),
        ("Notice what you're feeling right now. Then name it, softly, in one word: fear... anger... sadness... "
         "shame... worry. Whatever fits.", 25),
        ("Find where it lives in your body, and name that too: tight chest... hot face... knot in the stomach.", 30),
        ("Now, as thoughts come, give each one a gentle label: planning... worrying... judging... remembering. Then "
         "let it go.", 45),
        ("Keep noting whatever comes, a word at a time, in a calm, friendly voice inside. Feeling... thinking... "
         "hearing...", 60),
        ("Notice what happens to the feeling when you name it. Often it loosens its grip a little.", 30),
        ("You don't have to get rid of the feeling. Naming it means you're the one noticing it, not the one drowning "
         "in it.", 15),
        ("Take a slow breath, and come back.", 0)]}}},
    {"id": "mindful-walk", "title": "A mindful walk", "category": "feel_good", "type": M,
     "evidence": "Good: walking is one of the most effective exercises for depression in a large review (Noetel and "
                 "others, 2024), and time outdoors adds to wellbeing. This adds calm attention to it.",
     "when": "Outdoors, on any walk. Keep your eyes open and stay aware of traffic.",
     "versions": {"long": {"minutes": 15, "steps": [
        ("Start walking at a comfortable pace, a little slower than usual. There's nowhere you need to be.", 10),
        ("Feel your feet: the heel touching the ground, the roll forward, the push off. Left... right...", 40),
        ("Notice the rhythm of your arms swinging, and your breath finding its own pace with your steps.", 40),
        ("Now look around. Notice colours: three different greens, or the colour of the sky right now.", 45),
        ("Notice the light: where it falls, where the shadows are.", 40),
        ("Listen: birds, wind, traffic, voices. Let sounds come and go.", 45),
        ("Feel the air on your face and hands. Is it cool, warm, still, moving?", 40),
        ("Find one thing that's beautiful or interesting, however small. Let your eyes rest on it for a few "
         "breaths.", 45),
        ("Try matching your breath to your steps: in for three or four steps, out for four to six.", 60),
        ("Notice how your body feels now compared with when you set off.", 30),
        ("Carry on walking in your own way. Thank your body for carrying you.", 0)]}}},
    # Tools run with the therapist
    {"id": "wheel-of-life", "title": "Wheel of life", "category": "tools", "type": I, "minutes": 10,
     "practice_name": "wheel of life", "when": "To see where life feels balanced and where you'd like change.",
     "about": "With your therapist: name your own life areas, rate them, and choose one to raise."},
    {"id": "ikigai", "title": "Ikigai: your reason for being", "category": "tools", "type": I, "minutes": 15,
     "practice_name": "ikigai questions", "when": "When you're searching for direction or meaning.",
     "about": "With your therapist: what you love, what you're good at, what the world needs, what sustains you."},
    {"id": "values-compass", "title": "Values compass", "category": "tools", "type": I, "minutes": 10,
     "practice_name": "values compass", "when": "When you feel stuck or unsure what to do next.",
     "about": "With your therapist: what matters most in one area of life, and one step towards it."},
    {"id": "nightmare-rescripting", "title": "Rewriting a nightmare", "category": "tools", "type": I, "minutes": 15,
     "practice_name": "nightmare rescripting", "when": "For a nightmare that keeps coming back.",
     "about": "With your therapist: change the dream into a new, safer version (without going back through the old "
              "one in detail), then rehearse the new version for a few minutes each day. A recommended treatment for "
              "nightmares (imagery rehearsal)."},
    {"id": "habit-design", "title": "Designing a habit", "category": "tools", "type": I, "minutes": 10,
     "practice_name": "habit design", "when": "To start a habit that lasts.",
     "about": "With your therapist: start tiny, link it to a routine, plan for missed days."},
]

WPM = 140
# Intended lengths. Depth comes from unhurried silence, so only reflective silences (10 s or more) are lengthened
# towards the target, never the short transitions; each pause stays at most 150 s. The label is the real length.
TARGET = {"cyclic-sighing": 5, "six-breaths": 10, "morning-lift": 4, "compassionate-companion": 10,
          "loving-kindness": 6, "future-self": 8, "letting-go-bridge": 8, "rain": 7, "calm-body-hypnosis": 15,
          "deep-rest": 15, "sleep-shuffle": 12, "body-scan": 12, "savouring": 6, "calm-place": 6,
          "muscle-relaxation": 12, "urge-surfing": 6, "breathing-space": 3, "sounds-and-thoughts": 10, "name-it": 8,
          "mindful-walk": 15}

out = Path(__file__).resolve().parent.parent / "assets" / "practices" / "library_v2.json"
rows = []
for p in library:
    p = dict(p)
    if p["type"] != I:
        vs = {}
        for k, v in p["versions"].items():
            steps = [{"text": s[0], "pause": s[1], "pacer": len(s) > 2} for s in v["steps"]]
            spoken = sum(len(s["text"].split()) for s in steps) * 60 / WPM
            fixed = sum(s["pause"] for s in steps if s["pause"] < 10)
            stretchable = sum(s["pause"] for s in steps if s["pause"] >= 10)
            want = TARGET.get(p["id"], 0) * 60
            if want and stretchable and spoken + fixed + stretchable < want:
                f = (want - spoken - fixed) / stretchable
                for s in steps:
                    if s["pause"] >= 10:
                        s["pause"] = min(150, round(s["pause"] * f))
            real = (spoken + sum(s["pause"] for s in steps)) / 60
            vs[k] = {"minutes": max(1, round(real)), "steps": steps}  # the label is always the real length
        p["versions"] = vs
    rows.append(p)
out.write_text(json.dumps(rows, ensure_ascii=False, indent=1))
for p in rows:
    if p["type"] != I:
        print(f"{p['id']:24} {p['category']:9} " + ", ".join(f"{k} {v['minutes']} min" for k, v in p["versions"].items()))
print(len(rows), "items")
