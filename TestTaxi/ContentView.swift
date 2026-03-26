import SwiftUI
import UIKit
import MapKit
import GoogleMaps
import CoreLocation
import UserNotifications
import Combine

final class PermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var permissionsResolved = false
    private var didRequestPermissions = false
    private var isLocationResolved = false
    private var isNotificationsResolved = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestRequiredPermissions() {
        guard !didRequestPermissions else { return }
        didRequestPermissions = true

        requestLocationPermission()
        requestNotificationPermission()
    }

    private func requestLocationPermission() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else {
            isLocationResolved = true
            resolveIfNeeded()
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    DispatchQueue.main.async {
                        self.isNotificationsResolved = true
                        self.resolveIfNeeded()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isNotificationsResolved = true
                    self.resolveIfNeeded()
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined {
            isLocationResolved = true
            resolveIfNeeded()
        }
    }

    private func resolveIfNeeded() {
        if isLocationResolved && isNotificationsResolved {
            permissionsResolved = true
        }
    }
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var speed: Double = 0
    @Published var distance: Double = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        start()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        speed = max(location.speed, 0)

        if let previous = lastLocation, location.horizontalAccuracy >= 0 {
            distance += location.distance(from: previous)
        }
        lastLocation = location
    }
}

struct RootView: View {
    @State private var isLaunchLoading = true
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var locationService = LocationService()

    var body: some View {
        Group {
            if isLaunchLoading || !permissionManager.permissionsResolved {
                LoadingView()
                    .transition(.opacity)
            } else {
                AppShellView(locationService: locationService)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLaunchLoading || !permissionManager.permissionsResolved)
        .task {
            // Simulates short app loading before showing main screen.
            try? await Task.sleep(for: .seconds(1.5))
            permissionManager.requestRequiredPermissions()
            isLaunchLoading = false
        }
        .onChange(of: permissionManager.permissionsResolved) { _, resolved in
            if resolved {
                locationService.start()
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)

                ProgressView()
                    .controlSize(.large)
            }
        }
    }
}

enum MenuDestination: String, CaseIterable, Identifiable {
    case map = "Карта"
    case list = "Список"
    case info = "Информация"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .map: return "map"
        case .list: return "list.bullet"
        case .info: return "info.circle"
        }
    }
}

enum CarType: String, CaseIterable, Identifiable {
    case standard = "Стандарт"
    case comfort = "Комфорт"
    case business = "Бизнес"

    var id: String { rawValue }
}

struct CarOrderPanel: View {
    @Binding var selectedCarType: CarType
    let onOrder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 60, height: 5)
                .padding(.top, 6)

            Text("Выберите автомобиль")
                .font(.headline)

            VStack(spacing: 8) {
                carButton(.standard)
                carButton(.comfort)
                carButton(.business)
            }

            Button {
                onOrder()
            } label: {
                Text("Заказать")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.95))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: -2)
    }

    @ViewBuilder
    private func carButton(_ type: CarType) -> some View {
        Button {
            selectedCarType = type
        } label: {
            HStack {
                Image(systemName: type == .standard ? "car" : (type == .comfort ? "car.fill" : "crown"))
                    .foregroundStyle(type == selectedCarType ? .blue : .secondary)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if selectedCarType == type {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selectedCarType == type ? Color.blue.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AppShellView: View {
    @ObservedObject var locationService: LocationService
    @State private var isSideMenuOpen = false
    @State private var destination: MenuDestination = .map

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                Group {
                    switch destination {
                    case .map:
                        MainMapView(locationService: locationService)
                    case .list:
                        PhotosListView()
                    case .info:
                        InfoView(locationService: locationService)
                    }
                }

                if isSideMenuOpen {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSideMenuOpen = false
                            }
                        }
                }

                SideMenuView(selected: destination) { selected in
                    destination = selected
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSideMenuOpen = false
                    }
                }
                .frame(width: 280)
                .offset(x: isSideMenuOpen ? 0 : -300)
                .animation(.easeInOut(duration: 0.25), value: isSideMenuOpen)
            }
            .navigationTitle(destination.rawValue)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSideMenuOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
        }
    }
}

