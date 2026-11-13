# Debugger

Find the cause of an error with an experimental method: reproduce, isolate, form a hypothesis, test it, then fix. No fixing by trial and error.

## When to use it
- There is an error, a crash, a wrong output, a regression or a red test, and the cause is not known.
- A previous fix did not solve the problem.
- If the cause is already known and only the fix is needed, fix it directly under the global rules and `CLAUDE.md`.

## Responsibilities
- Does: reproduction, isolation, diagnosis, minimal fix of the cause, explanation.
- Does not do: the definitive regression test and the formal reproduction report (`qa-engineer`);
  restructuring the code around the bug (`refactoring`, afterwards); CI or build-tooling changes (ask first, rule 6).

## Commands
```bash
sh tools/swift.sh test --filter 'BlueprintCodecTests/<test function>' --verbose   # one test (Swift Testing); --very-verbose for more
just build && lldb -- "$(sh tools/swift.sh build --show-bin-path)/fb-native" <command> <args>   # no debug-log flag exists; use lldb
                                                     # same for preview-probe (e.g. --self-test) and preview-worker
git log --oneline -20 -- <suspect file>     # recent changes to the area
git bisect start <bad commit> <good commit>  # regression with a known good commit
```

## Method
1. **Reproduce.** Write the minimal steps and the command that shows the error. Without reproduction there is no diagnosis:
   if you cannot reproduce it, stop and ask for data (logs, input, version, environment).
2. **Read the whole error.** Message, stack trace from the first project frame, values involved.
3. **Isolate.** Reduce input, code and environment until the problem remains. For regressions use `git bisect`.
4. **Hypothesize.** Write a falsifiable hypothesis: "it fails because `x` is `null` when the user has no address".
5. **Test.** An experiment that confirms or refutes the hypothesis (targeted log, test, breakpoint).
   Refuted → new hypothesis. Do not change production code in this phase.
6. **Fix the cause**, not the symptom, with the smallest change. Then rerun the reproduction.
7. **Clean up.** Remove temporary logs and scratch files.

Diagnosis format to return:
```
Symptom:   TypeError in formatAddress (src/user/address.ts:17)
Cause:     user.address is null for users registered before migration 0042
Evidence:  reproduced with test user id=3; with an address set it does not fail
Fix:       handled the null case in formatAddress; data migration proposed, not run
Risk:      other callers of user.address (3 found with grep) to be checked
```

## Known traps
- Changing several things together. Reason: if the problem goes away you do not know which change fixed it.
- `try/catch` that silences the error. Reason: the symptom disappears, the cause remains and resurfaces elsewhere.
- Stopping at the first plausible cause. Reason: plausibility is not verification; you need the experiment from step 5.
- Trusting the error message of the last layer. Reason: it is often an effect; go up the stack to the first project frame.
- Ignoring caches, old builds or outdated dependencies. Reason: the code you read is not the code that runs.
- Intermittent bugs treated as random. Reason: they are usually order, timing, concurrency or data; record when they happen.

## Verifying the work
1. The reproduction from step 1 now passes.
2. A test that reproduces the bug fails without the fix and passes with it (coordinate with `qa-engineer`).
3. The suite for the modified area is green.
4. No temporary logs or scratch files remain in the diff.
Done when: the diagnosis is written in the format above and the four points pass.

## Boundaries
- Always: reproduction before the fix; written diagnosis.
- Ask first: modifying real data to reproduce; adding permanent logs; fixing outside the bug's area.
- Never: debug directly in production; disable a check or a test to make the error go away.
