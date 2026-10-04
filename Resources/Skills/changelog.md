# The house style for "what I did"

Write release notes, not a diary. The reader is a colleague who was not there
and does not care about your process — they want to know what is different now.

## Shape

Group the work into themed sections. **Never put everything under one heading** —
a single section with fifteen bullets is a list, not release notes, and it is
the most common way this goes wrong.

Name a section after the part of the product the reader uses, never after the
project or repository. With more than about six changes, find three to six
themes and spread the work across them. Sections like Leads, Deals, Contracts,
Reporting, Access, Notifications are the right size; "CRM" or "Floater" is not —
that is the whole product.

Put a **Bug fixes** section last if there were any.

Inside a section, one bullet per change:

```
* Short label: what is different now, in plain language
```

The label is the headline — two to five words, lowercase after the first word,
no full stop. Then a colon, then one sentence a non-engineer would understand.
Two sentences only if the second genuinely adds something.

## Write the outcome, not the task

A task title describes what you set out to do. A changelog line describes what
is now true. Translate.

- Task: "Fix the lost reason tree"
  Line: "Lost reasons cascade: picking a general reason now filters the
  intermediate list to match"
- Task: "CRM : Hatif api"
  Line: "Hatif calls log themselves: every call on the sales number shows on the
  client's deal with the recording and transcript"

Prefer the active voice and the present tense. "Everyone sees every deal", not
"Visibility was increased".

## Bug fixes

Say what was broken, in the reader's words, and that it is fixed by implication.
No severity labels, no ticket numbers.

- "The deal page used to freeze for up to a minute before you could edit; it
  now opens in about a second"
- "Searching or clicking fast used to sign you out"

## Every line is something that is now true

A finished task means the thing is done. If its title names a problem, write the
fixed state, not the problem.

- Task: "Not all leads have # of workers"
  Wrong: "this data validation issue needs resolution"
  Right: "Worker count is required: leads now carry a worker count"

If a line would say no more than the task title already did — "Data cleanup:
data cleanup has been completed" — either work out what actually changed for the
reader, or leave it out. A line that carries no information is worse than a
shorter list.

## Rules

- Every line must trace to something in the fact sheet. Invent nothing — not a
  feature, not a number, not a project.
- No preamble, no summary paragraph, no sign-off, no "this week I".
- Do not report time spent, task counts, levels or streaks. Nobody reading a
  changelog cares how long it took.
- A section needs at least two bullets to be worth having; otherwise fold it
  into a more general one.
- Merge near-duplicate changes into one line. "Filter by date entered" and
  "filter by qualifier" are one bullet about new filters, not two.
- If there is nothing to report, say so in one line and stop.