struct MainMapView: View {
    @ObservedObject var locationService: LocationService
    @State private var centerOnUserTrigger = 0
    @State private var useCurrentLocation = true
    @State private var pinnedFromCoordinate: CLLocationCoordinate2D?
    @State private var fromAddress: String = ""
    @State private var toAddress: String = ""
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var destinationGeocodeTask: Task<Void, Never>?
    @State private var showRoutePage = false
    @State private var showOriginSearch = false
    @State private var showCarPanel = false
    @State private var selectedCarType: CarType = .standard
    @State private var showOrderSuccessAlert = false
    @State private var lastPanelShownDestinationId: String = ""

    var body: some View {
        let currentUserCoordinate = CLLocationCoordinate2D(
            latitude: locationService.latitude,
            longitude: locationService.longitude
        )
        let isUserCoordinateValid = CLLocationCoordinate2DIsValid(currentUserCoordinate) &&
            (abs(locationService.latitude) > 0.0001 || abs(locationService.longitude) > 0.0001)
        let fromCoordinate = useCurrentLocation ? (isUserCoordinateValid ? currentUserCoordinate : nil) : pinnedFromCoordinate
        let centerCoordinateOverride: CLLocationCoordinate2D? = useCurrentLocation ? nil : fromCoordinate
        let fromCoordId: String = {
            guard let fromCoordinate else { return "none" }
            return "\(fromCoordinate.latitude),\(fromCoordinate.longitude)"
        }()

        ZStack(alignment: .bottomTrailing) {
            DarkMapView(
                centerOnUserTrigger: centerOnUserTrigger,
                locationService: locationService,
                fromCoordinate: fromCoordinate,
                destinationCoordinate: destinationCoordinate,
                centerCoordinate: centerCoordinateOverride,
                onMapTap: { coordinate in
                    pinnedFromCoordinate = coordinate
                    useCurrentLocation = false
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            // Checkbox on map (controls "Откуда едем").
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    useCurrentLocation.toggle()
                    if useCurrentLocation && isUserCoordinateValid {
                        pinnedFromCoordinate = nil
                        centerOnUserTrigger += 1
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: useCurrentLocation ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                        Text(useCurrentLocation ? "Мое местоположение" : "Выбор точки")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                }
            }
            .padding(.trailing, 16)
            .padding(.top, 70)

            Button {
                if isUserCoordinateValid {
                    pinnedFromCoordinate = nil
                    useCurrentLocation = true
                    centerOnUserTrigger += 1
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.8))
                    .clipShape(Circle())
            }
            .padding(.trailing, 16)
            .padding(.bottom, 200)

            // "Откуда едем" / "Куда едем" bottom inputs.
            VStack(spacing: 10) {
                VStack(spacing: 8) {
                    Button {
                        showOriginSearch = true
                    } label: {
                        HStack(spacing: 10) {
                            Text(fromAddress.isEmpty ? "Откуда едем" : fromAddress)
                                .foregroundStyle(fromAddress.isEmpty ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 8) {
                    Button {
                        showRoutePage = true
                    } label: {
                        HStack(spacing: 10) {
                            Text(toAddress.isEmpty ? "Куда едем" : toAddress)
                                .foregroundStyle(toAddress.isEmpty ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 95)

            if showCarPanel {
                CarOrderPanel(
                    selectedCarType: $selectedCarType,
                    onOrder: placeOrder
                )
                .transition(.move(edge: .bottom))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .task(id: fromCoordId) {
            guard let fromCoordinate, isUserCoordinateValid || !useCurrentLocation else { return }
            await updateFromAddress(for: fromCoordinate)
        }
        // Destination input is done on the route page.
        .navigationDestination(isPresented: $showOriginSearch) {
            OriginSearchView(
                initialQuery: fromAddress,
                regionCenter: isUserCoordinateValid ? currentUserCoordinate : nil
            ) { pickedCoordinate in
                // Switch to "Выбор точки" mode and treat picked coordinate as origin.
                useCurrentLocation = false
                pinnedFromCoordinate = pickedCoordinate
                centerOnUserTrigger += 1
            }
        }
        .navigationDestination(isPresented: $showRoutePage) {
            RouteView(
                locationService: locationService,
                fromAddress: fromAddress,
                fromCoordinate: fromCoordinate,
                toAddress: $toAddress,
                destinationCoordinate: $destinationCoordinate,
                isRoutePresented: $showRoutePage
            )
        }
        .onChange(of: destinationCoordinateId) { _, newValue in
            guard !newValue.isEmpty else { return }
            guard newValue != lastPanelShownDestinationId else { return }
            lastPanelShownDestinationId = newValue
            selectedCarType = .standard
            withAnimation(.easeInOut(duration: 0.25)) {
                showCarPanel = true
            }
        }
        .alert("Заказ", isPresented: $showOrderSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Ваш заказ успешен")
        }
    }

    @State private var lastGeocodedCoordinate: CLLocationCoordinate2D?

    private var destinationCoordinateId: String {
        guard let destinationCoordinate else { return "" }
        return "\(destinationCoordinate.latitude),\(destinationCoordinate.longitude)"
    }

    private func placeOrder() {
        showCarPanel = false
        showOrderSuccessAlert = true

        let content = UNMutableNotificationContent()
        content.title = "Заказ"
        content.body = "Ваш заказ успешен"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func updateFromAddress(for coordinate: CLLocationCoordinate2D) async {
        if let last = lastGeocodedCoordinate {
            let lastLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let newLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if newLoc.distance(from: lastLoc) < 25 {
                return // Throttle reverse-geocoding.
            }
        }

        lastGeocodedCoordinate = coordinate

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await reverseGeocode(location: location, geocoder: geocoder)
            if let placemark = placemarks.first {
                let formatted = formatAddress(placemark: placemark)
                fromAddress = formatted
            } else {
                fromAddress = "Не удалось определить адрес"
            }
        } catch {
            fromAddress = "Не удалось определить адрес"
        }
    }

    private func formatAddress(placemark: CLPlacemark) -> String {
        let street = placemark.thoroughfare ?? ""
        let number = placemark.subThoroughfare ?? ""
        let city = placemark.locality ?? placemark.administrativeArea ?? ""

        let streetPart: String = {
            if !street.isEmpty && !number.isEmpty {
                return "\(street) \(number)"
            }
            if !street.isEmpty {
                return street
            }
            if let name = placemark.name, !name.isEmpty {
                return name
            }
            return ""
        }()

        if !streetPart.isEmpty && !city.isEmpty {
            return "\(streetPart), \(city)"
        }
        if !streetPart.isEmpty {
            return streetPart
        }
        if !city.isEmpty {
            return city
        }
        return "Не удалось определить адрес"
    }

    private func reverseGeocode(location: CLLocation, geocoder: CLGeocoder) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: placemarks ?? [])
                }
            }
        }
    }

    private func geocodeDestinationAddress(_ address: String) async {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            guard let placemark = placemarks.first,
                  let coordinate = placemark.location?.coordinate else {
                destinationCoordinate = nil
                return
            }
            destinationCoordinate = coordinate
        } catch {
            destinationCoordinate = nil
        }
    }

}

final class StreetSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            completions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    func updateRegion(center: CLLocationCoordinate2D?, radiusMeters: CLLocationDistance = 8000) {
        guard let center else { return }
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }
}

struct OriginSearchView: View {
    let initialQuery: String
    let regionCenter: CLLocationCoordinate2D?
    let onPick: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @StateObject private var completer = StreetSearchCompleter()

    init(
        initialQuery: String,
        regionCenter: CLLocationCoordinate2D?,
        onPick: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.initialQuery = initialQuery
        self.regionCenter = regionCenter
        self.onPick = onPick
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Введите адрес или название улицы", text: $query)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if completer.completions.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                ProgressView("Поиск улицы...")
                    .padding(.top, 20)
                Spacer()
            } else {
                List(completer.completions, id: \.self) { completion in
                    Button {
                        Task {
                            await pick(completion: completion)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(completion.title)
                                .font(.subheadline.weight(.semibold))
                            Text(completion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Откуда едем")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            completer.updateRegion(center: regionCenter)
            completer.updateQuery(query)
        }
        .onChange(of: query) { _, newValue in
            completer.updateQuery(newValue)
        }
    }

    private func pick(completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response: MKLocalSearch.Response? = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKLocalSearch.Response?, Error>) in
                search.start { response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: response)
                    }
                }
            }

            guard let coordinate = response?.mapItems.first?.placemark.coordinate else { return }
            onPick(coordinate)
            dismiss()
        } catch {
            // Ignore selection errors.
        }
    }
}

