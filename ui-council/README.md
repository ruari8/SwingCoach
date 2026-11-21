# Screenshot tour

A repeatable screenshot run of the app's main screens on real range footage, made for a design review of the UI in November 2026 and kept so later UI work can be compared like for like.

| File | What it is |
| --- | --- |
| [capture.sh](capture.sh) | One iPhone 17 Simulator, a pinned status bar, the seeded range session, and `UICouncilTourUITests` in light and dark: 16 screens each |
| [tools/build_seed.py](tools/build_seed.py) | Builds the seed library from a range session and its coaching harness output |
| [tools/baseline-fixture.patch](tools/baseline-fixture.patch) | Lets `capture.sh --ref` run the tour on a commit older than the tour |

The seed and the screenshots show the owner's own range footage, so they are not in this public repository. Point `UI_COUNCIL_SEED` at a seed built with `build_seed.py` and write screenshots outside the checkout.

```bash
ui-council/capture.sh <out-dir>                 # this checkout
ui-council/capture.sh <out-dir> --ref d75f001   # an older commit
```

The tour is in the `OnRequest` test plan and skipped by the default one.
