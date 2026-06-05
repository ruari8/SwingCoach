# Swing Intelligence / Swing Coach Competitive Research

Research date: 2026-06-05

## Executive Summary

Swing Intelligence's "Swing Coach - Golf" is a direct competitor to this project. It is not simply a Me and My Golf app feature. The App Store seller is Swing Intelligence, Inc., while Me and My Golf appears to be a marketing/content partner or distribution channel.

The strongest product insight is that their core loop is not "upload a swing and wait for a report." Their loop is "record continuously, analyze each swing quickly on-device, and speak feedback without requiring the golfer to walk back to the phone." That is a materially better practice workflow than a conventional video-analysis queue.

Their technical positioning strongly suggests an on-device-first iOS implementation:

- iOS only.
- iOS 18.0 minimum.
- Recommended minimum iPhone 14 Pro / Pro Max.
- Android paused because of high-FPS capture and AI/ML processing constraints.
- Offline day-to-day operation claimed.
- Privacy policy still allows videos to be sent to servers.

Implication for SwingCoach: the MVP can still be backend-first for speed of iteration, but the long-term competitive bar is local capture plus near-real-time feedback. The product should avoid over-investing in a slow upload/report workflow as the primary practice experience.

## Confirmed Facts

- App name: "Swing Coach - Golf".
- App Store seller: Swing Intelligence, Inc.
- App category: Sports.
- Current US App Store metadata observed via Apple's lookup API:
  - Version: 2.0.3.
  - Current version release date: 2026-05-26.
  - Initial release date: 2025-03-08.
  - Minimum OS: iOS 18.0.
  - Size: 238,743,552 bytes, about 238.7 MB.
  - User rating count: 1,797.
  - Average rating: about 4.86.
- App Store in-app purchases observed on the public App Store page:
  - Monthly: $14.99.
  - Annual: $119.99.
- The public App Store description claims:
  - instant voice feedback after each swing;
  - work areas including swing plane, hand path, hip depth, spine stability, flying elbow, shoulder plane;
  - tracking club head and body with only the phone;
  - no markers/dots/special equipment.
- Swing Intelligence's own site claims:
  - proprietary AI models;
  - patent-pending algorithms;
  - over 7M swings analyzed;
  - founded by Briscoe Rodgers and Jason Squatrito in 2024;
  - Android development paused after work on it since 2025;
  - day-to-day use can be fully offline, with Wi-Fi needed for install/update and periodic subscription refresh.
- Me and My Golf's Swing Coach landing page was published 2026-04-17 and modified 2026-04-30. Its copy says "Swing Coach AI analyses your golf swing instantly" and is "Available on iPhone only."

## Product Positioning

Their wedge is practice feedback, not historical library management. They are selling the feeling of a coach watching every rep.

Public copy emphasizes:

- "Swing, listen, improve."
- AI voice feedback after each swing.
- No need to walk back to the phone.
- Personalized coach instruction from known coaches.
- Indoor/outdoor use, with or without a ball.

This maps very closely to the most valuable user problem: golfers struggle to connect a swing feel to the actual movement change. Voice feedback after each rep is a strong UX choice because it preserves practice flow.

## Coach / Content Strategy

They appear to be building around named coach personalities and "Coach IQ." Public website video embeds include instruction clips with topics such as:

- "Swing Plane Takeaway Inside"
- "Too Much Shaft Lean at Impact"
- "Head Too Far Back in Backswing"
- "Chest Too Forward at Impact"
- "How to Improve Your Swing Plane"
- "AI Golf Swing Instruction App"
- "Practice with Feedback"
- "Working On Take Away"

Observed inference: their defensibility is not only CV. They are pairing detected faults with pre-recorded coach content, then making that feel personalized. This lets them ship useful fixes without needing a fully generative golf pedagogy engine.

For SwingCoach, this suggests two viable paths:

1. Build a small, high-quality drill/feel corpus mapped to detections.
2. Later partner with coaches or creators once detection quality is credible.

## Offline / Backend Assessment

The app can plausibly work offline without meaning "no backend exists."

Evidence:

- Their Android page claims no active cellular connection is needed for swing feedback, and Wi-Fi is only needed for install/update and periodic subscription refresh.
- Their privacy policy says videos are stored on the phone and "may" be sent to servers.
- App privacy disclosures include identifiers, usage data, diagnostics, and body data.

Technical inference:

- Core swing detection and scoring likely run on-device.
- Account/subscription, analytics, crash reporting, model/content updates, and maybe selected video upload likely use backend services.
- The 238 MB app size is consistent with bundled ML models plus UI/content assets. It is not enough to include a large library of full-resolution coaching videos, so video content is likely streamed/cached, heavily compressed, or fetched selectively.

## How They May Render Club-Path Dots

The yellow club-path dots in screenshots do not require analyzing every 240 FPS frame with a heavyweight model.

