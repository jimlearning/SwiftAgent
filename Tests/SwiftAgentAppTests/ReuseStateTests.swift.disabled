import XCTest
@testable import SwiftAgentApp

final class ReuseStateTests: XCTestCase {

    // MARK: - ThreadReuseState

    func testReuseStateRawValues() {
        XCTAssertEqual(ThreadReuseState.new.rawValue, "new")
        XCTAssertEqual(ThreadReuseState.active.rawValue, "active")
        XCTAssertEqual(ThreadReuseState.idle.rawValue, "idle")
        XCTAssertEqual(ThreadReuseState.resumed.rawValue, "resumed")
        XCTAssertEqual(ThreadReuseState.paused.rawValue, "paused")
    }

    func testReuseStateRoundTrip() {
        for state in [ThreadReuseState.new, .active, .idle, .resumed, .paused] {
            let fromRaw = ThreadReuseState(rawValue: state.rawValue)
            XCTAssertEqual(fromRaw, state)
        }
    }

    func testInvalidReuseStateReturnsNil() {
        XCTAssertNil(ThreadReuseState(rawValue: "invalid"))
    }

    // MARK: - ThreadState persistence strings

    @MainActor
    func testThreadStatePersistedString() {
        let vm = ThreadViewModel()
        vm.state = .idle
        XCTAssertEqual(vm.persistedState, "idle")

        vm.state = .executing
        XCTAssertEqual(vm.persistedState, "executing")

        vm.state = .done
        XCTAssertEqual(vm.persistedState, "done")

        vm.state = .failed("error")
        XCTAssertEqual(vm.persistedState, "failed")
    }

    func testThreadStateInitFromString() {
        XCTAssertEqual(ThreadState(rawValue: "idle"), .idle)
        XCTAssertEqual(ThreadState(rawValue: "executing"), .executing)
        XCTAssertEqual(ThreadState(rawValue: "done"), .done)
        if case .failed = ThreadState(rawValue: "failed") {
            // Pass
        } else {
            XCTFail("Expected .failed")
        }
        if case .failed = ThreadState(rawValue: "failed:something") {
            // Pass
        } else {
            XCTFail("Expected .failed with message")
        }
    }

    @MainActor
    func testReuseStatePersistenceOnThreadViewModel() {
        let vm = ThreadViewModel()
        vm.reuseState = .active
        XCTAssertEqual(vm.reuseState.rawValue, "active")
        vm.reuseState = .idle
        XCTAssertEqual(vm.reuseState.rawValue, "idle")
    }
}
