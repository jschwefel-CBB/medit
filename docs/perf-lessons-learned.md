# Lessons learned: the 2026-07-14 perf pass

Companion to `perf-findings.md` (which has the numbers). This is what to carry
forward — into the next perf pass on medit, or any similar main-thread-hitch chase.

## 1. Fixing the visible symptom can unmask a bigger hidden one
The highlighter fix (tokenize off the main thread) was the obvious, documented,
highest-ranked cause. Fixing it dropped `tab.viewDidLoad.total` on a large file from
"window frozen ~1.7 s" to 580 ms — progress, but not the 10–20 ms an empty tab gets.
The bracket colorizer had been costing 365 ms on the main thread the entire time; it
was invisible in the original profile because the 1.6 s tokenize dwarfed it in the
same trace. **Re-profile after every fix, not just at the start and the end** — the
ranking of "what's slow" changes as you remove the biggest offender, and the next
offender is often a total surprise (nobody suspected bracket coloring here).

## 2. "Negligible" is a property of the test case, not the code
`perf-findings.md`'s first pass measured `bracketColorizer` at 0.01–0.03 ms and
called it negligible — true, but only because that measurement ran on an **empty**
tab. The same code costs 365 ms on a 470 KB file. A cost that scales with document
size will look free on every quick smoke check and then blow up in production.
**When profiling, always include at least one large/adversarial input**, not just
the fast path you happen to be sitting on. This class of doc has a name here already
— the AutoPilot "auto-preview blind spot" postmortems are the same shape: a happy
path that hides the real behavior.

## 3. A background fix isn't done until you check for the failure modes concurrency adds
Both fixes (highlighter, bracket colorizer) followed the same shape: snapshot text →
work on a background queue → apply on main. Getting that shape right required three
separate protections, not one:
- **Generation counter** — a slow background pass must not clobber a newer one that
  finished first (classic out-of-order completion).
- **Snapshot-vs-live equality check** — the text can change *while* the background
  pass is running; applying an attribute run computed from stale text onto current
  text misaligns colors silently (no crash, just wrong-looking output — the kind of
  bug that's easy to ship because it "mostly" looks right).
- **In-flight coalescing** — without it, multiple callers requesting the same result
  before the first one lands each kick off a redundant background pass. This was
  caught mid-pass: an early "fix" only deduplicated the *apply* step via generation
  counting, but still ran the expensive scan three times. The fix wasn't done until
  the scan itself ran once.

If you're moving synchronous work to a background queue anywhere in this codebase,
budget for all three, not just "dispatch async and hope."

## 4. Equivalence tests catch real bugs that unit tests on the old code never could
Rewriting `updateCaretEmphasis` to read from a cached hit list (instead of walking
the live text) is a different algorithm claiming to produce the same answer as the
original `BracketMatcher`. Ordinary unit tests on a handful of hand-picked strings
would not have caught a subtle divergence. The test that mattered was
`testColorizerHitWalkAgreesWithMatcherAtEveryCaret`: it runs the OLD algorithm and
the NEW algorithm side by side, over every caret position, across a set of
adversarial strings (nesting, mismatches, multibyte). **When a perf fix changes how
a result is computed rather than just where, write the equivalence test before
trusting the fix** — it's the only test shape that actually verifies "still correct,
just faster."

## 5. Multibyte content was untested before this pass, and the perf work exposed it
`BracketMatcher.enclosingPair` had zero multibyte test coverage before this pass.
The perf rewrite (materializing offsets differently) forced the question of whether
character-offset and UTF-16-offset math actually agreed on emoji/CJK content, and
the answer wasn't obviously yes. This is a general pattern worth remembering: **perf
work that touches offset/indexing math is exactly the kind of change that silently
breaks Unicode correctness**, because ASCII test strings never exercise the
divergence between character offsets and UTF-16 offsets. Any future touch to this
code (or similar string-offset code elsewhere in medit) should default to including
a multibyte case, not add it defensively after the fact.

## 6. The stale-index compiler noise is real and needs to be triaged past, not chased
Through this pass, SourceKit repeatedly reported "Cannot find X in scope" for symbols
(`PerfLog`, `PreviewWebView`, freshly added methods) that were correctly defined and
that `swift build` compiled without complaint. This is an incremental-index lag, not
a real error — but it looks identical to a real error in the tool output. **The
tie-breaker is always `swift build`/`swift test`, never the live diagnostics list.**
Don't spend time hand-checking brace balance or re-reading a file because SourceKit
flagged it; run the actual compiler and trust that.

## 7. The discipline that made this pass trustworthy (keep doing this)
- Every fix was measured with the *same* file, same probes, before and after — not
  a vibe, a number.
- `--profile` is a launch flag, off by default, zero cost in normal use — so the
  instrumentation could stay in the codebase permanently instead of being ripped out
  after one pass. The next perf investigation starts from working tooling, not zero.
- Every fix was verified against the full unit suite AND an end-to-end AutoPilot
  plan (`preview-edit-ops-noop.json`) before being called done — a perf change that
  silently breaks a feature is not a perf win.
- Trade-offs were written down honestly rather than hidden (colors arriving late on
  huge files is a visible behavior change; the tokenize wall-time went *up* on the
  background queue even though it stopped blocking anything). A fix doc that only
  reports the win it wants you to see isn't trustworthy the next time you read it.
