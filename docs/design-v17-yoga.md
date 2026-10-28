# New Me v17: yoga, from pose library to weekly plan

Earlier design documents still hold unless a section below changes them.

## Why

Nick, a strength-training beginner, and Nadia asked for three things.
They wanted pictures of yoga poses, guided yoga, and a way to plan it.
v11 made yoga minutes a quest, v13 added the Mobility 10 guided routine and the stretch catalog, and v15 put an exercise's how-to on its own page.
v17 builds on all three instead of adding a parallel feature.

## What is new

- Twenty-five yoga poses join the exercise catalog as a new `kind`, `yoga`, with photos, steps, cues, what each pose works, how long to hold it and cautions.
- The Exercises library gains a Strength and Yoga switch, and the Yoga side groups poses as standing, kneeling and all fours, seated, on your front and on your back.
- Three guided flows of about 10, 20 and 30 minutes run on the Mobility runner, which is now a shared guided runner.
- A weekly plan picks how many yoga days and which flow, places the days around heavy leg sessions, counts the week, and offers a longer flow after two finished weeks.
- The Train tab gets a Yoga card next to Mobility.

## The pose library

Poses are catalog exercises with `kind = 'yoga'`, stored as v13 stored stretches.
They are bodyweight holds measured in seconds, they have no owner, and they never enter strength plans, weekly muscle sets or the plan design prompt.
`db.Exercise.Stretch()` now means "not a strength exercise", so every place that kept stretches out of strength work keeps poses out as well.
Pose keys start with `yoga_` so they cannot collide with the v13 stretch keys such as `childs_pose`.
Migration `0027_v17_yoga.sql` adds the pose columns, widens the kind and shape checks, seeds the poses, and creates the plan table.
The pose columns are `sanskrit`, `pose_group`, `effect`, `hold_note`, `cautions` and `image_credits`.
A check ties `pose_group` to `kind = 'yoga'` so a pose cannot lack its group and a strength exercise cannot have one.
The muscle fields use the existing vocabulary, so a pose lists the nearest fit, and Corpse lists back because the vocabulary has no empty choice.

### The 25 poses

| Group | Pose | Sanskrit | Each side | Works |
| --- | --- | --- | --- | --- |
| Standing | Mountain | Tadasana | no | Builds standing posture and body awareness; lightly works the legs and core. |
| Standing | Chair | Utkatasana | no | Strengthens the thighs, glutes and back. |
| Standing | Warrior I | Virabhadrasana I | yes | Strengthens the legs; stretches the hip flexors and chest. |
| Standing | Warrior II | Virabhadrasana II | yes | Strengthens the thighs and shoulders; stretches the inner thighs. |
| Standing | Triangle | Trikonasana | yes | Stretches the hamstrings, hips and side body. |
| Standing | Extended side angle | Utthita Parsvakonasana | yes | Strengthens the legs; stretches the side body and groin. |
| Standing | Tree | Vrksasana | yes | Trains balance and the standing leg and hip. |
| Standing | Standing forward fold | Uttanasana | no | Stretches the hamstrings, calves and back. |
| Kneeling and all fours | Low lunge | Anjaneyasana | yes | Stretches the hip flexors and thighs. |
| Kneeling and all fours | Cat-cow | Marjaryasana-Bitilasana | no | Mobilizes the spine; gently works the core. |
| Kneeling and all fours | Child's pose | Balasana | no | Gently stretches the back, hips and thighs; a resting pose. |
| Kneeling and all fours | Downward dog | Adho Mukha Svanasana | no | Stretches the hamstrings, calves and back; loads the shoulders and arms. |
| Seated | Easy pose | Sukhasana | no | A comfortable base for breathing and for the start or end of a flow. |
| Seated | Staff | Dandasana | no | Builds sitting posture; prepares for seated folds. |
| Seated | Butterfly | Baddha Konasana | no | Stretches the inner thighs and hips. |
| Seated | Seated forward fold | Paschimottanasana | no | Stretches the hamstrings and back. |
| Seated | Seated twist | Ardha Matsyendrasana | yes | Rotates and stretches the spine and outer hip. |
| On your front | Cobra | Bhujangasana | no | Strengthens the back and stretches the front of the chest and abdomen. |
| On your front | Sphinx | Salamba Bhujangasana | no | A gentler back extension than cobra; stretches the front of the torso. |
| On your front | Locust | Salabhasana | no | Strengthens the back and glutes. |
| On your back | Bridge | Setu Bandha Sarvangasana | no | Strengthens the glutes and hamstrings; stretches the front of the hips. |
| On your back | Happy baby | Ananda Balasana | no | Stretches the inner thighs, hips and lower back. |
| On your back | Knees to chest | Apanasana | no | Gently stretches the lower back and hips. |
| On your back | Legs up the wall | Viparita Karani (supported) | no | A restful pose that eases tired legs. |
| On your back | Corpse | Savasana | no | Rest to finish a practice. |

