// WebgridView — the SwiftUI-embeddable Metal surface that hosts the `CAMetalLayer` + the platform
// display-link adapter, so the app targets (CortexiOS / CortexMac) render the 30×30 webgrid by
// dropping `WebgridView(ring:)` into their view tree (Plan 03).
//
// One representable per platform over the SAME shared core: iOS is a `UIViewRepresentable` backed by
// a `CAMetalLayer`-`layerClass` `UIView` driving an `iOSDisplayLinkAdapter`; macOS is an
// `NSViewRepresentable` backed by a layer-hosting `NSView` driving a `MacDisplayLinkAdapter`. Only
// the host view + adapter differ; both feed the SAME `WebgridFrameEncoder` via the SAME
// `CursorIntegrator`/`VelocityRing` (D-03/D-04).
//
// ## Producer ownership (SPSC discipline)
// `WebgridView` is the CONSUMER side: it takes a caller-supplied `VelocityRing` and the
// display-link callback `pop`s it. The HOST (the app's `ContentView`) owns the single PRODUCER —
// a `LissajousProducer` push loop on one thread — so the SPSC invariant (exactly one producer
// thread, exactly one consumer thread) holds: the producer is the host loop, the consumer is the
// display-link callback. The view never pushes.

import Metal
import os
import QuartzCore
import SwiftUI

#if os(iOS)
  import UIKit

  /// A `UIView` whose backing layer IS a `CAMetalLayer` (via `layerClass`) — the cleanest way to host
  /// a Metal layer at full size with automatic resize, no manual frame syncing.
  public final class WebgridMetalUIView: UIView {
    override public static var layerClass: AnyClass {
      CAMetalLayer.self
    }

    /// The backing `CAMetalLayer` (guaranteed by `layerClass`).
    public var metalLayer: CAMetalLayer {
      // `layerClass` above returns `CAMetalLayer.self`, so UIKit always makes the backing layer one.
      // Trap with the reason instead of a bare `as!`.
      guard let metal = layer as? CAMetalLayer else {
        preconditionFailure("layerClass returns CAMetalLayer.self, so the backing layer is always one")
      }
      return metal
    }

    /// Keep `drawableSize` in step with the view's pixel size.
    ///
    /// `CAMetalLayer` does NOT track its bounds reliably, so without this the kernel receives a
    /// viewport extent that disagrees with the layer's on-screen size and its letterboxed square is
    /// scaled non-uniformly - square cells render as rectangles.
    override public func layoutSubviews() {
      super.layoutSubviews()
      let scale = window?.screen.nativeScale ?? metalLayer.contentsScale
      metalLayer.contentsScale = scale
      let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
      guard pixels.width > 0, pixels.height > 0, metalLayer.drawableSize != pixels else { return }
      metalLayer.drawableSize = pixels
    }
  }

  /// SwiftUI host for the iOS webgrid surface. Drop into a view tree; pass the `VelocityRing` the
  /// host's producer pushes into.
  public struct WebgridView: UIViewRepresentable {
    private let ring: VelocityRing
    private let targets: TargetChannel?
    private let selection: SelectionChannel?
    private let cursorPositions: CursorPositionChannel?
    private let lattice: GridLattice
    /// Half-extent of the drawn target = the radius the run is SCORED at, so what a viewer
    /// sees inside the square is what the dwell criterion accepts.
    private let targetHalfExtent: Float
    private let board: Board
    private let log = Logger(subsystem: "app.cortex.render", category: "WebgridView")

    /// - Parameter ring: the SPSC ring the host's single producer pushes into; the display-link
    ///   callback (consumer) pops it each frame.
    public init(
      ring: VelocityRing,
      targets: TargetChannel? = nil,
      selection: SelectionChannel? = nil,
      cursorPositions: CursorPositionChannel? = nil,
      lattice: GridLattice = .uniform30,
      targetHalfExtent: Float = 0.5 / 30.0,
      board: Board = .wholeGrid
    ) {
      self.ring = ring
      self.targets = targets
      self.selection = selection
      self.cursorPositions = cursorPositions
      self.lattice = lattice
      self.targetHalfExtent = targetHalfExtent
      self.board = board
    }

    public func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    public func makeUIView(context: Context) -> WebgridMetalUIView {
      let view = WebgridMetalUIView()
      guard let device = MTLCreateSystemDefaultDevice() else {
        log.error("no Metal device; webgrid surface inert")
        return view
      }
      let metalLayer = view.metalLayer
      MetalLayerConfig.configure(metalLayer, device: device)
      do {
        let adapter = try iOSDisplayLinkAdapter(
          layer: metalLayer,
          device: device,
          ring: ring,
          targets: targets,
          selection: selection,
          cursorPositions: cursorPositions,
          lattice: lattice,
          targetHalfExtent: targetHalfExtent,
          board: board
        )
        adapter.start()
        context.coordinator.adapter = adapter
      } catch {
        log.error("failed to start iOS display-link adapter: \(String(describing: error))")
      }
      return view
    }

    public func updateUIView(_: WebgridMetalUIView, context _: Context) {
      // The layer resizes with the view automatically (layerClass-backed). Nothing per-update.
    }

    public static func dismantleUIView(_: WebgridMetalUIView, coordinator: Coordinator) {
      coordinator.adapter?.stop()
      coordinator.adapter = nil
    }

    /// Retains the adapter for the view's lifetime (the representable struct itself is transient).
    @MainActor
    public final class Coordinator {
      var adapter: iOSDisplayLinkAdapter?
      public init() {}
    }
  }
