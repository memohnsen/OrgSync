# Repository Agent Instructions

## Starting work

- Before beginning any work, run `git pull --ff-only` so the local branch is up to date with its upstream branch.

## Delivery workflow

- After completing a repository change, commit it, push the branch, and open a pull request.
- Monitor the pull request checks and merge the pull request once CI is green.
- If CI fails only because of a billing, credits, or account-payment restriction, merge the pull request despite that infrastructure failure.
- If verification cannot run because 1Password authentication fails, commit and deliver the change unverified instead of blocking the delivery. State clearly that verification was skipped for that reason.
- Do not treat ordinary test, build, lint, or product failures as billing or 1Password exceptions.

## Code quality

Build for the long term, not merely to finish quickly. Prefer small functions that can be tested in isolation. Make them pure when possible: put parsing, calculations, transformations, and decision logic in focused Swift helpers under the appropriate domain directory, such as `OrgSync/OrgKit/`, `OrgSync/Sync/`, `OrgSync/Agenda/`, `OrgSync/Support/`, or `Shared/`, rather than burying that logic in SwiftUI views, app-intent wrappers, store objects, or platform callback handlers.

For the complete maintenance cycle, use the repository skill at `.codex/skills/review-code-performance-tests/`: perform a code-quality review, an evidence-based performance review, and then a risk-based test and edge-case review.

## Reliability guideposts

Use the high-level principles from Gerard Holzmann's Power of Ten and TigerBeetle's TigerStyle, adapted to this Swift/SwiftUI codebase:

- Favor simple, explicit control flow and the minimum useful abstractions. Avoid recursion or indirection when it obscures boundedness, ownership, or the call graph.
- Put an explicit, defensible bound on work, collections, retries, queues, payloads, and resource use. Treat external input as unbounded until it has been validated.
- Keep functions small enough to understand and verify as a unit. Centralize branching and state transitions in orchestrators; move calculations and iteration into focused, preferably pure helpers.
- State and enforce invariants at boundaries. Validate function inputs and outputs, use assertions for impossible programmer errors, test both valid and invalid input space, and pair checks across write/read or encode/decode boundaries when practical.
- Declare data in the smallest useful scope. Maintain one source of truth, calculate values close to use, and avoid aliases or duplicated state that can drift.
- Handle every error and non-void result deliberately. Propagate it, recover explicitly, or document why ignoring it is safe.
- Prefer transparent language features, direct data flow, and tool-friendly types over metaprogramming, hidden defaults, forced casts, and deeply nested indirection.
- Keep the strictest compiler, linter, static-analysis, and test checks warning-free. Rewrite confusing code instead of suppressing a tool without a documented reason.
- Optimize design goals in this order: safety, performance, developer experience. Do design and back-of-the-envelope resource sketches early; optimize the slowest or highest-frequency resource first, and batch external work where appropriate.
- Use precise nouns and verbs, include units or qualifiers in names, avoid ambiguous abbreviations, and explain why surprising decisions or invariants exist.
- Treat discovered correctness, security, and architecture debt as current work. Remove dead or repeated code rather than adding compatibility layers without a demonstrated caller.
- Keep dependencies and bespoke tooling intentional. Every dependency, abstraction, default, and mutable-state owner adds failure and maintenance surface.
