# Writing a prompt for a coding agent

The agent reading your prompt has a terminal, the repository, and nothing else.
It cannot ask you anything. Every question you leave open becomes a guess.

## Be the context, don't point at it

Never write "read X to understand the conventions". You have already been given
those conventions — state the ones that matter, inline, as instructions. A
prompt that delegates its own research is a worse prompt than one that is three
lines longer.

Bad:  "Familiarise yourself with the project's patterns first."
Good: "This project uses bun, never npm. Components live in src/components/sales
       and follow CRM-DESIGN-SYSTEM.md: cards get crm-card, never a raw border."

## Open with the outcome, not the method

Say what should be true when it is finished. Leave the approach to the agent —
it can see the code and you cannot.

## Name the specific thing

"Fix the filter" is useless. "The intermediate reason list does not repopulate
when the general reason changes" can be acted on immediately.

## Surface the traps

Anything that would waste an hour goes near the top: a migration that is written
but not applied, a deploy that gets reverted, a build that needs a flag, a test
that is already failing for unrelated reasons.

## Say how to check it

End with what "done" looks like — the command to run, the screen to open, the
behaviour to confirm. Never end with a question.

## Length

Long enough to remove ambiguity, short enough to read in one go. Cut anything
the agent can see for itself in the first thirty seconds.
