import CodexLidKeeperCore
import Darwin
import Foundation

@main
struct CodexLidKeeperSelfTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("hook decodes current payload", testHookDecode),
            ("session end accepts no turn id", testSessionEnd),
            ("turn event requires turn id", testMissingTurnID),
            ("oversized hook input is rejected", testOversizedInput),
            ("parallel turns remain independent", testParallelTurns),
            ("stop delay can be cancelled", testStopDelayContinuation),
            ("renew recreates missed start", testRenewRecreatesLease),
            ("session end is scoped", testSessionEndScope),
            ("hard lease expiry restores safety", testHardLeaseExpiry),
            ("event pipeline separates enqueue from consume", testEventPipeline),
            ("event replay is idempotent", testEventReplay),
            ("malformed event is rejected", testMalformedEvent),
            ("far-future event is rejected", testFutureEvent),
            ("concurrent Hook events do not collide", testConcurrentEvents),
            ("event spool enforces capacity", testEventCapacity),
            ("event spool capacity is strict under concurrency", testConcurrentEventCapacity),
            ("daemon coordinator becomes idle after startup", testDaemonIdle),
            ("daemon coordinator maintains active power", testDaemonMaintenance),
            ("runtime metadata detects concurrent tasks", testRuntimeTaskDetection),
            ("rollout lifecycle closes runtime log delay", testRolloutLifecycleDetection),
            ("runtime tasks drive daemon power and release", testRuntimeDaemonLifecycle),
            ("hook and runtime observations are deduplicated", testTaskDeduplication),
            ("active AC task heartbeats", testActiveAC),
            ("active owned state skips early heartbeat", testHeartbeatCadence),
            ("battery power restores", testBatteryRestore),
            ("battery mode keeps eligible work active", testBatteryAllowed),
            ("battery mode rejects unknown charge", testBatteryChargeUnknown),
            ("low battery restores on AC", testLowBatteryRestore),
            ("unknown power fails safe", testUnknownPower),
            ("power error retains lease", testPowerFailure),
            ("prior disabled state restores to zero", testRestorePriorDisabled),
            ("prior enabled state is preserved", testPreservePriorEnabled),
            ("battery profile does not mask AC prior state", testBatteryProfileIgnored),
            ("battery mode restores both prior profiles", testBatteryModeRestore),
            ("battery mode preserves an existing battery override", testBatteryPriorEnabled),
            ("watchdog follows the recorded power mode", testWatchdogPowerMode),
            ("missing AC profile refuses change", testMissingACProfile),
            ("heartbeat touches ownership", testOwnershipHeartbeat),
            ("expired heartbeat restores", testExpiredHeartbeat),
            ("malformed ownership refuses guess", testMalformedOwnership),
            ("configuration rejects unsafe bounds", testConfigurationValidation),
            ("legacy configuration and state migrate", testLegacyMigration),
            ("log rotates within its size bound", testLogRotation),
            ("state round trip is private", testStateRoundTrip),
            ("concurrent state updates are serialized", testConcurrentUpdates)
        ]

        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures += 1
                fputs("FAIL \(name): \(error)\n", stderr)
            }
        }

        print("\(tests.count - failures)/\(tests.count) self-tests passed")
        Darwin.exit(failures == 0 ? 0 : 1)
    }

    private static func testHookDecode() throws {
        let data = Data(
            """
            {
              "session_id": "thr_123",
              "turn_id": "turn_456",
              "cwd": "/tmp/example",
              "hook_event_name": "UserPromptSubmit",
              "prompt": "private prompt intentionally ignored",
              "model": "example"
            }
            """.utf8
        )
        let input = try HookProcessor.decode(data)
        try expect(input.sessionID == "thr_123")
        try expect(input.turnID == "turn_456")
        try expect(try HookProcessor.action(for: input) == .acquire)
        try expect(HookProcessor.projectName(from: input.cwd) == "example")
    }

    private static func testSessionEnd() throws {
        let input = hookInput(session: "s", turn: nil, event: "SessionEnd")
        try expect(try HookProcessor.action(for: input) == .releaseSession)
    }

    private static func testMissingTurnID() throws {
        let input = hookInput(session: "s", turn: nil, event: "Stop")
        do {
            _ = try HookProcessor.action(for: input)
            throw SelfTestFailure("expected missingTurnID")
        } catch let error as HookProcessingError {
            try expect(error == .missingTurnID("Stop"))
        }
    }

    private static func testOversizedInput() throws {
        let data = Data(repeating: 0x20, count: KeeperConstants.hookInputLimit + 1)
        do {
            _ = try HookProcessor.decode(data)
            throw SelfTestFailure("oversized input was accepted")
        } catch let error as HookProcessingError {
            try expect(error == .inputTooLarge)
        }
    }

    private static func testParallelTurns() throws {
        let configuration = testConfiguration
        let start = testDate
        var state = KeeperState()
        try acquire(session: "s1", turn: "t1", state: &state, now: start)
        try acquire(session: "s2", turn: "t2", state: &state, now: start)
        try expect(state.leases.count == 2)

        try LeaseReducer.apply(
            event: try lifecycleEvent(
                session: "s1",
                turn: "t1",
                event: "Stop",
                now: start.addingTimeInterval(10)
            ),
            to: &state,
            configuration: configuration
        )
        _ = LeaseReducer.pruneExpiredLeases(
            from: &state,
            now: start.addingTimeInterval(31)
        )
        try expect(state.leases.count == 1)
        try expect(state.leases.values.first?.turnID == "t2")
    }

    private static func testStopDelayContinuation() throws {
        var state = KeeperState()
        try acquire(session: "s", turn: "t", state: &state, now: testDate)
        let stopAt = testDate.addingTimeInterval(10)
        try LeaseReducer.apply(
            event: try lifecycleEvent(
                session: "s",
                turn: "t",
                event: "Stop",
                now: stopAt
            ),
            to: &state,
            configuration: testConfiguration
        )
        try expect(
            state.leases.values.first?.releaseAfter
                == stopAt.addingTimeInterval(testConfiguration.releaseDelay)
        )
        try LeaseReducer.apply(
            event: try lifecycleEvent(
                session: "s",
                turn: "t",
                event: "UserPromptSubmit",
                now: stopAt.addingTimeInterval(5)
            ),
            to: &state,
            configuration: testConfiguration
        )
        try expect(state.leases.values.first?.releaseAfter == nil)
    }

    private static func testRenewRecreatesLease() throws {
        var state = KeeperState()
        try LeaseReducer.apply(
            event: try lifecycleEvent(
                session: "s",
                turn: "t",
                event: "PreToolUse",
                now: testDate
            ),
            to: &state,
            configuration: testConfiguration
        )
        try expect(state.leases.count == 1)
    }

    private static func testSessionEndScope() throws {
        var state = KeeperState()
        try acquire(session: "s1", turn: "t1", state: &state, now: testDate)
        try acquire(session: "s2", turn: "t2", state: &state, now: testDate)
        let transition = try LeaseReducer.apply(
            event: try lifecycleEvent(
                session: "s1",
                turn: nil,
                event: "SessionEnd",
                now: testDate
            ),
            to: &state,
            configuration: testConfiguration
        )
        try expect(transition == .sessionReleased(1))
        try expect(state.leases.values.first?.sessionID == "s2")
    }

    private static func testHardLeaseExpiry() throws {
        var state = KeeperState()
        try acquire(session: "s", turn: "t", state: &state, now: testDate)
        let removed = LeaseReducer.pruneExpiredLeases(
            from: &state,
            now: testDate.addingTimeInterval(testConfiguration.leaseDuration + 1)
        )
        try expect(removed == 1)
        try expect(state.leases.isEmpty)
    }

    private static func testEventPipeline() throws {
        let fixture = EventFixture()
        let eventID = UUID()
        _ = try fixture.pipeline.enqueue(
            hookInput(session: "s", turn: "t", event: "UserPromptSubmit"),
            id: eventID,
            occurredAt: testDate
        )
        try expect(try fixture.pipeline.pendingCount() == 1)
        try expect(try fixture.store.read().leases.isEmpty)
        let eventFile = try FileManager.default.contentsOfDirectory(
            at: fixture.directory,
            includingPropertiesForKeys: nil
        ).first { $0.pathExtension == "json" }
        let eventPermissions = try FileManager.default.attributesOfItem(
            atPath: try require(eventFile).path
        )[.posixPermissions] as? NSNumber
        try expect(eventPermissions?.intValue == 0o600)

        let report = try fixture.pipeline.consume(configuration: testConfiguration)
        let state = try fixture.store.read()
        try expect(report.appliedCount == 1)
        try expect(report.remainingCount == 0)
        try expect(state.leases.count == 1)
        try expect(state.hasProcessed(eventID: eventID))
    }

    private static func testEventReplay() throws {
        let fixture = EventFixture()
        let eventID = UUID()
        let input = hookInput(session: "s", turn: "t", event: "UserPromptSubmit")
        _ = try fixture.pipeline.enqueue(input, id: eventID, occurredAt: testDate)
        _ = try fixture.pipeline.consume(configuration: testConfiguration)
        _ = try fixture.pipeline.enqueue(input, id: eventID, occurredAt: testDate)

        let replay = try fixture.pipeline.consume(configuration: testConfiguration)
        try expect(replay.appliedCount == 0)
        try expect(replay.duplicateCount == 1)
        try expect(try fixture.store.read().leases.count == 1)
    }

    private static func testMalformedEvent() throws {
        let fixture = EventFixture()
        _ = try fixture.pipeline.pendingCount()
        let malformed = fixture.directory.appendingPathComponent("bad.json")
        try Data("{bad".utf8).write(to: malformed)

        let report = try fixture.pipeline.consume(configuration: testConfiguration)
        try expect(report.rejectedCount == 1)
        try expect(report.remainingCount == 0)
        try expect(try fixture.store.read().leases.isEmpty)
    }

    private static func testFutureEvent() throws {
        let fixture = EventFixture()
        _ = try fixture.pipeline.enqueue(
            hookInput(session: "s", turn: "t", event: "UserPromptSubmit"),
            occurredAt: Date().addingTimeInterval(3_600)
        )

        let report = try fixture.pipeline.consume(
            configuration: testConfiguration
        )
        try expect(report.rejectedCount == 1)
        try expect(report.appliedCount == 0)
        try expect(try fixture.store.read().leases.isEmpty)
    }

    private static func testConcurrentEvents() throws {
        let fixture = EventFixture()
        let queue = DispatchQueue(label: "events-test", attributes: .concurrent)
        let group = DispatchGroup()
        let errors = LockedErrors()

        for index in 0..<40 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    _ = try fixture.pipeline.enqueue(
                        hookInput(
                            session: "s\(index)",
                            turn: "t\(index)",
                            event: "UserPromptSubmit"
                        ),
                        occurredAt: testDate.addingTimeInterval(Double(index))
                    )
                } catch {
                    errors.append(error)
                }
            }
        }
        group.wait()

        try expect(errors.values.isEmpty)
        try expect(try fixture.pipeline.pendingCount() == 40)
        let report = try fixture.pipeline.consume(configuration: testConfiguration)
        try expect(report.appliedCount == 40)
        try expect(try fixture.store.read().leases.count == 40)
    }

    private static func testEventCapacity() throws {
        let fixture = EventFixture(maximumPendingEventCount: 2)
        _ = try fixture.pipeline.enqueue(
            hookInput(session: "s1", turn: "t1", event: "UserPromptSubmit")
        )
        _ = try fixture.pipeline.enqueue(
            hookInput(session: "s2", turn: "t2", event: "UserPromptSubmit")
        )
        do {
            _ = try fixture.pipeline.enqueue(
                hookInput(session: "s3", turn: "t3", event: "UserPromptSubmit")
            )
            throw SelfTestFailure("full event queue accepted another event")
        } catch HookEventPipelineError.queueFull {
            // Expected: the Hook can fail open without growing the spool.
        }
        try expect(try fixture.pipeline.pendingCount() == 2)
    }

    private static func testConcurrentEventCapacity() throws {
        for round in 0..<8 {
            let fixture = EventFixture(maximumPendingEventCount: 2)
            let queue = DispatchQueue(
                label: "capacity-test-\(round)",
                attributes: .concurrent
            )
            let group = DispatchGroup()
            let successes = LockedCounter()
            let errors = LockedErrors()

            for index in 0..<64 {
                group.enter()
                queue.async {
                    defer { group.leave() }
                    do {
                        _ = try fixture.pipeline.enqueue(
                            hookInput(
                                session: "s\(round)-\(index)",
                                turn: "t\(round)-\(index)",
                                event: "UserPromptSubmit"
                            ),
                            occurredAt: testDate
                        )
                        successes.increment()
                    } catch {
                        errors.append(error)
                    }
                }
            }
            group.wait()

            try expect(successes.value == 2)
            try expect(errors.values.count == 62)
            for error in errors.values {
                guard case HookEventPipelineError.queueFull = error else {
                    throw SelfTestFailure(
                        "capacity race returned unexpected error: \(error)"
                    )
                }
            }
            try expect(try fixture.pipeline.pendingCount() == 2)
        }
    }

    private static func testDaemonIdle() throws {
        let fixture = EventFixture()
        let powerSource = MutablePowerSourceProvider(
            snapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 80)
        )
        let controller = FakePowerController()
        let coordinator = DaemonCoordinator(
            eventDirectory: fixture.directory,
            stateStore: fixture.store,
            powerSourceProvider: powerSource,
            powerController: controller
        )

        let startup = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate
        )
        try expect(startup.reconciliation?.decision == .noTasks)
        try expect(powerSource.readCount == 1)

        let idle = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate.addingTimeInterval(1)
        )
        try expect(idle.reconciliation == nil)
        try expect(powerSource.readCount == 1)

        let longIdle = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate.addingTimeInterval(3_600)
        )
        try expect(longIdle.reconciliation == nil)
        try expect(powerSource.readCount == 1)
    }

    private static func testDaemonMaintenance() throws {
        let fixture = EventFixture()
        let powerSource = MutablePowerSourceProvider(
            snapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 80)
        )
        let controller = FakePowerController()
        let coordinator = DaemonCoordinator(
            eventDirectory: fixture.directory,
            stateStore: fixture.store,
            powerSourceProvider: powerSource,
            powerController: controller
        )
        _ = try fixture.pipeline.enqueue(
            hookInput(session: "s", turn: "t", event: "UserPromptSubmit"),
            occurredAt: testDate
        )

        let acquired = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate
        )
        try expect(acquired.eventConsumption.appliedCount == 1)
        try expect(acquired.reconciliation?.decision == .active)
        try expect(controller.heartbeatCount == 1)

        let early = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate.addingTimeInterval(1)
        )
        try expect(early.reconciliation == nil)
        try expect(controller.heartbeatCount == 1)

        powerSource.snapshot = PowerSnapshot(
            isOnACPower: false,
            batteryPercent: 80
        )
        let unplugged = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate.addingTimeInterval(10)
        )
        try expect(unplugged.reconciliation?.decision == .onBattery)
        try expect(controller.restoreCount == 1)

        let clockRolledBack = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate.addingTimeInterval(5)
        )
        try expect(clockRolledBack.reconciliation?.decision == .onBattery)
        try expect(powerSource.readCount == 3)
    }

    private static func testRuntimeTaskDetection() throws {
        let fixture = try RuntimeDetectionFixture()
        let detector = CodexRuntimeTaskDetector(
            homeDirectory: fixture.homeDirectory
        )
        let detection = detector.detectActiveTasks(
            now: Date(timeIntervalSince1970: 10_000),
            maximumAge: 3_600
        )

        try expect(detection.sourceAvailable)
        try expect(detection.activeTasks.count == 2)
        try expect(
            Set(detection.activeTasks.map(\.sessionID))
                == Set(["thread-1", "thread-3"])
        )
        try expect(
            Set(detection.activeTasks.map(\.projectName))
                == Set(["alpha", "gamma"])
        )
        let first = try require(
            detection.activeTasks.first { $0.sessionID == "thread-1" }
        )
        try expect(
            first.startedAt == Date(timeIntervalSince1970: 9_800)
        )
        try expect(
            first.lastActivityAt == Date(timeIntervalSince1970: 9_900)
        )
    }

    private static func testRolloutLifecycleDetection() throws {
        let fixture = try RolloutRuntimeDetectionFixture()
        let detector = CodexRuntimeTaskDetector(
            homeDirectory: fixture.homeDirectory
        )
        let now = Date(timeIntervalSince1970: 10_000)

        let started = detector.detectActiveTasks(
            now: now,
            maximumAge: 3_600
        )
        try expect(started.sourceAvailable)
        try expect(started.activeTasks.count == 3)
        try expect(
            Set(started.activeTasks.map(\.sessionID))
                == Set(["thread-1", "thread-2", "thread-3"])
        )

        try fixture.completeThread2()
        let completed = detector.detectActiveTasks(
            now: now.addingTimeInterval(1),
            maximumAge: 3_600
        )
        try expect(completed.activeTasks.count == 2)
        try expect(
            Set(completed.activeTasks.map(\.sessionID))
                == Set(["thread-1", "thread-3"])
        )
    }

    private static func testRuntimeDaemonLifecycle() throws {
        let fixture = EventFixture()
        let powerSource = MutablePowerSourceProvider(
            snapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 80)
        )
        let controller = FakePowerController()
        let lease = TaskLease(
            id: HookProcessor.leaseID(sessionID: "runtime", turnID: "turn"),
            sessionID: "runtime",
            turnID: "turn",
            projectName: "project",
            startedAt: testDate,
            lastActivityAt: testDate,
            expiresAt: testDate.addingTimeInterval(3_600)
        )
        let detector = MutableRuntimeTaskDetector(
            detection: RuntimeTaskDetection(
                sourceAvailable: true,
                activeTasks: [lease]
            )
        )
        let coordinator = DaemonCoordinator(
            eventDirectory: fixture.directory,
            stateStore: fixture.store,
            powerSourceProvider: powerSource,
            powerController: controller,
            runtimeTaskDetector: detector
        )

        let active = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate
        )
        try expect(active.reconciliation?.decision == .active)
        try expect(active.reconciliation?.activeLeaseCount == 1)
        try expect(controller.owned)

        detector.detection = RuntimeTaskDetection(
            sourceAvailable: true,
            activeTasks: []
        )
        let completed = try coordinator.runCycle(
            configuration: testConfiguration,
            now: testDate.addingTimeInterval(1)
        )
        try expect(completed.reconciliation?.decision == .noTasks)
        try expect(completed.reconciliation?.activeLeaseCount == 0)
        try expect(!controller.owned)
    }

    private static func testTaskDeduplication() throws {
        let hook = TaskLease(
            id: HookProcessor.leaseID(sessionID: "same", turnID: "old"),
            sessionID: "same",
            turnID: "old",
            projectName: "hook",
            startedAt: testDate,
            lastActivityAt: testDate,
            expiresAt: testDate.addingTimeInterval(3_600),
            releaseAfter: testDate.addingTimeInterval(20)
        )
        let runtime = TaskLease(
            id: HookProcessor.leaseID(sessionID: "same", turnID: "new"),
            sessionID: "same",
            turnID: "new",
            projectName: "runtime",
            startedAt: testDate.addingTimeInterval(10),
            lastActivityAt: testDate.addingTimeInterval(10),
            expiresAt: testDate.addingTimeInterval(3_600)
        )
        let other = TaskLease(
            id: HookProcessor.leaseID(sessionID: "other", turnID: "turn"),
            sessionID: "other",
            turnID: "turn",
            projectName: "other",
            startedAt: testDate,
            lastActivityAt: testDate,
            expiresAt: testDate.addingTimeInterval(3_600)
        )
        let state = KeeperState(
            leases: [hook.id: hook, other.id: other],
            runtimeLeases: [runtime.id: runtime]
        )

        try expect(state.activeTaskLeases.count == 2)
        try expect(
            state.activeTaskLeases.first {
                $0.sessionID == "same"
            }?.turnID == "new"
        )
    }

    private static func testActiveAC() throws {
        var state = stateWithLease()
        let controller = FakePowerController()
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: .default,
            powerSnapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 80),
            powerController: controller,
            now: testDate
        )
        try expect(result.decision == .active)
        try expect(controller.heartbeatCount == 1)
        try expect(state.powerRequested)
    }

    private static func testHeartbeatCadence() throws {
        var state = stateWithLease()
        let controller = FakePowerController(owned: true)
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: .default,
            powerSnapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 80),
            powerController: controller,
            refreshHeartbeat: false,
            now: testDate
        )
        try expect(result.decision == .active)
        try expect(controller.heartbeatCount == 0)
        try expect(controller.owned)
    }

    private static func testBatteryRestore() throws {
        var state = stateWithLease()
        let controller = FakePowerController(owned: true)
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: .default,
            powerSnapshot: PowerSnapshot(isOnACPower: false, batteryPercent: 80),
            powerController: controller,
            now: testDate
        )
        try expect(result.decision == .onBattery)
        try expect(controller.restoreCount == 1)
        try expect(!controller.owned)
    }

    private static func testBatteryAllowed() throws {
        var state = stateWithLease()
        let controller = FakePowerController()
        let configuration = RuntimeConfiguration(
            powerMode: .allowBattery
        )
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: configuration,
            powerSnapshot: PowerSnapshot(
                isOnACPower: false,
                batteryPercent: 80
            ),
            powerController: controller,
            now: testDate
        )
        try expect(result.decision == .active)
        try expect(controller.heartbeatCount == 1)
        try expect(controller.owned)
    }

    private static func testBatteryChargeUnknown() throws {
        var state = stateWithLease()
        let controller = FakePowerController(owned: true)
        let configuration = RuntimeConfiguration(
            powerMode: .allowBattery
        )
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: configuration,
            powerSnapshot: PowerSnapshot(
                isOnACPower: false,
                batteryPercent: nil
            ),
            powerController: controller,
            now: testDate
        )
        try expect(result.decision == .powerUnknown)
        try expect(controller.restoreCount == 1)
        try expect(!controller.owned)
    }

    private static func testLowBatteryRestore() throws {
        var state = stateWithLease()
        let controller = FakePowerController(owned: true)
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: .default,
            powerSnapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 10),
            powerController: controller,
            now: testDate
        )
        try expect(result.decision == .lowBattery)
        try expect(controller.restoreCount == 1)
    }

    private static func testUnknownPower() throws {
        var state = stateWithLease()
        let controller = FakePowerController()
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: .default,
            powerSnapshot: .unknown,
            powerController: controller,
            now: testDate
        )
        try expect(result.decision == .powerUnknown)
        try expect(controller.heartbeatCount == 0)
    }

    private static func testPowerFailure() throws {
        var state = stateWithLease()
        let controller = FakePowerController(heartbeatError: SelfTestFailure("boom"))
        let result = KeeperReconciler.reconcile(
            state: &state,
            configuration: .default,
            powerSnapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 80),
            powerController: controller,
            now: testDate
        )
        try expect(result.activeLeaseCount == 1)
        try expect(state.lastError != nil)
        try expect(!state.powerRequested)
    }

    private static func testRestorePriorDisabled() throws {
        let fixture = try PowerFixture(pmsetOutput: "AC Power:\n sleep 1\n")
        try fixture.manager.enable(now: fixture.now)
        try fixture.manager.restore()
        try expect(
            fixture.runner.commands.map(\.arguments) == [
                ["-g", "custom"],
                ["-c", "disablesleep", "1"],
                ["-c", "disablesleep", "0"]
            ]
        )
        try expect(!FileManager.default.fileExists(atPath: fixture.marker.path))
    }

    private static func testPreservePriorEnabled() throws {
        let fixture = try PowerFixture(
            pmsetOutput: "AC Power:\n disablesleep 1\n sleep 1\n"
        )
        try fixture.manager.enable(now: fixture.now)
        try fixture.manager.restore()
        try expect(
            fixture.runner.commands.map(\.arguments) == [
                ["-g", "custom"],
                ["-c", "disablesleep", "1"]
            ]
        )
    }

    private static func testBatteryProfileIgnored() throws {
        let fixture = try PowerFixture(
            pmsetOutput:
                "Battery Power:\n disablesleep 1\n sleep 1\nAC Power:\n sleep 1\n"
        )
        try fixture.manager.enable(now: fixture.now)
        try fixture.manager.restore()
        try expect(
            fixture.runner.commands.map(\.arguments).last
                == ["-c", "disablesleep", "0"]
        )
    }

    private static func testBatteryModeRestore() throws {
        let fixture = try PowerFixture(
            pmsetOutput:
                "Battery Power:\n sleep 1\nAC Power:\n sleep 1\n"
        )
        try fixture.manager.enable(
            mode: .allowBattery,
            now: fixture.now
        )
        try fixture.manager.restore()
        try expect(
            fixture.runner.commands.map(\.arguments) == [
                ["-g", "custom"],
                ["-c", "disablesleep", "1"],
                ["-b", "disablesleep", "1"],
                ["-c", "disablesleep", "0"],
                ["-b", "disablesleep", "0"]
            ]
        )
    }

    private static func testBatteryPriorEnabled() throws {
        let fixture = try PowerFixture(
            pmsetOutput:
                "Battery Power:\n disablesleep 1\n sleep 1\nAC Power:\n sleep 1\n"
        )
        try fixture.manager.enable(
            mode: .allowBattery,
            now: fixture.now
        )
        try fixture.manager.restore()
        try expect(
            fixture.runner.commands.map(\.arguments) == [
                ["-g", "custom"],
                ["-c", "disablesleep", "1"],
                ["-b", "disablesleep", "1"],
                ["-c", "disablesleep", "0"]
            ]
        )
    }

    private static func testWatchdogPowerMode() throws {
        let batteryFixture = try PowerFixture(
            pmsetOutput:
                "Battery Power:\n sleep 1\nAC Power:\n sleep 1\n"
        )
        try batteryFixture.manager.enable(
            mode: .allowBattery,
            now: batteryFixture.now
        )
        let kept = try batteryFixture.manager.restoreIfPowerUnsafe(
            snapshot: PowerSnapshot(
                isOnACPower: false,
                batteryPercent: 80
            )
        )
        try expect(!kept)
        try expect(
            FileManager.default.fileExists(
                atPath: batteryFixture.marker.path
            )
        )
        let lowBattery = try batteryFixture.manager.restoreIfPowerUnsafe(
            snapshot: PowerSnapshot(
                isOnACPower: false,
                batteryPercent: 20
            )
        )
        try expect(lowBattery)
        try expect(
            !FileManager.default.fileExists(
                atPath: batteryFixture.marker.path
            )
        )

        let acFixture = try PowerFixture(
            pmsetOutput:
                "Battery Power:\n sleep 1\nAC Power:\n sleep 1\n"
        )
        try acFixture.manager.enable(mode: .acOnly, now: acFixture.now)
        let unplugged = try acFixture.manager.restoreIfPowerUnsafe(
            snapshot: PowerSnapshot(
                isOnACPower: false,
                batteryPercent: 80
            )
        )
        try expect(unplugged)
    }

    private static func testMissingACProfile() throws {
        let fixture = try PowerFixture(
            pmsetOutput: "Battery Power:\n sleep 1\n"
        )
        do {
            try fixture.manager.enable(now: fixture.now)
            throw SelfTestFailure("missing AC profile was accepted")
        } catch let error as PrivilegedPowerError {
            try expect(error == .missingACPowerProfile)
            try expect(!FileManager.default.fileExists(atPath: fixture.marker.path))
        }
    }

    private static func testOwnershipHeartbeat() throws {
        let fixture = try PowerFixture(pmsetOutput: "AC Power:\n sleep 1\n")
        try fixture.manager.enable(now: fixture.now)
        let later = fixture.now.addingTimeInterval(30)
        try fixture.manager.enable(now: later)
        try expect(fixture.runner.commands.count == 2)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.marker.path
        )
        let modified = attributes[.modificationDate] as? Date
        try expect(abs((modified?.timeIntervalSince1970 ?? 0) - later.timeIntervalSince1970) < 0.01)
    }

    private static func testExpiredHeartbeat() throws {
        let fixture = try PowerFixture(pmsetOutput: "AC Power:\n sleep 1\n")
        try fixture.manager.enable(now: fixture.now)
        let restored = try fixture.manager.restoreIfHeartbeatExpired(
            now: fixture.now.addingTimeInterval(121),
            maximumAge: 120
        )
        try expect(restored)
        try expect(fixture.runner.commands.last?.arguments == ["-c", "disablesleep", "0"])
    }

    private static func testMalformedOwnership() throws {
        let fixture = try PowerFixture(pmsetOutput: "AC Power:\n sleep 1\n")
        try Data("not-json".utf8).write(to: fixture.marker)
        do {
            try fixture.manager.enable(now: fixture.now.addingTimeInterval(30))
            throw SelfTestFailure("malformed record was accepted")
        } catch let error as PrivilegedPowerError {
            try expect(error == .malformedOwnershipRecord)
            try expect(FileManager.default.fileExists(atPath: fixture.marker.path))
        }
        try expect(fixture.runner.commands.isEmpty)
    }

    private static func testConfigurationValidation() throws {
        do {
            _ = try RuntimeConfiguration(minimumBatteryPercent: 29).validated()
            throw SelfTestFailure("unsafe battery threshold was accepted")
        } catch let error as RuntimeConfigurationError {
            try expect(error == .invalidMinimumBatteryPercent)
        }
        do {
            _ = try RuntimeConfiguration(eventPollInterval: 0).validated()
            throw SelfTestFailure("invalid poll interval was accepted")
        } catch let error as RuntimeConfigurationError {
            try expect(error == .invalidEventPollInterval)
        }
        do {
            _ = try RuntimeConfiguration(powerHeartbeatInterval: 31).validated()
            throw SelfTestFailure("invalid heartbeat interval was accepted")
        } catch let error as RuntimeConfigurationError {
            try expect(error == .invalidPowerHeartbeatInterval)
        }
        try expect(try RuntimeConfiguration.default.validated() == .default)
    }

    private static func testLegacyMigration() throws {
        let legacyConfiguration = Data(
            """
            {
              "minimumBatteryPercent": 35,
              "leaseDuration": 3600,
              "releaseDelay": 10,
              "pollInterval": 12
            }
            """.utf8
        )
        let configuration = try LockedStateStore.decoder.decode(
            RuntimeConfiguration.self,
            from: legacyConfiguration
        )
        try expect(configuration.eventPollInterval == 1)
        try expect(configuration.powerHeartbeatInterval == 12)

        let fixture = StoreFixture()
        try FileManager.default.createDirectory(
            at: fixture.directory,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "schemaVersion": 1,
              "automationEnabled": false
            }
            """.utf8
        ).write(to: fixture.stateFile)
        try fixture.store.update { state in
            try expect(state.schemaVersion == KeeperConstants.schemaVersion)
            try expect(state.recentEventIDs.isEmpty)
        }
        let rewritten = try String(contentsOf: fixture.stateFile, encoding: .utf8)
        try expect(
            rewritten.contains(
                "\"schemaVersion\" : \(KeeperConstants.schemaVersion)"
            )
        )
        try expect(rewritten.contains("\"recentEventIDs\""))

        let previewFixture = StoreFixture()
        try FileManager.default.createDirectory(
            at: previewFixture.directory,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "schemaVersion": 4,
              "automationEnabled": true,
              "runtimeLeases": {}
            }
            """.utf8
        ).write(to: previewFixture.stateFile)
        try previewFixture.store.update { state in
            try expect(state.schemaVersion == KeeperConstants.schemaVersion)
        }
        let migratedPreview = try String(
            contentsOf: previewFixture.stateFile,
            encoding: .utf8
        )
        try expect(
            migratedPreview.contains(
                "\"schemaVersion\" : \(KeeperConstants.schemaVersion)"
            )
        )
    }

    private static func testLogRotation() throws {
        let fixture = StoreFixture()
        let log = fixture.directory.appendingPathComponent("keeper.log")
        let logger = KeeperLogger(file: log, maximumBytes: 180)
        for index in 0..<12 {
            logger.append(
                "entry=\(index) value=abcdefghijklmnopqrstuvwxyz",
                now: testDate.addingTimeInterval(Double(index))
            )
        }

        let rotated = log.appendingPathExtension("1")
        try expect(FileManager.default.fileExists(atPath: log.path))
        try expect(FileManager.default.fileExists(atPath: rotated.path))
        let currentSize = try FileManager.default.attributesOfItem(
            atPath: log.path
        )[.size] as? NSNumber
        let rotatedSize = try FileManager.default.attributesOfItem(
            atPath: rotated.path
        )[.size] as? NSNumber
        try expect((currentSize?.intValue ?? .max) <= 180)
        try expect((rotatedSize?.intValue ?? .max) <= 180)
    }

    private static func testStateRoundTrip() throws {
        let fixture = StoreFixture()
        let now = Date(timeIntervalSince1970: 1_234)
        try fixture.store.update { state in
            state.automationEnabled = false
            state.lastReconciledAt = now
        }
        let loaded = try fixture.store.read()
        try expect(!loaded.automationEnabled)
        try expect(loaded.lastReconciledAt == now)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.stateFile.path
        )
        let permissions = attributes[.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o600)
    }

    private static func testConcurrentUpdates() throws {
        let fixture = StoreFixture()
        let queue = DispatchQueue(label: "state-test", attributes: .concurrent)
        let group = DispatchGroup()
        let errors = LockedErrors()

        for index in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    try fixture.store.update { state in
                        let id = "s\(index)\u{1F}t\(index)"
                        state.leases[id] = TaskLease(
                            id: id,
                            sessionID: "s\(index)",
                            turnID: "t\(index)",
                            projectName: "project",
                            startedAt: Date(),
                            lastActivityAt: Date(),
                            expiresAt: Date().addingTimeInterval(60)
                        )
                    }
                } catch {
                    errors.append(error)
                }
            }
        }
        group.wait()
        try expect(errors.values.isEmpty)
        try expect(try fixture.store.read().leases.count == 20)
    }

    private static let testDate = Date(timeIntervalSince1970: 1_000)
    private static let testConfiguration = RuntimeConfiguration(
        leaseDuration: 3_600,
        releaseDelay: 20
    )

    private static func acquire(
        session: String,
        turn: String,
        state: inout KeeperState,
        now: Date
    ) throws {
        try LeaseReducer.apply(
            event: try lifecycleEvent(
                session: session,
                turn: turn,
                event: "UserPromptSubmit",
                now: now
            ),
            to: &state,
            configuration: testConfiguration
        )
    }

    private static func lifecycleEvent(
        session: String,
        turn: String?,
        event: String,
        now: Date
    ) throws -> LifecycleEvent {
        try HookProcessor.makeEvent(
            from: hookInput(session: session, turn: turn, event: event),
            occurredAt: now
        )
    }

    private static func hookInput(
        session: String,
        turn: String?,
        event: String
    ) -> CodexHookInput {
        CodexHookInput(
            sessionID: session,
            turnID: turn,
            cwd: "/tmp/project",
            hookEventName: event
        )
    }

    private static func stateWithLease() -> KeeperState {
        let lease = TaskLease(
            id: "s\u{1F}t",
            sessionID: "s",
            turnID: "t",
            projectName: "project",
            startedAt: testDate,
            lastActivityAt: testDate,
            expiresAt: testDate.addingTimeInterval(3_600)
        )
        return KeeperState(leases: [lease.id: lease])
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String = "expectation failed"
    ) throws {
        guard try condition() else {
            throw SelfTestFailure(message)
        }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else {
            throw SelfTestFailure("required value was missing")
        }
        return value
    }
}

