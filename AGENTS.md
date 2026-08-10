# Agent Instructions

## Writing

- State the answer first.
- Use clear, simple English.
- Include context and reasons when they help the reader understand or verify the answer.
- Write literal statements. Do not use hyperbole, boilerplate labels, or emphasis words.
- Do not make a reviewer infer meaning or filter out extra words.
- Do not remove useful facts only to make text shorter.
- Remove words, comments, and prose that add no fact or only restate the code.

Read `.pi/PROJECT-ROLLUP.md` first when it exists. It is private and Git-ignored.

After compaction, read `.pi/PROJECT-ROLLUP.md` when it exists and search project memory before work. Treat the compacted summary as navigation. Confirm the environment and next step.

After each meaningful work unit, and before compaction or handoff, append a dated entry to `.pi/PROJECT-ROLLUP.md`. Do not replace, rewrite, or remove earlier entries. Add a later correction when an earlier entry becomes obsolete. Record work, failures, blockers, decisions, live-device state, and the next action. Put commands and evidence in the validation record.

Search project memory before work. Repository files do not replace it.

Read the applicable documents:

- [REQUIREMENTS.md](REQUIREMENTS.md) for scope and completion.
- [wiki/Technical-Reference.md](wiki/Technical-Reference.md) for ownership, boundaries, and interfaces.
- [wiki/Research.md](wiki/Research.md) for source-backed research.
- [wiki/Validation.md](wiki/Validation.md) for live tests.

Keep research and live validation separate.

Do not store applyable patch series. Per-driver annotated review diffs are allowed. Store complete project source files based on the selected upstream source. Extend Lenovo fan support only in `wmi-other.c`; keep its sibling OGC owner files unchanged. Do not fetch or transfer a complete upstream kernel tree to the live device.

Record a work result in no more than three places: `.pi/PROJECT-ROLLUP.md`, the concise `README.md`, and one detail document. Do not copy run narratives into requirements, architecture, interface contracts, research, or unrelated component documents.

Do not enable a write from static evidence alone. Do not add secrets, host addresses, raw logs, or personal data to repository documents or project memory.
