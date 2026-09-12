import Testing
import SwiftUI
@testable import Tract

/// The paper is document content: picking one has to reach the autosave, and it
/// has to leave the ink visible on the sheet the user just chose.
@Suite("Canvas paper styles")
@MainActor
struct CanvasBackgroundStyleTests {

    @Test("A new canvas starts on the dot grid")
    func defaultPaperIsDots() {
        #expect(CanvasViewModel().backgroundStyle == .dots)
    }

    @Test("Picking a paper records an edit so it is autosaved")
    func pickingPaperRecordsAnEdit() {
        let viewModel = CanvasViewModel()
        let revisionBefore = viewModel.revision

        viewModel.selectBackgroundStyle(.blueprint)

        #expect(viewModel.backgroundStyle == .blueprint)
        #expect(viewModel.revision > revisionBefore)
    }

    @Test("Re-picking the paper already in use writes nothing")
    func repickingTheSamePaperIsNotAnEdit() {
        let viewModel = CanvasViewModel()
        viewModel.selectBackgroundStyle(.ruled)
        let revisionAfterFirstPick = viewModel.revision

        viewModel.selectBackgroundStyle(.ruled)

        #expect(viewModel.revision == revisionAfterFirstPick)
    }

    @Test("Default black ink turns white on blueprint, and back on a pale sheet")
    func inkFollowsTheSheetBetweenDefaults() {
        let viewModel = CanvasViewModel()

        viewModel.selectBackgroundStyle(.blueprint)
        #expect(viewModel.strokeColor == InkColor.white)

        viewModel.selectBackgroundStyle(.legalPad)
        #expect(viewModel.strokeColor == InkColor.black)
    }

    @Test("A colour the user picked themselves survives a paper change")
    func chosenInkIsNotOverridden() {
        let viewModel = CanvasViewModel()
        viewModel.selectInkColor(InkColor.red)

        viewModel.selectBackgroundStyle(.blueprint)

        #expect(viewModel.strokeColor == InkColor.red)
    }

    @Test("Restoring a document puts its paper back")
    func restoreAppliesStoredPaper() {
        let viewModel = CanvasViewModel()
        viewModel.restore(strokes: [], outline: ProblemOutline(), origin: .zero, scale: 1,
                          background: .grid)

        #expect(viewModel.backgroundStyle == .grid)
        // A restore is a load, not an edit — it must not dirty the document.
        #expect(viewModel.revision == 0)
    }

    @Test("Only the blueprint sheet is dark enough to need light ink")
    func onlyBlueprintNeedsLightInk() {
        let needingLightInk = CanvasBackgroundStyle.allCases.filter(\.needsLightInk)
        #expect(needingLightInk == [.blueprint])
    }

    @Test("Every paper has a name and a sheet colour for its swatch")
    func everyPaperIsPresentable() {
        for style in CanvasBackgroundStyle.allCases {
            #expect(!style.displayName.isEmpty)
            #expect(style.sheetUIColor.cgColor.alpha > 0)
        }
    }
}
