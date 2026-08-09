# Scout Live Validation Policy

Read-only live-validation policy for the LBWC scout role when investigating bugs, issues, or external data sources (APIs, databases, third-party services). This is scout-specific: no other LBWC agent performs live validation this way.

## Bash Usage

- **Allowed:** Use Bash only for read-only, deterministic research and live validation: existing helper scripts, curl wrappers, jq/grep/search commands, and read-only git inspection (`git status`, `git log`, `git show`, safe `git diff`). Public and anonymous HTTP checks should still use WebFetch when it fits the task.
- **Preflight:** Before running any helper script or curl wrapper, inspect its usage, help text, or source enough to verify it is read-only or query-only and will not print tokens, credentials, or other secrets. If you cannot verify that, do not run it.
- **Forbidden:** Do not run commands that mutate files, git state, packages, services, databases, credentials, or external systems. Do not use Bash heredocs, redirection, `tee`, `sed -i`, or similar shell-based file writes. Do not use `eval`, command or process substitution (`$(...)`, `<(...)`, `>(...)`, or backticks), or nested shell execution such as `bash -c` or `sh -c`, including static quoted or absolute interpreter forms and shell control or grouping wrappers. These forms can hide mutating payloads from the scout's read-only validation. Call verified read-only helper scripts or curl wrappers directly instead. Never use Bash to create or edit research artifacts. Use Write for the provided output path instead.
- **Evidence:** When you run or defer live validation, include `## Live Validation Evidence` in the research artifact with these fields: `command_shape`, `exit_status`, `redacted_evidence`, `expected_shape`, `confidence`, and `limitations_or_deferred_reason`.
- **Fallback:** If a validation check is unsafe, mutating, unclear, or requires secrets that would be exposed, mark it incomplete for the engineer or debugger role to validate instead of running it.

## Public vs Authenticated APIs

- **Public and anonymous HTTP endpoints** (docs pages, open APIs, status endpoints): WebFetch is appropriate. Query accessible HTTP endpoints and compare actual responses against what the code expects. Real API responses often reveal the root cause faster than reading code alone.
- **Authenticated and private APIs** (signed requests, tokens, env-based secrets, custom headers): do not validate these via WebFetch. Use verified-safe Bash helper scripts or curl wrappers for read-only checks, following the Bash Usage rules above. Redact tokens, account IDs, credentials, and other sensitive output from findings. If safety, credentials, or expected result shape cannot be verified, document the required validation and emit `⚠ REQUIRES AUTHENTICATED LIVE VALIDATION` for the engineer or debugger role.
- **Non-HTTP data sources** (databases, file systems, local services): run only read-only checks whose safety you can verify. Otherwise document what live data needs to be checked and flag it for the engineer or debugger role to validate.
- Use LSP to trace data flow from external responses through the codebase: jump to definitions, find references, and follow the transformation chain.
- Always include actual response data, or relevant redacted excerpts, in your findings. Do not just describe what the code does. Show what the external source actually returns.

## Empty and Contradictory Response Handling

If a filtered query returns an empty result (`[]`, no matches, blank response):
1. Do NOT assume empty means success.
2. Broaden the query once (remove filters, widen search scope, check for environment or account differences).
3. Compare the result against the expected outcome from the task or plan.
4. If the result still contradicts expectations, write the contradiction explicitly in your findings. Do not silently proceed as if validation passed.
