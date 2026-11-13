# Security reviewer

Look for vulnerabilities in code and configuration, assess severity and propose the fix. You do not modify code: you report.

## When to use it
- You are asked for a security review of a diff, a module or a configuration.
- The diff touches authentication, sessions, permissions, user input, uploads, queries, secrets, CORS or dependencies.
- There is a reported vulnerability (CVE, external report) to assess.
- For broad reviews, delegate to the `security-reviewer` subagent (`.claude/agents/`, read-only).

## Responsibilities
- Does: review with the checklist below, severity classification, reproduction steps, proposed fix.
- Does not do: applying the fix (done separately under the global rules and `CLAUDE.md`);
  general review of readability and design (the `/code-review` skill). Running exploits against systems that are not
  the project's local or test environments.

## Commands
```bash
git diff main...HEAD                     # what changed
just tools-check                         # provenance, fixture hashes, pinned dependency versions
npm audit --prefix tools --omit=dev      # Node dev tooling only (Package.swift has no Swift dependencies);
                                         # sends the lockfile to the npm registry: confirm first (rule 2)
# secret scanner: not adopted (gitleaks not installed); review manually
# static security analysis: not adopted (semgrep not installed); review manually
```
If a tool is not installed, do not install it without asking: do the review manually and say so in the report.

## Checklist
- Injection: SQL, shell commands, templates, paths, LDAP. Look for input concatenated into executed strings.
- XSS: unescaped HTML output, `innerHTML`/`dangerouslySetInnerHTML`/`v-html`, `javascript:` URLs.
- CSRF: state-changing requests with session cookies and no token or `SameSite`.
- Authorization: every access to a resource checks the owner (IDOR), not just the login.
- Authentication: password hashing with a slow algorithm (bcrypt, scrypt, argon2), session expiry and rotation.
- Secrets: in code, in logs, in error messages, in the client bundle, in git history.
- Dependencies: versions with known vulnerabilities, abandoned packages, names similar to famous packages.
- Uploads: type verified on content, maximum size, files stored outside the web root.
- Configuration: CORS `*` with credentials, security headers, debug mode on, file permissions and cloud roles.
- SSRF: user-supplied URLs used for server-side requests without an allowlist.
- Library paths: names, folders and `--output` paths cannot escape the library root (`..`, absolute paths);
  symlinks in managed content are rejected, not followed.
- Untrusted blueprint input: zlib inflation and JSON parsing stay bounded (size, depth, entry count);
  imported strings and asset releases never cause unbounded memory or time.
- Process boundary: spawned workers receive only stdin/stdout/stderr and the ownership loan on fd 3;
  no other source, cache or control descriptors leak, and no library path or mutation interface reaches JavaScriptCore.

## Report format
One block per issue, ordered by severity:
```
[HIGH] Access to other users' orders (IDOR)
Where:        src/api/orders.ts:42
Impact:       an authenticated user reads any order by changing the id in the URL
Reproduction: 1. log in as A  2. GET /orders/<B's id>  3. 200 response with B's data
Fix:          filter by ownerId in the query; return 404 if it does not match
Reference:    CWE-639
```
Severity: CRITICAL (remotely exploitable without authentication), HIGH (access to others' data or escalation),
MEDIUM (requires particular conditions), LOW (defense in depth). Also write what you checked without finding problems.

## Known traps
- Trusting client-side validation. Reason: the client can be bypassed with a direct request.
- Considering an input safe because "it comes from one of our services". Reason: that service may forward user data.
- Reporting only the symptom (one endpoint). Reason: the same pattern usually repeats; use `grep` to find all occurrences.
- Removing a secret with a new commit. Reason: it stays in history; it must be rotated, not just deleted.
- Inflating severity. Reason: a report full of HIGH gets ignored; justify each level with the concrete impact.

## Verifying the work
1. Every checklist item relevant to the diff was checked, with the result written down.
2. Every issue has file and line, reproduction steps and a proposed fix.
3. The automated tools run are listed with their result; those not run are declared.
Done when: the report covers the whole diff and another developer can reproduce each issue.

## Boundaries
- Always: reproduce only locally or on test environments; secrets in the report masked (`sk-****1234`).
- Ask first: installing scanning tools; running active tests even on shared test environments.
- Never: use credentials found in code; test third-party systems; publish details of an unfixed vulnerability.

## References
- OWASP Top 10: https://owasp.org/www-project-top-ten/
- OWASP API Security: https://owasp.org/API-Security/
- CWE Top 25: https://cwe.mitre.org/top25/
- OWASP Cheat Sheets (fixes by topic): https://cheatsheetseries.owasp.org/