struct RouteView: View {
    @ObservedObject var locationService: LocationService

    let fromAddress: String
    let fromCoordinate: CLLocationCoordinate2D?

    @Binding var toAddress: String
    @Binding var destinationCoordinate: CLLocationCoordinate2D?
    @Binding var isRoutePresented: Bool

    @State private var query: String = ""
    @StateObject private var completer = StreetSearchCompleter()
    @State private var centerTrigger = 0

    var body: some View {
        let regionCenter = fromCoordinate ?? CLLocationCoordinate2D(
            latitude: locationService.latitude,
            longitude: locationService.longitude
        )

        ZStack(alignment: .bottom) {
            DarkMapView(
                centerOnUserTrigger: centerTrigger,
                locationService: locationService,
                fromCoordinate: fromCoordinate,
                destinationCoordinate: destinationCoordinate,
                centerCoordinate: destinationCoordinate ?? fromCoordinate,
                onMapTap: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                VStack(spacing: 8) {
                    TextField("Откуда едем", text: .constant(fromAddress))
                        .foregroundStyle(.primary)
                        .disabled(true)
                    Divider()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 8) {
                    TextField("Куда едем", text: $query)
                        .textInputAutocapitalization(.words)

                    Divider()

                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 2 {
                        if completer.completions.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            List(completer.completions, id: \.self) { completion in
                                Button {
                                    Task { await pick(completion: completion) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(completion.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                            .listStyle(.plain)
                            .frame(maxHeight: 260)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .navigationTitle("Маршрут")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            query = toAddress
            completer.updateRegion(center: regionCenter)
            completer.updateQuery(query)
        }
        .onChange(of: query) { _, newValue in
            completer.updateQuery(newValue)
        }
        .onChange(of: destinationCoordinateId) { _, _ in
            centerTrigger += 1
        }
    }

    private var destinationCoordinateId: String {
        guard let destinationCoordinate else { return "" }
        return "\(destinationCoordinate.latitude),\(destinationCoordinate.longitude)"
    }

    private func reverseGeocode(location: CLLocation) async throws -> [CLPlacemark] {
        let geocoder = CLGeocoder()
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: placemarks ?? [])
                }
            }
        }
    }

    private func formatAddress(placemark: CLPlacemark) -> String {
        let street = placemark.thoroughfare ?? ""
        let number = placemark.subThoroughfare ?? ""
        let city = placemark.locality ?? placemark.administrativeArea ?? ""

        let streetPart: String = {
            if !street.isEmpty && !number.isEmpty { return "\(street) \(number)" }
            if !street.isEmpty { return street }
            if let name = placemark.name, !name.isEmpty { return name }
            return ""
        }()

        if !streetPart.isEmpty && !city.isEmpty { return "\(streetPart), \(city)" }
        if !streetPart.isEmpty { return streetPart }
        if !city.isEmpty { return city }
        return "Не удалось определить адрес"
    }

    private func pick(completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response: MKLocalSearch.Response? = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKLocalSearch.Response?, Error>) in
                search.start { response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: response)
                    }
                }
            }

