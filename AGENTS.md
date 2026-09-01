# Repository Agent Instructions

## Delivery workflow

- After completing a repository change, commit it, push the branch, and open a pull request.
- Monitor the pull request checks and merge the pull request once CI is green.
- If CI fails only because of a billing, credits, or account-payment restriction, merge the pull request despite that infrastructure failure.
- If verification cannot run because 1Password authentication fails, commit and deliver the change unverified instead of blocking the delivery. State clearly that verification was skipped for that reason.
- Do not treat ordinary test, build, lint, or product failures as billing or 1Password exceptions.
