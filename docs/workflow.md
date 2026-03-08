# Workflow: How we produce results we can trust

This repo is a modelling + inference lab. The workflow below is mandatory: it prevents us from believing pretty maps that are actually nonsense.

---

## 1) Ground rules

1. **Everything heavy runs through `targets`.**
   - No “one-off scripts” that bypass QA unless they live in `dev/` and are explicitly labelled as benchmarks.
2. **Use `renv` always.**
   - Do not install packages into the system library and assume they exist.
3. **Streaming TX-only is the default for scale.**
   - If you allocate a 3D abundance cube for large screens, you are reintroducing the very failure mode we already escaped.
4. **Extirpation timing must use the first-passage estimator.**
   - Any alternative must be justified and recorded in `docs/decisions.md`.

---

## 2) The Result Review Cycle (the only way results become “real”)

For any new result (figure/table/report section), complete all three steps:

### Step A — Sanity (numerical + ecological)
You must implement and run explicit checks. Examples:
- Coverage sanity:
  - observed and simulated coverage in plausible ranges
- Lag sanity:
  - mean lag in expected range (and sign convention consistent)
- Geometry sanity:
  - if you expect a front, check that front summaries behave sensibly
- Failure-mode detection:
  - NaNs, Infs, degenerate summaries, zero extirpations, “extinct from day one” artefacts

Where possible:
- codify these checks as tests (`tests/testthat/`) or assertion helpers.

### Step B — Interpretation (write it down)
In `docs/interpretation_notes.md`, write:
- what the artefact shows (not what you hoped it would show),
- what is surprising,
- what is inconsistent with the model’s intended meaning,
- what you think is driving the behaviour.

Keep it bullet-pointed and blunt.

### Step C — Iteration (change something, or accept the limitation)
Based on interpretation notes:
- update `docs/plan.md` “Current status and next steps”
- if a design choice changes, write a short entry in `docs/decisions.md`
- implement the next iteration through `targets`

No iteration, no progress.

---

## 3) Practical run patterns (minimal commands)

### Environment + tests
- `make setup`
- `make init`
- `make test`

Notes:
- `make setup` is the non-mutating restore path for a fresh checkout.
- `make init` is the maintainer path when you intentionally want to re-document and snapshot the lockfile.

### Running pipelines
- Full pipeline (expensive): `make run`
- Pilot (real mink→vole): `make pilot`
- Synthetic twin: run the synthetic targets directly (and/or add a Makefile shortcut).

### Reports
Render after targets exist:
- `make report-qa`
- `make report-id`
- `make report-sens`
- `quarto::quarto_render("reports/pilot_mink_vole.qmd")`
- `quarto::quarto_render("reports/synthetic_mink_vole.qmd")`

---

## 4) Logging rules (audit trail)

### Narrative logs (required)
For each phase of substantial work, create/update:
- `docs/log/NNN_<short_name>.md`

Each log must include:
- what changed (code + config),
- what you ran (commands + key targets),
- key outputs (file paths),
- sanity check outcomes,
- what we learned and what is next.

### Runtime logs (already present)
`logs/wo*.log` are runtime/event logs produced by pipelines. Keep them, but treat them as “instrument traces”, not as scientific interpretation.

---

## 5) Minimum gating criteria (don’t move goalposts silently)

We use gates to stop ourselves from rationalising garbage.

### Synthetic twin gates (Phase 010)
- Replicated recovery must report:
  - bias and interval coverage for key parameters,
  - posterior predictive geometry + coverage curve diagnostics.
- If a parameter is weakly identified, it must be labelled as such (not quietly ignored).

### Real-case gates (Phase 020)
We do not claim success unless:
- best draw achieves at least modest spatial agreement (e.g., R²≥0.2) and
- lag is positive and plausible and
- coverage is non-trivial
without implausible δ distortions.

Failure to pass gates is a result, not an embarrassment.
