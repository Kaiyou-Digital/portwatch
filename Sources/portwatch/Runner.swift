import Darwin
import Dispatch
import PortwatchCore

/// Owns the single `AppState` and all I/O. Everything here runs on the main
/// queue; slow work (walking the process table) hops to a background queue and
/// back, with at most one collection in flight at a time.
@MainActor
final class Runner {
    private var state = AppState()
    private let source: ProcessSource
    private let excludeStore: ExcludeStore
    private var collecting = false
    private var decoder = KeyDecoder()
    private var lastFrame = ""
    private var retained: [any DispatchSourceProtocol] = []

    init(source: ProcessSource = LibprocSource(), excludeStore: ExcludeStore = ExcludeStore()) {
        self.source = source
        self.excludeStore = excludeStore
    }

    func run() -> Never {
        enterRawMode()

        loadExcludes()
        draw()
        tick()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler { Task { @MainActor in self.tick() } }
        retain(timer)

        let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        input.setEventHandler { Task { @MainActor in self.readInput() } }
        retain(input)

        for number in [SIGWINCH, SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let handler = DispatchSource.makeSignalSource(signal: number, queue: .main)
            handler.setEventHandler {
                Task { @MainActor in
                    if number == SIGWINCH {
                        self.draw(force: true)
                    } else {
                        self.quit()
                    }
                }
            }
            retain(handler)
        }

        dispatchMain()
    }

    private func retain(_ source: any DispatchSourceProtocol) {
        retained.append(source)
        source.resume()
    }

    private func loadExcludes() {
        do {
            try handle(.excludesLoaded(excludeStore.load()))
        } catch {
            handle(.excludesLoadFailed(error.localizedDescription))
        }
    }

    private func tick() {
        guard !collecting else { return }
        collecting = true
        let source = source
        Task {
            // Walking the process table runs off the main actor; the result comes back to it.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try collectServices(from: source) }
            }.value
            collecting = false
            switch result {
            case let .success(services): handle(.tickSucceeded(services))
            case let .failure(error): handle(.tickFailed(error.localizedDescription))
            }
        }
    }

    private func readInput() {
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count == 0 {
            quit()
        } // stdin closed
        guard count > 0 else { return }
        let keys = decoder.decode(Array(buffer.prefix(count)))
        if !keys.isEmpty {
            handle(.input(keys))
        }
    }

    private func handle(_ event: Event) {
        for effect in state.apply(event) {
            switch effect {
            case .quit:
                quit()
            case let .kill(pid):
                if case let .failure(error) = killService(pid: pid) {
                    _ = state.apply(.killFailed(error.message))
                }
            case let .saveExcludes(names):
                do {
                    try excludeStore.save(names)
                } catch {
                    _ = state.apply(.saveFailed(error.localizedDescription))
                }
            }
        }
        draw()
    }

    private func draw(force: Bool = false) {
        let size = terminalSize()
        let lines = Renderer.lines(for: state, height: size.height).map { $0.ansi(width: size.width) }
        let frame = lines.joined(separator: "\u{1B}[K\r\n") + "\u{1B}[K\u{1B}[J"
        if !force, frame == lastFrame {
            return
        }
        lastFrame = frame
        writeOut("\u{1B}[H" + frame)
    }

    private func quit() -> Never {
        restoreTerminal()
        exit(0)
    }
}
