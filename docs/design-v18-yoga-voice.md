# New Me v18: a yoga class voice

Earlier design documents still hold unless a section below changes them.

## Why

Nick found the yoga voice terrible and asked for a better model, a voice that feels like a yoga class, and, if possible, video of each pose.
The v17 runner spoke through `flutter_tts`, which on iPhone is the compact system voice and sounds robotic.
It also only said the pose name, so there was no teaching in it.

## What changed

- The voice is a neural model, Kokoro, rendered offline and bundled as audio clips.
  Nothing is generated on the phone, so there is no network, no latency and no account.
- A written class script covers a welcome, every pose, mid-hold cues, breath cues, side switches, repeated rounds and a closing.
- The runner plays the clips for each event of the session.
  Text-to-speech stays only as the fallback for text that has no clip, which today means the Mobility stretches.
- Pose videos were researched and are not added (see below).

## The voice

- Model: Kokoro v1.0 (82M parameters, Apache-2.0) through `kokoro-onnx`, run on a laptop CPU.
- Voice: `af_heart`.
  Kokoro's own voice notes (VOICES.md in the model repository) grade `af_heart` A, the top grade, and `af_bella` A-.
  The next grades are a step lower, so `af_heart` is the pick on the project's own quality rating.
  Nobody on the project could listen to the candidates while this was built, so a second listen on a phone is worth doing, and swapping the voice is one line in the manifest.
- Pace: speed 0.8, which is slower than the default so it reads as a teacher and not a narrator.
- Encoding: AAC in an `.m4a` container, mono, 24 kHz, 28 kbit/s, with single-pass loudness normalization to about -18 LUFS so every clip has the same level.
- Size: 110 clips, about 3.0 MB in all, under the 6 MB budget.
  A test fails the build if the folder passes 6 MB.

## Regenerating the clips

`tools/voice/manifest.json` is the only source of the words, the voice and the speed.
`tools/voice/render.py` renders every clip from it and writes:

- `app/assets/audio/voice/<id>.m4a`, one per clip;
- `app/lib/audio/voice_clips.dart`, a generated map from clip id to its text and length;
- `tools/voice/durations.json`, which remembers lengths between runs.

The script's docstring lists the one-time setup (a virtualenv with `kokoro-onnx` and `soundfile`, the two model files from the kokoro-onnx releases, ffmpeg, and the system espeak-ng library on Linux).
`--only <prefix>` re-renders a few clips and `--missing` skips clips that already have a file.
A test checks that the Dart map, the manifest and the audio files agree, so editing the manifest without re-rendering fails.

## The class script

The poses are the 25 of v17.
Every line below comes from the pose's own steps and cues in migration `0027_v17_yoga.sql`, reworded to be spoken, and adds no anatomy claim of its own.

| Clip id | When it plays | Content |
| --- | --- | --- |
| `welcome` | At Start, before the first pose | A short welcome and settle-in: find a seat, drop the shoulders, one slow breath. |
| `<pose>.again` | At Start after the welcome, after Skip and after Previous | The pose name, the side if it has one, and the first one or two setup steps. |
| `<pose>.intro` | When a new pose starts by itself | The same, with "Next," in front: "Next, Downward dog. Come onto your hands and knees, ..." |
| `<pose>.cue`, `<pose>.cue2` | During the hold | One or two alignment or breath cues from the pose's own cues. The first hold of a pose gets the first, the second hold (the other side, or the next round) gets the second. |
| `switch_sides` | When the left side ends | "Switch sides. Now the right side." |
| `stay.1` to `stay.3` | When the same pose and side holds for another round | A nudge to keep breathing. |
| `breath.1` to `breath.4` | During the hold, and every 21 seconds of a long rest | "Breathe in... and out." in four wordings. |
| `closing` | In the last hold, ending a few seconds before the chime | Deepen the breath, wiggle fingers and toes, roll to one side, thanks. |

A pose done on each side is named "left side" in its first intro, matching the "Left side" label on screen, and the other side gets `switch_sides`.

### Timing inside a hold

`GuidedVoice` in `app/lib/features/training/guided_voice.dart` plans the cues as pure functions of the hold list, so tests read the plan and the page only plays it.
For a 30 second hold the sequence is the opening line during the 3 second lead-in and the first seconds of the hold, the alignment cue at about 9 seconds, the existing soft halfway tone at 15, a breath cue at about 19, and the 3, 2, 1 ticks at the end.
The plan uses each clip's real length to keep a gap of two seconds between lines, to wait for a long opening line, and to finish every line before the ticks start.
In the final rest the closing clip is placed so it ends four seconds before the last chime, and breath cues fill the time before it.
Time replayed after the app was in the background plays no cues, as before.

### Playing and stopping

- `SessionAudio` has a new `playClips(ids)`.
  A new request replaces whatever clip is playing, so a skip never queues behind an old line.
- The voice waits 450 ms after a change of pose so the chime rings first.
- `stopSpeaking()` now cuts clips as well as text-to-speech, and runs on pause, on the end-early sheet, when a session finishes and when the page closes.
  Resuming does not replay the line that was cut off.
- The audio session is unchanged: `playback` with `mixWithOthers` and `duckOthers`, so the person's own music dips under a clip and comes back, and the clips play through the silent switch.
- The speaker button works as before: sounds and voice, tones only, silent.
  With VoiceOver on the clips stay silent, because the page already announces each change.
- If a clip cannot be played its text is spoken through text-to-speech, so a bad file never leaves a silent gap.
- The halfway tone, ticks, chimes and the end-early sheet are unchanged.

## Pose videos

Nick asked whether a GIF or video of an instructor doing each pose is possible.
Wikimedia Commons was searched through its API for video and animated files (webm, ogv, gif, mp4, apng) for each of the 25 poses by English and Sanskrit name.
Only licenses that allow display with credit (CC0, public domain, CC BY, CC BY-SA) were acceptable.

| Pose | Openly licensed clip found |
| --- | --- |
| Mountain | "Yoga with Modi - Tadasana", CC BY 3.0, 21 MB webm |
| Triangle | "Yoga with Modi - Trikonasana", CC BY 3.0, 33 MB webm |
| Tree | "Yoga with Modi - Vrikshasana", CC BY 3.0, 16 MB webm; "Vriksasana", NCSM Kolkata 2015, CC BY 3.0, 28 MB ogv |
| Corpse | "Savasana", NCSM Kolkata 2015, CC BY 3.0, 17 MB ogv |
| The other 21 poses | None |

Coverage is 4 of 25 poses.
The clips that exist are 16 to 33 MB each, from two unrelated productions (a studio series and a stage event) with different framing and lengths, and none is a short loop.
Four mismatched clips would make the library look uneven, and bundling or streaming tens of megabytes for four poses is out of proportion for a private app.

Recommendation: do not add video now.
The consistent, openly licensed option is to keep the v17 photos, which cover all 25 poses, and let the voice teach the movement.
If video matters, the route that gives one look across all poses is to film Nick or Nadia doing each pose as a short loop, which also removes every licensing question.
That is a later piece of work, and the runner needs no change to show it, only a media field on the pose.
No media with unclear licensing was added.

## Not done

- A different voice per language or a male voice option.
- Clips for the Mobility stretches, which keep the text-to-speech voice.
- Pausing a clip and resuming it mid-sentence; a paused session cuts the line and carries on from the clock.
