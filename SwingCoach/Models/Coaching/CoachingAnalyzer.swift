//
//  CoachingAnalyzer.swift
//  SwingCoach
//
//  Scores one swing: evidence in, a level and a drawing for each metric out.
//  Pure geometry, no model: the same evidence always gives the same report.
//
//  Every drawing has the same three parts where they apply: where the golfer
//  was at address (white), where good players end up (the shaded zone), and
//  where this swing is (coloured by its level).
//

import Foundation

nonisolated enum CoachingAnalyzer {
    /// Results under this confidence are left out rather than shown.
    static let minimumConfidence = 0.3
    /// A swing with fewer judged measurements than this (of 17) is not
    /// judged at all.
    static let minimumJudgedMetrics = 8

    /// `lens` is the swing's recorded lens data, when it has any: it adds
    /// the camera's distance to the placement check.
    static func analyze(_ evidence: SwingCoachingEvidence, positions: SwingPositions? = nil,
                        lens: CameraLensData? = nil) -> SwingCoachingReport? {
        guard let geometry = CoachingSwingGeometry(evidence: evidence) else { return nil }
        let builder = Builder(geometry: geometry, positions: positions)
        // The club checks are judged only from a camera known to be on the
        // hand line at hand height. Unsure is not a pass.
        let placement = CoachingCameraPlacement(geometry: geometry, lens: lens)
        var metrics: [CoachingMetricResult] = []
        var unavailable: [CoachingMetricID] = []
        let live = evidence.fromLiveCopies == true
        for definition in CoachingMetricDefinition.all {
            // Left for the saved clip: see `needsClip`.
            if live, definition.needsClip {
                unavailable.append(definition.id)
            } else if var result = builder.measure(definition), result.confidence >= minimumConfidence,
               definition.isBelievable(result.value) {
                if definition.dependsOnCamera, definition.scored, !placement.passes { result.cameraHold = true }
                metrics.append(result)
            } else {
                unavailable.append(definition.id)
            }
        }
        let short = (geometry.handsAboveShoulderAtTop ?? 1) < 0
        let moved = (geometry.footShiftAtTop ?? 0) > SwingCoachingReport.steadyFootShift
        // "Good swing" has to mean most of the swing was seen and in zone,
        // not that little of it could be measured. A held club check was
        // still seen.
        let judged = metrics.filter { $0.definition.scored }.count
        let unclear = !geometry.positionsLookRight || judged < minimumJudgedMetrics
        return SwingCoachingReport(rightHanded: geometry.isRightHanded, swingLength: short ? .short : .full,
                                   cameraMoved: moved, positionsUnclear: unclear, fromLiveCopies: live,
                                   cameraPlacement: placement, metrics: metrics, unavailable: unavailable)
    }

    private struct Builder {
        let geometry: CoachingSwingGeometry
        let positions: SwingPositions?

        private var scale: Double { geometry.bodyScale }
        private var facing: Double { geometry.facing }

        private func percent(_ lengthInHeightUnits: Double) -> Double {
            lengthInHeightUnits / scale * 100
        }

        /// A share of body scale back in height units.
        private func length(_ percent: Double) -> Double {
            percent / 100 * scale
        }

        private func point(_ vector: CoachingVector) -> CoachingPoint {
            geometry.point(vector)
        }

        // MARK: - Shapes

        private func line(_ role: CoachingDrawing.Role, _ a: CoachingVector, _ b: CoachingVector, dashed: Bool = false) -> CoachingDrawing {
            CoachingDrawing(kind: .line, role: role, points: [point(a), point(b)], dashed: dashed)
        }

        private func dot(_ role: CoachingDrawing.Role, _ at: CoachingVector) -> CoachingDrawing {
            CoachingDrawing(kind: .dot, role: role, points: [point(at)])
        }

        private func area(_ corners: [CoachingVector]) -> CoachingDrawing {
            CoachingDrawing(kind: .area, role: .zone, points: corners.map(point))
        }

        /// The zone as an upright strip: `zone` is measured toward the ball
        /// from `origin`, between heights `top` and `bottom`.
        private func strip(_ zone: ClosedRange<Double>, from origin: Double, top: Double, bottom: Double) -> CoachingDrawing {
            let near = origin + length(zone.lowerBound) * facing
            let far = origin + length(zone.upperBound) * facing
            return area([CoachingVector(near, top), CoachingVector(far, top), CoachingVector(far, bottom), CoachingVector(near, bottom)])
        }

        /// The zone as a fan of directions from `pivot`. `direction` gives
        /// the point at `reach` along an angle in degrees.
        private func fan(
            _ angles: ClosedRange<Double>,
            from pivot: CoachingVector,
            reach: Double,
            direction: (Double) -> CoachingVector
        ) -> CoachingDrawing {
            let steps = 6
            let rim = (0...steps).map { step -> CoachingVector in
                let angle = angles.lowerBound + (angles.upperBound - angles.lowerBound) * Double(step) / Double(steps)
                return pivot + reach * direction(angle)
            }
            return area([pivot] + rim)
        }

        /// How sure the position model was of this position's frame.
        private func timing(_ position: Int) -> Double {
            guard let found = positions?.positions.first(where: { $0.number == position }) else { return 1 }
            return found.confidence >= 0.5 ? 1 : 0.6
        }

        private func result(
            _ definition: CoachingMetricDefinition,
            value: Double,
            confidence: Double,
            drawings: [CoachingDrawing]
        ) -> CoachingMetricResult {
            CoachingMetricResult(
                id: definition.id,
                position: definition.position,
                clipTime: geometry.evidence.frame(definition.position)?.clipTime ?? 0,
                value: value,
                level: definition.level(for: value),
                confidence: min(1, confidence) * timing(definition.position),
                drawings: drawings
            )
        }

        func measure(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            switch definition.id {
            case .setupPosture: setupPosture(definition)
            case .setupHands: setupHands(definition)
            case .takeawayClub: takeawayClub(definition)
            case .planeTakeaway, .planeDelivery: plane(definition)
            case .shaftHalfwayBack, .shaftHalfwayDown: shaftPointing(definition)
            case .leadArmTop: leadArmTop(definition)
            case .handDepthTop: handDepthTop(definition)
            case .hipDepthTop, .hipDepthImpact: hipDepth(definition)
            case .headHeightTop, .headHeightImpact: head(definition, vertical: true)
            case .headDepthTop, .headDepthImpact: head(definition, vertical: false)
            case .postureTop, .postureImpact: postureChange(definition)
            case .transition: transition(definition)
            case .handsHeightImpact: handsAtImpact(definition, vertical: true)
            case .handsOutImpact: handsAtImpact(definition, vertical: false)
            case .trailKneeImpact: trailKnee(definition)
            }
        }

        // MARK: - Setup

        /// Forward bend: the hips-to-neck line's angle from vertical, leaning
        /// toward the ball.
        private func bend(at position: Int) -> (angle: Double, hips: CoachingVector, neck: CoachingVector)? {
            guard let hips = geometry.hipCentre(at: position), let neck = geometry.shoulderCentre(at: position) else {
                return nil
            }
            let forward = (neck.x - hips.x) * facing
            let up = hips.y - neck.y
            guard up > 0.02 * scale else { return nil }
            return (atan2(forward, up) * 180 / .pi, hips, neck)
        }

        /// Unit vector leaning `degrees` from vertical toward the ball.
        private func leaning(_ degrees: Double) -> CoachingVector {
            let angle = degrees * .pi / 180
            return CoachingVector(facing * sin(angle), -cos(angle))
        }

        private func setupPosture(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let bend = bend(at: 1) else { return nil }
            let reach = bend.hips.distance(to: bend.neck)
            return result(definition, value: bend.angle, confidence: 0.8, drawings: [
                fan(definition.zone, from: bend.hips, reach: reach, direction: leaning),
                line(.reference, bend.hips, CoachingVector(bend.hips.x, bend.neck.y), dashed: true),
                line(.subject, bend.hips, bend.neck),
            ])
        }

        private func setupHands(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let shaft = geometry.shaft(at: 1),
                  let shoulder = geometry.joint(geometry.trailSide.shoulder, at: 1)
            else { return nil }
            let value = percent((shaft.grip.x - shoulder.x) * facing)
            let bottom = shaft.grip.y + 0.04 * scale
            return result(definition, value: value, confidence: shaft.confidence, drawings: [
                strip(definition.zone, from: shoulder.x, top: shaft.grip.y - 0.04 * scale, bottom: bottom),
                line(.reference, shoulder, CoachingVector(shoulder.x, bottom), dashed: true),
                dot(.subject, shaft.grip),
            ])
        }

        // MARK: - Club

        private func takeawayClub(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let shaft = geometry.shaft(at: 2), shaft.headDetected else { return nil }
            let value = percent((shaft.head.x - shaft.grip.x) * facing)
            // The zone is measured across, from the grip toward the ball:
            // drawn as a band that runs down past the club head, so a head
            // in zone sits inside it wherever the club hangs.
            let top = min(shaft.grip.y - 0.1 * scale, shaft.head.y - 0.06 * scale)
            let bottom = max(shaft.grip.y + 0.14 * scale, shaft.head.y + 0.06 * scale)
            return result(definition, value: value, confidence: shaft.confidence, drawings: [
                strip(definition.zone, from: shaft.grip.x, top: top, bottom: bottom),
                line(.reference, CoachingVector(shaft.grip.x, top), CoachingVector(shaft.grip.x, bottom), dashed: true),
                line(.subject, shaft.grip, shaft.head),
                dot(.subject, shaft.head),
            ])
        }

        /// The address plane: from the soled clubhead through a point just
        /// up the trail forearm from the wrist.
        private func addressPlane() -> (head: CoachingVector, through: CoachingVector, confidence: Double)? {
            guard let shaft = geometry.shaft(at: 1) else { return nil }
            let elbow = geometry.joint(geometry.trailSide.elbow, at: 1, minimumConfidence: 0.15)
            if let wrist = geometry.joint(geometry.trailSide.wrist, at: 1), let elbow {
                return (shaft.head, 0.8 * wrist + 0.2 * elbow, shaft.confidence)
            }
            // Wrists are usually hidden at address: step from the grip end
            // toward the elbow instead.
            guard let elbow else { return nil }
            return (shaft.head, shaft.grip + 0.3 * (elbow - shaft.grip), shaft.confidence * 0.85)
        }

        /// A guide, not a judgement: good players' clubheads sit anywhere
        /// within a third of body scale of this line.
        private func plane(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let plane = addressPlane(), let shaft = geometry.shaft(at: definition.position), shaft.headDetected else {
                return nil
            }
            let distance = CoachingSwingGeometry.signedDistance(of: shaft.head, fromLine: plane.head, plane.through)
            let above = CoachingSwingGeometry.signedDistance(
                of: plane.head + CoachingVector(0, -1), fromLine: plane.head, plane.through
            )
            let value = percent(distance * (above >= 0 ? 1 : -1))
            let end = plane.head + 1.9 * (plane.through - plane.head)
            return result(definition, value: value, confidence: min(plane.confidence, shaft.confidence), drawings: [
                line(.reference, plane.head, end),
                dot(.reference, shaft.head),
            ])
        }

        /// Height of the ground the ball sits on.
        private var ground: (ball: CoachingVector, confidence: Double)? {
            if let ball = geometry.ball { return (ball, 1) }
            return geometry.shaft(at: 1).map { ($0.head, 0.7) }
        }

        private func shaftPointing(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let shaft = geometry.shaft(at: definition.position), let ground,
                  // The club has to be pointing up for its butt to point at the ground.
                  shaft.grip.y - shaft.head.y > 0.25 * shaft.length,
                  let landing = CoachingSwingGeometry.x(ofLine: shaft.head, shaft.grip, atY: ground.ball.y)
            else { return nil }
            let value = max(-150, min(150, percent((landing - ground.ball.x) * facing)))
            let landingPoint = CoachingVector(ground.ball.x + length(value) * facing, ground.ball.y)
            // The zone on the ground, fanned back up to the hands: a shaft
            // inside the fan points where good players' shafts point.
            let near = CoachingVector(ground.ball.x + length(definition.zone.lowerBound) * facing, ground.ball.y)
            let far = CoachingVector(ground.ball.x + length(definition.zone.upperBound) * facing, ground.ball.y)
            return result(definition, value: value, confidence: min(shaft.confidence, ground.confidence), drawings: [
                area([shaft.grip, near, far]),
                line(.subject, shaft.head, landingPoint),
                dot(.reference, ground.ball),
            ])
        }

        private func transition(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let back = geometry.shaft(at: 3), let down = geometry.shaft(at: 5),
                  back.grip.y - back.head.y > 0.25 * back.length,
                  down.grip.y - down.head.y > 0.25 * down.length
            else { return nil }
            // Both angles are measured the same way round, so a shaft
            // leaning the other side of upright reads as far off, as drawn.
            let backShaft = back.head - back.grip
            let backAngle = geometry.angleFromBack(backShaft)
            let downAngle = geometry.angleFromBack(down.head - down.grip)
            // The backswing shaft redrawn from the downswing hands, so the
            // two angles sit on the same pivot.
            let allowed = (backAngle + definition.zone.lowerBound)...(backAngle + definition.zone.upperBound)
            return result(definition, value: downAngle - backAngle, confidence: min(back.confidence, down.confidence), drawings: [
                fan(allowed, from: down.grip, reach: down.length, direction: geometry.direction(atAngleFromBack:)),
                line(.reference, down.grip, down.grip + backShaft, dashed: true),
                line(.subject, down.grip, down.head),
            ])
        }

        // MARK: - Top

        private func leadArmTop(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let leadShoulder = geometry.joint(geometry.leadSide.shoulder, at: 4),
                  let trailShoulder = geometry.joint(geometry.trailSide.shoulder, at: 4),
                  let hands = geometry.wrists(at: 4),
                  leadShoulder.distance(to: trailShoulder) > 0.06 * scale
            else { return nil }
            let shoulderLine = trailShoulder - leadShoulder
            let shoulders = geometry.angleFromBack(shoulderLine)
            let arm = geometry.angleFromBack(hands - leadShoulder)
            let armLength = leadShoulder.distance(to: hands)
            let extended = leadShoulder + shoulderLine * (armLength * 1.15 / shoulderLine.length)
            let allowed = (shoulders + definition.zone.lowerBound)...(shoulders + definition.zone.upperBound)
            return result(definition, value: arm - shoulders, confidence: 0.7, drawings: [
                fan(allowed, from: leadShoulder, reach: armLength, direction: geometry.direction(atAngleFromBack:)),
                line(.reference, leadShoulder, extended, dashed: true),
                line(.subject, leadShoulder, hands),
            ])
        }

        private func handDepthTop(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let hands = geometry.wrists(at: 4), let heel = geometry.joint(geometry.trailSide.ankle, at: 1) else {
                return nil
            }
            let value = percent((hands.x - heel.x) * facing)
            let top = hands.y - 0.08 * scale
            return result(definition, value: value, confidence: 0.7, drawings: [
                strip(definition.zone, from: heel.x, top: top, bottom: hands.y + 0.08 * scale),
                line(.reference, heel, CoachingVector(heel.x, top), dashed: true),
                dot(.subject, hands),
            ])
        }

        // MARK: - Body against address

        private func hipDepth(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let address = geometry.backside(at: 1), let now = geometry.backside(at: definition.position) else {
                return nil
            }
            let value = percent((now.x - address.x) * facing)
            let top = address.y - 0.3 * scale
            let bottom = address.y + 0.3 * scale
            return result(definition, value: value, confidence: 0.85, drawings: [
                strip(definition.zone, from: address.x, top: top, bottom: bottom),
                line(.reference, CoachingVector(address.x, top), CoachingVector(address.x, bottom)),
                line(.subject, CoachingVector(address.x, now.y), now),
                dot(.subject, now),
            ])
        }

        private func trailKnee(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            let knee = geometry.trailSide.knee
            guard let address = geometry.joint(knee, at: 1), let now = geometry.joint(knee, at: definition.position) else {
                return nil
            }
            let value = percent((now.x - address.x) * facing)
            let top = address.y - 0.12 * scale
            let bottom = address.y + 0.12 * scale
            return result(definition, value: value, confidence: 0.7, drawings: [
                strip(definition.zone, from: address.x, top: top, bottom: bottom),
                line(.reference, CoachingVector(address.x, top), CoachingVector(address.x, bottom), dashed: true),
                line(.subject, CoachingVector(address.x, now.y), now),
                dot(.subject, now),
            ])
        }

        /// Head height and head depth are one picture: the address head, the
        /// box good players' heads end up in, and the head now.
        private func head(_ definition: CoachingMetricDefinition, vertical: Bool) -> CoachingMetricResult? {
            guard let head = geometry.head(at: definition.position, sharedWith: 1) else { return nil }
            let value = vertical
                ? percent(head.there.y - head.here.y)
                : percent((head.here.x - head.there.x) * facing)
            let atTop = definition.position == 4
            let height = CoachingMetricDefinition.definition(atTop ? .headHeightTop : .headHeightImpact).zone
            let depth = CoachingMetricDefinition.definition(atTop ? .headDepthTop : .headDepthImpact).zone
            let radius = headRingRadius(head, at: definition.position)
            return result(definition, value: value, confidence: 0.8, drawings: [
                // Up is positive for the metric and negative on screen.
                strip(depth, from: head.there.x, top: head.there.y - length(height.upperBound),
                      bottom: head.there.y - length(height.lowerBound)),
                CoachingDrawing(kind: .circle, role: .reference, points: [point(head.there)], size: radius),
                CoachingDrawing(kind: .circle, role: .subject, points: [point(head.here)], size: radius, dashed: true),
                dot(.subject, head.here),
            ])
        }

        /// The head rings' radius, in height units: the head's size from the
        /// pose (face centre to neck, in both frames), so the ring takes in
        /// the whole head on a golfer bent over the ball, not only the face.
        /// Without a neck, a fixed share of body scale. The centre, and so the
        /// reading, is unchanged.
        private func headRingRadius(_ head: (here: CoachingVector, there: CoachingVector), at position: Int) -> Double {
            let sizes = [(head.here, position), (head.there, 1)].compactMap { centre, position in
                geometry.joint(.neck, at: position).map { centre.distance(to: $0) }
            }
            guard !sizes.isEmpty else { return 0.13 * scale }
            let size = 0.85 * sizes.reduce(0, +) / Double(sizes.count)
            return min(max(size, 0.11 * scale), 0.16 * scale)
        }

        private func postureChange(_ definition: CoachingMetricDefinition) -> CoachingMetricResult? {
            guard let address = bend(at: 1), let now = bend(at: definition.position) else { return nil }
            let reach = now.hips.distance(to: now.neck)
            let allowed = (address.angle + definition.zone.lowerBound)...(address.angle + definition.zone.upperBound)
            return result(definition, value: now.angle - address.angle, confidence: 0.75, drawings: [
                fan(allowed, from: now.hips, reach: reach, direction: leaning),
                // The address line redrawn from the current hips.
                line(.reference, now.hips, now.hips + (address.neck - address.hips), dashed: true),
                line(.subject, now.hips, now.neck),
            ])
        }

        /// Hands height and hands out are one picture, like the head.
        private func handsAtImpact(_ definition: CoachingMetricDefinition, vertical: Bool) -> CoachingMetricResult? {
            guard let address = geometry.shaft(at: 1), let impact = geometry.shaft(at: 7) else { return nil }
            let value = vertical
                ? percent(address.grip.y - impact.grip.y)
                : percent((impact.grip.x - address.grip.x) * facing)
            let height = CoachingMetricDefinition.definition(.handsHeightImpact).zone
            let out = CoachingMetricDefinition.definition(.handsOutImpact).zone
            return result(definition, value: value, confidence: min(address.confidence, impact.confidence), drawings: [
                strip(out, from: address.grip.x, top: address.grip.y - length(height.upperBound),
                      bottom: address.grip.y - length(height.lowerBound)),
                dot(.reference, address.grip),
                line(.subject, address.grip, impact.grip),
                dot(.subject, impact.grip),
            ])
        }
    }
}