private struct SelfTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private final class FakePowerController: PowerControlling {
    var owned: Bool
    var heartbeatCount = 0
    var restoreCount = 0
    var lastHeartbeatMode: GuardPowerMode?
    let heartbeatError: Error?

    init(owned: Bool = false, heartbeatError: Error? = nil) {
        self.owned = owned
        self.heartbeatError = heartbeatError
    }

    func isOwned() -> Bool {
        owned
    }

    func heartbeat(mode: GuardPowerMode) throws {
        heartbeatCount += 1
        lastHeartbeatMode = mode
        if let heartbeatError {
            throw heartbeatError
        }
        owned = true
    }

    func restore() throws {
        restoreCount += 1
        owned = false
    }
}

private final class MutablePowerSourceProvider: PowerSourceProviding {
    var snapshot: PowerSnapshot
    var readCount = 0

    init(snapshot: PowerSnapshot) {
        self.snapshot = snapshot
    }

    func currentSnapshot() -> PowerSnapshot {
        readCount += 1
        return snapshot
    }
}

private final class MutableRuntimeTaskDetector: RuntimeTaskDetecting {
    var detection: RuntimeTaskDetection

    init(detection: RuntimeTaskDetection) {
        self.detection = detection
    }

    func detectActiveTasks(
        now: Date,
        maximumAge: TimeInterval
    ) -> RuntimeTaskDetection {
        detection
    }
}

