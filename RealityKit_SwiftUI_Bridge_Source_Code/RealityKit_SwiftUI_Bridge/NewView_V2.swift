//
//  NewView_V2.swift
//  RealityKit_SwiftUI_Bridge
//
//  Created by Cong Le on 4/11/25.
//

import SwiftUI
import UIKit // Keep UIKit for UIColor
import ARKit
import SceneKit

// MARK: - Enum for Selectable Objects
enum SelectableObjectType: String, CaseIterable, Identifiable {
    case cube = "Cube"
    case sphere = "Sphere"
    case capsule = "Capsule" // New shape

    var id: String { rawValue }

    // Simple color representation for the UI
    var color: Color {
        switch self {
        case .cube: return .yellow
        case .sphere: return .red
        case .capsule: return .green
        }
    }
}

// MARK: - Object Settings Model
/// Holds configuration for a placeable object.
struct ObjectSettings: Identifiable, Equatable, Hashable {
    let id = UUID()
    var size: CGFloat = 0.05
    var color: Color = .yellow

    // Improved conversion: if available, use SwiftUI’s UIColor(Color) initializer;
    // otherwise fall back to a default color.
    var uiColor: UIColor {
        if #available(iOS 14.0, *) {
            // ---- FIX 1: Use self.color ----
            return UIColor(self.color)
        } else {
            // For earlier iOS versions, estimate the UIColor
            // This is a basic estimation and might not be accurate for all SwiftUI Colors.
            // Consider using a more robust conversion library if needed for older iOS.
            switch self.color {
                case .yellow: return UIColor.yellow
                case .red: return UIColor.red
                case .green: return UIColor.green
                // Add other common Color mappings if needed
                default: return UIColor.gray // Fallback
            }
        }
    }

    // Static default settings for each type
    static func defaultSettings(for type: SelectableObjectType) -> ObjectSettings {
        switch type {
        case .cube:
            return ObjectSettings(size: 0.05, color: .yellow)
        case .sphere:
            return ObjectSettings(size: 0.03, color: .red)
        case .capsule:
            return ObjectSettings(size: 0.06, color: .green)
        }
    }
}

// MARK: - Dictionary Extension for Default Settings
extension Dictionary where Key == SelectableObjectType, Value == ObjectSettings {
    static func defaultObjectSettings() -> [SelectableObjectType: ObjectSettings] {
        var settings: [SelectableObjectType: ObjectSettings] = [:]
        for type in SelectableObjectType.allCases {
            settings[type] = ObjectSettings.defaultSettings(for: type)
        }
        return settings
    }
}

// MARK: - Object Settings View
struct ObjectSettingsView: View {
    @Environment(\.dismiss) var dismiss
    let objectType: SelectableObjectType
    // Rather than relying on a dictionary subscript with default, we create a computed Binding.
    @Binding var settings: ObjectSettings

    // Private slider constants
    private let minSize: CGFloat = 0.01
    private let maxSize: CGFloat = 0.20
    private let sizeStep: CGFloat = 0.005

    var body: some View {
        NavigationView {
            Form {
                Section("Preview") {
                    HStack {
                        Spacer()
                        // Use a simple shape based on current type and fill with the bound color.
                        // Apply fill *here* since previewShape now returns `some Shape`
                        previewShape()
                            .fill(settings.color)
                            .frame(width: 60, height: 60)
                            .shadow(radius: 3)
                        Spacer()
                    }
                    .padding(.vertical)
                }

                Section("Size") {
                    VStack(alignment: .leading) {
                        Text("Approximate Size: \(settings.size, specifier: "%.3f") m")
                            .font(.caption)
                        Slider(value: $settings.size, in: minSize...maxSize, step: sizeStep) {
                            Text("Size")
                        } minimumValueLabel: {
                            Text("\(minSize, specifier: "%.2f")").font(.caption2)
                        } maximumValueLabel: {
                            Text("\(maxSize, specifier: "%.2f")").font(.caption2)
                        }
                    }
                }

                Section("Color") {
                    ColorPicker("Object Color", selection: $settings.color, supportsOpacity: false)
                }
            }
            .navigationTitle("\(objectType.rawValue) Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                        print("Settings updated for \(objectType.rawValue): Size \(settings.size), Color \(settings.color)")
                    }
                }
            }
        }
    }

     // Returns a suitable shape for preview based on the object type.
    // ---- FIX 2: Change return type to `some Shape` ----
    @ViewBuilder
    private func previewShape() -> some Shape {
        switch objectType {
        case .cube:
            RoundedRectangle(cornerRadius: 5)
        case .sphere:
            Circle()
        case .capsule:
            Capsule()
        }
    }
}