            guard let coordinate = response?.mapItems.first?.placemark.coordinate else { return }

            destinationCoordinate = coordinate
            do {
                let placemarks = try await reverseGeocode(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                if let placemark = placemarks.first {
                    let formatted = formatAddress(placemark: placemark)
                    toAddress = formatted
                    query = formatted
                } else {
                    toAddress = completion.title
                    query = completion.title
                }
            } catch {
                toAddress = completion.title
                query = completion.title
            }

            await MainActor.run {
                isRoutePresented = false
            }
        } catch {
            // Ignore selection errors.
        }
    }
}

// MARK: - Google Maps (вместо MKMapView). Маршрут считаем через MKDirections, линию рисуем GMSPolyline.
private extension MKPolyline {
    var coordinateArray: [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

struct DarkMapView: UIViewRepresentable {
    let centerOnUserTrigger: Int
    @ObservedObject var locationService: LocationService
    let fromCoordinate: CLLocationCoordinate2D?
    let destinationCoordinate: CLLocationCoordinate2D?
    let centerCoordinate: CLLocationCoordinate2D?
    var onMapTap: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Контейнер + Auto Layout: иначе в SwiftUI `GMSMapView` часто остаётся с нулевым размером → белый экран.
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true

        let camera = GMSCameraPosition.camera(withLatitude: 50.45, longitude: 30.52, zoom: 14)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.isMyLocationEnabled = true
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        mapView.delegate = context.coordinator
        // Стандартный тип карты (дороги, здания). Кастомный GMSMapStyle с «урезанным» JSON часто
        // оставляет жесты и маркеры, но векторные тайлы не рисуются — «пустая» карта.
        mapView.mapType = .normal
        mapView.mapStyle = nil

        container.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: container.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.mapView = mapView
        context.coordinator.lastTrigger = centerOnUserTrigger
        context.coordinator.onMapTap = onMapTap
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()

        guard let mapView = context.coordinator.mapView else { return }

        context.coordinator.onMapTap = onMapTap
        context.coordinator.centerCoordinateOverride = centerCoordinate

        if context.coordinator.lastTrigger != centerOnUserTrigger {
            context.coordinator.lastTrigger = centerOnUserTrigger
            context.coordinator.centerOnUserLocation()
        }

        if CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: locationService.latitude, longitude: locationService.longitude)) {
            context.coordinator.lastKnownCoordinate = CLLocationCoordinate2D(
                latitude: locationService.latitude,
                longitude: locationService.longitude
            )
        }

