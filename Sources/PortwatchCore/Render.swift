public struct Style: Equatable, Sendable {
    public enum Color: Equatable, Sendable { case red, yellow }

    public var bold = false
    public var dim = false
    public var inverse = false
    public var color: Color?

    public init(bold: Bool = false, dim: Bool = false, inverse: Bool = false, color: Color? = nil) {
        self.bold = bold
        self.dim = dim
        self.inverse = inverse
        self.color = color
    }

    var escape: String {
        var codes: [String] = []
        if bold {
            codes.append("1")
        }
        if dim {
            codes.append("2")
        }
        if inverse {
            codes.append("7")
        }
        switch color {
        case .red: codes.append("31")
        case .yellow: codes.append("33")
        case nil: break
        }
        return codes.isEmpty ? "" : "\u{1B}[\(codes.joined(separator: ";"))m"
    }
}

public struct Cell: Equatable, Sendable {
    public var text: String
    public var style: Style

    public init(_ text: String, _ style: Style = Style()) {
        self.text = text
        self.style = style
    }
}

public struct StyledLine: Equatable, Sendable {
    public var cells: [Cell]

    public init(_ cells: [Cell]) {
        self.cells = cells
    }

    public var plainText: String {
        cells.map(\.text).joined()
    }

    /// The line with ANSI styling, clipped to `width` visible characters.
    public func ansi(width: Int) -> String {
        var remaining = max(0, width)
        var output = ""
        for cell in cells where remaining > 0 {
            let text = String(cell.text.prefix(remaining))
            remaining -= text.count
            let escape = cell.style.escape
            output += escape.isEmpty ? text : escape + text + "\u{1B}[0m"
        }
        return output
    }
}

public enum Renderer {
    public static let columnWidths = (process: 20, port: 8, pid: 8, source: 44)
    public static let footerHint = "j/k or arrows: move   x: kill   e: exclude   a: show all   q: quit"

    /// Pads or truncates (from the end) to `width`, always leaving one trailing space.
    static func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width {
            return String(text.prefix(width - 1)) + " "
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    /// The SOURCE column holds paths where the distinguishing part (the project
    /// directory) is at the end, so over-long values are cut from the front,
    /// keeping the tail, with a leading ellipsis.
    static func padLeftTruncate(_ text: String, _ width: Int) -> String {
        if text.count >= width {
            return "…" + String(text.suffix(width - 2)) + " "
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    static var headerLine: StyledLine {
        let bold = Style(bold: true)
        return StyledLine([
            Cell(pad("PROCESS", columnWidths.process), bold),
            Cell(pad("PORT", columnWidths.port), bold),
            Cell(pad("PID", columnWidths.pid), bold),
            Cell(pad("SOURCE", columnWidths.source), bold),
            Cell("UPTIME", bold),
        ])
    }

    /// Shown once above a multi-port process's rows, carrying what's common to
    /// all of them (name, pid, source).
    static func headingLine(_ group: Group, excluded: Bool) -> StyledLine {
        let style = Style(bold: true, dim: excluded)
        return StyledLine([
            Cell(pad(group.process, columnWidths.process), style),
            Cell(pad("", columnWidths.port), style),
            Cell(pad(String(group.pid), columnWidths.pid), style),
            Cell(padLeftTruncate(group.source, columnWidths.source), style),
            Cell(excluded ? "(excluded)" : "", style),
        ])
    }

    /// A sub-row of a multi-port group (`indent`) shows only what differs from
    /// its siblings (port, uptime); a single-port row shows every column.
    static func serviceLine(_ service: Service, selected: Bool, indent: Bool, excluded: Bool) -> StyledLine {
        let style = Style(dim: excluded && !selected, inverse: selected)
        return StyledLine([
            Cell(indent ? pad("", columnWidths.process) : pad(service.process, columnWidths.process), style),
            Cell(pad(String(service.port), columnWidths.port), style),
            Cell(indent ? pad("", columnWidths.pid) : pad(String(service.pid), columnWidths.pid), style),
            Cell(indent ? pad("", columnWidths.source) : padLeftTruncate(service.source, columnWidths.source), style),
            Cell(service.uptime, style),
        ])
    }

    /// The whole frame: header, rows (scrolled to keep the selection visible
    /// when they don't fit), then an optional error line and the footer.
    public static func lines(for state: AppState, height: Int) -> [StyledLine] {
        var body: [(line: StyledLine, selected: Bool)] = []
        for group in state.groups {
            let excluded = state.excludes.contains(group.process)
            let isMultiPort = group.ports.count > 1
            if isMultiPort {
                body.append((headingLine(group, excluded: excluded), false))
            }
            for entry in group.ports {
                let service = Service(
                    pid: group.pid, process: group.process, port: entry.port,
                    source: group.source, uptime: entry.uptime
                )
                let selected = service.key == state.selectedKey
                body.append((
                    serviceLine(service, selected: selected, indent: isMultiPort, excluded: excluded),
                    selected
                ))
            }
        }

        var footer: [StyledLine] = []
        if let error = state.error {
            footer.append(StyledLine([Cell("Error: \(error)", Style(color: .red))]))
        }
        if let service = state.confirmingService {
            footer.append(StyledLine([Cell(
                "Kill \(service.process) (PID \(service.pid))? y/n",
                Style(color: .yellow)
            )]))
        } else {
            let hint = footerHint + (state.showAll ? "  [showing excluded]" : "")
            footer.append(StyledLine([Cell(hint, Style(dim: true))]))
        }

        let capacity = max(0, height - 1 - footer.count)
        var visible = body
        if body.count > capacity {
            let selectedIndex = body.firstIndex { $0.selected } ?? 0
            let start = max(0, min(selectedIndex - capacity / 2, body.count - capacity))
            visible = Array(body[start ..< start + capacity])
        }

        return [headerLine] + visible.map(\.line) + footer
    }
}