### Poses considered and left out

- Reclined pigeon (figure-four) has no photo on Wikimedia Commons that is clear, free to display and unmistakably the pose, so it is dropped.
  The v13 catalog already has a Figure-four stretch with a free-exercise-db photo, and Mobility keeps it.
- Supine twist had no usable photo either, so the seated twist stands in as the spinal twist.
- Reclined hand-to-big-toe had no photo that showed the pose.
- Warrior III, headstand, shoulder stand and lotus are left out on purpose, because NCCIH advises beginners to avoid headstands, shoulder stands and the lotus position, and Cramer et al. found headstand the most often reported pose in adverse event cases.

### How the stated cautions were chosen

Each pose lists one to three cautions, and every one maps a condition NCCIH names onto the poses that load it.
NCCIH ("Yoga: What You Need To Know", nccih.nih.gov/health/yoga-what-you-need-to-know) says yoga is generally considered safe for healthy people when done properly.
It lists preexisting injuries, lumbar spine disease, severe high blood pressure, balance issues and glaucoma among the reasons to modify poses and to ask a provider.
It advises pregnant people to avoid long periods of lying on the back, and says the most common injuries are sprains and strains, mostly of the knee or lower leg.
It also says beginners should avoid extreme practices such as headstands, shoulder stands, the lotus position and forceful breathing.
Cramer H, Krucoff C, Dobos G. Adverse Events Associated with Yoga: A Systematic Review of Published Case Reports and Case Series. PLoS One 2013;8(10):e75515, found 76 cases, mostly musculoskeletal (27), nervous system (14) and eye (9) events, with headstand the most cited posture (10 cases).
The mapping is New Me's own reading and is not a pose-specific trial finding: knee loads get the injury caution, head-below-heart poses get the glaucoma and blood pressure caution, back bends and folds get the lumbar caution, standing balance poses get the balance caution, and poses on the back get the pregnancy caution.
The pose page shows the cautions under "Take care" with both sources named and says it is not medical advice.

## Images and licensing

Photos come from Wikimedia Commons only, found through its API with `prop=imageinfo&iiprop=url|extmetadata`.
Only files under CC0, public domain, CC BY or CC BY-SA were accepted, and each was opened and looked at to confirm it shows the pose it is used for.
No image is AI-generated.
Where no acceptable photo existed for a pose the pose was dropped, and several candidate poses were.
Each photo is a 600 pixel wide recompression of the Commons file, so it is a modified copy.
The copies are bundled in the server's embedded `static/exercises` folder as `yoga_<pose>-<n>.jpg`, the same mechanism as the v12 how-to photos, and the app loads them through the existing authenticated image route.
Total size of the 26 added photos is under 1 MB.
`server/static/exercises/YOGA_SOURCES.tsv` records the file page, author, license and modification of every photo.
The API returns one credit per photo in `pose.imageCredits`, and every pose page and how-to sheet shows "Photo: author, license" as a link to the file page, which satisfies the attribution these licenses require.
Where a license is ShareAlike (CC BY-SA), the recompressed copy is offered under the same license.

