import AppIntents

extension WidgetLayout: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Layout" }
    static var caseDisplayRepresentations: [WidgetLayout: DisplayRepresentation] {
        [.balance: "Balance", .recovery: "Recovery", .schedule: "Schedule"]
    }
}

extension WidgetMetricChoice: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Primary metric" }
    static var caseDisplayRepresentations: [WidgetMetricChoice: DisplayRepresentation] {
        [
            .automatic: "Automatic",
            .readiness: "Readiness",
            .sleep: "Sleep",
            .steps: "Steps",
            .heart: "Resting heart rate",
            .nextEvent: "Next event"
        ]
    }
}

extension WidgetPrivacyMode: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Privacy" }
    static var caseDisplayRepresentations: [WidgetPrivacyMode: DisplayRepresentation] {
        [.discreet: "Discreet — hide health values and event titles", .showValues: "Show values — allow private values"]
    }
}

protocol PulseboardWidgetIntent: WidgetConfigurationIntent {
    var instanceConfiguration: WidgetInstanceConfiguration { get }
    static var defaultConfiguration: WidgetInstanceConfiguration { get }
}

struct HomeWidgetIntent: PulseboardWidgetIntent {
    static var title: LocalizedStringResource { "Pulseboard Home Screen" }
    static var description: IntentDescription {
        IntentDescription("Choose this widget's layout, primary metric, and privacy. Event titles also require permission in Pulseboard's Calendar settings.")
    }

    @Parameter(title: "Layout", default: .balance)
    var layout: WidgetLayout

    @Parameter(title: "Primary metric", default: .automatic)
    var primaryMetric: WidgetMetricChoice

    @Parameter(title: "Privacy", default: .showValues)
    var privacyMode: WidgetPrivacyMode

    static var defaultConfiguration: WidgetInstanceConfiguration { .homeDefault }

    var instanceConfiguration: WidgetInstanceConfiguration {
        WidgetInstanceConfiguration(layout: layout, primaryMetricID: primaryMetric.metricID, privacyMode: privacyMode)
    }
}

struct LockWidgetIntent: PulseboardWidgetIntent {
    static var title: LocalizedStringResource { "Pulseboard Lock Screen" }
    static var description: IntentDescription {
        IntentDescription("Discreet hides health values and event titles even while unlocked. Select Show values to opt in for this Lock Screen widget. Event titles also require permission in Pulseboard's Calendar settings.")
    }

    @Parameter(title: "Layout", default: .balance)
    var layout: WidgetLayout

    @Parameter(title: "Primary metric", default: .automatic)
    var primaryMetric: WidgetMetricChoice

    @Parameter(title: "Privacy", default: .discreet)
    var privacyMode: WidgetPrivacyMode

    static var defaultConfiguration: WidgetInstanceConfiguration { .lockDefault }

    var instanceConfiguration: WidgetInstanceConfiguration {
        WidgetInstanceConfiguration(layout: layout, primaryMetricID: primaryMetric.metricID, privacyMode: privacyMode)
    }
}
