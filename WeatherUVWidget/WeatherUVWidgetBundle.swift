import WidgetKit
import SwiftUI

@main
struct WeatherUVWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeatherUVWidget()          // Home Screen small
        WeatherUVAccessoryWidget() // Lock Screen circular / rectangular / inline
    }
}