| Pose | Commons file page | Author | License |
| --- | --- | --- | --- |
| Mountain | https://commons.wikimedia.org/wiki/File:Tadasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Chair | https://commons.wikimedia.org/wiki/File:Utkatasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Warrior I | https://commons.wikimedia.org/wiki/File:Virabhadrasana_I_-_Warrior_Pose_I.jpg | OrenBochman | CC BY-SA 3.0 |
| Warrior II | https://commons.wikimedia.org/wiki/File:Virabhadrasana_II_-_Warrior_II_Pose.jpg | lululemon athletica | CC BY 2.0 |
| Triangle | https://commons.wikimedia.org/wiki/File:Trikonasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Extended side angle | https://commons.wikimedia.org/wiki/File:Utthita-Parshvakonasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Tree | https://commons.wikimedia.org/wiki/File:Vriksasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Standing forward fold | https://commons.wikimedia.org/wiki/File:Flickr_-_Nicholas_T_-_Uttanasana.jpg | Nicholas A. Tonelli | CC BY 2.0 |
| Low lunge | https://commons.wikimedia.org/wiki/File:%C4%80%C3%B1janey%C4%81sana,_Julija_Zora_Mazover,_2023.jpg | Julija Zora Mazover | CC BY-SA 4.0 |
| Cat-cow | https://commons.wikimedia.org/wiki/File:Yoga_at_Your_Park_-_Bidalasana.jpg | Mary O'Neill | Public domain |
| Cat-cow | https://commons.wikimedia.org/wiki/File:Yoga_at_Your_Park_-_Bitilasana.jpg | Mary O'Neill | Public domain |
| Child's pose | https://commons.wikimedia.org/wiki/File:Balasana.JPG | Iveto | CC BY-SA 4.0 |
| Downward dog | https://commons.wikimedia.org/wiki/File:Downward-Facing-Dog.JPG | Iveto | CC BY 3.0 |
| Easy pose | https://commons.wikimedia.org/wiki/File:Sukkasana.jpg | Joseph RENGER | CC BY-SA 3.0 |
| Staff | https://commons.wikimedia.org/wiki/File:A_style_of_Dandasana.JPG | Thamizhpparithi Maari | CC BY-SA 3.0 |
| Butterfly | https://commons.wikimedia.org/wiki/File:Baddha_Ko%E1%B9%87%C4%81sana-bound_angle.jpg | Jfbongarçon | CC BY-SA 3.0 |
| Seated forward fold | https://commons.wikimedia.org/wiki/File:An_art_of_Paschimottanasana_1.JPG | Thamizhpparithi Maari | CC BY-SA 3.0 |
| Seated twist | https://commons.wikimedia.org/wiki/File:Ardha-Matsyendrasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Cobra | https://commons.wikimedia.org/wiki/File:Bhujangasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Sphinx | https://commons.wikimedia.org/wiki/File:IMG_0549_2_Sphinx.jpg | Christy Collins | CC BY-SA 3.0 |
| Locust | https://commons.wikimedia.org/wiki/File:Salabhasana_Yoga-Asana_Nina-Mel.jpg | Kennguru | CC BY 3.0 |
| Bridge | https://commons.wikimedia.org/wiki/File:Dvipada_pitham.jpg | Joseph RENGER | CC BY-SA 3.0 |
| Happy baby | https://commons.wikimedia.org/wiki/File:IMG_0377_2_Happy_Baby.jpg | Christy Collins | CC BY-SA 3.0 |
| Knees to chest | https://commons.wikimedia.org/wiki/File:A_style_of_pavanamuktasana_1.JPG | Thamizhpparithi Maari | CC BY-SA 3.0 |
| Legs up the wall | https://commons.wikimedia.org/wiki/File:Woman_reading_a_book._Legs_up_the_wall_pose.jpg | Shixart1985 | CC BY 2.0 |
| Corpse | https://commons.wikimedia.org/wiki/File:Shavasana.jpg | Joseph RENGER | CC BY-SA 3.0 |

## Guided flows

The Mobility runner became a shared guided runner: `GuidedController` and `GuidedPage` hold the timer, the lead-in, auto-advance, skip, back, haptics, VoiceOver announcements, background time replay and the minute logging.
`MobilityPage` and the yoga flows differ only in a `GuidedRoutine`, which carries the title, the words around the timer and the way the holds are built.
Each hold now has its own length, so a rest pose can last longer than a stretch.
Every hold still has a 3 second lead-in, and the intro's total counts the lead-ins.
Finishing logs the active minutes as yoga minutes through the same activity log, once per session id, and ending early offers to log what was done when it passed 30 seconds.

### Hold times and why

- One static hold is 30 seconds.
  ACSM's position stand recommends holding a static stretch 10 to 30 seconds and 60 seconds in total per stretch (Garber et al., Med Sci Sports Exerc 2011;43:1334), so 30 seconds is the top of the single-hold range.
