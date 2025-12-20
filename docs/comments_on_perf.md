## Human questions

My question: do you propose further work on the 0.2.x line (i.e., additional milestones), or is it okay to proceed to run through the 0.3.x line now on the toy/medium settings? Or should we move to 0.3.x line but add further milestone gates on this? 

I guess my point is, we want to have all this clearly locked down BEFORE we move back to the full GB-scale synthetic example, which is current 0.3.5 on the roadmap. 

My second question: can you think of any clever ways of improving speed of execution and/or memory use on the full runs, or is this essentially a canoncial constraint of dealing with large grids with this spatio-temporal model?

## PI_1 response
You were right to get twitchy. And the Codex work basically proves it: **the “8‑hour smoke test” wasn’t exposing a slow ecological simulator — it was exposing a workflow/perf trap (observation mapping + I/O + accidentally running something non‑smoke at full scale).**

From the profiling artefacts you now have:

* **The TX‑only simulator is cheap.** In the toy stage profile, the *entire* per‑year sim loop (`sim_total`) is tiny compared to everything else.
* **The expensive bit was the observation pipeline, especially TX mapping + saving.** In `stage_profile_smoke.csv`, `observation_tx_map` and `save_outputs` are the largest single stages, and you’ve already shown the old TX mapping path was a pig: `exdyn_tx_map_fast` gives ~**4.2×** speedup on that stage (`optimisation_before_after.csv`).
* **So the root cause wasn’t “large grids are impossible”.** It was: (i) a non‑toy run profile being triggered, (ii) the realistic observation pipeline being engaged, (iii) a slow `tx_map` implementation, plus (iv) I/O overhead being nontrivial when repeated many times.

That’s consistent with the grant’s own philosophy: you *must* control tractability and scaling first; otherwise pattern‑oriented calibration/ABC becomes computationally unwieldy and you learn nothing. 

---

## Q1) Do we extend 0.2.x further, or proceed to 0.3.x on toy/medium?

### My PI call: **Proceed to 0.3.x now — but add one hard gate before touching 0.3.5.**

You’ve already done the right 0.2.x work. I **do not** want you disappearing into an endless “perf improvement” rabbit hole. The point of 0.2.x was to (a) find the hotspot, (b) stop accidental inferno runs, (c) fix the most obvious bottleneck, and (d) put guardrails in place. You’ve done that.

**However**: there’s one thing I would *still* treat as non‑negotiable before 0.3.5 (full GB synthetic benchmark):

### Add a single new gate WP (call it WP‑0.2.7 or WP‑0.3.4b)

**WP‑0.2.7 — GB‑scale preflight budget check (single‑replicate, realistic mode, real RSS)**

Why: your current “peak_mem_mb” values are clearly not true peak RSS (they’re flat in the perf tables), so you don’t yet have a trustworthy memory envelope. Also, the only way to avoid another “8 hours later…” incident is to do a *single* GB‑scale preflight and pin its budget.

**Acceptance criteria (black‑and‑white):**

* Run **one** GB‑geometry synthetic replicate in **realistic** mode (sim + obs + TX estimator), with canonical output enabled, and measure:

  * wall clock time,
  * **true peak RSS** (via `/usr/bin/time -v` or equivalent).
* Write the measured budgets into `docs/decisions.md` (Performance Budget) and link the canonical folder.
* If the single‑replicate runtime implies WP‑0.3.5 will exceed your acceptable walltime (given planned replicates and ABC sims), the roadmap halts and you do *targeted* optimisation (not hand‑waving).

That’s it. One extra gate. Not a new performance epic.

### What proceeds immediately

Go straight back to **WP‑0.3.1–0.3.4 on toy/medium only**. That’s the correct workflow:

* schema/canonical scaffolding,
* mode separation,
* replicated recovery metrics,
* summary/loss alignment and regression tests,

…all of which can and should be validated on toy/medium profiles.

This is exactly what the grant expects conceptually: **scale up only after tractability + validation**, because the scientific claims depend on being able to run many models and compare emergent patterns. 

---

## Q2) Can we make full runs faster / smaller, or is this “canonical large-grid pain”?

### Blunt answer: **it’s not canonical pain — you still have big wins available.**

Some cost is unavoidable (ABC means “lots of sims”), but your current profiling screams: **constant factors are dominating**, not asymptotics.

Here are the genuinely high‑leverage moves, in the order I’d consider them **if and only if** the GB preflight gate shows WP‑0.3.5 will be too expensive.

---

### 1) Stop generating point-level observations for synthetic runs (simulate cell‑year counts directly)

Right now, “realistic mode” likely does something like:

1. simulate latent dynamics,
2. generate presence‑only *points* (a data frame of events),
3. map points back to cell‑year counts/index,
4. run first‑passage TX estimator.

For **synthetic** data, that point layer is pure waste: **the inference only depends on cell‑year counts/index**, not on within-cell coordinates.

**Replace synthetic observation generation with:**

* directly sample `y[x,t] ~ Poisson(λ[x,t])` (and background effort counts similarly),
* compute the effort-normalised index matrix,
* run first‑passage TX estimator on matrices.