private final class RuntimeDetectionFixture {
    let homeDirectory: URL

    init() throws {
        homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexDirectory = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )

        try Self.runSQLite(
            database: codexDirectory.appendingPathComponent("logs_2.sqlite"),
            sql: """
                CREATE TABLE logs (
                    ts INTEGER NOT NULL,
                    ts_nanos INTEGER NOT NULL,
                    target TEXT NOT NULL,
                    feedback_log_body TEXT NOT NULL
                );
                CREATE INDEX idx_logs_ts ON logs(ts);
                INSERT INTO logs VALUES (
                    9800, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-1}:turn{ turn.id=turn-1 } needs_follow_up=true'
                );
                INSERT INTO logs VALUES (
                    9900, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-1}:turn{ turn.id=turn-1 } model_needs_follow_up=true needs_follow_up=true'
                );
                INSERT INTO logs VALUES (
                    9850, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-2}:turn{ turn.id=turn-2 } needs_follow_up=true'
                );
                INSERT INTO logs VALUES (
                    9950, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-2}:turn{ turn.id=turn-2 } model_needs_follow_up=true needs_follow_up=false'
                );
                INSERT INTO logs VALUES (
                    9700, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-3}:turn{ turn.id=old-turn } needs_follow_up=false'
                );
                INSERT INTO logs VALUES (
                    9975, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-3}:turn{ turn.id=turn-3 } needs_follow_up=true'
                );
                INSERT INTO logs VALUES (
                    9999, 1, 'unrelated',
                    'private content is never selected'
                );
                """
        )
        try Self.runSQLite(
            database: codexDirectory.appendingPathComponent("state_5.sqlite"),
            sql: """
                CREATE TABLE threads (
                    id TEXT PRIMARY KEY,
                    cwd TEXT NOT NULL
                );
                INSERT INTO threads VALUES ('thread-1', '/tmp/alpha');
                INSERT INTO threads VALUES ('thread-2', '/tmp/beta');
                INSERT INTO threads VALUES ('thread-3', '/tmp/gamma');
                """
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: homeDirectory)
    }

    private static func runSQLite(database: URL, sql: String) throws {
        let process = Process()
        let input = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path]
        process.standardInput = input
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw SelfTestFailure("sqlite fixture failed: \(message)")
        }
    }
}

