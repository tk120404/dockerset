import CoreLocation

/// One-shot current location (city-level accuracy) plus a city name, cached for 30 minutes.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    struct Place: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    @Published private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private var cached: (place: Place, date: Date)?

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var denied: Bool { status == .denied || status == .restricted }

    func currentPlace() async -> Place? {
        if let cached, Date().timeIntervalSince(cached.date) < 30 * 60 { return cached.place }
        guard let location = await location() else { return nil }
        let name = (try? await CLGeocoder().reverseGeocodeLocation(location))?.first?.locality ?? "Current Location"
        let place = Place(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        cached = (place, Date())
        return place
    }

    private func location() async -> CLLocation? {
        if denied { return nil }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            guard waiting.count == 1 else { return } // a request is already in flight
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization() // continues in locationManagerDidChangeAuthorization
            } else {
                manager.requestLocation()
            }
            // Never leave the widget waiting forever (no fix, prompt left unanswered).
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.finish(nil) }
        }
    }

    private func finish(_ location: CLLocation?) {
        let pending = waiting
        waiting = []
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            status = manager.authorizationStatus
            guard !waiting.isEmpty else { return }
            if denied { finish(nil) } else if status != .notDetermined { manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { finish(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}
