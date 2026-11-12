import Foundation

public enum TimeFormat {
    /// "1:05.3" (with tenths) or "1:05".
    public static func string(_ seconds: Double, tenths: Bool = true) -> String {
        let value = seconds.isFinite && seconds > 0 ? seconds : 0
        if tenths {
            let totalTenths = Int((value * 10).rounded())
            let minutes = totalTenths / 600
            let secs = (totalTenths % 600) / 10
            let tenth = totalTenths % 10
            return "\(minutes):\(pad(secs)).\(tenth)"
        } else {
            let total = Int(value.rounded(.down))
            return "\(total / 60):\(pad(total % 60))"
        }
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
