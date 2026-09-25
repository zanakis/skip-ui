// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.runtime.Composable
import androidx.compose.ui.geometry.Rect
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGFloat
#endif

public struct SafeAreaRegions : OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let container = SafeAreaRegions(rawValue: 1)
    public static let keyboard = SafeAreaRegions(rawValue: 2)
    public static let all = SafeAreaRegions(rawValue: 3)
}

#if SKIP
import androidx.compose.ui.geometry.Rect

/// Track safe area.
struct SafeArea: Equatable, CustomStringConvertible {
    /// Total bounds of presentation root.
    let presentationBoundsPx: Rect

    /// Safe bounds of presentation root.
    let safeBoundsPx: Rect

    /// The edges whose safe area is solely due to system bars.
    let absoluteSystemBarEdges: Edge.Set

    /// How the safe bottom edge moves with the keyboard, if it does.
    ///
    /// The bounds hold where the bottom edges come to rest once any keyboard animation ends. While it runs, layout
    /// follows the live keyboard: see `followingKeyboard()` and `keyboardBottomInsetOffsetPx()`.
    let keyboardBottom: KeyboardTrackedEdge?

    init(presentation: Rect, safe: Rect, absoluteSystemBars: Edge.Set = [], keyboardBottom: KeyboardTrackedEdge? = nil) {
        self.presentationBoundsPx = presentation
        self.safeBoundsPx = safe
        self.absoluteSystemBarEdges = absoluteSystemBars
        self.keyboardBottom = keyboardBottom
    }

    /// Update the safe area.
    ///
    /// - Parameter keyboardBottom: How the new bottom edge moves with the keyboard, when insetting the bottom edge.
    @Composable func insetting(_ edge: Edge, to value: Float, keyboardBottom newKeyboardBottom: KeyboardTrackedEdge? = nil) -> SafeArea {
        guard value > Float(0.0) else {
            return self
        }
        var systemBarEdges = absoluteSystemBarEdges
        var (safeLeft, safeTop, safeRight, safeBottom) = safeBoundsPx
        var keyboardBottom = self.keyboardBottom
        switch edge {
        case .top:
            safeTop = value
            systemBarEdges.remove(.top)
        case .bottom:
            safeBottom = value
            systemBarEdges.remove(.bottom)
            keyboardBottom = newKeyboardBottom
        case .leading:
            safeLeft = value
            systemBarEdges.remove(.leading)
        case .trailing:
            safeRight = value
            systemBarEdges.remove(.trailing)
        }
        return SafeArea(presentation: presentationBoundsPx, safe: Rect(top: safeTop, left: safeLeft, bottom: safeBottom, right: safeRight), absoluteSystemBars: systemBarEdges, keyboardBottom: keyboardBottom)
    }

    /// This safe area with its bottom edges where the keyboard currently has them. Read in the layout phase or in
    /// callbacks.
    func followingKeyboard() -> SafeArea {
        guard let keyboardBottom else {
            return self
        }
        let presentationOffset = Float(keyboardBottom.presentationOffsetPx())
        let safeOffset = Float(keyboardBottom.offsetPx())
        guard presentationOffset != Float(0.0) || safeOffset != Float(0.0) else {
            return self
        }
        let presentation = Rect(left: presentationBoundsPx.left, top: presentationBoundsPx.top, right: presentationBoundsPx.right, bottom: presentationBoundsPx.bottom + presentationOffset)
        let safe = Rect(left: safeBoundsPx.left, top: safeBoundsPx.top, right: safeBoundsPx.right, bottom: safeBoundsPx.bottom + safeOffset)
        return SafeArea(presentation: presentation, safe: safe, absoluteSystemBars: absoluteSystemBarEdges, keyboardBottom: keyboardBottom)
    }

    /// How much the bottom inset currently differs from `presentationBoundsPx.bottom - safeBoundsPx.bottom` because of
    /// a keyboard animation. Read in the layout phase or in callbacks.
    func keyboardBottomInsetOffsetPx() -> Int {
        guard let keyboardBottom else {
            return 0
        }
        return keyboardBottom.presentationOffsetPx() - keyboardBottom.offsetPx()
    }

