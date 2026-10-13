import Darwin
import Foundation

let version = "0.2.1"

if CommandLine.arguments.contains("--version") {
    print(version)
    exit(0)
}

guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
    FileHandle.standardError.write(Data("portwatch needs an interactive terminal.\n".utf8))
    exit(1)
}

MainActor.assumeIsolated {
    Runner().run()
}
