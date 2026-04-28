// Reserved for Phase 5 — CoreML deployment of the NDT1 decoder (~1.3M params,
// h=1-2 attention heads, 6 layers, 128 hidden dim, 20ms binning, BC1S layout)
// with verified ANE residency. See REQUIREMENTS.md DEC-06 through DEC-12.

// Marker so the file has at least one declaration (SwiftPM linter quirk avoidance).
public enum CortexDecoder {
  public static let phase: Int = 1
}
