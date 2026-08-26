import AppTokenKit
import Foundation

package enum NotaryTokenFeature {
    package static let transport = AppTokenDefaults.transporterFeature
    package static let reporter = AppTokenDefaults.reporterFeature
    package static let configurator = AppTokenDefaults.configuratorFeature
}