- Yoga teaching commonly holds a pose for 3 to 5 breaths.
  Five slow breaths of about 6 seconds is also 30 seconds, so the pose page says "around 5 slow breaths".
  The breath pace is New Me's own choice and not a trial result.
- Yoga 10 holds every pose or side once.
- Yoga 20 and Yoga 30 give the stretching poses a second hold in a row on the same side, which reaches the 60 seconds per stretch ACSM recommends in total.
- The rest at the end is New Me's own and not from research: 60 seconds in Yoga 10, 120 in Yoga 20, and in Yoga 30 90 seconds of legs up the wall and 180 of corpse.
- Poses done on each side run left then right, and a repeated hold stays on its side before the other side starts.

### The sequences

The sequences run from warm-up to cool-down and end resting in Corpse.
They are New Me's own and not from a trial, and the app says so on every flow intro.
A pose the server lacks is skipped, so an older server still runs a shorter flow.

| Flow | Poses | Time with lead-ins | Final rest |
| --- | --- | --- | --- |
| Yoga 10 | 14 | about 10 minutes | Corpse 60 s |
| Yoga 20 | 23 | about 20 minutes | Corpse 120 s |
| Yoga 30 | 26 | about 29 minutes | Legs up the wall 90 s, Corpse 180 s |

## The runner on a phone set down

Nick tried Mobility on his iPhone and found that the steps ran off the screen under the Pause button and that nothing made a sound.
The shared runner, which Mobility and yoga both use, changed as follows.

### One screen

- The tall timer card is a 64 point ring with the seconds inside it, which fills as the hold passes, and a one-word status under it ("seconds left", "Get ready" or "Paused").
- The pose name, the side or hold label and a "Next: ..." line sit beside the ring, and "Pose 3 of 14" sits above them.
- A hold shows one photo, small and whole, with its credit under it.
  A stretch shows its end position, and a yoga pose shows all its photos, so cat-cow keeps its two.
- All the steps show at body size with their numbers, followed by the form cues, with no sheet or fold between them.
- Pause sits in the middle of the footer with Previous and Skip beside it and the speaker button, so the footer is one row.
  The back arrow is how a session ends, and it asks first.
- At text scales above 1.3 the footer returns to its stacked, wrapping form and the page scrolls.
- Widget tests load the real Nunito and check that every pose of Yoga 30 and every Mobility stretch fits without scrolling, with every step on screen, at 390 by 844 and at 375 by 667 (iPhone SE).
  A test at text scale 2.0 checks that nothing overflows and that scrolling takes over.

### Screen awake

The screen is held on from Start until the session finishes, is ended or the page goes away, through `wakelock_plus` behind a `ScreenAwake` interface.

### Sound cues

- The audio sits behind a `SessionAudio` interface, so tests record the cues a session asks for and play nothing.
  A later spoken-instruction or time-call cue needs only a new method there.
- A short tick plays at 3, 2 and 1 seconds left.
- A single soft tone plays at the midpoint of a hold of 20 seconds or longer, so shorter holds stay quiet.
- A chime plays when a hold ends and the next pose or side starts, and at the end of the session.
- The voice says "Starting with ..." at the start and "Next: ..." at each change, naming the pose and, where there is one, the side.
  It says only the label when the next hold is the same pose.
- Ticks, tones and chimes are bundled WAV files made for New Me, about 40 KB in all.
  The voice is the platform text-to-speech through `flutter_tts`, and playback uses `audioplayers`.
- The audio session is `playback` with `mixWithOthers` and `duckOthers`, so Apple Music or Spotify dips while a cue plays and comes back, and cues sound through the silent switch and while the screen dims.
  The app stays in the foreground with the screen held on, so no background audio mode is declared.
- The speaker button cycles sounds and voice, tones only, and silent, is remembered on the phone, and starts on.
- With VoiceOver on, nothing is spoken by the voice, because the page already announces each change to VoiceOver, but the tones still play.
- Time replayed after the app was in the background plays no catch-up cues, and pausing cuts speech off.
- Music is not part of this change.

### Ending early

