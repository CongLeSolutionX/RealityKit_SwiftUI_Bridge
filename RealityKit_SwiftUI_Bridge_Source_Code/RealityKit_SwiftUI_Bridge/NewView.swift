
import SwiftUI
import UIKit
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

    // Improved conversion: if available, use SwiftUI’s UIColor(_:) initializer;
    // otherwise fall back to a default color.
    var uiColor: UIColor {
        if #available(iOS 14.0, *) {
            return UIColor(self)
        } else {
            // For earlier iOS versions, use a default conversion (or implement custom logic)
            return UIColor.yellow
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
        arView.showsStatistics = true
        arView.debugOptions = [.showFeaturePoints]
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
        configuration.environmentTexturing = .automatic
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
            let hitTestResults = arView.hitTest(tapLocation, types: .existingPlaneUsingExtent)
            
            guard let hitResult = hitTestResults.first else {
                print("Tap did not hit any detected plane.")
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
            
            // Calculate vertical offset for proper placement.
            let objectHeight = objectNode.boundingBox.max.y - objectNode.boundingBox.min.y
            let yOffset = objectHeight / 2 + 0.001
            
            let position = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y + yOffset,
                hitResult.worldTransform.columns.3.z
            )
            objectNode.position = position
            arView.scene.rootNode.addChildNode(objectNode)
            
            print("Added \(currentSelectedObject.rawValue) with Size: \(settings.size), Color: \(settings.color) at position: \(position)")
        }
        
        // MARK: - Helper Methods for Creating 3D Nodes
        func createCubeNode(settings: ObjectSettings) -> SCNNode {
            let cube = SCNBox(width: settings.size, height: settings.size, length: settings.size, chamferRadius: settings.size * 0.05)
            let material = SCNMaterial()
            material.diffuse.contents = settings.uiColor
            material.lightingModel = .physicallyBased
            cube.materials = [material]
            return SCNNode(geometry: cube)
        }
        
        func createSphereNode(settings: ObjectSettings) -> SCNNode {
            let sphere = SCNSphere(radius: settings.size)
            let material = SCNMaterial()
            material.diffuse.contents = settings.uiColor
            material.lightingModel = .physicallyBased
            sphere.materials = [material]
            return SCNNode(geometry: sphere)
        }
        
        func createCapsuleNode(settings: ObjectSettings) -> SCNNode {
            let height = settings.size
            let capRadius = height * 0.25
            let capsule = SCNCapsule(capRadius: capRadius, height: height)
            let material = SCNMaterial()
            material.diffuse.contents = settings.uiColor
            material.lightingModel = .physicallyBased
            capsule.materials = [material]
            return SCNNode(geometry: capsule)
        }
        
        // MARK: - ARSCNViewDelegate Plane Methods
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
        .background(Color.black.opacity(0.5))
        .cornerRadius(15)
    }
}

// MARK: - Preview Providers
struct ObjectSettingsView_Previews: PreviewProvider {
    @State static var previewSettings_Cube = ObjectSettings.defaultSettings(for: .cube)
    @State static var previewSettings_Sphere = ObjectSettings.defaultSettings(for: .sphere)
    
    static var previews: some View {
        Group {
            ObjectSettingsView(objectType: .cube, settings: $previewSettings_Cube)
                .previewDisplayName("Cube Settings")
            ObjectSettingsView(objectType: .sphere, settings: $previewSettings_Sphere)
                .previewDisplayName("Sphere Settings")
        }
    }
}

struct ContentViewWithSelection_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ContentViewWithSelection()
        }
        .previewDisplayName("AR View with Selection Menu")
    }
}
