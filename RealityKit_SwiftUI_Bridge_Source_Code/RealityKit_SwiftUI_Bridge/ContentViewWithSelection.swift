//
//  ContentViewWithSelection.swift
//  RealityKit_SwiftUI_Bridge
//
//  Created by Cong Le on 4/11/25.
//

import SwiftUI
import ARKit
import SceneKit

// MARK: - Enum for Selectable Objects

enum SelectableObjectType: String, CaseIterable, Identifiable {
    case cube = "Cube"
    case sphere = "Sphere"
    case capsule = "Capsule" // New shape

    var id: String { self.rawValue }

    // Simple color representation for the UI
    var color: Color {
        switch self {
        case .cube: return .yellow
        case .sphere: return .red
        case .capsule: return .green
        }
    }
}

// MARK: - Modified ARViewRepresentable

struct ARViewRepresentableWithSelection: UIViewRepresentable {
    // Binding to communicate the selected object type from ContentView
    @Binding var selectedObject: SelectableObjectType

    // Create the ARSCNView (mostly unchanged)
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.showsStatistics = true
        arView.debugOptions = [.showFeaturePoints] // Simplified debug options
        startARSession(for: arView)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        return arView
    }

    // UpdateUIView might be used if configuration needs changing based on selection
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Example: If changing the selectedObject required different AR configurations
        // you might update the session here. For simple object placement,
        // the Coordinator handles it directly based on the binding state.
        context.coordinator.updateSelectedObject(selectedObject)
    }

    // Make Coordinator, passing the initial selected object state
    func makeCoordinator() -> Coordinator {
        Coordinator(self, initialSelection: selectedObject)
    }

    // startARSession remains the same as before
    private func startARSession(for arView: ARSCNView) {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("AR World Tracking is not supported on this device.")
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
             configuration.sceneReconstruction = .mesh
        }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("AR Session Started with Horizontal Plane Detection")
    }

    // MARK: - Modified Coordinator Class
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewRepresentableWithSelection
        var planeNodes: [UUID: SCNNode] = [:]
        // Store the currently selected object type within the Coordinator
        var currentSelectedObject: SelectableObjectType

        init(_ parent: ARViewRepresentableWithSelection, initialSelection: SelectableObjectType) {
            self.parent = parent
            self.currentSelectedObject = initialSelection
            super.init() // Call super.init() after initializing properties
        }

        // Method to update the selection if needed via updateUIView
        func updateSelectedObject(_ newSelection: SelectableObjectType) {
             self.currentSelectedObject = newSelection
        }

        // --- ARSCNViewDelegate Methods (didAdd, didUpdate, didRemove) ---
        // These remain identical to the original implementation for plane handling
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
             guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
             print("Detected Plane: \(planeAnchor.identifier)")
             let planeNode = createPlaneNode(for: planeAnchor)
             node.addChildNode(planeNode)
             planeNodes[planeAnchor.identifier] = planeNode
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
             guard let planeAnchor = anchor as? ARPlaneAnchor,
                   let planeNode = planeNodes[planeAnchor.identifier] else { return }
             updatePlaneNode(planeNode, for: planeAnchor)
        }

        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
             guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
             print("Removed Plane: \(planeAnchor.identifier)")
             if let planeNode = planeNodes.removeValue(forKey: planeAnchor.identifier) {
                 planeNode.removeFromParentNode()
             }
        }

        // --- Helper Methods for Plane Visualization (createPlaneNode, updatePlaneNode) ---
        // These remain identical to the original implementation
        func createPlaneNode(for planeAnchor: ARPlaneAnchor) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.5)
            plane.materials = [material]
            let planeNode = SCNNode(geometry: plane)
            planeNode.position = SCNVector3(0, -0.005, 0)
            planeNode.transform = SCNMatrix4MakeRotation(-Float.pi / 2, 1, 0, 0)
            return planeNode
        }

        func updatePlaneNode(_ node: SCNNode, for planeAnchor: ARPlaneAnchor) {
            guard let plane = node.geometry as? SCNPlane else { return }
            plane.width = CGFloat(planeAnchor.extent.x)
            plane.height = CGFloat(planeAnchor.extent.z)
        }

        // --- Modified Gesture Handling ---
        @objc func handleTap(_ gestureRecognize: UITapGestureRecognizer) {
            guard let arView = gestureRecognize.view as? ARSCNView else { return }
            let tapLocation = gestureRecognize.location(in: arView)
            let hitTestResults = arView.hitTest(tapLocation, types: .existingPlaneUsingExtent)

            guard let hitResult = hitTestResults.first else {
                print("Tap did not hit any detected plane.")
                return
            }
            
            //print("Tap hit plane anchor: \(hitResult.anchor?.identifier ?? "N/A")")

            // Create the selected 3D object
            let objectNode: SCNNode

            // Use the coordinator's current selection state
            switch currentSelectedObject {
            case .cube:
                objectNode = createCubeNode(size: 0.05)
            case .sphere:
                objectNode = createSphereNode(radius: 0.03) // Example size
            case .capsule:
                objectNode = createCapsuleNode(capRadius: 0.02, height: 0.06) // Example size
            }

            // Position the object (same logic as before)
            let position = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y + objectNode.boundingBox.max.y / 2 + 0.001, // Use object's bounding box
                hitResult.worldTransform.columns.3.z
            )
            objectNode.position = position

            // Add the selected object node to the scene
            arView.scene.rootNode.addChildNode(objectNode)

            print("Added \(currentSelectedObject.rawValue) at position: \(position)")
        }

        // --- Helper Methods for Creating Different 3D Content ---
        func createCubeNode(size: CGFloat) -> SCNNode {
            let cube = SCNBox(width: size, height: size, length: size, chamferRadius: size * 0.05)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemYellow
            material.lightingModel = .physicallyBased
            cube.materials = [material]
            let cubeNode = SCNNode(geometry: cube)
            return cubeNode
        }

        func createSphereNode(radius: CGFloat) -> SCNNode {
            let sphere = SCNSphere(radius: radius)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemRed
            material.lightingModel = .physicallyBased
            sphere.materials = [material]
            let sphereNode = SCNNode(geometry: sphere)
            return sphereNode
        }

        func createCapsuleNode(capRadius: CGFloat, height: CGFloat) -> SCNNode {
            let capsule = SCNCapsule(capRadius: capRadius, height: height)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemGreen
            material.lightingModel = .physicallyBased
            capsule.materials = [material]
            let capsuleNode = SCNNode(geometry: capsule)
            // Capsules stand upright by default, adjust pivot if needed depending on desired origin
            return capsuleNode
        }
    }
}

