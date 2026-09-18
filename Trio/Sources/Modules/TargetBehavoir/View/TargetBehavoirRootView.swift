import SwiftUI
import Swinject

extension TargetBehavoir {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var showAutosensMaxAlert = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.highTemptargetRaisesSensitivity,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.highTempTargetRaisesSensitivityLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.highTempTargetRaisesSensitivityLabel,
                    miniHint: AlgorithmSettingHints.highTempTargetRaisesSensitivityMini(units: state.units),
                    verboseHint: AlgorithmSettingHints.highTempTargetRaisesSensitivityVerbose(units: state.units),
                    headerText: String(
                        localized: "Algorithmic Target Settings",
                        comment: "Section header on the Target Behavior screen grouping sensitivity-vs-target controls"
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: effectiveLowTTLowersSensBinding,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.lowTempTargetLowersSensitivityLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.lowTempTargetLowersSensitivityLabel,
                    miniHint: state.dosingMode == .basalTesting
                        ? String(localized: "Basal Testing is on. Low temp targets will not lower sensitivity.")
                        : AlgorithmSettingHints.lowTempTargetLowersSensitivityMini(units: state.units),
                    verboseHint: AlgorithmSettingHints.lowTempTargetLowersSensitivityVerbose(units: state.units)
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.sensitivityRaisesTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.sensitivityRaisesTargetLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.sensitivityRaisesTargetLabel,
                    miniHint: AlgorithmSettingHints.sensitivityRaisesTargetMini,
                    verboseHint: AlgorithmSettingHints.sensitivityRaisesTargetVerbose()
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.resistanceLowersTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.resistanceLowersTargetLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.resistanceLowersTargetLabel,
                    miniHint: AlgorithmSettingHints.resistanceLowersTargetMini,
                    verboseHint: AlgorithmSettingHints.resistanceLowersTargetVerbose()
                )

                SettingInputSection(
                    decimalValue: $state.halfBasalExerciseTarget,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.halfBasalExerciseTargetLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("halfBasalExerciseTarget"),
                    label: AlgorithmSettingHints.halfBasalExerciseTargetLabel,
                    miniHint: AlgorithmSettingHints.halfBasalExerciseTargetMini,
                    verboseHint: AlgorithmSettingHints.halfBasalExerciseTargetVerbose(units: state.units)
                )
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .alert(
                "Cannot Enable This Setting",
                isPresented: $showAutosensMaxAlert
            ) {
                // Alert button(s). For a single button:
                Button("Got it!", role: .cancel) {}
            } message: {
                Text(
                    "This feature cannot be enabled unless Algorithm Settings > Autosens > Autosens Max is set higher than 100%."
                )
            }
            .navigationTitle("Target Behavior")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }

        private var effectiveLowTTLowersSensBinding: Binding<Bool> {
            Binding(
                get: { state.autosensMax > 1 && state.lowTemptargetLowersSensitivity },
                set: { newValue in
                    if newValue, state.autosensMax <= 1 {
                        showAutosensMaxAlert = true
                    } else {
                        state.lowTemptargetLowersSensitivity = newValue
                    }
                }
            )
        }
    }
}
