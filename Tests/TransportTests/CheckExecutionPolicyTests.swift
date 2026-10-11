import NotaryCore

enum CheckExecutionPolicyTests {
    static func run() {
        expect(CheckExecutionPriority.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5], "unique scheduling priorities")
        expect(CheckExecutionPriority.everyTenMinutes.fixedIntervalSeconds == 600, "ten-minute interval")
        expect(CheckExecutionPriority.hourly.fixedIntervalSeconds == 3600, "hourly interval")
        expect(CheckExecutionPriority.daily.fixedIntervalSeconds == 86400, "daily interval")
        for priority in [CheckExecutionPriority.realtime, .configuredInterval, .serviceStart] {
            expect(priority.fixedIntervalSeconds == nil, "no invented fixed interval")
        }
        let policies = CheckExecutionCatalog.policyByKeyPath()
        expect(policies.count == CheckIssueCatalog.all().count, "all registry entries carry scheduling metadata")
        for key in ["CoreSecurity.CheckSIPStatus", "CoreSecurity.CheckARStatus"] {
            expect(policies[key]?.priority == .serviceStart, "boot-bound checks run per service start")
            expect(policies[key]?.failure.retryCadence == .everySchedulerTick, "failed start read retries")
        }
        let xprotect = policies["CoreSecurity.UpdateXProtect"]
        expect(xprotect?.priority == .hourly, "XProtect hourly")
        expect(xprotect?.failure.retryCadence == .interval(seconds: 300), "XProtect retries every five minutes")
        expect(xprotect?.failure.previousResultRetentionSeconds == 3600, "XProtect one-hour grace")
        expect(policies["CoreSecurity.CheckFileVaultStatus"] == CheckExecutionPolicy(), "unassigned checks retain configured interval")
        expect(CheckExecutionPolicy().failure.previousResultRetentionSeconds == nil, "no implicit result grace")
        print("Check execution policy tests passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "Check execution policy regression: \(message)")
    }
}