// MARK: - Modified SwiftUI ContentView

struct ContentViewWithSelection: View {
    // State to track the currently selected object type
    @State private var selectedObject: SelectableObjectType = .cube

    var body: some View {
        ZStack(alignment: .bottom) { // Use ZStack for overlay
            // AR View takes up the background
            ARViewRepresentableWithSelection(selectedObject: $selectedObject)
                .ignoresSafeArea()

            // Object Selection Menu Overlay
            ObjectSelectionMenu(selectedObject: $selectedObject)
                .padding(.bottom, 30) // Add some padding from the bottom edge
        }
        .navigationTitle("ARKit Object Placer") // Can keep title for context
        .navigationBarHidden(true) // Keep immersive
    }
}

// MARK: - SwiftUI View for the Object Selection Menu

struct ObjectSelectionMenu: View {
    @Binding var selectedObject: SelectableObjectType

    var body: some View {
        HStack(spacing: 20) {
            ForEach(SelectableObjectType.allCases) { objectType in
                Button {
                    // Update the state when a button is tapped
                    selectedObject = objectType
                    print("Selected: \(objectType.rawValue)")
                } label: {
                    VStack {
                        // Simple visual representation (could be images or 3D previews)
                        Circle()
                            .fill(objectType.color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedObject == objectType ? 3 : 0) // Highlight selected
                            )
                            .shadow(radius: 3)

                        Text(objectType.rawValue)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5)) // Semi-transparent background
        .cornerRadius(15)
    }
}

// MARK: - Preview Provider

struct ContentViewWithSelection_Previews: PreviewProvider {
    static var previews: some View {
        // Preview will show ContentView layout, but AR won't work.
        // You'll see the selection menu at the bottom.
        NavigationView { // Wrap for preview context if needed
             ContentViewWithSelection()
        }
         .previewDisplayName("AR View with Selection Menu")

    }
}

// MARK: - App Entry Point (Using the new ContentView)
//
//@main
//struct ARKitSwiftUIAppWithSelection: App {
//    var body: some Scene {
//        WindowGroup {
//            // Use the new ContentView that includes selection
//             ContentViewWithSelection()
//             // You might still wrap in NavigationView if other non-AR screens are planned
//             // NavigationView { ContentViewWithSelection() }
//        }
//    }
//}
