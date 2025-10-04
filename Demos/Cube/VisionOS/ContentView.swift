import SwiftUI
import QuartzCore
import Metal

final class MetalHostView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private var didStart = false

    override func layoutSubviews() {
        super.layoutSubviews()

        // Make sure we actually have size
        guard bounds.width > 0, bounds.height > 0 else { return }

        metalLayer.frame = bounds
        metalLayer.contentsScale = 1.0
        metalLayer.drawableSize = CGSize(
            width:  max(1, bounds.width),
            height: max(1, bounds.height)
        )

        if !didStart {                      // start only once, with real size
            didStart = true
            let opaque = Unmanaged.passUnretained(metalLayer).toOpaque()
            cube_runner_start(opaque)
        } else {
            cube_runner_resize()            // keep resizing after start
        }
    }
}

struct ContentView: View {
    var body: some View {
        CubeHostView()
            .ignoresSafeArea()
    }
}

struct CubeHostView: UIViewRepresentable {
    final class Coordinator: NSObject {
        var displayLink: CADisplayLink?
        @objc func tick() { cube_runner_draw() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MetalHostView {
        let view = MetalHostView()

        // Configure the CAMetalLayer
        view.metalLayer.device = MTLCreateSystemDefaultDevice()
        view.metalLayer.pixelFormat = .bgra8Unorm
        view.metalLayer.isOpaque = true
        view.metalLayer.framebufferOnly = true
        view.metalLayer.presentsWithTransaction = false

        // Drive rendering
        let cADisplayLink = CADisplayLink(target: context.coordinator, selector: #selector(Coordinator.tick))
        cADisplayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        cADisplayLink.add(to: .main, forMode: .default)
        context.coordinator.displayLink = cADisplayLink

        return view
    }

    func updateUIView(_ uiView: MetalHostView, context: Context) {
        uiView.setNeedsLayout()  // layoutSubviews will size & start/resize
    }

    static func dismantleUIView(_ uiView: MetalHostView, coordinator: Coordinator) {
        coordinator.displayLink?.invalidate()
        cube_runner_stop()
    }
}
