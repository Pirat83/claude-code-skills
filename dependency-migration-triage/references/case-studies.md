# Case studies: what this skill exists to catch (and not overclaim)

Eight real findings, each illustrating a different failure mode the phases in SKILL.md are
designed to catch. Read before Phase 4 if a result feels uncertain, or as a sanity check on
your own findings before writing them up. Cases 5 and 8 cite the real PRs the skill's regression
evals replay, so a run that reads this file already knows those answers: treat such evals as
regression checks, not as tests of the general wording.

The first four come from one Python repo (`pybroker`), because that is where this skill was
built; 5-8 come from later runs across npm, GitHub Actions and Python/conda repos. Cases 4-8 are
all misses made while this skill was being followed. The examples have ecosystems; **the lessons
do not.** A silently-ignored Helm values key is case study 2 with different nouns. A chart or
image whose default changed underneath you is case study 1. A policy engine flagging a rule that
is unreachable in context is case study 3. Read them as claims about evidence, not about
packaging.

## 1. Conceptual/behavioral change with no signature change (mypy)

Two separate mypy version bumps broke this codebase's typecheck step with **zero config
changes on this repo's side** — proof that a version bump can change what "correct" code
looks like without touching any function signature this repo calls.

- Commit `5d65b0c` ("Fix typecheck broken by mypy 2.0 ndarray narrowing"): mypy 2.0 reworked
  how it narrows `numpy.ndarray` generic types. Code that had type-checked cleanly for years
  suddenly didn't, because mypy got *more precise* about what it could prove — not because
  any pybroker code changed.
- Commit `bfd8172` ("Fix mypy 2.3 errors and pin mypy 2.3 release"): a second, unrelated
  tightening — this time around how `@njit`-wrapped function return types
  (`np.floating` vs `float`) flow through `Callable[...]` parameter matching.

The lesson: when triaging a type-checker, linter, or any tool whose whole job is "decide
whether code is correct," don't just check for removed functions or renamed parameters —
ask whether the tool's *definition of correct* changed. Running the new version against the
real codebase (Phase 4) is the only way to find this; changelog-reading alone under-reports
it unless the changelog explicitly calls out "stricter narrowing" or similar, and even then
you won't know which lines it touches without running it.

