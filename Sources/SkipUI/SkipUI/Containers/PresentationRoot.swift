// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if SKIP
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imeAnimationTarget
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.offset

/// The root of a presentation, such as the root presentation or a sheet.
@Composable public func PresentationRoot(defaultColorScheme: ColorScheme? = nil, absoluteSystemBarEdges systemBarEdges: Edge.Set = .all, depth: Int = 0, context: ComposeContext, content: @Composable (ComposeContext) -> Void) {
    launchUIApplicationActivity()

    let preferredColorScheme = rememberSaveable(stateSaver: context.stateSaver as! Saver<Preference<PreferredColorScheme>, Any>) { mutableStateOf(Preference<PreferredColorScheme>(key: PreferredColorSchemePreferenceKey.self)) }
    let preferredColorSchemeCollector = PreferenceCollector<PreferredColorScheme>(key: PreferredColorSchemePreferenceKey.self, state: preferredColorScheme)
    PreferenceValues.shared.collectPreferences([preferredColorSchemeCollector]) {
        let materialColorScheme = preferredColorScheme.value.reduced.colorScheme?.asMaterialTheme() ?? defaultColorScheme?.asMaterialTheme() ?? MaterialTheme.colorScheme
        MaterialTheme(colorScheme: materialColorScheme) {
            // Recording the bounds the root would have without the keyboard keeps the per-frame keyboard animation out of
            // composition: the safe area follows the keyboard's animation target and layout tracks its live position
            let keyboardFreeBounds = remember { mutableStateOf(Rect.Zero) }
            let density = LocalDensity.current
            let layoutDirection = LocalLayoutDirection.current
            let covered = ModalPresentationRegistry.shared.isCovered(depth: depth)
            let keyboard = rememberPresentationKeyboard()
            keyboard.isCovered = covered
            keyboard.followsBottomEdge = systemBarEdges.contains(.bottom)
            var rootModifier = Modifier
                .background(androidx.compose.ui.graphics.Color.Black)
                .fillMaxSize()
            if systemBarEdges.contains(.leading) {
                rootModifier = rootModifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Start))
            }
            if systemBarEdges.contains(.trailing) {
                rootModifier = rootModifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.End))
            }
            if systemBarEdges.contains(.bottom) && !covered {
                rootModifier = rootModifier.imePadding()
            }
            rootModifier = rootModifier.background(Color.background.colorImpl())
                .onGloballyPositionedInWindow {
                    keyboardFreeBounds.value = Rect(left: $0.left, top: $0.top, right: $0.right, bottom: $0.bottom + Float(keyboard.rootImeBottom()))
                }
            Box(modifier: rootModifier) {
                guard keyboardFreeBounds.value != Rect.Zero else {
                    return
                }
                let targetImeBottom = keyboard.targetImeBottom()
                let rootTargetImeBottom = keyboard.followsBottomEdge ? targetImeBottom : 0
                let systemBarsBottom = keyboard.systemBarsBottom()
                let presentationBounds = Rect(left: keyboardFreeBounds.value.left, top: keyboardFreeBounds.value.top, right: keyboardFreeBounds.value.right, bottom: keyboardFreeBounds.value.bottom - Float(rootTargetImeBottom))
                // Cannot get accurate WindowInsets until we're in the content box. We only check top and bottom
                // because we've padded the content to within horizontal safe insets already, mirroring standard
                // Android app behavior like e.g. Settings
                var (safeLeft, safeTop, safeRight, safeBottom) = presentationBounds
                if systemBarEdges.contains(.top) {
                    safeTop += WindowInsets.systemBars.union(WindowInsets.displayCutout).getTop(density)
                }
                if systemBarEdges.contains(.bottom) {
                    safeBottom -= max(0, systemBarsBottom - rootTargetImeBottom)
                }
                let safeBounds = Rect(left: safeLeft, top: safeTop, right: safeRight, bottom: safeBottom)
                let safeArea = SafeArea(presentation: presentationBounds, safe: safeBounds, absoluteSystemBars: systemBarEdges, keyboardBottom: KeyboardTrackedEdge(keyboard: keyboard, isPresentationEdge: false, targetImeBottomPx: targetImeBottom, systemBarsBottomPx: systemBarsBottom))
                EnvironmentValues.shared.setValues {
                    // Detect whether the app is edge to edge mode based on whether we're padding horizontally (landscape)
                    // or we have a top/bttom safe area (portrait)
                    if $0._isEdgeToEdge == nil {
                        $0.set_isEdgeToEdge(safeBounds != presentationBounds)
                    }
                    $0.set_safeArea(safeArea)
                    // A presentation is a new layout root: scroll axes inherited from the presenting
                    // context (e.g. a sheet presented from a button inside a ScrollView) must not
                    // leak in. Otherwise expanding content in the presentation is sized with
                    // IntrinsicSize as if it were in the presenter's scroll direction, which crashes
                    // when that content contains a lazy container: intrinsic measurement of
                    // SubcomposeLayout-based components is unsupported in Compose
                    $0.set_layoutScrollAxes(Axis.Set(rawValue: 0))
                    $0.set_scrollAxes(Axis.Set(rawValue: 0))
                    return ComposeResult.ok
                } in: {
                    // SKIP INSERT: val providedPresentationDepth = LocalPresentationDepth provides depth
                    // SKIP INSERT: val providedPresentationKeyboard = LocalPresentationKeyboard provides keyboard
                    CompositionLocalProvider(providedPresentationDepth, providedPresentationKeyboard) {
                        Box(modifier: Modifier.fillMaxSize().padding(safeArea), contentAlignment = androidx.compose.ui.Alignment.Center) {
                            content(context)
                        }
                    }
                }
            }
        }
    }
}