private final class RolloutRuntimeDetectionFixture {
    let homeDirectory: URL
    private let thread2Rollout: URL

    init() throws {
        homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexDirectory = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )

        let thread1Rollout = codexDirectory.appendingPathComponent("thread-1.jsonl")
        thread2Rollout = codexDirectory.appendingPathComponent("thread-2.jsonl")
        let thread3Rollout = codexDirectory.appendingPathComponent("thread-3.jsonl")
        try Data().write(to: thread1Rollout)
        try Data().write(to: thread2Rollout)
        try Data(
            """
            {"timestamp":"1970-01-01T02:46:35.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-3","started_at":"1970-01-01T02:46:35.000Z"}}

            """.utf8
        ).write(to: thread3Rollout)

        try Self.runSQLite(
            database: codexDirectory.appendingPathComponent("logs_2.sqlite"),
            sql: """
                CREATE TABLE logs (
                    ts INTEGER NOT NULL,
                    ts_nanos INTEGER NOT NULL,
                    target TEXT NOT NULL,
                    feedback_log_body TEXT NOT NULL
                );
                CREATE INDEX idx_logs_ts ON logs(ts);
                INSERT INTO logs VALUES (
                    9990, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-1}:turn{ turn.id=turn-1 } needs_follow_up=true'
                );
                INSERT INTO logs VALUES (
                    9991, 1, 'codex_core::session::turn',
                    'session_loop{thread_id=thread-2}:turn{ turn.id=turn-2 } needs_follow_up=true'
                );
                """
        )
        try Self.runSQLite(
            database: codexDirectory.appendingPathComponent("state_5.sqlite"),
            sql: """
                CREATE TABLE threads (
                    id TEXT PRIMARY KEY,
                    rollout_path TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    archived INTEGER NOT NULL DEFAULT 0,
                    cwd TEXT NOT NULL
                );
                INSERT INTO threads VALUES (
                    'thread-1', '\(Self.sqlQuote(thread1Rollout.path))',
                    9999, 0, '/tmp/alpha'
                );
                INSERT INTO threads VALUES (
                    'thread-2', '\(Self.sqlQuote(thread2Rollout.path))',
                    9999, 0, '/tmp/beta'
                );
                INSERT INTO threads VALUES (
                    'thread-3', '\(Self.sqlQuote(thread3Rollout.path))',
                    9999, 0, '/tmp/gamma'
                );
                """
        )
    }

    func completeThread2() throws {
        let handle = try FileHandle(forWritingTo: thread2Rollout)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(
            contentsOf: Data(
                """
                {"timestamp":"1970-01-01T02:46:36.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-2","completed_at":"1970-01-01T02:46:36.000Z"}}

                """.utf8
            )
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: homeDirectory)
    }

    private static func sqlQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func runSQLite(database: URL, sql: String) throws {
        let process = Process()
        let input = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path]
        process.standardInput = input
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw SelfTestFailure("sqlite fixture failed: \(message)")
        }
    }
}