// MARK: - Content View with Object Selection
struct ContentViewWithSelection: View {
    // The currently selected object type.
    @State private var selectedObject: SelectableObjectType = .cube
    // Dictionary of custom settings for each object type.
    @State private var objectCustomSettings: [SelectableObjectType: ObjectSettings] = .defaultObjectSettings()
    @State private var isShowingSettingsSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewRepresentableWithSelection(
                selectedObject: $selectedObject,
                objectSettings: objectCustomSettings
            )
            .ignoresSafeArea()

            // Bottom control bar for settings and object selection.
            HStack(alignment: .bottom, spacing: 15) {
                Button {
                    isShowingSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                }
                .padding(.leading, 10)

                ObjectSelectionMenu(selectedObject: $selectedObject)
            }
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("ARKit Object Placer")
        .navigationBarHidden(true)
        // Use an explicit computed binding for the settings to ensure changes
        // update the dictionary correctly.
        .sheet(isPresented: $isShowingSettingsSheet) {
            ObjectSettingsView(
                objectType: selectedObject,
                settings: bindingForSelectedSettings
            )
        }
    }

    // Computed binding that reads and writes back to the dictionary.
    private var bindingForSelectedSettings: Binding<ObjectSettings> {
        return Binding<ObjectSettings>(
            get: { objectCustomSettings[selectedObject] ?? ObjectSettings.defaultSettings(for: selectedObject) },
            set: { newSettings in objectCustomSettings[selectedObject] = newSettings }
        )
    }
}

// MARK: - ARView Representable with Object Selection
struct ARViewRepresentableWithSelection: UIViewRepresentable {
    @Binding var selectedObject: SelectableObjectType
    let objectSettings: [SelectableObjectType: ObjectSettings]

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        // Optional: Improve rendering quality
        arView.automaticallyUpdatesLighting = true
        arView.autoenablesDefaultLighting = true
        arView.scene.lightingEnvironment.intensity = 1.5 // Adjust intensity as needed

