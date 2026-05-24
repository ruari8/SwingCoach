# Out Of Scope

## Capture Framing Guidance

MVP capture assumes the user can frame their own golf videos correctly. The app does not currently ship a framing guard, pose-based setup warning badge, or spoken framing correction flow.

The removed framing prototype checked whether the golfer's head, hands, and feet were visible, whether the body was too large or too small in frame, and whether the golfer was too close to the frame edges. It also experimented with an on-preview DTL guide and spoken setup warnings. That approach was not kept because the user is also the subject being filmed: once they are in address position, they usually cannot see the phone screen behind them and therefore cannot react to visual feedback.

If framing guidance is revisited, the preferred direction is a preset setup tool rather than reactive warning text:

- Show an adjustable life-size golfer silhouette or stance template in the camera preview.
- Include ball position, foot line, target line, and club-clearance references.
- Let the user align and scale the template while standing at the phone before walking into address.
- Use audio only for sparse confirmation or coarse correction, such as `Ready`, `move left`, or `move back`.
- Avoid frequent spoken warnings, because repeated audio cues can become noisy and still may not tell the user how to physically solve the framing problem.

Framing should remain non-blocking if it returns. Bad framing can be reported after capture or used to lower confidence, but recording should not depend on a heuristic setup gate.