    var description: String {
        "SafeArea(presentationBoundsPx: \(presentationBoundsPx), safeBoundsPx: \(safeBoundsPx), absoluteSystemBarEdges: \(absoluteSystemBarEdges))"
    }
}

/// A bottom edge that moves with a presentation root's keyboard: the root's presentation or safe bottom edge, or the
/// top of bars pulled under the keyboard from one of those.
///
/// Only the live keyboard height is read at layout time. The keyboard's animation target and the system bars are the
/// values the presentation root composed its safe area with: Android delivers new insets after Compose's composition
/// and before its layout in the same frame, so reading them live here would pair them with a safe area composed from
/// the previous frame's values.
struct KeyboardTrackedEdge: Equatable {
    let keyboard: PresentationKeyboard
    let isPresentationEdge: Bool
    let pulledBarHeightsPx: [Int]
    /// The keyboard height the safe area was composed for.
    let targetImeBottomPx: Int
    /// The system bars' bottom inset the safe area was composed for.
    let systemBarsBottomPx: Int

    init(keyboard: PresentationKeyboard, isPresentationEdge: Bool, pulledBarHeightsPx: [Int] = [], targetImeBottomPx: Int, systemBarsBottomPx: Int) {
        self.keyboard = keyboard
        self.isPresentationEdge = isPresentationEdge
        self.pulledBarHeightsPx = pulledBarHeightsPx
        self.targetImeBottomPx = targetImeBottomPx
        self.systemBarsBottomPx = systemBarsBottomPx
    }

    /// The top edge of a bar of the given height that sits on this edge and is pulled under the keyboard.
    func pullingBar(heightPx: Int) -> KeyboardTrackedEdge {
        return KeyboardTrackedEdge(keyboard: keyboard, isPresentationEdge: isPresentationEdge, pulledBarHeightsPx: pulledBarHeightsPx + [heightPx], targetImeBottomPx: targetImeBottomPx, systemBarsBottomPx: systemBarsBottomPx)
    }

    /// This edge's keyboard as the presentation root's own presentation edge.
    func presentationEdge() -> KeyboardTrackedEdge {
        return KeyboardTrackedEdge(keyboard: keyboard, isPresentationEdge: true, targetImeBottomPx: targetImeBottomPx, systemBarsBottomPx: systemBarsBottomPx)
    }

    private func imeBottom(target: Bool) -> Int {
        return target ? targetImeBottomPx : keyboard.imeBottom()
    }

    private func rootImeBottom(target: Bool) -> Int {
        return keyboard.followsBottomEdge ? imeBottom(target: target) : 0
    }

    /// How far below its resting position the presentation root's bottom edge currently is while the keyboard animates.
    func presentationOffsetPx() -> Int {
        return rootImeBottom(target: true) - rootImeBottom(target: false)
    }

    /// How far above its keyboard-free position the edge is, or with `target` will be when the keyboard animation ends.
    func raisePx(target: Bool) -> Int {
        let rootIme = rootImeBottom(target: target)
        var raise: Int
        if isPresentationEdge {
            raise = rootIme
        } else {
            raise = max(rootIme, systemBarsBottomPx) - systemBarsBottomPx
        }
        if !pulledBarHeightsPx.isEmpty {
            let ime = imeBottom(target: target)
            for heightPx in pulledBarHeightsPx {
                raise -= min(heightPx, ime)
            }
        }
        return raise
    }

    /// How far below its resting position the edge currently is while the keyboard animates.
    func offsetPx() -> Int {
        return raisePx(target: true) - raisePx(target: false)
    }
}
#endif

extension View {
    @available(*, unavailable)
    public func safeAreaInset(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> any View) -> some View {
        return self
    }

    @available(*, unavailable)
    public func safeAreaInset(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> any View) -> some View {
        return self
    }

    @available(*, unavailable)
    public func safeAreaPadding(_ insets: EdgeInsets) -> some View {
        return self
    }

    @available(*, unavailable)
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        return self
    }

    @available(*, unavailable)
    public func safeAreaPadding(_ length: CGFloat) -> some View {
        return self
    }

    @available(*, unavailable)
    public func safeAreaBar(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        return self
    }

    @available(*, unavailable)
    public func safeAreaBar(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        return self
    }
}

#endif
