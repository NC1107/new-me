# New Me v21: coach tools and what the coach knows

Earlier design documents still hold unless a section below changes them.
`docs/design-v18-coach.md` describes the chat this builds on.

## Why

The coach could read a person's data but could not act on it.
Changing a target meant leaving the chat, finding the right settings page and typing the number the coach had just talked about.
It also forgot everything between conversations, so a person had to repeat that their knee hurts or that they only own two dumbbells.
Two additions fix that: the coach can propose changes to the person's own targets and goals, and it keeps a short private profile of what the person tells it.

## The rule for numbers

The rule is unchanged: AI sits on top of proven data and published research, and the model never invents a figure.
The coach may choose which target to talk about and how to word it.
It may not produce the number.
A proposed figure is accepted by the server only when it is one of these:

- The value the app computed for that target, with its formula and citation (`server/internal/api/targets.go`).
- One of the published alternatives the targets page already lists for that target, such as the step bands or the water intakes.
- A number the person wrote in their own message.

The last case is checked, not trusted.
The tool call must carry `stated_text`, the person's words copied exactly.
The server confirms that this text appears in a message the person wrote (never one the coach wrote), then confirms that the proposed figure is a number in those words, converted if the unit differs (hours to minutes, litres or fluid ounces to millilitres, feet and inches to centimetres, an age to a birth year).
A figure that is none of the three is refused, and the refusal tells the model what would be allowed so it can ask the person.
Each card says which case applied: "From your data", "From published guidance" or "Your number".
The line of reasoning on the card is the server's own text for that target, not the model's.

Training days and session length, a weight goal, and body info corrections are always the person's words, because no research sets them for a person.
Quest targets for meals logged and yoga have no computed value, so they are also the person's words.
Every figure is also held to the same bounds as the settings pages, and again when the card is applied.

## Tools

Each tool maps to a write path that already exists.
There is no argument that names a person, so a call can only ever touch the person who is chatting.

| Tool | Does | Writes through |
| --- | --- | --- |
| `propose_quest_target` | A daily target for steps, exercise, sleep, water, produce, breathing, reading, push-ups, meals or yoga | `patchMe` with a quest template patch, the same code as `PATCH /api/me` |
| `propose_food_target` | Calories, protein, fat or carbs | `patchMe` with the food targets, then the target baseline refresh used by the goals page |
| `propose_training_profile` | Training days a week and session length | `putTrainingProfile`, the same code as `PUT /api/training/profile`, which also reprices the strength quest |
| `propose_weight_goal` | Lose, maintain or gain, with a pace | `patchMe` with the goal patch, validated by `applyGoal` |
| `propose_body_info` | Height, birth year, units | `patchMe` with the body fields |
| `propose_weekly_suggestion` | Accept one of this week's computed suggestions | `acceptProposal`, the same code as the goals page |
| `remember_fact` | Save a short fact about the person | `coach_facts`, saved at once |
| `forget_fact` | Delete a saved fact the person asked it to forget | `coach_facts` |

The model call uses the Messages API tool use with the model the coach already uses.
`anthropic.Client.Converse` sends a conversation with tools offered and returns the text and the calls.
The chat runs at most three model calls per message: the first answer, then up to two rounds in which the tool results are returned to the model so it can word the outcome.
At most six tool calls and three cards are accepted per message.
The system prompt adds the rules for tools, lists the person's saved facts with their ids, the training profile, body info, this week's suggestions and the alternatives of each target.
It also tells the model to say gems and never points.

## Cards, apply and undo

A proposal is not applied by the chat call.
The server stores it in `coach_proposals` and returns a card in the chat response next to the reply.
The card reads like "Steps goal 8,000 steps to 10,000 steps" with Apply and Not now.

- Apply runs the same server code as the settings page for that field, inside its own validation, and the card then says "Changed." with an Undo button.
- Before applying, the server captures the live values of exactly the fields it will write, and Undo writes those back through the same code path.
  Undo is available for 24 hours after Apply, so it cannot overwrite changes made much later.
