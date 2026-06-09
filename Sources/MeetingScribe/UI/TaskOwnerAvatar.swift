import SwiftUI

/// Task-owner monogram (VD-6). Thin wrapper over the shared `MSAvatar` so the
/// table/board/calendar call sites stay unchanged while the avatar is defined
/// in exactly one place.
@available(macOS 14.0, *)
struct TaskOwnerAvatar: View {
    let name: String
    var size: CGFloat = 18

    var body: some View { MSAvatar(name: name, size: size) }
}