        arView.showsStatistics = true // Keep for debugging
        arView.debugOptions = [.showFeaturePoints] // Keep for debugging
        startARSession(for: arView)
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.updateSelectedObject(selectedObject)
        context.coordinator.updateSettings(objectSettings)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, initialSelection: selectedObject, initialSettings: objectSettings)
    }

    // Starts the AR session with horizontal plane detection and (if supported) scene reconstruction.
    private func startARSession(for arView: ARSCNView) {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("AR World Tracking is not supported on this device.")
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic // Use environment texture for reflections
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("AR Session Started with Horizontal Plane Detection")
    }

    // MARK: - Coordinator for ARSCNViewDelegate and Gesture Handling
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewRepresentableWithSelection
        var planeNodes: [UUID: SCNNode] = [:]
        var currentSelectedObject: SelectableObjectType
        var currentObjectSettings: [SelectableObjectType: ObjectSettings]

        init(_ parent: ARViewRepresentableWithSelection, initialSelection: SelectableObjectType, initialSettings: [SelectableObjectType: ObjectSettings]) {
            self.parent = parent
            self.currentSelectedObject = initialSelection
            self.currentObjectSettings = initialSettings
            super.init()
        }

        func updateSelectedObject(_ newSelection: SelectableObjectType) {
            self.currentSelectedObject = newSelection
        }

        func updateSettings(_ newSettings: [SelectableObjectType: ObjectSettings]) {
            self.currentObjectSettings = newSettings
        }

        // MARK: - Gesture Handler
        @objc func handleTap(_ gestureRecognize: UITapGestureRecognizer) {
            guard let arView = gestureRecognize.view as? ARSCNView else { return }
            let tapLocation = gestureRecognize.location(in: arView)
            
            // Prioritize hitting existing planes, but allow hitting feature points roughly on planes as a fallback
            let hitTestTypes: ARHitTestResult.ResultType = [.existingPlaneUsingExtent]
            let hitTestResults = arView.hitTest(tapLocation, types: hitTestTypes)

            guard let hitResult = hitTestResults.first else {
                // Maybe try hitting feature points if no planes were hit
                // let featurePointResults = arView.hitTest(tapLocation, types: .featurePoint)
                // if let featureResult = featurePointResults.first { ... handle feature point hit ... } else { print(...) }
                print("Tap did not hit any detected plane extent.")
                return
            }

            // Retrieve (or use default) settings for the current object.
            let settings = currentObjectSettings[currentSelectedObject] ?? ObjectSettings.defaultSettings(for: currentSelectedObject)

            let objectNode: SCNNode
            switch currentSelectedObject {
            case .cube:
                objectNode = createCubeNode(settings: settings)
            case .sphere:
                objectNode = createSphereNode(settings: settings)
            case .capsule:
                objectNode = createCapsuleNode(settings: settings)
            }

            // Add physics if desired
            // let physicsShape = SCNPhysicsShape(geometry: objectNode.geometry!, options: nil)
            // objectNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: physicsShape)
            // objectNode.physicsBody?.mass = 1.0
            // objectNode.physicsBody?.restitution = 0.5 // Bounciness

            // Calculate vertical offset for proper placement *relative to the plane*
            let objectHeight = objectNode.boundingBox.max.y - objectNode.boundingBox.min.y
            let yOffset = objectHeight / 2 + 0.001 // Small epsilon to prevent Z-fighting

            // Position the object directly on the hit plane surface + offset
            let position = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y + yOffset, // Add offset to plane hit y
                hitResult.worldTransform.columns.3.z
            )
            objectNode.position = position

            // Optional: Rotate object based on plane orientation (can be complex)
            // objectNode.simdOrientation = hitResult.worldTransform.orientation

            arView.scene.rootNode.addChildNode(objectNode)

            print("Added \(currentSelectedObject.rawValue) with Size: \(settings.size), Color: \(settings.color) at position: \(position)")
        }

        // MARK: - Helper Methods for Creating 3D Nodes
        func createCubeNode(settings: ObjectSettings) -> SCNNode {
            let cube = SCNBox(width: settings.size, height: settings.size, length: settings.size, chamferRadius: settings.size * 0.05)
            applyMaterial(to: cube, with: settings.uiColor)
            return SCNNode(geometry: cube)
        }

        func createSphereNode(settings: ObjectSettings) -> SCNNode {
            let sphere = SCNSphere(radius: settings.size / 2) // Radius is half the desired diameter/size
            applyMaterial(to: sphere, with: settings.uiColor)
            return SCNNode(geometry: sphere)
        }

        func createCapsuleNode(settings: ObjectSettings) -> SCNNode {
            let height = settings.size
            let capRadius = height * 0.25 // Adjust proportion as needed
            let capsule = SCNCapsule(capRadius: capRadius, height: height)
            applyMaterial(to: capsule, with: settings.uiColor)
            return SCNNode(geometry: capsule)
        }
        
        // Helper to apply a standard physically based material
        private func applyMaterial(to geometry: SCNGeometry, with color: UIColor) {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .physicallyBased
            material.metalness.contents = 0.1 // Slightly metallic
            material.roughness.contents = 0.6 // Moderately rough
            geometry.materials = [material]
        }

        // MARK: - ARSCNViewDelegate Plane Methods
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            print("Detected Plane: \(planeAnchor.identifier), Center: \(planeAnchor.center), Extent: \(planeAnchor.extent)")
            let planeNode = createPlaneNode(for: planeAnchor)
            node.addChildNode(planeNode)
            planeNodes[planeAnchor.identifier] = planeNode
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor,
                  let planeNode = planeNodes[planeAnchor.identifier],
                  let plane = planeNode.geometry as? SCNPlane // Ensure geometry is SCNPlane
                  else { return }

            // Update plane geometry size based on the anchor's extent
            plane.width = CGFloat(planeAnchor.extent.x)
            plane.height = CGFloat(planeAnchor.extent.z)

            // Update plane node position based on the anchor's center
            // The SCNPlane's center is relative to the node's origin, so we set the node's position.
            planeNode.position = SCNVector3(planeAnchor.center.x, -0.005, planeAnchor.center.z) // Keep slightly below anchor
            // print("Updated Plane: \(planeAnchor.identifier), Center: \(planeAnchor.center), Extent: \(planeAnchor.extent)")

        }

        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            print("Removed Plane: \(planeAnchor.identifier)")
            if let planeNode = planeNodes.removeValue(forKey: planeAnchor.identifier) {
                planeNode.removeFromParentNode()
            }
        }

        // Create a visualization node for the detected plane
       func createPlaneNode(for planeAnchor: ARPlaneAnchor) -> SCNNode {
            // Create the plane geometry using the anchor's extent
            let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))

            // Add a semi-transparent material for visualization
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.4) // Example color
            plane.materials = [material]
           
            // Create the node containing the plane geometry
            let planeNode = SCNNode(geometry: plane)
           
            // Position the node at the center of the plane anchor **relative to its parent node**
            // The parent node (created by ARKit for the anchor) is already at the anchor's transform.
            // Position the plane slightly below the anchor's y-level to avoid z-fighting with placed objects
            planeNode.position = SCNVector3(planeAnchor.center.x, -0.005, planeAnchor.center.z)

            // Rotate the plane geometry to be horizontal (X-Z plane)
            // SCNPlane is vertical in X-Y by default.
            planeNode.transform = SCNMatrix4MakeRotation(-Float.pi / 2.0, 1, 0, 0)

            return planeNode
        }
    }
}