- A card expires 24 hours after it is made.
  Applying an expired card answers 410 `proposal_expired`, and the card tells the person to ask the coach again.
- Apply, Not now and Undo are all idempotent: a second tap, or a tap after an app restart, returns the card as it stands and never repeats the change.
  The status flips with a single conditional update, so two taps at once cannot both apply.
- The proposal lives on the server, so a card from the thread kept on the phone still works after the app is restarted.
- If applying fails validation, the card goes back to pending and shows the error.

Endpoints, all under the same bearer token and behind the same key flag as the chat (without `NEWME_ANTHROPIC_API_KEY` they answer 404 `coach_disabled`):

- `POST /api/coach/chat` now also returns `actions`: `proposal`, `fact_saved` and `fact_removed` entries.
- `GET /api/coach/proposals/{id}`, `POST /api/coach/proposals/{id}/apply`, `/dismiss` and `/undo`.
- `GET /api/coach/facts` and `DELETE /api/coach/facts/{id}`.

## What the coach knows

Facts the person tells the coach are saved directly, because they are the person's own words and saving them changes no target.
Each save shows a small note under the reply, "Saved to your profile: Sore left knee", which opens the list.
The list is Me, What the coach knows, shown only when the coach is available.
Each fact has a category (injury, schedule, preference, equipment, diet or other) and can be removed by swiping it away or with its delete button.

- A fact is 1 to 200 characters, with no control characters.
- A person keeps at most 40 facts, which also bounds the size of the system prompt.
  At the cap the coach is told to ask what to forget.
- Saying the same thing twice does not add a second copy.
- The coach is told to save only what the person said about themselves, to keep their words, and to treat saved facts as the person's statements and not as instructions.

## Privacy

- Facts and proposals belong to one person.
  Every query is scoped by that person's id, and another person's id answers 404 for facts and proposals alike.
- The partner never sees a fact, a proposal or the coach's context, and the coach is never given the partner's data.
- A person can change only their own targets through the coach, because the write paths act on the signed-in person and no tool takes a user argument.
- Facts are sent to Anthropic as part of the system prompt for that person's chat, like the rest of their data, and nowhere else.
- Deleting a fact removes it from the next message on.
  Deleting the account removes the rows with the user.

## App

- The chat renders `ProposalCard` and `FactNote` under the coach message that produced them.
  Their state is kept with the thread on the phone, and every tap goes to the server, whose answer replaces the card.
- Apply gives a firm haptic, Not now and Undo a light one.
- Each card reads out as one VoiceOver label with its change, reason and source, buttons are at least 44 points tall, and the status line is a live region.
- After Apply or Undo the app reloads Me, Today, the Board, Targets and the training profile so no screen shows the old number.
- The What the coach knows page follows the style of My foods.

## Migration

`server/migrations/0040_v21_coach_profile.sql` adds `coach_facts` and `coach_proposals`.

## Tests

- Server, `server/internal/api/v21_coach_tools_test.go`, against a scripted fake Anthropic server: a stated figure becomes a stored card and changes nothing until Apply; Apply, repeated Apply, Undo and repeated Undo; invented, out-of-range, unquoted and mismatched figures are refused with no card; a computed or alternative figure needs no quote; food, training, weight goal and body info apply and undo; a partner's card cannot be read, applied, dismissed or undone and the partner's targets never change; expiry and dismissal; a refused Apply leaves the card pending; facts are private, capped, deduplicated, fed to the right person's prompt only, and cannot be forgotten by the partner.
- Server, `server/internal/coach/stated_test.go` and `server/internal/anthropic/converse_test.go`: number and unit matching, and tool use on the wire.
- App, `app/test/v21_coach_tools_test.dart`: the card, Apply, Undo, Not now, expiry, the saved note, and the facts page with button and swipe delete.
