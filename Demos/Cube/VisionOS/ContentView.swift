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
        ZStack(alignment: .bottom) {
            // 1. The 3D Vulkan Content Layer
            CubeHostView()
                .ignoresSafeArea()
            
            // 2. The 2D Spatial UI Layer
            VStack(spacing: 20) {
                Text("Vulkan Live on visionOS")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(15)
                
                Button(action: {
                    // Triggers the C-function to re-initialize swapchain logic
                    cube_runner_resize()
                }) {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .padding()
                        .frame(minWidth: 200)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.bottom, 50)
            }
        }
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
        let displayLink = CADisplayLink(target: context.coordinator, selector: #selector(Coordinator.tick))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .default)
        context.coordinator.displayLink = displayLink

        return view
    }

    func updateUIView(_ uiView: MetalHostView, context: Context) {
        uiView.setNeedsLayout()
    }

    static func dismantleUIView(_ uiView: MetalHostView, coordinator: Coordinator) {
        coordinator.displayLink?.invalidate()
        cube_runner_stop()
    }
}