// MARK: - Object Selection Menu
struct ObjectSelectionMenu: View {
    @Binding var selectedObject: SelectableObjectType

    var body: some View {
        HStack(spacing: 20) {
            ForEach(SelectableObjectType.allCases) { objectType in
                Button {
                    selectedObject = objectType
                    print("Selected: \(objectType.rawValue)")
                } label: {
                    VStack {
                        Circle()
                            .fill(objectType.color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedObject == objectType ? 3 : 0)
                                    .animation(.easeIn(duration: 0.1), value: selectedObject) // Add animation
                            )
                            .shadow(radius: 3)
                        Text(objectType.rawValue)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                 .scaleEffect(selectedObject == objectType ? 1.1 : 1.0) // Scale up selected
                 .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedObject)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
             RoundedRectangle(cornerRadius: 15) // Use RR for background
                 .fill(Color.black.opacity(0.6)) // Slightly darker background
                 .shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 2) // Add shadow to menu
        )
        .cornerRadius(15) // Ensure clipping if needed, though RR background handles it
    }
}

// MARK: - Preview Providers
struct ObjectSettingsView_Previews: PreviewProvider {
    @State static var previewSettings_Cube = ObjectSettings.defaultSettings(for: .cube)
    @State static var previewSettings_Sphere = ObjectSettings.defaultSettings(for: .sphere)
    @State static var previewSettings_Capsule = ObjectSettings.defaultSettings(for: .capsule)

    static var previews: some View {
        Group {
            ObjectSettingsView(objectType: .cube, settings: $previewSettings_Cube)
                .previewDisplayName("Cube Settings")
            ObjectSettingsView(objectType: .sphere, settings: $previewSettings_Sphere)
                .previewDisplayName("Sphere Settings")
             ObjectSettingsView(objectType: .capsule, settings: $previewSettings_Capsule)
                .previewDisplayName("Capsule Settings")
        }
    }
}

struct ContentViewWithSelection_Previews: PreviewProvider {
    static var previews: some View {
        // Wrap in NavigationView if appropriate for your app's flow
        ContentViewWithSelection()
            .edgesIgnoringSafeArea(.all) // Often desired for AR views
            .previewDisplayName("AR View")
    }
}
