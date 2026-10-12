import Foundation

/// One listening TCP port as read from the system, before filtering or formatting.
public struct RawService: Equatable, Sendable {
    public var pid: Int32
    public var port: Int
    public var name: String
    public var cwd: String
    public var startTime: Date

    public init(pid: Int32, port: Int, name: String, cwd: String, startTime: Date) {
        self.pid = pid
        self.port = port
        self.name = name
        self.cwd = cwd
        self.startTime = startTime
    }
}

/// One row's worth of data, ready to display.
public struct Service: Equatable, Sendable {
    public var pid: Int32
    public var process: String
    public var port: Int
    public var source: String
    public var uptime: String

    public init(pid: Int32, process: String, port: Int, source: String, uptime: String) {
        self.pid = pid
        self.process = process
        self.port = port
        self.source = source
        self.uptime = uptime
    }

    /// A pid can hold more than one listening port (e.g. mysqld on 3306 and
    /// 33060), so pid alone isn't a unique row identity. Rows are keyed and
    /// selected by pid+port; kills still target the pid.
    public var key: String {
        "\(pid):\(port)"
    }
}

public struct PortEntry: Equatable, Sendable {
    public var port: Int
    public var uptime: String

    public init(port: Int, uptime: String) {
        self.port = port
        self.uptime = uptime
    }
}

/// All the listening ports of a single process.
public struct Group: Equatable, Sendable {
    public var pid: Int32
    public var process: String
    public var source: String
    public var ports: [PortEntry]

    public init(pid: Int32, process: String, source: String, ports: [PortEntry]) {
        self.pid = pid
        self.process = process
        self.source = source
        self.ports = ports
    }
}
