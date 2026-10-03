import Foundation
import Testing
@testable import ClaudeSessionCore

struct NotificationPolicyTests {
    private let policy = NotificationPolicy()

    private func change(_ from: Phase, _ to: Phase, held: Duration = .seconds(10)) -> SessionEvent {
        .phaseChanged(live(phase: .idle), from: from, to: to, timeInPreviousPhase: held)
    }

    @Test func needingTheUserAlwaysNotifies() {
        #expect(policy.shouldNotify(change(.running, .waiting)))
        #expect(policy.shouldNotify(change(.idle, .waiting)))
    }

    @Test func finishingRealTurnNotifies() {
        #expect(policy.shouldNotify(change(.running, .idle, held: .seconds(30))))
    }

    @Test func tooShortTurnDoesNotNotify() {
        #expect(!policy.shouldNotify(change(.running, .idle, held: .milliseconds(400))))
        #expect(policy.shouldNotify(change(.running, .idle, held: .seconds(2))))
    }

    @Test func answeringPromptYourselfDoesNotNotify() {
        #expect(!policy.shouldNotify(change(.waiting, .idle)))
    }

    @Test func startingWorkDoesNotNotify() {
        #expect(!policy.shouldNotify(change(.idle, .running)))
        #expect(!policy.shouldNotify(change(.waiting, .running)))
    }

    @Test func appearingAndEndingAreNotInterruptions() {
        #expect(!policy.shouldNotify(.appeared(live())))
        #expect(!policy.shouldNotify(.ended(live())))
    }

    @Test func unknownOnEitherSideNeverNotifies() {
        #expect(!policy.shouldNotify(change(.unknown, .waiting)))
        #expect(!policy.shouldNotify(change(.running, .unknown)))
    }

    @Test func idleThresholdIsConfigurable() {
        #expect(NotificationPolicy(minRunBeforeIdle: .zero).shouldNotify(change(.running, .idle, held: .milliseconds(1))))
    }
}

struct NotificationComposerTests {
    private func event(_ to: Phase, waitingFor: String? = nil, held: Duration = .seconds(90)) -> SessionEvent {
        .phaseChanged(live(phase: to, name: "Update Billing Library", waitingFor: waitingFor, focusUrl: "warp://session/x"),
                      from: .running, to: to, timeInPreviousPhase: held)
    }

    @Test func sessionNameIsTitle() {
        #expect(NotificationComposer.compose(event(.idle))?.title == "Update Billing Library")
    }

    @Test func eachWaitingForReadsAsSomethingToActOn() {
        func body(_ w: String?) -> String? { NotificationComposer.compose(event(.waiting, waitingFor: w))?.body }
        #expect(body("input needed") == "Needs your input")
        #expect(body("dialog open") == "Waiting on a dialog")
        #expect(body("sandbox request") == "Wants sandbox access")
        #expect(body("goal proposal") == "Waiting on a goal proposal")
        #expect(body("worker request") == "Waiting on a worker request")
        #expect(body("quantum entanglement") == "Waiting: quantum entanglement")
        #expect(body(nil) == "Needs your attention")
    }

    @Test func finishingReportsHowLongItTook() {
        #expect(NotificationComposer.compose(event(.idle, held: .seconds(4 * 60 + 12)))?.body == "Finished after 4m 12s")
        #expect(NotificationComposer.compose(event(.idle, held: .seconds(45)))?.body == "Finished after 45s")
        #expect(NotificationComposer.compose(event(.idle, held: .seconds(63 * 60)))?.body == "Finished after 1h 3m")
    }

    @Test func carriesSessionIdAndFocusUrl() {
        let n = NotificationComposer.compose(event(.idle))
        #expect(n?.sessionId == "a")
        #expect(n?.focusUrl == "warp://session/x")
    }

    @Test func onlyPhaseChangesCompose() {
        #expect(NotificationComposer.compose(.appeared(live())) == nil)
    }
}

struct SessionMonitorTests {
    private struct Scripted: SnapshotSource {
        let snapshots: [RegistrySnapshot]
        let index = Counter()
        func read() -> RegistrySnapshot {
            defer { index.value += 1 }
            return snapshots[min(index.value, snapshots.count - 1)]
        }
    }
    private final class Counter { var value = 0 }

    @Test func notifiesOnlyWhatPolicyAllows() {
        let monitor = SessionMonitor(source: Scripted(snapshots: [
            RegistrySnapshot(sessions: [live(phase: .running, at: 1_000)]),
            RegistrySnapshot(sessions: [live(phase: .waiting, at: 2_000, waitingFor: "input needed")]),
            RegistrySnapshot(sessions: [live(phase: .running, at: 3_000)]),
            RegistrySnapshot(sessions: [live(phase: .idle, at: 3_500)]),
        ]))
        #expect(monitor.tick().notifications.isEmpty)               // appeared
        #expect(monitor.tick().notifications.map(\.body) == ["Needs your input"])
        #expect(monitor.tick().notifications.isEmpty)               // back to running
        #expect(monitor.tick().notifications.isEmpty)               // 0.5s turn is too short
    }

    @Test func exposesKnownSessions() {
        let monitor = SessionMonitor(source: Scripted(snapshots: [RegistrySnapshot(sessions: [live(id: "x")])]))
        #expect(monitor.tick().sessions.map(\.sessionId) == ["x"])
    }
}
