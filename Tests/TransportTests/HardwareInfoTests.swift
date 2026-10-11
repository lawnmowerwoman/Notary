import NotaryCore

enum HardwareInfoTests {
    static func run() {
        for model in ["Mac17,7", "Mac14,6", "MacBookPro18,3", "MacBookAir10,1"] {
            expect(HardwareInfo.classifyFormFactor(model: model, hasBuiltInLid: true) == .notebook,
                   "notebook with built-in lid: \(model)")
        }
        expect(HardwareInfo.classifyFormFactor(model: "MacBookPro16,1", hasBuiltInLid: nil) == .notebook,
               "legacy notebook fallback")
        expect(HardwareInfo.classifyFormFactor(model: "Mac16,11", hasBuiltInLid: false) == .desktop,
               "modern desktop with no lid")
        expect(HardwareInfo.classifyFormFactor(model: "iMac20,2", hasBuiltInLid: nil) == .desktop,
               "legacy desktop fallback")
        for model in [nil, "", "Mac17,7"] as [String?] {
            expect(HardwareInfo.classifyFormFactor(model: model, hasBuiltInLid: nil) == .unknown,
                   "failed detection must not imply desktop")
        }
        print("Hardware form-factor tests passed (local: \(HardwareInfo.formFactor()))")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "Hardware detection regression: \(message)")
    }
}
