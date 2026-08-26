import Foundation

package enum NotaryBuildCapabilities {
    #if NOTARY_CONFIDENTIAL_REPORTER
    package static let hasReporter = true
    #else
    package static let hasReporter = false
    #endif

    package static let hasConfigurator = true
}
