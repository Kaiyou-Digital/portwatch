/// Groups services by pid. Precondition: `services` is sorted by port ascending
/// (as `collectServices` guarantees), so each group's ports come out ascending.
/// Groups are ordered by their lowest port.
public func groupServices(_ services: [Service]) -> [Group] {
    var order: [Int32] = []
    var groups: [Int32: Group] = [:]

    for service in services {
        if groups[service.pid] == nil {
            order.append(service.pid)
            groups[service.pid] = Group(
                pid: service.pid,
                process: service.process,
                source: service.source,
                ports: []
            )
        }
        groups[service.pid]?.ports.append(PortEntry(port: service.port, uptime: service.uptime))
    }

    return order.compactMap { groups[$0] }.sorted { lhs, rhs in
        let (a, b) = (lhs.ports[0].port, rhs.ports[0].port)
        return a != b ? a < b : lhs.pid < rhs.pid
    }
}

/// One selectable row per port, in display order.
public func flattenGroups(_ groups: [Group]) -> [Service] {
    groups.flatMap { group in
        group.ports.map {
            Service(pid: group.pid, process: group.process, port: $0.port, source: group.source, uptime: $0.uptime)
        }
    }
}
