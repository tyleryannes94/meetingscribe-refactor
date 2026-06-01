import Foundation

/// Hardware-aware defaults so the local-AI stack fits the machine it's on
/// instead of a one-size model that's too big on 8 GB Macs and too small on
/// 64 GB ones. (C5-3)
enum HardwareProfile {
    static var physicalMemoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    static var performanceCoreCount: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    /// Recommended Ollama summarization model for this Mac's RAM. Conservative —
    /// errs toward a model that runs comfortably rather than the largest that
    /// might fit.
    static var recommendedSummaryModel: String {
        switch physicalMemoryGB {
        case ..<12:  return "qwen2.5:3b"
        case 12..<32: return "qwen2.5:7b"
        default:      return "qwen2.5:14b"
        }
    }

    /// A human-readable one-liner for the Settings hint.
    static var summary: String {
        "\(physicalMemoryGB) GB RAM · \(performanceCoreCount) cores → \(recommendedSummaryModel)"
    }
}
