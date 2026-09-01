---
name: review-code-performance-tests
description: Review OrgSync repository changes through a complete code-quality, evidence-based performance, and risk-based test and edge-case maintenance cycle. Use for repository-wide TigerStyle reviews and when AGENTS.md requires the full maintenance cycle.
---

# Review Code, Performance, and Tests

Run the three phases below in order. Keep findings tied to observable code,
tests, measurements, or explicit resource estimates. Do not turn a review-only
request into repository changes; when fixes are requested, address validated
findings and verify them before delivery.

## 1. Code-quality review

- Read the applicable `AGENTS.md`, the relevant diff, and enough callers and
  tests to understand ownership and invariants.
- Prioritize correctness and data preservation, especially around note writes,
  Git synchronization, persistence, external services, and async state changes.
- Check that every error and non-void result is propagated, explicitly
  recovered, or intentionally documented as best effort.
- Look for duplicated state, hidden defaults, unsafe fallbacks, excessive
  indirection, untestable view/controller logic, and mutations that can absorb
  stale or unreadable data.
- Prefer focused pure helpers for parsing, calculations, transformations, and
  iteration. Keep orchestration and state transitions explicit at the boundary.
- Report findings by severity with a concrete file and line reference. Explain
  the failure mode, not merely the stylistic preference.

## 2. Evidence-based performance review

- Identify the highest-frequency or highest-cost paths before proposing an
  optimization. Inspect actual collection sizes, loops, parsing, filesystem
  scans, network calls, render-time work, and allocation patterns.
- Treat repository contents, note text, API payloads, retries, queues, and
  recursion depth as unbounded until a checked limit proves otherwise.
- Write a short resource sketch for material risks: input bound, asymptotic
  cost, approximate worst-case allocation or request count, and the chosen cap.
- Prefer removing repeated work, bounding it, caching with explicit
  invalidation, or batching external operations. Do not make speculative
  micro-optimizations without evidence that the path matters.
- For quadratic algorithms such as line diff or merge, enforce the bound before
  multiplication or allocation so integer overflow cannot bypass it.

## 3. Risk-based tests and edge cases

- Build a risk map from the reviewed changes and findings. Cover the
  highest-impact failure modes first: data loss, partial persistence, remote
  truncation, unreadable or invalid input, size/depth boundaries, concurrency,
  and externally injected failures.
- Test valid, invalid, and exact-boundary behavior. Pair checks across
  write/read and encode/decode boundaries when practical.
- Prefer deterministic unit or integration seams over live services. Use the
  opt-in live GitHub task only when its credentials and marker are intentionally
  in scope.
- Run the narrowest useful tests while iterating, then the repository checks
  appropriate to the change. `mise.toml` is the command source of truth:
  `mise run build`, `mise run test-ci`, and `mise run test`.
- Keep complete concurrency checking, compiler warnings, and test output clean.
  Do not suppress a diagnostic without a documented correctness reason.

## Handoff

Summarize validated findings and fixes, performance bounds or measurements,
tests run, and any remaining risk. Distinguish a verified defect from a design
tradeoff or untested hypothesis.
