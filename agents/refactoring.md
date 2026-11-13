# Refactoring

Restructure code without changing its observable behavior, in small steps, with green tests before and after every step.

## When to use it
- You are asked to rename, extract, move, merge duplicates or simplify existing code.
- The ground must be prepared for a new feature ("first make the change easy, then make the change").
- If the behavior must change, it is not a refactoring: separate the two into different commits.

## Responsibilities
- Does: behavior-preserving transformations, characterization tests where missing, one commit per step.
- Does not do: fixing bugs found along the way (note them and hand them to `debugger` or the area's role);
  changing public APIs without confirmation; performance optimizations nobody asked for.

## Commands
```bash
<TO FILL IN: full test suite, non-interactive>
<TO FILL IN: typecheck and lint>
git diff --stat           # check that the step touches only what is needed
git commit -m "refactor: <single step>"   # adapt to the commit convention
```

## Procedure
1. **Green baseline.** Run tests and typecheck before starting. If they are red, stop and report it: you do not restructure on a broken base.
2. **Coverage.** If the code to be touched has no tests, first write characterization tests that pin
   down the current behavior, even the odd parts.
3. **One step.** A single transformation (e.g. extract function, rename, move file).
4. **Verify.** Tests and typecheck green after the step.
5. **Commit.** One commit per step, with a message that names the transformation.
6. Repeat from 3. If a step breaks the tests and the cause is not obvious, undo the step (`git restore` on the step's files) instead of chasing the problem.

Example of a single step (extract function, identical behavior):
```ts
// before
const total = items.reduce((s, i) => s + i.price * i.qty, 0) * (1 - discount);

// after
function subtotal(items: Item[]): number {
  return items.reduce((s, i) => s + i.price * i.qty, 0);
}
const total = subtotal(items) * (1 - discount);
```

## Known traps
- Mixing refactoring and behavior change in the same commit. Reason: in review you cannot tell what really changes.
- Renaming with textual find-and-replace. Reason: it touches strings, comments and same-named symbols; use the IDE's rename
  or check every occurrence.
- Forgetting dynamic callers (reflection, strings, dynamic imports, config, templates). Reason: the typecheck does not see them;
  search for the name as a string too.
- Fixing an odd behavior "in passing". Reason: someone may depend on it; note it and ask.
- A large refactoring in one block. Reason: if something breaks you do not know where; stick to small steps.
- Abstractions created for a single use. Reason: they increase complexity without reducing duplication.

## Verifying the work
1. Tests and typecheck green after every commit, not just at the end.
2. No test assertions modified (only names or imports changed, if needed).
3. `git diff <starting commit> --stat` contains only the expected files.
Done when: behavior is identical (same suite green) and every commit is a single, reversible step.

## Boundaries
- Always: green baseline before starting; one commit per step.
- Ask first: changing signatures or names of public or exported APIs; moving files between packages or modules; deleting code that looks dead.
- Never: modify test assertions to make them pass; merge refactoring and a new feature in the same commit.

## References
- Catalog of transformations: https://refactoring.com/catalog/
