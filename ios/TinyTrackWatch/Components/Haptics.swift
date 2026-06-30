import WatchKit

/// Thin wrapper over the Taptic Engine for consistent haptic feedback.
enum Haptics {
    static func click()   { WKInterfaceDevice.current().play(.click) }
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func start()   { WKInterfaceDevice.current().play(.start) }
    static func stop()    { WKInterfaceDevice.current().play(.stop) }
    static func notify()  { WKInterfaceDevice.current().play(.notification) }
    static func directionUp()   { WKInterfaceDevice.current().play(.directionUp) }
    static func directionDown() { WKInterfaceDevice.current().play(.directionDown) }
}