Related, sharper finding from the same investigation: running `mypy --show-error-codes
--warn-unused-ignores` (a flag this repo's own CI does *not* use) against the exact
CI-pinned environment found that **18 of 32 existing `# type: ignore` suppressions were
already dead** under the currently-pinned version — including two added by `bfd8172` itself,
already stale again by the time they were checked. The generalizable lesson: don't just ask
"does this pass," ask "would anything today catch drift going forward" — and if the answer
is no (as it was here, since `--warn-unused-ignores` wasn't enabled), that's a finding in its
own right, independent of the specific bump being triaged.

## 2. Coverage illusion (akshare)

`src/pybroker/ext/data.py`'s AKShare TX-fallback path renamed an incoming `"amount"` column
to `"volume"` unconditionally. As of akshare 1.18.74, the TX API started returning its own
real `"volume"` column, with `"amount"` repurposed as a distinct RMB figure — so the
unconditional rename produced **two columns both named `"volume"`** after the bump, silently
corrupting the output instead of raising.

The existing test for this exact code path (`test_query_when_em_unavailable_then_uses_tx_fallback`,
before the fix in PR #250) passed at 100% line coverage on every run, before and after the
akshare bump — because it mocked the fallback API's return value using the **old** schema.
The line executed every time; the mock never reflected the new reality, so the test could
never have caught this regression no matter how many times it ran.

The lesson (Phase 5): "this line has test coverage" and "a test here would catch a real
regression" are different claims. The only way to tell them apart is to read what shape of
data the test actually constructs and ask whether that shape still matches what the
dependency's new version actually returns — not whether the assertion count is nonzero.

Fixed in PR https://github.com/edtechre/pybroker/pull/250 — only remap the legacy `amount`
alias when a real `volume` column isn't already present, plus two tests pinning both the old
and new schema, each asserting `volume` appears exactly once (the literal thing that broke).

## 3. Overclaiming a lint finding (ruff)

`ruff`'s `B905` rule flagged `eval.py:1146` — `zip(("99.9%", "99%", "95%", "90%"), *metrics)`
— for missing `strict=True`, which in general risks silently truncating data on a length
mismatch. Read in isolation, that looks like a real bug and was initially reported as one.

Tracing the actual dataflow showed it wasn't: `metrics` is a `DrawdownMetrics` NamedTuple
containing two `DrawdownConfs` NamedTuples, both **hardcoded to exactly 4 fields** by their
type definitions. The three operands being zipped are therefore *statically guaranteed*
equal length — there is no code path where they could ever differ, so `B905`'s "silent
truncation" concern doesn't apply here no matter what future code changes happen elsewhere.

The lesson: a static/lint tool's finding describes a *pattern*, not a proof about this
specific code. Before writing "X is a bug" in a report, trace where the actual values come
from and confirm the failure mode the tool warns about is actually reachable. Getting this
wrong in the other direction — dismissing a real finding as "probably fine" without tracing
it — is just as much a failure of this phase; the discipline is doing the trace either way,
not defaulting to belief or disbelief.

## 4. Verifying only one direction (nbsphinx) — a miss this skill made against itself

During this skill's own calibration, one run triaged an `nbsphinx` bump that had zero test or
CI coverage (docs-tooling-only, nothing in the pipeline builds the docs). Correctly following
Phase 5's instinct to become the coverage, it built the actual documentation with the *new*
nbsphinx version, watched it succeed with zero warnings, and concluded "safe, nothing to
fix" — a clean, confident verdict, arrived at by actually executing something rather than
just reading a changelog.

It was still wrong. A parallel run (no skill at all, just told to check the same PR) happened
to build the docs with *both* the old and new versions to compare, and found the old version
**crashes outright** against the currently-installed Sphinx (`sphinx.util.status_iterator`
was removed from Sphinx; old nbsphinx still called it). The bump wasn't a no-op — it was the
only thing keeping the documentation buildable at all. The skill-following run never
discovered this because it only ever asked "does the new version work," never "was the old
version already broken."

The lesson (why Phase 5 now says to check both directions): confirming the new version works
answers half the question. It catches regressions but is blind to the mirror case — a bump
that's actually a load-bearing fix — because "safe, nothing to fix" and "safe, and here's
what it silently fixed" look identical from the forward-only check alone. Whenever you're
about to spend effort empirically verifying a version (because coverage is absent and
changelog-reading alone can't settle it), that same effort spent on the *old* version too is
usually cheap relative to what it can reveal, and skipping it means half of what an empirical
check could tell you never gets asked.

## 5. A green gate that checked nothing (TypeScript 7) — a miss made while following this skill

A TypeScript 6 → 7 bump in an npm repo was triaged and cleared, in part because the `arch`
(dependency-cruiser) and `dead` (dead-code) gates passed in CI against 7.0.2, and because the
lockfile showed no tool declaring a `typescript` peer dependency. It was merged.

Later, dependency-cruiser turned out to have been reporting `0 modules, 0 dependencies cruised`
under TypeScript 7 — and exiting 0. Every `arch` run since the merge had checked nothing. The
correction in the follow-up PR said it plainly: "the earlier triage cleared it partly because
`arch` passed in CI. That was wrong; passing with zero inputs is not a pass." TypeScript was
reverted to 6.x with a bot rule holding it there.

Two things went wrong, and both generalise:
- **A gate's exit code says nothing about how much it looked at.** The fix is cheap: read the
  gate's input count on the base branch and the bump branch. A later triage in the same repo did
  exactly that ("148 modules and 490 dependencies cruised on both") and settled the question in
  one command.
- **"No declared peer" is not "compatible".** dependency-cruiser declares TypeScript support in
  its own `supportedTranspilers` field of `package.json` (`npm view dependency-cruiser
  supportedTranspilers`), not in `peerDependencies` or `peerDependenciesMeta`, so `npm ls` and
  the lockfile show nothing and reading peer ranges finds nothing. The rule is general: read the
  consumer tool's **own** declared support wherever it lives (peer ranges, a `supportedX` field,
  its docs, its runtime warning). The revert's hold also needs a precise unblock condition
  (TypeScript >=7.1 AND dependency-cruiser >=18.8; 7.0.x never works): see bots.md, Holds.

This is case study 2 one level up: there, a test executed the line with stale data; here, a gate
executed with no data at all. Both are green, both are worthless for this bump, and only reading
what the check actually consumed tells you so.

## 6. A merged pin that never took effect (Helm v4 through nested workflow pins)

A lab's CI renders charts with `helm`, installed by a composite action that a reusable workflow
pins by SHA, which every consumer repo pins by digest. A bot PR bumped the Helm pin to v4.3.0;
it was triaged, merged, and the nineteen digest PRs that followed to the consumers all went
green.

Reading the consumers' job logs showed `helm version --short` printing `v3.21.4`. The inner
action pins were stale, so neither the Helm bump nor its predecessor had ever reached a
consumer's CI. "A green mark alone would not have shown this." The fix was a separate PR moving
the inner pins.

The lesson (Phase 9): when a dependency reaches its consumers through several layers of pins,
"merged" and "green downstream" are both true while the old version keeps running. The only
evidence that the bump took effect is the tool reporting its own version where it is consumed.
The same shape appears whenever one artifact is pinned inside another: a base image inside an
image, a chart inside an umbrella chart, a lockfile inside a container build.

## 7. "Freeze it" overruled, and "safe to merge" on a dependency nothing used (psycopg2, dash-extensions)

Two verdicts from one Python/conda repo, both technically defensible and both wrong for the user.

**psycopg2.** The bump was test-only, and a conda dry run showed it would drag libpq, libgcc and
openssl forward onto a production-adjacent host. The triage recommended closing the PR and
pinning psycopg2 permanently. The user rejected that: "if it is an dependency it needs to be
managed and updated". The settled outcome was a third option the triage never offered: remove
psycopg2 entirely and convert the twelve differential tests that used it into golden-value
tests.

**dash-extensions.** Phase 3 found zero usage, yet the verdict was "safe to merge". The user had
to ask "so does the codebase even use the dash-extensions?" before removal was on the table.
Removing it then exposed that six modules imported `pydantic`, which had only ever been installed
because dash-extensions pulled it in, and `conda remove` tried to delete pydantic along with it.

The lessons (Phase 3 and 4):
- **A freeze is a cost, not a resting state.** A pinned dependency still has to be maintained; it
  just stops telling you when it needs it. Whenever a freeze or close is on the table, put its
  long-run cost next to it, and put *removing the dependency* next to that.
- **Zero usage is a verdict, not a footnote.** "Unused — remove, don't bump" leads the report.
- **Removal needs its own check.** What a package provided transitively is usage too. Run the
  suite with the departing modules blocked before the removal ships.

## 8. Production followed the merge; the developer's machine did not (unternehmen-walkuere)

Nine bot PRs were triaged and rolled out on 2026-11-01. CI and the image install `uv.lock`
fresh, so both followed every bump. The shared main-checkout `.venv` did not: Python 3.12.14
against `.python-version` 3.12.15, redis 5.2.1 (lock 8.1.0), quantstats 0.0.62 (0.0.86),
dotenv 1.2.2 (1.2.4), and `ipython` plus 14 dependencies still installed after the lock dropped
them.

The drift was known during triage: wheels were tested on a scratch `PYTHONPATH`
(`uv pip install --target <scratch> --no-deps`) precisely to avoid touching the shared venv.
But no phase said to bring the venv back in line afterwards, so nothing did. The user had to
ask "update my local environment".

The lesson (Phase 9): merge closes the repo side; the local side is its own step. Run it once
after the last merge of a batch, interpreter first, then an exact sync, and prove it with
`uv sync --frozen --check` ("Would make no changes") plus per-package versions against the
lock. A green CI says the pins solve, not that this machine matches. The procedure is in
`local-env.md`; note it compares against the *current* lock (a later commit, #105, re-added
ipykernel, so "the dropped package is gone" is only true against the lock of that date).
