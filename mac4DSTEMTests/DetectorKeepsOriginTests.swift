//
//  DetectorKeepsOriginTests.swift
//  #348: placing a virtual detector never changes the calibrated origin (py4DSTEM and pyxem keep the two apart); a centre by hand is
//  set on purpose in Prepare and is not a measurement.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class DetectorKeepsOriginTests: XCTestCase {
    /// With nothing measured the origin is the detector's middle, wherever the detector sits (it used to follow the detector).
    func testAnUncalibratedOriginDoesNotFollowTheDetector() {
        let calibration = Calibration()
        let reference = calibration.referenceOrigin(detectorQX: 128, detectorQY: 96)
        XCTAssertEqual(reference.kind, .geometricMiddle)
        XCTAssertEqual(reference.x, 64); XCTAssertEqual(reference.y, 48)
    }

    /// A dark-field detector moved onto a spot leaves the file's recorded centre and its provenance untouched.
    func testMovingTheDetectorLeavesTheFilesCentre() async throws {
        let state = AppState()
        await state.openDemoFixture()
        let before = state.calibrationSession.calibration
        XCTAssertNotNil(before.recordedOriginX, "precondition: the file records a centre")
        var moved = state.aperture
        moved.centerX += 9; moved.centerY -= 7
        state.updateAperture(moved)
        let after = state.calibrationSession.calibration
        XCTAssertEqual(after.recordedOriginX, before.recordedOriginX)
        XCTAssertEqual(after.recordedOriginY, before.recordedOriginY)
        XCTAssertEqual(after.originProvenance, before.originProvenance)
        XCTAssertEqual(after.origin?.fittedX, before.origin?.fittedX)
        XCTAssertFalse(state.canRestoreFittedOrigin)
    }

    /// The manual centre takes the recorded slot while it is in force and leaves it on Restore: a file with fitted maps and no
    /// recorded centre must not keep the hand-set one behind the restored maps.
    func testRestoreLeavesNoManualCentreBehind() {
        let state = AppState()
        state.calibrationSession.calibration.origin = OriginMaps(
            width: 2, height: 2, measuredX: [50, 50, 50, 50], measuredY: [60, 60, 60, 60],
            fittedX: [50, 50, 50, 50], fittedY: [60, 60, 60, 60])
        state.calibrationSession.calibration.originProvenance = .fitted
        state.setManualOrigin(x: 40, y: 41)
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginX, 40)
        state.restoreFittedOrigin()
        XCTAssertNil(state.calibrationSession.calibration.recordedOriginX)
        XCTAssertNil(state.calibrationSession.calibration.recordedOriginY)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .fitted)
    }

    /// A fit after a centre by hand clears it from the recorded slot: a later crop that drops the fitted maps must not bring the
    /// hand-set point back as a recorded, measured centre. Mutation: no `clearManualCentre` in the fit - the 30 stays, red.
    func testAFitReplacesTheManualCentreEverywhere() async throws {
        let state = AppState()
        await state.openDemoFixture()
        state.setManualOrigin(x: 30, y: 30)
        XCTAssertEqual(state.calibrationSession.calibration.recordedOriginX, 30)
        await state.calibrateOrigin()
        let calibration = state.calibrationSession.calibration
        XCTAssertEqual(calibration.originProvenance, .fitted, state.statusText)
        XCTAssertNotEqual(calibration.recordedOriginX, 30)
        XCTAssertNotEqual(calibration.recordedOriginY, 30)
    }

    /// A centre by hand is not a measurement: reciprocal calibration refuses it, in its own words.
    func testAManualCentreIsRefusedForReciprocalMetrology() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        let descriptor = try XCTUnwrap(state.descriptor)
        state.setManualOrigin(x: 30, y: 30)
        let refusal = try XCTUnwrap(state.gates.reciprocalMetrologyRefusal(for: state.calibrationSession.calibration,
                                                                           descriptor: descriptor))
        XCTAssertTrue(refusal.contains("set by hand"), refusal)
    }
}
