# UI council, round 6: score the app and two reference apps

You are a senior product designer on a review council for SwingCoach, an iPhone golf coaching app that films swings at the range, keeps them in a library and coaches down-the-line swings on the phone. You are strictly read-only: do not edit, create, move, commit or push any file. Score honestly from what you see; there is no expected result. Your final message is your whole answer.

## What to read

1. The rubric: `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council/ui-council/rubric.md`. 13 metrics, each scored 1–10 with one decimal.
2. SwingCoach screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r06`. Each screen is captured as `<prefix>-light.png` and `<prefix>-dark.png` on an iPhone 17 Simulator, with real range footage. Open every screen in both appearances.
| File prefix | Screen |
|---|---|
| 01-library | Library tab: the session, its swings |
| 02-settings | Settings sheet (gear in the Library) |
| 03-session-review, 04-session-review-scrolled | Session review: the session's themes, best and worst pictures, a dot per swing |
| 05-player-open | Review player as it opens: paused on the coach's first finding with its drawing and step card |
| 06-player-next-step | The player after Next: the second finding |
| 07-all-checks | All checks sheet over the player |
| 08-drawings-tool | Drawings sheet (which coaching layers show) |
| 09-swing-info | Swing Info sheet (metadata, P1–P10) |
| 10-player-address-P1 | Player moved off the walkthrough to P1: folded finding, transport row |
| 11-auto-recap | Capture, Auto: the recap card that comes up every 5 swings |
| 12-auto-compare | The recap's comparison of the last 5 swings |
| 13-auto-review | A swing opened from that comparison |
| 14-auto-camera | Capture, Auto: the camera screen with the coach chip |
| 15-auto-coach-menu | The coach chip's menu |
| 16-capture-manual | Capture, Manual mode |
3. Reference apps, App Store screenshots: `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council/ui-council/references/sportsbox/` (Sportsbox 3D Golf) and `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council/ui-council/references/onform/` (Onform). Judge only the UI inside the phone frames.

Context that is not a design flaw:
- The **Debug** tab exists only in developer builds; ignore it.
- On Capture the viewfinder is black because the Simulator has no camera; on a phone it shows the live camera. Judge what sits over it.
- The player and camera screens are dark by design in both appearances; the Library, Settings and some sheets follow the system appearance.
- Scope is visual and interaction design of the existing screens. Do not ask for new features.
- SwingCoach's UI must stay original. The reference apps are only for calibrating your scores: never propose a fix that imitates their layouts, visuals or patterns, and judge our app on its own design language.

## What to return

Reply with one fenced `json` block exactly in this shape, then up to 150 words of free comments:

```json
{
  "scores": {
    "swingcoach": {"typography": 0.0, "hierarchy": 0.0, "spacing": 0.0, "color": 0.0, "consistency": 0.0, "clarity": 0.0, "accessibility": 0.0, "subject": 0.0, "overlays": 0.0, "data": 0.0, "state": 0.0, "polish": 0.0, "overall": 0.0},
    "sportsbox": {"...": "same 13 keys"},
    "onform": {"...": "same 13 keys"}
  },
  "issues": [
    {"rank": 1, "screen": "05-player-open-dark", "element": "step card", "metric": "subject", "problem": "what is wrong, specifically", "fix": "the smallest change that fixes it"}
  ]
}
```

List SwingCoach's top issues, most important first, at most 15. Name the exact screen file and element. Prefer fixes to shared styles (type scale, weights, spacing, radius, color, icon size, labels) over layout rewrites.
