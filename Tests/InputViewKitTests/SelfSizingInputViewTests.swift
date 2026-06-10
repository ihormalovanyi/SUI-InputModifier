import UIKit
import Testing
@testable import InputViewKit

@MainActor
struct SelfSizingInputViewTests {

    @Test func firesReloadOnlyOnDistinctHeight() {
        let view = SelfSizingInputView()
        var reloads = 0
        view.onSizeShouldReload = { reloads += 1 }

        view.setIdealContentHeight(120)
        #expect(reloads == 1)
        #expect(view.intrinsicContentSize.height == 120 + view.safeAreaInsets.bottom)

        view.setIdealContentHeight(120)      // same value — no-op
        #expect(reloads == 1)

        view.setIdealContentHeight(180)
        #expect(reloads == 2)
        #expect(view.intrinsicContentSize.height == 180 + view.safeAreaInsets.bottom)
    }

    @Test func clampsNegativeHeightToZero() {
        let view = SelfSizingInputView()
        var reloads = 0
        view.onSizeShouldReload = { reloads += 1 }

        view.setIdealContentHeight(-50)      // clamped to 0 == initial — no-op
        #expect(reloads == 0)
        #expect(view.intrinsicContentSize.height == view.safeAreaInsets.bottom)

        view.setIdealContentHeight(90)
        view.setIdealContentHeight(-1)       // clamped to 0 — distinct from 90
        #expect(view.intrinsicContentSize.height == view.safeAreaInsets.bottom)
        #expect(reloads == 2)
    }
}
