# Market Thesis

SwingCoach is an AI golf coach in a pocket: a golfer props up an iPhone, records a swing, and gets video-backed feedback without needing a launch monitor, force plates, motion-capture lab, or a second camera.

The product is built around the widest realistic capture setup in golf: one consumer phone camera. That constraint matters. Most golfers will not own TPI-style equipment, will not calibrate multi-camera rigs, and will not set up a technical capture environment before practice. The app must make the best possible use of the phone they already have.

## Market Gap

Golf instruction has a long-standing gap between casual video analysis and high-end biomechanical systems.

At the high end, systems used by elite coaches and biomechanics labs can measure body motion, club delivery, pressure, force, and sequence with much higher precision. They are powerful, but they are expensive, hardware-heavy, and not accessible to most golfers during normal practice.

At the consumer end, golfers already record swings on phones, but the feedback loop is weak. A raw video can show obvious issues, but the golfer still needs enough knowledge to interpret what matters, what caused it, and what to work on next. Current consumer tooling often stops at storage, manual drawing, basic overlays, or lightweight automated comments.

The opportunity is to make phone video analytically useful by applying modern AI vision, temporal tracking, annotation, and coaching language to a golf-specific pipeline.

## Why Now

Computer vision models are improving quickly across segmentation, tracking, pose estimation, monocular depth, video understanding, and multimodal reasoning. These capabilities are not yet broadly packaged into a consumer golf coaching workflow.

The gap is not only model intelligence. The hard part is extraction and orchestration:

- get a useful swing recording from a single iPhone camera
- identify the camera view and video quality
- detect swing events
- track the body, hands, club, shaft, and ball where visible
- calculate view-appropriate metrics
- render annotations that prove the feedback visually
- turn the evidence into simple coaching language
- recommend drills that match the observed pattern

General AI systems may have strong visual reasoning, but golf feedback requires a domain pipeline. SwingCoach exists to connect modern AI capability to the specific structure of a golf swing.

## Product Thesis

The core product is not a generic chatbot for golf. The core product is a video analysis pipeline that produces coachable evidence.

The backend should treat video annotation and metrics calculation as the foundation. Coach voice and drills are downstream products of those two systems.

The user experience should feel like:

1. Record a swing with an iPhone.
2. See the exact frames and overlays that matter.
3. Understand the likely movement pattern.
4. Get one or two focused things to try.
5. Compare future swings against the same evidence.

## Hardware Constraint

SwingCoach should optimize for a single iPhone because that is the only setup most golfers can reliably use.

This means the product cannot honestly claim the same measurement quality as force plates, optical motion capture, high-speed multi-camera systems, or full launch-monitor data. The app should instead maximize what is visible from phone video and become better as phone cameras, on-device sensors, and AI vision models improve.

The long-term bet is that the hardware limitation shrinks over time. Better phone cameras, depth estimation, video foundation models, and 3D reconstruction models should make more swing information recoverable from ordinary footage. SwingCoach should be architected so newer models can be swapped into the pipeline without rewriting the product.

## How SwingCoach Wins

SwingCoach can win by blending three things that are rarely combined well:

1. Golf-specific coaching structure
2. SOTA AI and computer vision models
3. A consumer capture workflow that works with one iPhone

The product should not chase lab-grade measurement claims before the hardware supports them. It should become the best possible single-camera golf coach: useful, visual, fast, understandable, and constantly improving as AI vision improves.

The market opening is that SOTA vision is moving faster than consumer golf products are absorbing it. SwingCoach should keep its finger on that pulse and turn new model capability into practical golf feedback before slower incumbents do.