/// The keyboard as seen by a presentation root. Read it in the layout phase or in callbacks, where the per-frame
/// keyboard animation does not cause recomposition.
final class PresentationKeyboard: Equatable {
    private let density: Density
    private let ime: WindowInsets
    private let imeTarget: WindowInsets
    private let systemBars: WindowInsets
    /// Whether a modal covers the presentation, which then ignores the keyboard.
    var isCovered = false
    /// Whether the presentation root pads its bottom edge by the keyboard.
    var followsBottomEdge = false

    init(density: Density, ime: WindowInsets, imeTarget: WindowInsets, systemBars: WindowInsets) {
        self.density = density
        self.ime = ime
        self.imeTarget = imeTarget
        self.systemBars = systemBars
    }

    /// The keyboard height.
    func imeBottom() -> Int {
        guard !isCovered else {
            return 0
        }
        return ime.getBottom(density)
    }

    /// The keyboard height the presentation root pads its bottom edge by.
    func rootImeBottom() -> Int {
        return followsBottomEdge ? imeBottom() : 0
    }

    /// The keyboard height the current keyboard animation ends at. Read it only to compose a safe area, and use the
    /// safe area's `KeyboardTrackedEdge` in layout.
    func targetImeBottom() -> Int {
        guard !isCovered else {
            return 0
        }
        return imeTarget.getBottom(density)
    }

    func systemBarsBottom() -> Int {
        return systemBars.getBottom(density)
    }

    static func ==(lhs: PresentationKeyboard, rhs: PresentationKeyboard) -> Bool {
        return lhs === rhs
    }
}

let LocalPresentationKeyboard: ProvidableCompositionLocal<PresentationKeyboard?> = staticCompositionLocalOf { nil }

/// The enclosing presentation root's keyboard, or a keyboard that no presentation root pads for.
@Composable func currentPresentationKeyboard() -> PresentationKeyboard {
    return LocalPresentationKeyboard.current ?? rememberPresentationKeyboard()
}

// SKIP INSERT: @OptIn(ExperimentalLayoutApi::class)
@Composable func rememberPresentationKeyboard() -> PresentationKeyboard {
    let density = LocalDensity.current
    let ime = WindowInsets.ime
    let imeTarget = WindowInsets.imeAnimationTarget
    let systemBars = WindowInsets.systemBars.union(WindowInsets.displayCutout)
    return remember(density) { PresentationKeyboard(density: density, ime: ime, imeTarget: imeTarget, systemBars: systemBars) }
}

extension Modifier {
    /// Report a height reduced by as much of the content as the keyboard covers, letting the keyboard slide over
    /// the content as it rises from the bottom edge.
    func pulledUnderKeyboard(_ keyboard: PresentationKeyboard) -> Modifier {
        return self.layout { measurable, constraints in
            let placeable = measurable.measure(constraints)
            let pull = min(placeable.height, keyboard.imeBottom())
            return layout(width: placeable.width, height: max(constraints.minHeight, placeable.height - pull)) {
                placeable.place(x: 0, y: 0)
            }
        }
    }

    /// Pad the bottom by a length that is read in the layout phase.
    func paddingBottom(px: () -> Int) -> Modifier {
        return self.layout { measurable, constraints in
            let bottom = max(0, px())
            let placeable = measurable.measure(constraints.offset(vertical: -bottom))
            return layout(width: placeable.width, height: constraints.constrainHeight(placeable.height + bottom)) {
                placeable.place(x: 0, y: 0)
            }
        }
    }

    /// Set the height to a length that is read in the layout phase.
    func height(px: () -> Int) -> Modifier {
        return self.layout { measurable, constraints in
            let height = constraints.constrainHeight(max(0, px()))
            let placeable = measurable.measure(constraints.copy(minHeight: height, maxHeight: height))
            return layout(width: placeable.width, height: height) {
                placeable.place(x: 0, y: 0)
            }
        }
    }
}

@Composable func launchUIApplicationActivity() {
    // Modern Skip projects will set the launch activity in Main.kt. This function exists for older projects
    var context: Context? = LocalContext.current
    var activity: ComponentActivity? = nil
    while context != nil {
        if let a = context as? ComponentActivity {
            activity = a
            break
        } else if let w = context as? ContextWrapper {
            context = w.baseContext
        } else {
            break
        }
    }
    if let activity {
        UIApplication.launch(activity)
    }
}

#endif