#endif

#if os(macOS)
  import AppKit

  /// A layer-hosting `NSView` backed by a `CAMetalLayer` — `wantsLayer = true` + a `CAMetalLayer`
  /// backing layer, the AppKit analogue of the iOS `layerClass` host.
  public final class WebgridMetalNSView: NSView {
    override public func makeBackingLayer() -> CALayer {
      CAMetalLayer()
    }

    /// The backing `CAMetalLayer` (guaranteed by `makeBackingLayer`).
    public var metalLayer: CAMetalLayer {
      // `makeBackingLayer` returns a `CAMetalLayer`, so the backing layer is always one. Trap with
      // the reason instead of a bare `as!`.
      guard let metal = layer as? CAMetalLayer else {
        preconditionFailure("makeBackingLayer returns a CAMetalLayer, so the backing layer is always one")
      }
      return metal
    }

    override public init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError("init(coder:) is not used")
    }

    /// Keep `drawableSize` in step with the view's pixel size.
    ///
    /// `CAMetalLayer` does NOT track its bounds reliably, so without this the kernel receives a
    /// viewport extent that disagrees with the layer's on-screen size and its letterboxed square is
    /// scaled non-uniformly - square cells render as rectangles. It shows up the moment the view stops
    /// being the full window (a caption below it, a second pane beside it).
    override public func layout() {
      super.layout()
      updateDrawableSize()
    }

    override public func viewDidChangeBackingProperties() {
      super.viewDidChangeBackingProperties()
      updateDrawableSize()
    }

    private func updateDrawableSize() {
      let scale = window?.backingScaleFactor ?? metalLayer.contentsScale
      metalLayer.contentsScale = scale
      let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
      // A zero extent happens during teardown and before first layout; writing it would invalidate the
      // drawable for no gain.
      guard pixels.width > 0, pixels.height > 0, metalLayer.drawableSize != pixels else { return }
      metalLayer.drawableSize = pixels
    }
  }

  /// SwiftUI host for the macOS webgrid surface. Drop into a view tree; pass the `VelocityRing` the
  /// host's producer pushes into.
  public struct WebgridView: NSViewRepresentable {
    private let ring: VelocityRing
    private let targets: TargetChannel?
    private let selection: SelectionChannel?
    private let cursorPositions: CursorPositionChannel?
    private let lattice: GridLattice
    /// Half-extent of the drawn target = the radius the run is SCORED at, so what a viewer
    /// sees inside the square is what the dwell criterion accepts.
    private let targetHalfExtent: Float
    private let board: Board
    private let log = Logger(subsystem: "app.cortex.render", category: "WebgridView")

    /// - Parameter ring: the SPSC ring the host's single producer pushes into; the display-link
    ///   callback (consumer) pops it each frame.
    public init(
      ring: VelocityRing,
      targets: TargetChannel? = nil,
      selection: SelectionChannel? = nil,
      cursorPositions: CursorPositionChannel? = nil,
      lattice: GridLattice = .uniform30,
      targetHalfExtent: Float = 0.5 / 30.0,
      board: Board = .wholeGrid
    ) {
      self.ring = ring
      self.targets = targets
      self.selection = selection
      self.cursorPositions = cursorPositions
      self.lattice = lattice
      self.targetHalfExtent = targetHalfExtent
      self.board = board
    }

    public func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    public func makeNSView(context: Context) -> WebgridMetalNSView {
      let view = WebgridMetalNSView(frame: .zero)
      guard let device = MTLCreateSystemDefaultDevice() else {
        log.error("no Metal device; webgrid surface inert")
        return view
      }
      let metalLayer = view.metalLayer
      MetalLayerConfig.configure(metalLayer, device: device)
      do {
        let adapter = try MacDisplayLinkAdapter(
          layer: metalLayer,
          device: device,
          ring: ring,
          targets: targets,
          selection: selection,
          cursorPositions: cursorPositions,
          lattice: lattice,
          targetHalfExtent: targetHalfExtent,
          board: board
        )
        adapter.start(in: view)
        context.coordinator.adapter = adapter
      } catch {
        log.error("failed to start macOS display-link adapter: \(String(describing: error))")
      }
      return view
    }

    public func updateNSView(_: WebgridMetalNSView, context _: Context) {
      // The backing layer resizes with the view automatically. Nothing per-update.
    }

    public static func dismantleNSView(_: WebgridMetalNSView, coordinator: Coordinator) {
      coordinator.adapter?.stop()
      coordinator.adapter = nil
    }

    /// Retains the adapter for the view's lifetime (the representable struct itself is transient).
    @MainActor
    public final class Coordinator {
      var adapter: MacDisplayLinkAdapter?
      public init() {}
    }
  }
#endif
