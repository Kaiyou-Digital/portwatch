import Darwin
@testable import PortwatchCore
import Testing

struct KillTests {
    @Test func sendsSigterm() {
        var sent: (Int32, Int32)?
        let result = killService(pid: 42) { pid, signal in
            sent = (pid, signal)
            return 0
        }
        #expect(result.isSuccess)
        #expect(sent?.0 == 42)
        #expect(sent?.1 == SIGTERM)
    }

    @Test func alreadyGoneCountsAsSuccess() {
        let result = killService(pid: 42) { _, _ in
            errno = ESRCH
            return -1
        }
        #expect(result.isSuccess)
    }

    @Test func otherFailuresAreReported() {
        let result = killService(pid: 42) { _, _ in
            errno = EPERM
            return -1
        }
        #expect(result.failureCode == EPERM)
        #expect(KillError(code: EPERM).message == "Operation not permitted")
    }
}

private extension Result where Success == Void, Failure == KillError {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var failureCode: Int32? {
        if case let .failure(error) = self {
            return error.code
        }
        return nil
    }
}
