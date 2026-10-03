import Foundation
import Testing
@testable import ClaudeSessionsCore

struct TransitionDetectorTests {
    private func snapshot(_ sessions: LiveSession..., skipped: [SkippedEntry] = []) -> RegistrySnapshot {
        RegistrySnapshot(sessions: sessions, skipped: skipped)
    }

    private func unreadable(_ pid: Int32) -> SkippedEntry {
        SkippedEntry(file: URL(fileURLWithPath: "/tmp/sessions/\(pid).json"), reason: .unreadable)
    }

    @Test func newlySeenSessionAppears() {
        let events = TransitionDetector().update(snapshot(live()))
        guard case .appeared(let s) = events.first, events.count == 1 else { Issue.record("expected appeared"); return }
        #expect(s.sessionId == "a")
    }

    @Test func unchangedPhaseProducesNothing() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live(phase: .running)))
        #expect(d.update(snapshot(live(phase: .running, at: 2_000))).isEmpty)
    }

    @Test func phaseChangeReportsRealTurnDuration() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live(phase: .running, at: 1_000)))
        let events = d.update(snapshot(live(phase: .idle, at: 6_000)))
        guard case let .phaseChanged(_, from, to, held) = events.first, events.count == 1 else { Issue.record("expected change"); return }
        #expect(from == .running)
        #expect(to == .idle)
        #expect(held == .seconds(5))
    }

    @Test func departedSessionEnds() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live()))
        let events = d.update(snapshot())
        guard case .ended(let s) = events.first, events.count == 1 else { Issue.record("expected ended"); return }
        #expect(s.sessionId == "a")
    }

    @Test func fileCaughtMidWriteDoesNotEnd() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live(pid: 100)))
        #expect(d.update(snapshot(skipped: [unreadable(100)])).isEmpty)
        #expect(d.known.map(\.sessionId) == ["a"])
    }

    @Test func unreadableFileOnlyHoldsOverItsOwnSession() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live(id: "a", pid: 100), live(id: "b", pid: 200)))
        let events = d.update(snapshot(skipped: [unreadable(200)]))
        guard case .ended(let s) = events.first, events.count == 1 else { Issue.record("expected ended"); return }
        #expect(s.sessionId == "a")
        #expect(d.known.map(\.sessionId) == ["b"])
    }

    @Test func heldOverSessionEndsOnceReadableAgain() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live(pid: 100)))
        _ = d.update(snapshot(skipped: [unreadable(100)]))
        let events = d.update(snapshot())
        guard case .ended = events.first, events.count == 1 else { Issue.record("expected ended"); return }
        #expect(d.known.isEmpty)
    }

    @Test func unknownPhaseIsNotATransitionAndKeepsWhatWeKnew() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live(phase: .running, at: 1_000)))
        #expect(d.update(snapshot(live(phase: .unknown, at: 2_000))).isEmpty)
        let events = d.update(snapshot(live(phase: .idle, at: 9_000)))
        guard case let .phaseChanged(_, from, _, held) = events.first, events.count == 1 else { Issue.record("expected change"); return }
        #expect(from == .running)
        #expect(held == .seconds(8))
    }

    @Test func sessionsAreTrackedIndependently() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live(id: "a", pid: 1), live(id: "b", pid: 2)))
        let events = d.update(snapshot(live(id: "a", pid: 1, phase: .waiting, at: 3_000),
                                       live(id: "b", pid: 2, phase: .running, at: 3_000)))
        guard case let .phaseChanged(s, _, to, _) = events.first, events.count == 1 else { Issue.record("expected change"); return }
        #expect(s.sessionId == "a")
        #expect(to == .waiting)
    }

    @Test func sessionThatComesBackIsFreshAppearance() {
        let d = TransitionDetector()
        _ = d.update(snapshot(live()))
        _ = d.update(snapshot())
        guard case .appeared = d.update(snapshot(live())).first else { Issue.record("expected appeared"); return }
    }

    @Test func fallsBackToWallClockWithoutRegistryTimestamp() {
        nonisolated(unsafe) var now: Int64 = 10_000
        let d = TransitionDetector(clock: { now })
        _ = d.update(snapshot(live(phase: .running, at: 0)))
        now = 13_000
        let events = d.update(snapshot(live(phase: .idle, at: 0)))
        guard case let .phaseChanged(_, _, _, held) = events.first else { Issue.record("expected change"); return }
        #expect(held == .seconds(3))
    }
}
