import Darwin

public struct KillError: Error, Equatable, Sendable {
    public var code: Int32

    public var message: String {
        String(cString: strerror(code))
    }
}

/// Sends SIGTERM. A pid that is already gone (ESRCH) counts as success: the
/// process is gone either way.
public func killService(
    pid: Int32,
    kill killFn: (Int32, Int32) -> Int32 = { Darwin.kill($0, $1) }
) -> Result<Void, KillError> {
    if killFn(pid, SIGTERM) == 0 {
        return .success(())
    }
    let code = errno
    return code == ESRCH ? .success(()) : .failure(KillError(code: code))
}