        context.coordinator.updateFromMarker(coordinate: fromCoordinate)
        context.coordinator.updateRoute(
            origin: fromCoordinate,
            destination: destinationCoordinate
        )
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        weak var mapView: GMSMapView?
        var lastTrigger: Int = 0
        var lastKnownCoordinate: CLLocationCoordinate2D?
        var centerCoordinateOverride: CLLocationCoordinate2D?
        var onMapTap: ((CLLocationCoordinate2D) -> Void)?
        var fromMarker: GMSMarker?
        var destinationMarker: GMSMarker?
        var routePolyline: GMSPolyline?
        var routeTask: Task<Void, Never>?

        #if DEBUG
        /// Один раз после первой успешной отрисовки тайлов — признак, что SDK + сеть + ключ приняты сервером.
        private var didLogTilesRendered = false
        #endif

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            onMapTap?(coordinate)
        }

        #if DEBUG
        func mapViewDidFinishTileRendering(_ mapView: GMSMapView) {
            guard !didLogTilesRendered else { return }
            didLogTilesRendered = true
            print("[Google Maps] ✅ тайлы отрисованы впервые — Maps SDK отвечает; если на экране видны дороги, API key для iOS обычно настроен верно.")
        }
        #endif

        func updateFromMarker(coordinate: CLLocationCoordinate2D?) {
            guard let mapView else { return }

            if let coordinate {
                if let fromMarker {
                    fromMarker.position = coordinate
                } else {
                    let marker = GMSMarker(position: coordinate)
                    marker.title = "Откуда"
                    marker.map = mapView
                    fromMarker = marker
                }
            } else {
                fromMarker?.map = nil
                fromMarker = nil
            }
        }

        func centerOnUserLocation() {
            guard let mapView else { return }
            let coordinate = centerCoordinateOverride ?? lastKnownCoordinate ?? mapView.myLocation?.coordinate ?? kCLLocationCoordinate2DInvalid
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            let camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 15)
            mapView.animate(to: camera)
        }

        func updateRoute(origin: CLLocationCoordinate2D?, destination: CLLocationCoordinate2D?) {
            guard let mapView else { return }

            if let destination {
                if let destinationMarker {
                    destinationMarker.position = destination
                } else {
                    let marker = GMSMarker(position: destination)
                    marker.title = "Куда"
                    marker.map = mapView
                    destinationMarker = marker
                }
            } else {
                destinationMarker?.map = nil
                destinationMarker = nil
            }

            guard let origin else {
                clearRoute()
                return
            }
            guard let destination else {
                clearRoute()
                return
            }

            routeTask?.cancel()
            routeTask = Task { @MainActor in
                await calculateAndRenderRoute(
                    mapView: mapView,
                    origin: origin,
                    destination: destination
                )
            }
        }

        @MainActor
        private func clearRoute() {
            routeTask?.cancel()
            routeTask = nil
            routePolyline?.map = nil
            routePolyline = nil
        }

        @MainActor
        private func calculateAndRenderRoute(
            mapView: GMSMapView,
            origin: CLLocationCoordinate2D,
            destination: CLLocationCoordinate2D
        ) async {
            if Task.isCancelled { return }

            let request = MKDirections.Request()
            request.transportType = .automobile
            request.requestsAlternateRoutes = false
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))

            do {
                let directions = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled else { return }
                guard let route = directions.routes.first else {
                    clearRoute()
                    return
                }

                let coords = route.polyline.coordinateArray
                guard !coords.isEmpty else {
                    clearRoute()
                    return
                }

                let path = GMSMutablePath()
                for c in coords {
                    path.addLatitude(c.latitude, longitude: c.longitude)
                }

                routePolyline?.map = nil
                let polyline = GMSPolyline(path: path)
                polyline.strokeWidth = 5
                polyline.strokeColor = UIColor.systemBlue.withAlphaComponent(0.9)
                polyline.map = mapView
                routePolyline = polyline
            } catch {
                clearRoute()
            }
        }
    }
}

