# Codex prompt: set up weekly burn

Follow `AGENTS.md` in the repo root. Read `CLAUDE.md` as well; the project description there covers both agents.

Read `.claude/skills/set-up/SKILL.md` too. It is the reference setup procedure, and the questions it asks apply here unchanged except that reasoning level stands in for effort.

Ask the user's choices in a single batch, not one at a time.

Start by reading the `## Codex` section of `docs/quota-detection.md`. While it lists the Codex quota read as unresolved, tell the user plainly that the Codex burner cannot be armed yet and offer to wire the Claude side instead. Do not install a trigger that would fire against a quota you cannot read.

Do not run the burner at the end. Verification is structural, and a dry first fire is what proves the trigger.

Stop and report the exact failure if a step fails. Do not patch around it.
