public enum Key: Equatable, Sendable {
    case char(Character)
    case up
    case down
    case ctrlC
}

public enum Event: Equatable, Sendable {
    case tickSucceeded([Service])
    case tickFailed(String)
    case excludesLoaded(Set<String>)
    case excludesLoadFailed(String)
    case killFailed(String)
    case saveFailed(String)
    case key(Key)
}

/// Work the runner must do on the reducer's behalf. The reducer itself does no I/O.
public enum Effect: Equatable, Sendable {
    case kill(pid: Int32)
    case saveExcludes(Set<String>)
    case quit
}

public struct AppState: Equatable, Sendable {
    public var services: [Service] = []
    public var error: String?
    public var selectedKey: String?
    public var confirmingKey: String?
    public var excludes: Set<String> = []
    public var showAll = false

    public init() {}

    public var visibleServices: [Service] {
        showAll ? services : services.filter { !excludes.contains($0.process) }
    }

    public var groups: [Group] {
        groupServices(visibleServices)
    }

    public var flatRows: [Service] {
        flattenGroups(groups)
    }

    public var confirmingService: Service? {
        guard let confirmingKey else { return nil }
        return flatRows.first { $0.key == confirmingKey }
    }

    public mutating func apply(_ event: Event) -> [Effect] {
        switch event {
        case let .tickSucceeded(services):
            self.services = services
            error = nil
            reconcileSelection()
        case let .tickFailed(message):
            error = message
        case let .excludesLoaded(names):
            excludes = names
            reconcileSelection()
        case let .excludesLoadFailed(message):
            error = "Failed to read exclude list: \(message)"
        case let .killFailed(message):
            error = "Kill failed: \(message)"
        case let .saveFailed(message):
            error = "Failed to save exclude list: \(message)"
        case let .key(key):
            return handle(key)
        }
        return []
    }

    /// Keeps the highlighted row valid whenever the visible row set changes: a
    /// poll tick, an exclude toggle or show-all can each remove the selected row.
    private mutating func reconcileSelection() {
        let rows = flatRows
        if rows.isEmpty {
            selectedKey = nil
        } else if let selectedKey, rows.contains(where: { $0.key == selectedKey }) {
            return
        } else {
            selectedKey = rows[0].key
        }
    }

    private mutating func handle(_ key: Key) -> [Effect] {
        if key == .ctrlC {
            return [.quit]
        }
        if confirmingKey != nil {
            return handleConfirmation(key)
        }
        if key == .char("q") {
            return [.quit]
        }

        if key == .char("a") {
            showAll.toggle()
            reconcileSelection()
            return []
        }

        return handleRowKey(key)
    }

    /// Only `y` confirms; any other key cancels.
    private mutating func handleConfirmation(_ key: Key) -> [Effect] {
        defer { confirmingKey = nil }
        guard key == .char("y"), let service = confirmingService else { return [] }
        return [.kill(pid: service.pid)]
    }

    private mutating func handleRowKey(_ key: Key) -> [Effect] {
        let rows = flatRows
        if rows.isEmpty {
            return []
        }
        let index = rows.firstIndex { $0.key == selectedKey } ?? -1

        switch key {
        case .char("j"), .down:
            selectedKey = rows[(index + 1) % rows.count].key
        case .char("k"), .up:
            selectedKey = rows[(index - 1 + rows.count) % rows.count].key
        case .char("x"):
            confirmingKey = selectedKey
        case .char("e"):
            return toggleExclusion(of: rows.first { $0.key == selectedKey })
        default:
            break
        }
        return []
    }

    private mutating func toggleExclusion(of service: Service?) -> [Effect] {
        guard let service else { return [] }
        if excludes.contains(service.process) {
            excludes.remove(service.process)
        } else {
            excludes.insert(service.process)
        }
        return [.saveExcludes(excludes)]
    }
}