struct SideMenuView: View {
    let selected: MenuDestination
    let onSelect: (MenuDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                Text("TestTaxi")
                    .font(.title3.weight(.bold))
                Text("Быстрый доступ к карте, геоданных и списка.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(MenuDestination.allCases) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.iconName)
                            .frame(width: 22)
                        Text(item.rawValue)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(selected == item ? Color.blue.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }
}

struct InfoView: View {
    @ObservedObject var locationService: LocationService

    var body: some View {
        List {
            InfoRow(title: "Latitude", value: String(format: "%.6f", locationService.latitude))
            InfoRow(title: "Longitude", value: String(format: "%.6f", locationService.longitude))
            InfoRow(title: "Speed", value: String(format: "%.2f m/s", locationService.speed))
            InfoRow(title: "Distance", value: String(format: "%.2f m", locationService.distance))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

struct PhotoItem: Codable, Identifiable {
    let id: Int
    let title: String
    let thumbnailUrl: String
}

@MainActor
final class PhotosViewModel: ObservableObject {
    @Published var items: [PhotoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadIfNeeded() async {
        guard items.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let url = URL(string: "https://jsonplaceholder.typicode.com/photos")!
            let (data, _) = try await URLSession.shared.data(from: url)
            items = try JSONDecoder().decode([PhotoItem].self, from: data)
        } catch {
            errorMessage = "Не удалось загрузить список."
        }
    }
}

struct PhotosListView: View {
    @StateObject private var viewModel = PhotosViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Загрузка..")
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            } else {
                List(viewModel.items) { item in
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: item.thumbnailUrl)) { phase in
                            switch phase {
                            case .empty:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                    ProgressView()
                                }
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                            @unknown default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("id: \(item.id)")
                                .font(.subheadline.weight(.semibold))
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

#Preview {
    RootView()
}
