import SwiftUI

// MARK: - Overview
//
// `TextSelectionInteraction` manages the text selection model lifecycle for multiple `Text` fragments.
//
// Selection is opt-in through the `textSelection` environment value. When enabled, the modifier
// observes text layout changes via `overlayTextLayoutCollection` and creates or updates a
// `TextSelectionModel`. The model is then passed to the platform-specific implementation
// (`PlatformTextSelectionInteraction`), which presents the appropriate selection UI for macOS
// or iOS. This separation keeps model management in shared code while platform interactions
// remain independent.

struct TextSelectionInteraction: ViewModifier {
  #if TEXTUAL_ENABLE_TEXT_SELECTION
    @Environment(\.textSelection) private var textSelection
    @Environment(TextSelectionCoordinator.self) private var coordinator: TextSelectionCoordinator?

    @State private var model = TextSelectionModel()
    /// Coalesces the per-scroll-frame layout bursts into one model update.
    @State private var pendingLayoutUpdate: Task<Void, Never>?
  #endif

  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_TEXT_SELECTION
      if textSelection.allowsSelection {
        content
          .overlayTextLayoutCollection { layoutCollection in
            Color.clear
              .onChange(of: AnyTextLayoutCollection(layoutCollection), initial: true) {
                // With lazy layouts the collection changes on every scroll
                // frame; applying it synchronously re-enters the view-update
                // pass and stalls scrolling. Debounce: cancel the previous
                // pending update and apply only the latest collection after
                // the burst settles. Selection only needs the layout once
                // scrolling stops, so dropping intermediate frames is safe.
                pendingLayoutUpdate?.cancel()
                pendingLayoutUpdate = Task { @MainActor in
                  try? await Task.sleep(nanoseconds: 120_000_000)  // 120 ms
                  guard !Task.isCancelled else { return }
                  model.setCoordinator(coordinator)
                  model.setLayoutCollection(layoutCollection)
                }
              }
          }
          .modifier(PlatformTextSelectionInteraction(model: model))
      } else {
        content
      }
    #else
      content
    #endif
  }
}

#if TEXTUAL_ENABLE_TEXT_SELECTION
  extension EnvironmentValues {
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @usableFromInline
    @Entry var textSelection: any TextSelectability.Type = DisabledTextSelectability.self
  }
#endif