This:

* removes the entire “generate N points → group_by → summarise → reshape” tax,
* slashes memory pressure,
* keeps the observation model *statistically equivalent at the grid scale* (which is all you use).

This alone can turn “hours” into “minutes” for replicated realistic-mode benchmarks.

---

### 2) Slash I/O: only save heavy artefacts for canonical runs (and for *one* reference replicate)

Your profiling shows `save_outputs` is a major stage even in toy runs. Multiply that by:

* many draws,
* many replicates,
* ABC iterations…

…and I/O becomes a silent killer.

Rule:

* For screens/ABC internals: save **only** (a) summary vectors, (b) scalar metrics, (c) posterior samples.
* Save TX maps **only** for:

  * best screen draw,
  * posterior predictive representative draws,
  * the single “reference replicate” used in the report.

If you’re saving TX rasters/matrices for every replicate/draw, you’re paying rent on files you never look at.

---

### 3) Crop the computational domain aggressively (don’t FFT over ocean)

If your grid is defined by a big bounding box and most cells are “sea/masked out”, FFT dispersal is doing work on a rectangle full of zeros. That’s avoidable.

Two options:

* Use the **tightest bounding rectangle** of active cells (plus dispersal padding).
* Or (even better for riparian masks) stop using 2D convolution at all (see #4).

This reduces both runtime and memory, and it’s scientifically harmless if done correctly.

---

### 4) For riparian systems: simulate on a graph/segments, not on a 2D raster

This is the *structural* efficiency win.

If your ecology is river‑network constrained, the 2D grid is the wrong state space. A river‑segment graph:

* collapses the state dimension by an order of magnitude,
* makes dispersal a sparse graph operation,
* aligns the model with vole ecology *better*, not worse.

This isn’t “optimisation”; it’s fixing a representational mismatch that also improves identifiability for the real case.

---

### 5) Micro-optimisations only if needed (and only after the preflight)

If you still need more after the above, then:

* compile the inner update loop (Rcpp) **only for the dominant stage**,
* precompute ramp lookup tables for predator pressure,
* avoid per-year object allocation/copies (preallocate and reuse),
* use low-compression fast serialization (`qs` with low preset) for transient outputs.

But don’t start here. Start with the big structural wins above.

---

## Bottom line decisions

1. **Proceed to 0.3.x now** on toy/medium.
2. **Add exactly one new gate before 0.3.5:** GB‑scale single‑replicate realistic preflight with true peak RSS measurement, and freeze budgets based on that.
3. If that gate says “too slow”, the first fix is **synthetic observation as cell‑year counts** + **I/O discipline** — not more fiddling with the sim loop.

And yes: this is completely consistent with the project’s funding logic — tractability first, then pattern‑oriented calibration at scale (LHS/ABC/HPC). 



## PI_2 response

You’ve done the right thing, and Codex delivered the right kind of fix. **0.2.x did what it was supposed to do: it turned “mysterious 8‑hour smoke tests” into a measured, budgeted system with guardrails.**

### Q1 — Do we extend 0.2.x further, or proceed to 0.3.x now?

**Proceed to 0.3.x now** on **toy/medium only**. Do *not* keep polishing 0.2.x unless you hit a concrete new bottleneck that blocks 0.3.x.

But: **add one extra gate before WP‑0.3.5** (full GB synthetic). Not a whole new 0.2.x milestone line—just a hard gate that uses what you already built.

#### Why I’m comfortable moving on

The profiling data basically screams: *the simulator is not your problem.*

From `stage_profile_smoke.csv` on the 25×25 smoke profile:

* Core sim inner loop (`sim_total`) is ~**0.059 s**.
* The big costs are:

  * `observation_tx_map` ~**1.779 s**
  * `save_outputs` ~**1.818 s**
* Setup stages are also non-trivial (~0.65–0.75 s each), but not the “8 hours” kind of non-trivial.

And the optimisation benchmark shows the old TX mapping path really was a pig:

* `exdyn_tx_map_fast` drops mapping from **7.07 s → 1.67 s** (~**4.2×**). That’s a real win.

So: **the slow run was overwhelmingly pipeline choice + observation mapping + I/O**, not the TX-only simulator. Codex’s diagnosis is consistent with the measurements.

#### The one thing I don’t fully trust yet: memory numbers

Your scaling RSS plot is basically flat at ~3.5 MB, which is… not a real peak RSS measurement. That means the *time* story is solid, but the *memory* story is still a bit hand-wavy.

So I would **not** add another 0.2.x line, but I *would* add a **single hard gate** that requires a reliable peak RSS measurement before full GB.

### The gate I’d add before WP‑0.3.5 (full GB)

Before Codex is allowed to run WP‑0.3.5 on the British Isles grid:

1. **Run one medium “realistic-mode” synthetic build** (includes observation generation + TX estimator) under `/usr/bin/time -v` (or equivalent), record *peak RSS* and wall time in the canonical manifest.
2. **Prove we are not saving explosive objects** in canonical artefacts:

   * No per-cell-year “counts tables” saved for full runs unless explicitly requested.
   * No full 3‑D `N[x,y,t]` arrays written to disk in canonical output.
3. **Budget sanity:** declare the projected runtime for the full GB run *before* starting it (based on measured medium + cell/year scaling). If the projection is ugly, you don’t run—period.

That’s it. With that gate, **0.3.x can proceed safely**.

This is also exactly in the spirit of the funded science: **model complexity is explicitly framed as a trade-off between tractability and realism**, and the whole DP hinges on running *hundreds of thousands* of models via LHS + pattern-oriented screening + ABC—so predictability and tractability are not “engineering polish”, they’re core scientific feasibility. 

---

## Q2 — Clever ways to speed up / reduce memory on full runs (vs “canonical constraint”)

Some cost is unavoidable because you’re doing **(cells × years × draws)**. But you are **not** at the hard limit of physics here. There are still a few high-leverage moves that matter specifically for *your* architecture.

### The biggest speed/memory wins (the ones that actually change your life)

#### 1) Stop saving “quietly huge” objects

Your stage profile shows `save_outputs` is as expensive as the observation mapping even on toy runs. That’s a classic sign you’re writing more than you think.

For full GB runs, the canonical outputs should be:

* TX matrices (integer-ish), summary vectors (small), and diagnostics plots/tables.
* **Not** cell×year tables, not raw PO events, not intermediate big frames.

**Rule:** if it’s O(cells×years), it doesn’t get written by default.

This alone often turns “hours” into “tens of minutes” because disk churn kills throughput.

#### 2) Ensure “realistic mode” does *not* mean “re-observe every candidate draw”

This is the silent killer.

Realistic synthetic should be:

* generate synthetic observations **once per replicate**, estimate **TX_obs once**
* then inference compares **TX_sim** to **TX_obs** across candidate draws

If any pipeline step is simulating observation and re-running the TX estimator **inside** the ABC loop, you’ve basically invented a computational black hole.

So: **observation belongs outside the candidate-draw loop**.

#### 3) Stream the observation generator (avoid 3‑D arrays and PO point clouds)

Even if you only observe once per replicate, you can still cut memory and time by making the synthetic observation step streaming:

* While simulating forward, generate the **cell-year counts / index** directly on the fly.
* Feed that into the TX estimator.
* Never store `N[,,t]`.
* Never store millions of PO points.

You still get estimator-bias realism (because you still run the same first-passage TX estimator), but you don’t pay the 3‑D / point-cloud tax.

This is the cleanest “keep scientific meaning, drop computational burden” move available.

#### 4) Early-abort in candidate simulations (cheap rejection)

In screens/ABC, most draws are junk. So don’t fully simulate junk draws.

Add cheap “fail-fast” checks:

* If by year T the simulated extirpation coverage is still below a minimum threshold → abort.
* If lag has already gone negative beyond tolerance early → abort.
* If predation is clearly subcritical → abort (you already have a version of this idea; push it harder).

This reduces **average** runtime per draw, which is what matters.

---

### Medium wins (helpful, but not the main story)

#### 5) Parallelise across draws/particles (not within a draw)

Within-draw parallelism in R is usually a mess for memory and overhead. The clean scaling is:

* parallelise over parameter draws / replicates / particles,
* keep per-draw memory small (TX-only),
* avoid writing large per-draw artefacts.

This is where `targets` shines if the output payload per draw is tiny.

#### 6) Move the remaining tight loops to compiled code *only if needed*

You’ve already got a big win from replacing a dplyr-nested path with matrix/tabulate + a simple loop.

If full GB still hurts after the “don’t save huge things” rule, then the next likely hotspot is the **per-cell first-passage logic**. That is very R-loop-ish. Converting just that part to C++ can give another 2–10×, but only do it if profiling proves it’s now dominant.

---

### Big swing, bigger change (high payoff, but it’s a model-architecture decision)

#### 7) For riparian systems: stop pretending it’s a 2‑D raster

If the ecological unit is a river network, the fastest model is often:

* represent the system as a **graph of segments/nodes**
* dispersal is along edges (sparse), not FFT over a big matrix full of zeros
* predation front propagates along the graph

That can cut compute by an order of magnitude **and** makes the biology more faithful.

But it’s a real architecture choice, not a “speed tweak”.

---

## My bottom-line answers

1. **Proceed to 0.3.x now** on toy/medium. Don’t extend 0.2.x into a permanent hobby.
   **Add one hard gate before WP‑0.3.5:** reliable peak RSS measurement + “no explosive outputs” + runtime projection.

2. Full GB runtime is **not** an unavoidable curse of large grids. The main avoidable killers are:

   * saving O(cells×years) objects by default,
   * accidentally invoking observation/estimation inside candidate loops,
   * non-streaming observation generation.
     Fix those and full GB becomes “predictably expensive” rather than “mysteriously glacial.”

If you want the PI-style slogan to stick above the monitor:
**“TX-only inside the loop. Observation outside the loop. And don’t write giant crap to disk unless you’re being paid per byte.”**