Likely implementation pattern:

1. Capture high-FPS video, probably 120 FPS based on their Android comments and iPhone hardware targeting.
2. Detect the swing segment and key events.
3. Run fast pose/body/club tracking on selected frames or downsampled frames.
4. Track the club head/shaft across frames using a lighter temporal tracker between heavier detections.
5. Smooth/interpolate the resulting path.
6. Render sparse dots at sampled positions, not necessarily every original video frame.

Possible technical components:

- Native AVFoundation high-frame-rate capture.
- Core ML / Vision / Metal on-device inference.
- Custom club-head detector or shaft detector.
- Optical flow or point tracking between detector frames.
- Temporal smoothing and confidence gating.
- Event-specific overlays after the swing, rather than real-time overlay during capture.

Important distinction: the screenshot can look "real-time" even if the annotated path is produced after the swing is recorded, as long as feedback arrives within a few seconds.

## Android Signal

A developer account on Reddit said Android work hit a wall around high-FPS video capture and AI/ML processing, calling those foundational requirements. They also said Android was temporarily paused because they could not prioritize it without performance/accuracy confidence.

This is a useful validation point: the hardest mobile constraint is not only ML accuracy; it is the capture + inference + battery/thermal/runtime pipeline.

For SwingCoach, the iOS-first strategy is justified. Android parity should not drive early architecture unless the app is explicitly server-first.

## Public Repo / Code Footprint

No public Swing Intelligence app repository was found from:

- exact web search for `swingintelligence.com`;
- exact web search for `Swing Intelligence` and `Swing Coach`;
- GitHub CLI search for `swingintelligence.com`;
- GitHub repository search for related terms.

The broad GitHub search returns many unrelated "golf" repositories and no clear product source repo. Treat the app source as private.

The marketing website is a single-page React bundle that exposes:

- Lovable-style build artifacts;
- Supabase library code in the site bundle;
- a Supabase URL in the site bundle;
- YouTube embeds for marketing/coaching videos.

This only tells us about the marketing site implementation. It does not prove the iOS app backend stack.

## Competitive Implications For SwingCoach

1. Name risk is real.
   - "Swing Coach" is already active in-market, highly rated, and app-store-visible.
   - Defer renaming until TestFlight is reasonable, but do not build brand assets around the current name.

2. Backend-first MVP is still acceptable, but it is not the endgame.
   - It lets us iterate on metrics, annotations, drills, and teaching logic faster.
   - The competitive target should be on-device or hybrid fast feedback.

3. The most important UX metric is time-to-feedback.
   - A polished report after 60 seconds is less practice-useful than a simple voice cue after 2-5 seconds.

4. Club tracking is a priority, not a nice-to-have.
   - Their public differentiation includes club-head and body tracking.
   - Our `detect_shaft("club shaft")` and confidence-first outputs should remain core.

5. Drill mapping can start small.
   - A curated corpus tied to the most reliable detections is more valuable than a broad but weak library.

6. Confidence and uncertainty should be a product feature.
   - Swing Intelligence's terms disclaim analysis accuracy. We should be more explicit and user-trust-oriented by surfacing low-confidence reads rather than hiding them.

## Free-Trial Teardown Checklist

When testing the app, capture the following:

- Does it require account login before analysis?
- Does it work in airplane mode after subscription validation?
- Does it download coach videos on demand or ship them in-app?
- How fast is feedback from impact/end-of-swing to voice cue?
- Does it record continuously or only one swing per button press?
- Does it save every swing or only selected clips?
- What frame rates are selectable/used?
- Does iOS camera metadata show 120 FPS or 240 FPS?
- Does it process face-on and down-the-line differently?
- Which faults are available in custom mode?
- Which faults are "voice feedback only" versus visually annotated?
- Are club-path dots shown during recording or only in replay?
- Does annotation quality degrade indoors, dim lighting, busy backgrounds, no ball, or practice swings?
- Does it handle left-handed golfers cleanly?
- Does it allow import of old videos, or only in-app capture?
- Does it upload anything when Wi-Fi is restored after offline use?

## Sources

- App Store listing: https://apps.apple.com/us/app/swing-coach-golf/id6739074629
- Apple iTunes lookup API: https://itunes.apple.com/lookup?id=6739074629&country=us
- Swing Intelligence homepage: https://swingintelligence.com/
- Swing Intelligence about page: https://swingintelligence.com/about
- Swing Intelligence Android page: https://swingintelligence.com/android
- Swing Intelligence privacy policy: https://swingintelligence.com/privacy-policy
- Me and My Golf Swing Coach page: https://meandmygolf.com/swing-coach/
- Reddit discussion with apparent developer comments: https://www.reddit.com/r/GolfSwing/comments/1mnydn8/swing_coach_app_is_phenomenal/