private final class PowerFixture {
    let directory: URL
    let marker: URL
    let runner: RecordingCommandRunner
    let manager: PrivilegedPowerManager
    let now = Date(timeIntervalSince1970: 5_000)

    init(pmsetOutput: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        marker = directory.appendingPathComponent("ownership.json")
        runner = RecordingCommandRunner(pmsetOutput: pmsetOutput)
        manager = PrivilegedPowerManager(
            ownershipFile: marker,
            runner: runner
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class RecordingCommandRunner: CommandRunning {
    struct Invocation {
        let executable: String
        let arguments: [String]
    }

    var commands: [Invocation] = []
    let pmsetOutput: String

    init(pmsetOutput: String) {
        self.pmsetOutput = pmsetOutput
    }

    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        commands.append(Invocation(executable: executable, arguments: arguments))
        return CommandResult(
            exitCode: 0,
            standardOutput: Data(pmsetOutput.utf8),
            standardError: Data()
        )
    }
}

private final class StoreFixture {
    let directory: URL
    let stateFile: URL
    let store: LockedStateStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        stateFile = directory.appendingPathComponent("state.json")
        store = LockedStateStore(
            stateFile: stateFile,
            lockFile: directory.appendingPathComponent("state.lock")
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class EventFixture {
    let directory: URL
    let store: LockedStateStore
    let pipeline: HookEventPipeline

    init(maximumPendingEventCount: Int = KeeperConstants.pendingEventLimit) {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("events", isDirectory: true)
        let stateDirectory = directory.deletingLastPathComponent()
        store = LockedStateStore(
            stateFile: stateDirectory.appendingPathComponent("state.json"),
            lockFile: stateDirectory.appendingPathComponent("state.lock")
        )
        pipeline = HookEventPipeline(
            directory: directory,
            stateStore: store,
            maximumPendingEventCount: maximumPendingEventCount
        )
    }

    deinit {
        try? FileManager.default.removeItem(
            at: directory.deletingLastPathComponent()
        )
    }
}

private final class LockedErrors {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ error: Error) {
        lock.lock()
        storage.append(error)
        lock.unlock()
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
