import Foundation
import IOKit.ps

// MARK: - Power Service
// Monitors system power sources (AC power vs Battery power) using IOKit.ps.
// Allows LangSwitcher to automatically pause AI inference to save battery.

@MainActor
final class PowerService: ObservableObject {
    
    static let shared = PowerService()
    
    @Published private(set) var isOnBattery: Bool = false
    @Published private(set) var powerSourceDescription: String = "AC Power"
    
    private var runLoopSource: CFRunLoopSource?
    private let powerSourceProvider: (() -> (isOnBattery: Bool, description: String))?
    
    init(powerSourceProvider: (() -> (isOnBattery: Bool, description: String))? = nil) {
        self.powerSourceProvider = powerSourceProvider
        updatePowerStatus()
        startMonitoring()
    }
    
    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
    
    func updatePowerStatus() {
        if let customProvider = powerSourceProvider {
            let result = customProvider()
            self.isOnBattery = result.isOnBattery
            self.powerSourceDescription = result.description
            return
        }
        
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            self.isOnBattery = false
            self.powerSourceDescription = "AC Power"
            return
        }
        
        let type = (IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?) ?? ""
        let battery = (type == (kIOPMBatteryPowerKey as String))
        self.isOnBattery = battery
        self.powerSourceDescription = battery ? "Battery" : "AC Power"
        
        if battery && SettingsManager.shared.aiBatteryModeEnabled && SettingsManager.shared.aiBatteryPolicy == .pauseInference {
            AIInferenceEngine.shared.stop()
        }
    }
    
    private func startMonitoring() {
        guard powerSourceProvider == nil else { return }
        
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let unmanaged = Unmanaged<PowerService>.fromOpaque(context)
            DispatchQueue.main.async {
                unmanaged.takeUnretainedValue().updatePowerStatus()
            }
        }, context)?.takeRetainedValue() else {
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.runLoopSource = source
    }
    
    private func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }
}