The stock three-button dialog is a bottom sheet in the app's own pattern.
It has a title, one line of copy with the right singular or plural ("You've done 1 minute. Log it to your yoga quest?" or "... 6 minutes. Log them ..."), a primary "Log 1 min and end", a secondary "End without logging" and "Keep going" as a text button.
Dismissing the sheet also keeps going, so the safe choice is the default.
Under 30 seconds, where nothing can be logged, the sheet says so and offers only "End" and "Keep going".

## Weekly plan

`GET /api/yoga/plan` and `PUT /api/yoga/plan` are owner-only like every authenticated route, and the plan lives in the `yoga_plans` table, one row per person.
A person picks days a week from 1 to 7 and a flow of 10, 20 or 30 minutes, and the server chooses the weekdays.

### Default days

The default is 3 days a week and the 10 minute flow.
ACSM advises flexibility exercise on at least 2 to 3 days a week and finds more benefit from daily practice (Garber et al. 2011), so 3 is the top of the minimum range.
The plan page shows that sentence next to the day picker.

### Placing the days

- A strength day is a heavy lower-body day when at least two of its exercises have a leg muscle (quads, hamstrings or glutes) as their primary muscle.
  That definition is New Me's own.
- Yoga days avoid those weekdays whenever enough other weekdays remain, and otherwise take the fewest conflicts.
- Among the choices with the fewest conflicts the days are spread as evenly as possible around the week, then the earliest weekdays win.
- Without a strength plan the days are simply spread evenly, so 3 days land on Monday, Wednesday and Friday.
- Days are placed when the plan is saved, and saving again places them again after the strength plan changes.

### The week and today

The response counts the days of the current week, Monday to Sunday, that have yoga minutes, whether logged by hand, by a guided flow, or by an Apple Health yoga workout, which are the same minutes the yoga quest and the training calendar use.
The yoga page shows "Yoga this week: 1 of 3", a dot per weekday, and a "Today: Yoga 10" button on a planned day with no yoga yet.

### Progression

After two full weeks in a row in which the person did yoga on at least as many days as the plan asks, and both weeks began at the current flow length, the page offers the next longer flow.
The two weeks are New Me's own rule and not from a trial.
Nothing changes by itself: "Try Yoga 20" saves the new flow, and "Not now" saves the same plan with `restartLevel`, which starts another two-week count at the same length.
Changing the flow length by hand also restarts the count, and changing only the number of days does not.

### Not done: the Today plan list

The Today plan is a deterministic list built from quest facts, and it has no slot for a future planned activity.
Adding one would have meant a new fact type through `internal/plan`, `internal/coach` and the app's plan sheet for a single line, so the plan stays on the yoga page.

## Decisions the brief left open

- Poses live in the existing exercises table rather than a new one, with `Stretch()` widened, so nothing that excludes stretches needed a new rule.
- The pose extras are columns, not a JSON blob, because the project writes its SQL by hand and the checks above can then guard them.
- Photo credits are part of each pose's API payload, so the app never has to know where a photo came from.
- `dio` decodes responses with `SyncTransformer`, because the catalog now passes 50 KB, the size at which the default hands decoding to an isolate that a widget test cannot wait for.
- Mobility's footer actions wrap instead of overflowing at text scale 2.0, which the shared runner needed.
- The Exercises library keeps strength as the default side, so existing habits and tests are unchanged.
- Three of the photos are not studio-quality or uniform: Cat-cow is two outdoor photos of one person, Legs up the wall is a top-down photo, and Happy baby is a cropped black and white photo.
  They were kept because they show the pose, and no better free photo was found.

## Runner layout on a real phone

- On a phone at least 740 points tall the pose photo sits full width under the name and timer, taking what the screen has to spare past the fixed parts (about 170 points on a 390x844 phone), so it can be read from the mat.
- A shorter phone such as the iPhone SE keeps the photo as a thumbnail beside the name, which is what lets every step of every pose fit without scrolling there.
- The timer is a 76 point ring with 32 point digits.

## Training equipment

- Exercise equipment follows each exercise's own steps: an inverted row hangs under a bar at waist height, so it needs the new "Low bar or rack (waist height)" option, which a full gym includes; a decline push-up puts the feet on a bench or box like a step-up does.
- The bench option reads "Bench, box or sturdy chair", since a chair or a stair serves for all of those.
- Plans and targets read in lifters' notation, "3 × 5–10" and "3 × 8 @ 22.5 kg", after "3 × 5 to 10 reps" read as 150 push-ups.
