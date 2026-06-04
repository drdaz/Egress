//
//  CustomProviderEditorTests.swift
//  EgressTests
//
//  The picker + editor UI flow: the provider choice list (incl. "Add Custom"),
//  the conditional-display mapping from a choice to an editor mode, and the
//  editor model's range/name handling.
//

import Foundation
import Testing
@testable import Egress

// MARK: - Editor: provider choices (picker incl. "Add Custom")

struct ProviderChoiceItemsTests {

    @Test func defaultListsBuiltinsThenAddCustom() {
        let items = AppConfig.default.providerChoiceItems
        #expect(items.map(\.choice) == [
            .selection(.builtin(.mullvad)),
            .selection(.builtin(.airvpn)),
            .selection(.builtin(.ivpn)),
            .addCustom,
        ])
        #expect(items.last?.label == "Add Custom…")
    }

    @Test func customProvidersAppearBeforeAddCustom() {
        let home = CustomProvider(name: "Home", ranges: ["1.2.3.4"])
        let config = AppConfig(customProviders: [home], selection: .builtin(.mullvad))
        let items = config.providerChoiceItems
        #expect(items.map(\.choice) == [
            .selection(.builtin(.mullvad)),
            .selection(.builtin(.airvpn)),
            .selection(.builtin(.ivpn)),
            .selection(.custom(home.id)),
            .addCustom,
        ])
    }
}

// MARK: - Editor: conditional-display mapping

struct ProviderEditorModeTests {

    @Test func builtinSelectionHidesEditor() {
        #expect(ProviderEditorMode(choice: .selection(.builtin(.mullvad))) == .hidden)
    }

    @Test func customSelectionEditsThatProvider() {
        let id = UUID()
        #expect(ProviderEditorMode(choice: .selection(.custom(id))) == .editing(id))
    }

    @Test func addCustomCreatesNew() {
        #expect(ProviderEditorMode(choice: .addCustom) == .creating)
    }
}

// MARK: - Editor: model behaviour

@MainActor
struct CustomProviderEditorModelTests {

    @Test func addsValidHostAndCIDR() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "203.0.113.7"; m.addRange()
        m.rangeInput = "10.0.0.0/8"; m.addRange()
        #expect(m.ranges == ["203.0.113.7", "10.0.0.0/8"])
        #expect(m.rangeInput == "")
        #expect(m.rangeInputError == nil)
    }

    @Test func trimsWhitespaceWhenAdding() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "  1.2.3.4 "; m.addRange()
        #expect(m.ranges == ["1.2.3.4"])
    }

    @Test func rejectsInvalidRange() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "not-an-ip"; m.addRange()
        #expect(m.ranges.isEmpty)
        #expect(m.rangeInputError != nil)
        #expect(m.rangeInput == "not-an-ip")   // input kept so the user can fix it
    }

    @Test func rejectsMalformedCIDR() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "10.0.0.0/99"; m.addRange()
        #expect(m.ranges.isEmpty)
        #expect(m.rangeInputError != nil)
    }

    @Test func ignoresEmptyInput() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "   "; m.addRange()
        #expect(m.ranges.isEmpty)
        #expect(m.rangeInputError == nil)
    }

    @Test func rejectsDuplicateRange() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "1.2.3.4"; m.addRange()
        m.rangeInput = "1.2.3.4"; m.addRange()
        #expect(m.ranges == ["1.2.3.4"])
        #expect(m.rangeInputError != nil)
    }

    @Test func removesRange() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "1.2.3.4"; m.addRange()
        m.rangeInput = "5.6.7.8"; m.addRange()
        m.removeRange(at: IndexSet(integer: 0))
        #expect(m.ranges == ["5.6.7.8"])
    }

    @Test func removesRangeByValue() {
        let m = CustomProviderEditorModel()
        m.rangeInput = "1.2.3.4"; m.addRange()
        m.rangeInput = "5.6.7.8"; m.addRange()
        m.removeRange("1.2.3.4")
        #expect(m.ranges == ["5.6.7.8"])
    }

    @Test func canSaveRequiresNameAndRanges() {
        let m = CustomProviderEditorModel()
        #expect(m.canSave == false)
        m.name = "Home"
        #expect(m.canSave == false)            // no ranges yet
        m.rangeInput = "1.2.3.4"; m.addRange()
        #expect(m.canSave == true)
        m.name = "   "
        #expect(m.canSave == false)            // whitespace-only name
    }

    @Test func newDraftHasFreshIDAndTrimmedName() {
        let m = CustomProviderEditorModel()
        m.startNew()
        m.name = "  Home  "
        m.rangeInput = "1.2.3.4"; m.addRange()
        let draft = m.makeDraft()
        #expect(draft.name == "Home")
        #expect(draft.ranges == ["1.2.3.4"])
    }

    @Test func editingDraftPreservesID() {
        let existing = CustomProvider(name: "Office", ranges: ["10.0.0.0/8"])
        let m = CustomProviderEditorModel()
        m.populate(with: existing)
        m.name = "Office HQ"
        let draft = m.makeDraft()
        #expect(draft.id == existing.id)
        #expect(draft.name == "Office HQ")
        #expect(draft.ranges == ["10.0.0.0/8"])
    }
}
