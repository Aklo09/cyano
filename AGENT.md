# AGENT.md

Index of capabilities and global rules. The global rules apply to every task.
For roles, read only the file in `agents/` that matches the task, and only when the task requires it.

## Global rules
1. Reply in the language the user writes in. Code names, commands, flags and error messages stay in their original form.
2. Ask for confirmation before irreversible or outward-facing actions: deleting files or data, `git push --force`,
   `git reset --hard`, rebasing shared branches, deploying or changing production, sending data
   to external services, any operation that moves real money.
3. Never write secrets (keys, tokens, passwords, `.env` contents) in code, commits, logs or replies.
   If you find one in the diff or the repository, stop and report it with file and line.
4. Do not say "done" without running the verification in the role file. Report the command you ran and its result.
   If you could not run it, say so and explain why.
5. Do not delete, skip (`skip`) or weaken a failing test without explicit authorization:
   a red test is information, not an obstacle.
6. Ask before adding dependencies, changing the database schema or modifying CI/CD.
7. Change only what the task requires. Problems found out of scope: report them, do not fix them.
8. `<TO FILL IN: ...>` placeholders: derive the value from the project (`package.json`, `Makefile`,
   `pyproject.toml`, CI files, `git log`) and state which file you took it from. If you cannot find it, ask.
   Do not invent commands, paths or versions.
9. Commits: imperative, sentence-case subject with no type prefix or trailing period
   (e.g. `Implement native preview renderer and supervised workers`), derived from `git log --oneline -20`.
   One commit per logical change.

## Capability index

| Capability | File | Use it when |
|---|---|--- |
| Security reviewer | `agents/security-reviewer.md` | You are asked for a security review, or the diff touches authentication, permissions, user input, secrets, uploads or dependencies. |
| Debugger | `agents/debugger.md` | There is an error, a crash, a wrong output or a red test and the cause is not yet known. |
| Refactoring | `agents/refactoring.md` | You are asked to restructure code (rename, extract, move, remove duplication) without changing observable behavior. |
| Product manager | `agents/product-manager.md` | You need to write a spec, user stories or acceptance criteria, define what is out of scope or prioritize a backlog. |
| UX designer | `agents/ux-designer.md` | You need to design or review a user flow, a layout, empty/error/loading states or the accessibility of an interface from the user's point of view. |
| Technical writer | `agents/technical-writer.md` | You need to write or update READMEs, guides, changelogs or API references meant for people. |

## How to choose
- Read the minimum: one role if that is enough. Every file you read stays in context for the whole session and costs on every request.
- Frequent combinations, in order:
  - bug: `debugger` (cause) → fix under the global rules and `CLAUDE.md`, verified with the focused `just` suite → `qa-engineer` subagent (regression test);
  - new feature: `product-manager` (spec, if missing) → implement under the global rules and `CLAUDE.md` → `qa-engineer` subagent;
  - review: the `/code-review` skill, plus `security-reviewer` if the diff touches auth, input, secrets or dependencies.
- With several roles active, if two rules conflict the more restrictive one wins.
- If no entry matches, work with the global rules only and tell the user in one line.
- The user's explicit request overrides the role files, but not rule 2: confirmations stay.

## Context and cost
- Read large files by line ranges; search with `grep` before opening whole files.
- Voluminous output (test suites, logs, many web sources): delegate to a subagent and report only the summary.
  Ready-made subagents exist in `.claude/agents/` for QA (`qa-engineer`) and security (`security-reviewer`).
- Do not load whole datasets or time series into context: process them with a script that prints only the result.

## Compact instructions
When compacting, keep: the active role files, the commands run with their results, the decisions made
with the user, the files modified and the open items. Discard test output and logs that have already been summarized.

<!-- Maintainer notes: block-level HTML comments do not enter the context. -->
<!-- Do not import roles with @agents/...: an import loads the file every session and defeats the index. -->
<!-- Installation, choices made and verification: see README.md. -->
