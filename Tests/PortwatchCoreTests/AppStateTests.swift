@testable import PortwatchCore
import Testing

struct AppStateTests {
    func loaded(_ services: [Service], excludes: Set<String> = []) -> AppState {
        var state = AppState()
        _ = state.apply(.excludesLoaded(excludes))
        _ = state.apply(.tickSucceeded(services))
        return state
    }

    let three = [service(1, "a", port: 3000), service(2, "b", port: 4000), service(3, "c", port: 5000)]

    @Test func firstTickSelectsFirstRow() {
        #expect(loaded(three).selectedKey == "1:3000")
    }

    @Test func emptyListHasNoSelection() {
        #expect(loaded([]).selectedKey == nil)
    }

    @Test func selectionSurvivesATickThatKeepsTheRow() {
        var state = loaded(three)
        _ = state.apply(.key(.char("j")))
        _ = state.apply(.tickSucceeded(three.reversed()))
        #expect(state.selectedKey == "2:4000")
    }

    @Test func selectionMovesToFirstRowWhenItsRowDisappears() {
        var state = loaded(three)
        _ = state.apply(.key(.char("j")))
        _ = state.apply(.tickSucceeded([three[0], three[2]]))
        #expect(state.selectedKey == "1:3000")
    }

    @Test func navigationWrapsBothWays() {
        var state = loaded(three)
        _ = state.apply(.key(.up))
        #expect(state.selectedKey == "3:5000")
        _ = state.apply(.key(.down))
        #expect(state.selectedKey == "1:3000")
        _ = state.apply(.key(.char("k")))
        #expect(state.selectedKey == "3:5000")
        _ = state.apply(.key(.char("j")))
        #expect(state.selectedKey == "1:3000")
    }

    @Test func rowsOfOneMultiPortProcessAreSelectedIndividually() {
        var state = loaded([service(7, "mysqld", port: 3306), service(7, "mysqld", port: 33060)])
        _ = state.apply(.key(.char("j")))
        #expect(state.selectedKey == "7:33060")
    }

    @Test func killNeedsConfirmationThenTargetsThePid() {
        var state = loaded(three)
        _ = state.apply(.key(.char("j")))
        #expect(state.apply(.key(.char("x"))).isEmpty)
        #expect(state.confirmingService?.pid == 2)
        #expect(state.apply(.key(.char("y"))) == [.kill(pid: 2)])
        #expect(state.confirmingKey == nil)
    }

    @Test func anyOtherKeyCancelsTheConfirmation() {
        var state = loaded(three)
        _ = state.apply(.key(.char("x")))
        #expect(state.apply(.key(.char("n"))).isEmpty)
        #expect(state.confirmingKey == nil)
    }

    @Test func qDoesNotQuitWhileConfirmingButCtrlCDoes() {
        var state = loaded(three)
        _ = state.apply(.key(.char("x")))
        #expect(state.apply(.key(.char("q"))).isEmpty)
        _ = state.apply(.key(.char("x")))
        #expect(state.apply(.key(.ctrlC)) == [.quit])
    }

    @Test func qQuits() {
        var state = loaded(three)
        #expect(state.apply(.key(.char("q"))) == [.quit])
    }

    @Test func excludingHidesTheProcessAndRequestsASave() {
        var state = loaded(three)
        let effects = state.apply(.key(.char("e")))
        #expect(effects == [.saveExcludes(["a"])])
        #expect(state.visibleServices.map(\.process) == ["b", "c"])
        #expect(state.selectedKey == "1:3000") // still selected until the next reconcile
    }

    @Test func excludedProcessesAreHiddenFromTheListOnLoad() {
        let state = loaded(three, excludes: ["a"])
        #expect(state.flatRows.map(\.process) == ["b", "c"])
        #expect(state.selectedKey == "2:4000")
    }

    @Test func showAllRevealsExcludedRowsAndEIncludesThemAgain() {
        var state = loaded(three, excludes: ["a"])
        _ = state.apply(.key(.char("a")))
        #expect(state.flatRows.count == 3)
        _ = state.apply(.key(.char("e"))) // selected row is "b"; excludes it too
        #expect(state.excludes == ["a", "b"])
        _ = state.apply(.key(.char("k"))) // onto "a" (excluded)
        #expect(state.apply(.key(.char("e"))) == [.saveExcludes(["b"])])
    }

    @Test func keysDoNothingOnAnEmptyList() {
        var state = loaded([])
        for key: Key in [.char("j"), .char("x"), .char("e"), .up] {
            #expect(state.apply(.key(key)).isEmpty)
        }
        #expect(state.confirmingKey == nil)
    }

    @Test func tickFailureShowsErrorButKeepsRows() {
        var state = loaded(three)
        _ = state.apply(.tickFailed("lsof gone"))
        #expect(state.error == "lsof gone")
        #expect(state.services.count == 3)
        _ = state.apply(.tickSucceeded(three))
        #expect(state.error == nil)
    }

    @Test func failuresSurfaceAsErrors() {
        var state = AppState()
        _ = state.apply(.killFailed("Operation not permitted"))
        #expect(state.error == "Kill failed: Operation not permitted")
        _ = state.apply(.saveFailed("disk full"))
        #expect(state.error == "Failed to save exclude list: disk full")
        _ = state.apply(.excludesLoadFailed("bad json"))
        #expect(state.error == "Failed to read exclude list: bad json")
    }
}
