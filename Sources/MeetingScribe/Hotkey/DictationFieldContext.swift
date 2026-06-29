import SwiftUI

/// Tracks which in-app text fields are currently focused that should ALWAYS
/// receive the cleaned-up ("polished") dictation transcript rather than the raw
/// whisper output — regardless of the global `dictationUsePolished` default.
///
/// Why: on the Brain Dump page and the Tasks quick-add input, dictated text is
/// fed straight into the local planner / task extractor. Handing the model
/// already-cleaned prose (filler words removed, punctuation fixed, sentences
/// joined) means less work and better extraction, so these fields opt into the
/// polished version unconditionally.
///
/// Fields register by a stable id on focus-gain and deregister on focus-loss
/// (and on disappear, so a field focused when its view is torn down doesn't
/// leave a stale entry). A `Set` rather than a single `Bool` makes focus
/// hand-offs between two registered fields order-independent.
@MainActor
final class DictationFieldContext {
    static let shared = DictationFieldContext()
    private init() {}

    private var focusedPolishedFields = Set<String>()

    /// Register/deregister `id` as a focused always-polished field.
    func setFocused(_ id: String, _ focused: Bool) {
        if focused { focusedPolishedFields.insert(id) }
        else { focusedPolishedFields.remove(id) }
    }

    /// True while at least one "always-polished" field is focused — read by the
    /// dictation pipeline at record-start to force the polished transcript.
    var preferPolished: Bool { !focusedPolishedFields.isEmpty }
}

@available(macOS 14.0, *)
extension View {
    /// Marks a focusable text field as one that should always receive the
    /// polished dictation transcript. Pass the field's current focus value and
    /// a stable, instance-unique id. Cleans up on disappear.
    func dictationPrefersPolished(id: String, focused: Bool) -> some View {
        self
            .onChange(of: focused) { DictationFieldContext.shared.setFocused(id, $0) }
            .onDisappear { DictationFieldContext.shared.setFocused(id, false) }
    }
}
