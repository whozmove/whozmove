---
name: asking-questions
description: How to write a question for the user, with the AskUserQuestion tool, so it reads at a glance and the choice is clear. Use it whenever you're about to ask the user to choose between options, pick an approach, or answer yes or no, so the question, each option's name and its meaning stay short and plain.
---

# Asking the user a question

The user answers your question between other work, often from a small card beside their other windows. Write it so
they can answer at a glance, without reading a paragraph first.

## The question

- **One thing to decide**, in under 70 characters. Put no brackets in it. The detail goes in the options.
- Write it as the user would say it: "Add a test for expired coupons?", not "Should I proceed with test coverage
  augmentation (unit + integration) for the coupon module?"
- Its header (the short label) names the subject in one or two words: "Tests", "Payments".

## The options

- **Two to four.** If you need more, the question is two questions.
- **The name says what happens, in four words or fewer**: "Yes, add it", "Not now", "Use Stripe".
- **The one you'd pick goes first**, with "(Recommended)" after its name. That word doesn't count toward the four.
- **Its meaning is one line**: what the user gets or gives up by picking it. Write it in plain words, with no file
  names, code, settings or the names of other sessions unless the choice is about them.
- Every option is a real choice. Don't add one whose only purpose is to say "something else": the user can always
  type their own answer.

## When it doesn't fit

If a choice needs a paragraph to explain, write that paragraph in a file, and ask about the file: "Read the plan in
plans/coupons.md and approve it?", with the file named in the recommended option's meaning.

## Before you send it

Read it as the user will: the question, then each option's name and its one line. If any line wraps more than once,
or they'd need to look something up to choose, shorten it.
