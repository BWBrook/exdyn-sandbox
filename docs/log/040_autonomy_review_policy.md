# 040 — Roadmap review policy update (autonomous-by-default)

Date: 2026-02-09

## Change summary
- Updated governance language so external PI review is no longer a mandatory stop condition.
- Active policy is now:
  - internal Codex QA/review loops are default,
  - external PI review is optional and triggered only by explicit human request.

## Files updated
- `docs/roadmap.md`
  - Replaced mandatory PI-review gates with internal quality-gate/checkpoint policy (Section 5).
  - Updated WP‑0.3.5a and WP‑0.3.5b failure wording from mandatory PI escalation to internal failure bundle + autonomous remediation.
- `docs/plan.md`
  - Replaced “PI review clearance” next-step language with autonomous progression plus optional external handoff on request.
- `docs/decisions.md`
  - Added a dated decision recording the governance shift and implications.

## Rationale
- Current operating mode prioritises autonomous R&D with rapid iteration and in-repo validation.
- Mandatory PI stops remain available as an explicit human choice rather than a default policy.

## Notes
- This is a policy update only; no model, pipeline logic, or scientific outputs were changed.
