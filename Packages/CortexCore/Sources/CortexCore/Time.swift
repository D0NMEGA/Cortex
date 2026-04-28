// Monotonic time source backed by mach_absolute_time(). Required-reason API usage
// is declared in PrivacyInfo.xcprivacy with reason code CA92.1
// (NSPrivacyAccessedAPICategorySystemBootTime — "Approximate time interval").
//
// Source: cortex-spec.md (latency measurement); RESEARCH.md Q5 (CA92.1 reason).

import Foundation

public enum Time {
  /// Returns a monotonic nanosecond-resolution timestamp suitable for elapsed-interval
  /// measurement. Backed by mach_absolute_time() under the hood.
  public static func machAbsoluteNanoseconds() -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let raw = mach_absolute_time()
    // Convert mach ticks to nanoseconds.
    return raw &* UInt64(info.numer) / UInt64(info.denom)
  }
}
