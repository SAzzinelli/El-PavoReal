//  ContentView.swift
//  El-PavoReal
//  v5.0 –  Multi-Tab App: Home, H-ZOO, Minigame
//  v4.1 –  Themed: Levels, In-App Events, Tutorial+, Shop (PavoLire), Settings, Better Layout
//  Fixed: duplicate symbols, removed |> / clampTo, consistent Tutorial API
//  Created by Simone Azzinelli on 23/08/25.

import SwiftUI
import AVKit
import UserNotifications
import CoreLocation

extension Notification.Name {
    static let switchToTab = Notification.Name("switchToTab")
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isNearVenue: Bool = false
    @Published var distanceToVenue: Double = 0
    
    // Coordinate del locale El-PavoReal (esempio - da aggiornare con quelle reali)
    private let venueLocation = CLLocation(latitude: 45.4642, longitude: 9.1900) // Milano Duomo come esempio
    private let geofenceRadius: Double = 20.0 // 20 metri
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0 // Aggiorna ogni 5 metri
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        let distance = location.distance(from: venueLocation)
        distanceToVenue = distance
        
        let wasNearVenue = isNearVenue
        isNearVenue = distance <= geofenceRadius
        
        // Notifica se l'utente è entrato o uscito dalla zona
        if !wasNearVenue && isNearVenue {
            NotificationCenter.default.post(name: .init("UserEnteredVenue"), object: nil)
        } else if wasNearVenue && !isNearVenue {
            NotificationCenter.default.post(name: .init("UserExitedVenue"), object: nil)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates()
        case .denied, .restricted:
            isNearVenue = false
            stopLocationUpdates()
        case .notDetermined:
            requestLocationPermission()
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - 🎬 Local Video Models
struct LocalVideo: Identifiable {
    let id: String
    let title: String
    let videoName: String // Nome del file video in Assets
    let thumbnailName: String // Nome dell'immagine thumbnail in Assets
    let type: VideoType
    
    enum VideoType {
        case aftermovie
        case tiktok
    }
}

// MARK: - Remote Video Models (GitHub Pages)
struct RemoteVideo: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let thumbnail: String // URL della thumbnail
    let videoUrl: String // URL del video
    let date: String
    let duration: String
}

struct RemoteVideoResponse: Codable {
    let aftermovie: [RemoteVideo]
    let tiktok: [RemoteVideo]
}

// MARK: - 🎮 Minigame Dynamic Configuration

// Models
struct MinigamesConfig: Codable {
    let version: Int
    let lastUpdated: String
    let eventGames: [EventGame]?
    let minigames: [MinigameConfig]
    
    enum CodingKeys: String, CodingKey {
        case version
        case lastUpdated = "last_updated"
        case eventGames = "event_games"
        case minigames
    }
}

struct EventGame: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let eventNumbers: [Int]
    let prizes: String
    let startTime: String
    let location: String
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, icon, prizes, location
        case eventNumbers = "event_numbers"
        case startTime = "start_time"
    }
}

struct MinigameConfig: Codable, Identifiable {
    let id: String
    let title: String?
    let subtitle: String?
    let activeFrom: String
    let activeUntil: String
    let enabled: Bool
    let eventNumbers: [Int]
    let type: MinigameType
    let config: MinigameSpecificConfig
    
    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, enabled, type, config
        case activeFrom = "active_from"
        case activeUntil = "active_until"
        case eventNumbers = "event_numbers"
    }
    
    enum MinigameType: String, Codable {
        case slotMachine = "slot_machine"
        case roulette = "roulette"
        case scratchCard = "scratch_card"
        case none = "none"
    }
}

struct MinigameSpecificConfig: Codable {
    // Slot Machine
    let icons: [String]?
    let betAmount: Int?
    let jackpotMultiplier: Int?
    let doubleMultiplier: Int?
    let singleMultiplier: Int?
    
    // Roulette
    let minBet: Int?
    let maxBet: Int?
    let payoutMultiplier: Int?
    
    // Scratch Card
    let cardCost: Int?
    let prizes: [Int]?
    
    enum CodingKeys: String, CodingKey {
        case icons
        case betAmount = "bet_amount"
        case jackpotMultiplier = "jackpot_multiplier"
        case doubleMultiplier = "double_multiplier"
        case singleMultiplier = "single_multiplier"
        case minBet = "min_bet"
        case maxBet = "max_bet"
        case payoutMultiplier = "payout_multiplier"
        case cardCost = "card_cost"
        case prizes
    }
}

// Manager
class MinigameManager: ObservableObject {
    static let shared = MinigameManager()
    
    @Published var currentMinigame: MinigameConfig?
    @Published var currentEventGame: EventGame?
    @Published var isLoading = false
    @Published var lastError: String?
    
    // IMPORTANTE: Sostituisci con il tuo username GitHub
    private let remoteURL = "https://SAzzinelli.github.io/El-PavoReal/api/minigames.json"
    private let cacheKey = "El-PavoReal.minigamesCache"
    private let lastFetchKey = "El-PavoReal.lastMinigameFetch"
    
    private init() {
        loadCachedConfig()
    }
    
    // MARK: - Public Methods
    
    /// Fetch configurazione remota (con cache 24h)
    func fetchConfigIfNeeded() {
        let lastFetch = UserDefaults.standard.double(forKey: lastFetchKey)
        let now = Date().timeIntervalSince1970
        let dayInSeconds: Double = 86400
        
        // Se è passato più di 1 giorno (o mai fatto), fetch
        if now - lastFetch > dayInSeconds || lastFetch == 0 {
            fetchRemoteConfig()
        } else {
            print("🎮 MinigameManager: Cache valida, skip fetch")
        }
    }
    
    /// Forza fetch remoto (per debug/refresh manuale)
    func forceRefresh() {
        fetchRemoteConfig()
    }
    
    /// Ottieni minigame attivo per evento specifico
    func getMinigameForEvent(_ eventNumber: Int) -> MinigameConfig? {
        guard let cached = loadCachedData() else { return nil }
        
        // Trova minigame che contiene questo numero evento
        return cached.minigames.first { minigame in
            minigame.eventNumbers.contains(eventNumber) && minigame.enabled
        }
    }
    
    /// Ottieni minigame attivo per data
    func getMinigameForDate(_ date: Date) -> MinigameConfig? {
        guard let cached = loadCachedData() else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        return cached.minigames.first { minigame in
            guard minigame.enabled,
                  let from = formatter.date(from: minigame.activeFrom),
                  let until = formatter.date(from: minigame.activeUntil) else {
                return false
            }
            return date >= from && date <= until
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchRemoteConfig() {
        guard let url = URL(string: remoteURL) else {
            lastError = "URL non valido"
            return
        }
        
        isLoading = true
        lastError = nil
        
        print("🎮 MinigameManager: Fetching da \(remoteURL)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.lastError = error.localizedDescription
                    print("❌ MinigameManager: Errore fetch - \(error)")
                    return
                }
                
                guard let data = data else {
                    self?.lastError = "Nessun dato ricevuto"
                    print("❌ MinigameManager: Nessun dato")
                    return
                }
                
                do {
                    let config = try JSONDecoder().decode(MinigamesConfig.self, from: data)
                    self?.saveToCache(data)
                    self?.updateCurrentMinigame(from: config)
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self?.lastFetchKey ?? "")
                    print("✅ MinigameManager: Config aggiornata (v\(config.version))")
                } catch {
                    self?.lastError = "Errore parsing JSON: \(error)"
                    print("❌ MinigameManager: Parsing fallito - \(error)")
                }
            }
        }.resume()
    }
    
    private func loadCachedConfig() {
        guard let config = loadCachedData() else {
            print("⚠️ MinigameManager: Nessuna cache trovata")
            return
        }
        updateCurrentMinigame(from: config)
        print("✅ MinigameManager: Cache caricata (v\(config.version))")
    }
    
    private func loadCachedData() -> MinigamesConfig? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MinigamesConfig.self, from: data)
    }
    
    private func saveToCache(_ data: Data) {
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
    
    private func updateCurrentMinigame(from config: MinigamesConfig) {
        // Calcola numero evento corrente
        let eventNumber = HZooConfig.eventNumber(for: Date())
        
        // Trova minigame attivo per questo evento
        currentMinigame = config.minigames.first { minigame in
            minigame.eventNumbers.contains(eventNumber) && minigame.enabled
        }
        
        // Trova gioco della serata attivo per questo evento
        currentEventGame = config.eventGames?.first { game in
            game.eventNumbers.contains(eventNumber)
        }
        
        if let current = currentMinigame {
            print("🎮 Minigame attivo: \(current.title ?? "none") (tipo: \(current.type.rawValue))")
        } else {
            print("🎮 Nessun minigame attivo questa settimana")
        }
        
        if let eventGame = currentEventGame {
            print("🎯 Gioco serata: \(eventGame.title) alle \(eventGame.startTime)")
        } else {
            print("🎯 Nessun gioco della serata configurato")
        }
    }
}

// MARK: - 🎬 Local Video Player
import AVKit

struct LocalVideoPlayerView: View {
    let video: LocalVideo
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            
            VStack {
                HStack {
                    Button("Chiudi") {
                        player?.pause()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
        .onAppear {
            // Carica il video dal bundle
            if let videoURL = Bundle.main.url(forResource: video.videoName, withExtension: "mp4") {
                print("✅ Video trovato: \(video.videoName).mp4")
                print("📁 URL: \(videoURL)")
                player = AVPlayer(url: videoURL)
                player?.play()
                
                // Debug: controlla se il player è valido
                if player == nil {
                    print("❌ Errore: AVPlayer non inizializzato per \(video.videoName)")
                } else {
                    print("✅ AVPlayer inizializzato correttamente per \(video.videoName)")
                }
            } else {
                // Debug: mostra tutti i file disponibili nel bundle
                print("❌ Video non trovato: \(video.videoName).mp4")
                print("📁 File disponibili nel bundle:")
                
                if let resourcePath = Bundle.main.resourcePath {
                    let fileManager = FileManager.default
                    do {
                        let files = try fileManager.contentsOfDirectory(atPath: resourcePath)
                        let videoFiles = files.filter { $0.hasSuffix(".mp4") }
                        print("🎬 Video trovati: \(videoFiles)")
                        
                        // Controlla se il file esiste ma con nome diverso
                        let matchingFiles = files.filter { $0.lowercased().contains(video.videoName.lowercased()) }
                        if !matchingFiles.isEmpty {
                            print("🔍 File simili trovati: \(matchingFiles)")
                        }
                    } catch {
                        print("❌ Errore lettura bundle: \(error)")
                    }
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

import Combine
import UIKit
import UserNotifications

// MARK: - 🦩 H-ZOO Configuration
/// Configurazione centralizzata per la serata H-ZOO
struct HZooConfig {
    // Event Info
    static let eventName = "H-ZOO"
    static let eventTagline = "il venerdì del pavoreal"
    static let venueName = "El-Pavoreal"
    static let venueLocation = ""
    static let venueFullAddress = "Via di Pulicciano 53, Antella (BAGNO A RIPOLI - FIRENZE)"
    
    // Timing (Europe/Rome timezone)
    static let eventDay = 6 // Venerdì (1=Domenica, 7=Sabato secondo Calendar gregoriano standard)
    static let eventStartHour = 23
    static let eventStartMinute = 0
    static let eventEndHour = 5 // Sabato mattina
    static let ladiesDeadlineHour = 0 // Sabato
    static let ladiesDeadlineMinute = 30
    
    // Prezzi
    static let priceMan = "15€"
    static let priceLadyBefore = "Omaggio"
    static let priceLadyAfter = "15€"
    static let priceCoatCheck = "3€"
    static let priceDrink = "8€"
    
    // Contatti
    static let phoneNumber = "+393341812814"
    static let whatsappNumber = "393341812814"
    static let emailAddress = "info@elpavoreal.it"
    static let instagramURL = "https://instagram.com/hzoo_official"
    static let tiktokURL = "https://www.tiktok.com/@elpavorealofficial"
    
    // Video Remote (GitHub Pages)
    static let remoteVideosURL = "https://SAzzinelli.github.io/El-PavoReal/videos.json"
    
    // Video Locali (fallback)
    static let localVideos: [LocalVideo] = [
        LocalVideo(
            id: "aftermovie1",
            title: "AFTERMOVIE #1",
            videoName: "aftermovie1", // File: aftermovie1.mp4 in Assets
            thumbnailName: "aftermovie1_thumb", // File: aftermovie1_thumb.jpg/png in Assets
            type: .aftermovie
        ),
        LocalVideo(
            id: "tiktok1",
            title: "EP.1 - L'APERTURA",
            videoName: "tiktok1", // File: tiktok1.mp4 in Assets
            thumbnailName: "tiktok1_thumb", // File: tiktok1_thumb.jpg/png in Assets
            type: .tiktok
        )
    ]
    
    // KPI (opzionali - nil per nascondere)
    static var estimatedPeakTime: String? = nil
    static var estimatedOccupancy: Int? = nil
    static var tablesLeft: Int? = nil
    static var weatherInfo: String? = nil
    
    // Stile (palette dark/neon)
    static let backgroundDark = Color(hex: "0b0b0c")
    static let primaryNeon = Color(hex: "ff2d95") // Fucsia
    static let accentCyan = Color(hex: "00ffd1")  // Cyan
    static let textWhite = Color.white
    
    // Timezone
    static let timezone = TimeZone(identifier: "Europe/Rome")!
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }
    
    // Counter serate (prima serata: venerdì 3 ottobre 2025 = #1)
    static let firstEventDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 3
        components.hour = 23
        components.minute = 0
        components.timeZone = timezone
        return calendar.date(from: components)!
    }()
    
    static func eventNumber(for date: Date) -> Int {
        let weeksBetween = calendar.dateComponents([.weekOfYear], from: firstEventDate, to: date).weekOfYear ?? 0
        return max(1, weeksBetween + 1)
    }
    
    // Colori dinamici per serate
    static func eventColor(for eventNumber: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "ff2d95"), // Rosa (serata #1)
            Color(hex: "00ffd1"), // Cyan (serata #2)
            Color(hex: "ff6b35"), // Arancione (serata #3)
            Color(hex: "8e44ad"), // Viola (serata #4)
            Color(hex: "e74c3c"), // Rosso (serata #5)
            Color(hex: "f39c12"), // Giallo (serata #6)
            Color(hex: "1abc9c"), // Turchese (serata #7)
            Color(hex: "9b59b6"), // Lavanda (serata #8)
        ]
        return colors[(eventNumber - 1) % colors.count]
    }
}

// Extension per Color da hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

// Analytics tracking helper
func trackEvent(_ name: String, params: [String: Any] = [:]) {
    print("📊 Event: \(name)", params.isEmpty ? "" : "→ \(params)")
}

// Global haptic helper (disponibile ovunque nel file)
@inline(__always)
func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if os(iOS)
    UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
}

/// Pubblica un overlay a schermo intero (EventOverlay) da qualunque punto dell'app.
@inline(__always)
func postOverlayEvent(title: String,
                      icon: String = "sparkles",
                      tone: String = "system", // "positive" | "negative" | "system"
                      lines: [String] = []) {
    NotificationCenter.default.post(
        name: Notification.Name("El-PavoReal.eventOverlay"),
        object: nil,
        userInfo: [
            "title": title,
            "icon": icon,
            "tone": tone,
            "lines": lines
        ]
    )
}

// Effetto “press” usato dai bottoni
private struct PressEffect: ViewModifier {
    @GestureState private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, s, _ in s = true }
            )
    }
}

// Modello per gli eventi casuali (positivo/negativo)
private struct GameEvent {
    let text: String
    let apply: () -> Void
    let symbol: String
    let colors: [Color]
    static func positive(_ text: String, _ apply: @escaping () -> Void, _ symbol: String, _ colors: [Color]) -> GameEvent {
        .init(text: text, apply: apply, symbol: symbol, colors: colors)
    }
    static func negative(_ text: String, _ apply: @escaping () -> Void, _ symbol: String, _ colors: [Color]) -> GameEvent {
        .init(text: text, apply: apply, symbol: symbol, colors: colors)
    }
}

// Componenti usati nel MoodInfoSheet
private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
    }
}

private struct InfoBulletRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 6)
            Text(text).font(.subheadline).foregroundStyle(.white)
        }
    }
}

private struct InfoPill: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.caption.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .foregroundStyle(.white)
    }
}

// --- StatNumberChip & StatsInlineGroup helper views ---
private struct StatNumberChip: View {
    let icon: String
    let value: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(value)")
                .font(.caption2.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Valore: \(value)"))
    }
}

private struct StatsInlineGroup: View {
    @EnvironmentObject var vm: PetViewModel
    var body: some View {
        HStack(spacing: 6) {
            StatNumberChip(icon: "drop.fill", value: Int(vm.satiety.rounded()))     // Sete
            StatNumberChip(icon: "bolt.fill",  value: Int(vm.energy.rounded()))      // Energia
            StatNumberChip(icon: "sparkles",             value: Int(vm.hygiene.rounded()))     // Chill
            StatNumberChip(icon: "party.popper",         value: Int(vm.happiness.rounded()))   // Festa
        }
    }
}

// MARK: - ViewModel
final class PetViewModel: ObservableObject {
    // Core stats 0...100 (alti = meglio). Partono logici da LV0 e scalano col livello.
    @Published var life: Double
    @Published var satiety: Double  // "Sete"
    @Published var energy: Double
    @Published var hygiene: Double
    @Published var happiness: Double
    @Published var isForeground: Bool = true
    @Published var slotWinChance: Double = 0.01 // 1% = 1 su 100 (uguale per tutti i minigame "maglietta")
    
    // Meta
    @Published var ageSeconds: Int
    
    // Nutellino cooldown (absolute timestamp)
    @AppStorage("El-PavoReal.feedNextReadyAt") private var feedNextReadyAt: Double = 0
    private let feedCooldownNutellino: TimeInterval = 360  // o il valore che vuoi
    
    // MARK: - Timekeeping (linear seconds)
    private var lastTickDate: Date = Date()
    private var secondAccumulator: TimeInterval = 0
    
    @Published var lastTick: Date
    @Published var PavoLire: Int // valuta
    @Published var xp: Int = 0 // esperienza cumulativa per il livello

    // Cooldowns
    @Published var lastFed: Date?
    @Published var lastPlayed: Date?
    @Published var lastSlept: Date?
    @Published var lastCleaned: Date?

    // Booster (riduce il decay temporaneamente)
    @Published var boostUntil: Date?

    // Booster meta mostrata nel banner (derivata dall'item acquistato)
    @Published var activeBoosterItemTitle: String? = nil
    @Published var activeBoosterItemSymbol: String? = nil

    /// Chiamare quando si attiva un booster acquistato dallo shop
    func setActiveBooster(from item: ShopItem) {
        self.activeBoosterItemTitle = item.title
        self.activeBoosterItemSymbol = item.symbol
    }

    // Notifiche (antispam)
    @Published var lastLowSatietyNotify: Date?

    // Settings
    @AppStorage("El-PavoReal.hapticsEnabled") var hapticsEnabled: Bool = true

    // MARK: - Cooldowns (fissi, non accumulativi)
    
    // Persistence key (v4)
    private let saveKey = "El-PavoReal.PetState.v4"

    // Balance constants (game design)
    private struct Balance {
        // Livelli
        static let levelSeconds: Int = 600 // 10 min per livello

        // Cooldown base (secondi)
        static let satietyCooldown: TimeInterval = 120  // Nutellino
        static let coffeeCooldown:  TimeInterval = 60   // Caffè
        static let meetCooldown:    TimeInterval = 90   // Orienta su Meet
        static let cleanCooldown:   TimeInterval = 180  // Pulisci

        // Hard cap massimo: moltiplicatore del cooldown base (modifica qui)
        static let cooldownCapMultiplier: Double = 1.0  // hard cap massimo: x2 del cooldown base (modifica qui)

        // Finestre anti‑spam (secondi) e limiti per finestra
        static let satietyWindow: TimeInterval = 600   // 10 min
        static let satietyLimit:  Int         = 2      // max 2 Nutellino/10 min

        static let coffeeWindow:  TimeInterval = 600   // 10 min
        static let coffeeLimit:   Int         = 10     // max 10 Caffè/10 min (praticamente infinito in uso normale)

        static let meetWindow:    TimeInterval = 900   // 15 min
        static let meetLimit:     Int         = 5      // fino a 5 Meet/15 min

        static let cleanWindow:   TimeInterval = 900   // 15 min
        static let cleanLimit:    Int         = 4      // fino a 4 Pulizie/15 min
    }

    // Anti-spam usage timestamps
    private var feedTimes: [Date] = []
    private var coffeeTimes: [Date] = []
    private var meetTimes: [Date] = []
    private var cleanTimes: [Date] = []

    // Passive PavoLire throttle (online)
    private var PavoLireBucket: TimeInterval = 0
    private var rateWindowMinute: Int = Calendar.current.component(.minute, from: Date())
    private var PavoLireThisMinute: Int = 0
    private let maxPavoLirePerMinute: Int = 3

    init() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let s = try? JSONDecoder().decode(SaveState.self, from: data) {
            self.life = s.life
            self.satiety = s.satiety
            self.energy = s.energy
            self.hygiene = s.hygiene
            self.happiness = s.happiness
            self.ageSeconds = s.ageSeconds
            self.lastTick = s.lastTick
            self.PavoLire = s.PavoLire
            self.xp = s.xp
            self.lastFed = s.lastFed
            self.lastPlayed = s.lastPlayed
            self.lastSlept = s.lastSlept
            self.lastCleaned = s.lastCleaned
            self.boostUntil = s.boostUntil
            self.lastLowSatietyNotify = s.lastLowSatietyNotify
            self.activeBoosterItemTitle = s.activeBoosterItemTitle
            self.activeBoosterItemSymbol = s.activeBoosterItemSymbol
        } else {
            // LV0: valori iniziali "umani"
            self.life = 75
            self.satiety = 60
            self.energy = 55
            self.hygiene = 60
            self.happiness = 65
            self.ageSeconds = 0
            self.lastTick = Date()
            self.PavoLire = 50
            self.xp = 0
        }
        let __now = Date()
        prune(&feedTimes,   now: __now, window: Balance.satietyWindow)
        prune(&coffeeTimes, now: __now, window: Balance.coffeeWindow)
        prune(&meetTimes,   now: __now, window: Balance.meetWindow)
        prune(&cleanTimes,  now: __now, window: Balance.cleanWindow)
    }
    

    // MARK: - Level & XP (veloce, max 5 livelli)
    /// Livello massimo del gioco: al 5 il run è considerato concluso
    private let maxLevel: Int = 5
    /// XP necessari per avanzare di livello a partire dal livello corrente (0→1, 1→2, ...)
    /// Totale cumulativo per arrivare al 5 è 60 + 80 + 100 + 120 = 360 XP
    private let xpCostsPerLevel: [Int] = [60, 80, 100, 120, 0] // 0 costa l'ultimo salto (4→5) per chiudere il run

    /// Stato di fine‑gioco: diventa true quando raggiungi (o superi) il livello 5
    @Published var hasFinishedRun: Bool = false

    /// Livello corrente calcolato dagli XP; parte da 0 e arriva a 5
    var level: Int { levelForXP(xp) }

    /// Progresso 0…1 verso il prossimo livello (1 quando hai raggiunto il 5)
    var xpProgress: Double { levelProgress }

    /// Cap delle statistiche che cresce leggermente col livello
    var statCap: Double { min(100, 60 + Double(level) * 5) }

    /// Frazione 0…1 di avanzamento del livello corrente (rispetto al costo successivo)
    private var levelProgress: Double {
        let lv = min(level, maxLevel)
        if lv >= maxLevel { return 1 }
        let need = xpCostsPerLevel[lv]
        let have = xp - totalCostToReachLevel(lv)
        return need == 0 ? 0 : max(0, min(1, Double(have) / Double(need)))
    }

    /// Costo cumulativo per raggiungere esattamente `level` (senza superarlo)
    private func totalCostToReachLevel(_ level: Int) -> Int {
        guard level > 0 else { return 0 }
        // Somma solo i costi "reali" (fino al livello 4). Il 5º valore è un sentinella (.max) e non va sommato.
        let capped = max(0, min(level, maxLevel - 1))
        guard capped > 0 else { return 0 }
        return xpCostsPerLevel.prefix(capped).reduce(0, +)
    }

    /// Livello calcolato dagli XP totali usando `xpCostsPerLevel` (0…5)
    private func levelForXP(_ xp: Int) -> Int {
        var lv = 0
        var pool = xp
        while lv < maxLevel {
            let cost = xpCostsPerLevel[lv]
            if pool >= cost { pool -= cost; lv += 1 } else { break }
        }
        return lv
    }

    /// Forme evolutive del Pavone
    enum EvolutionForm: Int, CaseIterable {
        case pulcino, pavoletto, pavoforte, pavoprincipe, pavoreal
        var displayName: String {
            switch self {
            case .pulcino:       return "Pulcino"
            case .pavoletto:     return "Giovane Coda"
            case .pavoforte:     return "Pavetto"
            case .pavoprincipe:  return "Reale"
            case .pavoreal:      return "Il Pavo‑Real"
            }
        }
        /// Livello minimo per appartenere alla forma
        var minLevel: Int {
            switch self {
            case .pulcino:      return 0   // LV 0
            case .pavoletto:    return 1   // LV 1
            case .pavoforte:    return 2   // LV 2
            case .pavoprincipe: return 4   // LV 4 (nuovo nome: Reale)
            case .pavoreal:     return 5   // LV 5 finale
            }
        }
        /// Perk per forma
        var decayMul: Double {           // <1 = decay più lento
            switch self { case .pulcino:1.00; case .pavoletto:0.98; case .pavoforte:0.96; case .pavoprincipe:0.94; case .pavoreal:0.92 }
        }
        var coinRateMul: Double {        // >1 = P£ più veloci
            switch self { case .pulcino:1.00; case .pavoletto:1.10; case .pavoforte:1.20; case .pavoprincipe:1.35; case .pavoreal:1.50 }
        }
        var boosterMul: Double {         // durata booster
            switch self { case .pulcino:1.00; case .pavoletto:1.05; case .pavoforte:1.10; case .pavoprincipe:1.15; case .pavoreal:1.20 }
        }
        var auraScale: Double {          // grandezza aura sprite
            switch self { case .pulcino:1.00; case .pavoletto:1.06; case .pavoforte:1.12; case .pavoprincipe:1.18; case .pavoreal:1.24 }
        }
        var showsCrown: Bool { self == .pavoprincipe || self == .pavoreal }
        static func forLevel(_ level: Int) -> EvolutionForm {
            EvolutionForm.allCases.last { level >= $0.minLevel } ?? .pulcino
        }
    }

    /// Forma corrente del personaggio
    var form: EvolutionForm { EvolutionForm.forLevel(level) }
    
    // MARK: - Mood (derivato dalle statistiche e inattività)
    enum Mood: String { case felice, noia, rabbia, stanchezza, critico, neutro }

    var lastActionAt: Date? { [lastFed, lastPlayed, lastSlept, lastCleaned].compactMap { $0 }.max() }

    var mood: Mood {
        let now = Date()
        let minStat = min(satiety, energy, hygiene, happiness)
        let avgStat = (satiety + energy + hygiene + happiness) / 4.0

        // Più difficile entrare in "critico" e più facile uscire
        let criticalThreshold = max(8, 0.08 * statCap) // 8 punti o 8% del cap
        if life < 15 || minStat < criticalThreshold { return .critico }

        // Piccola finestra di "good vibes" dopo un'azione (2 min)
        let boostActive: Bool = {
            guard let t = lastActionAt else { return false }
            return now.timeIntervalSince(t) < 120
        }()

        // FELICE: soglie più permissive + consideriamo il boost
        if (minStat >= 58 && life >= 48)
            || (avgStat >= 65 && life >= 45)
            || (boostActive && avgStat >= 55 && life >= 40) {
            return .felice
        }

        // Stati mirati (soglie leggermente alzate per apparire più spesso)
        if energy < 40 { return .stanchezza }
        if happiness < 42 && (satiety < 45 || hygiene < 45) { return .rabbia }

        // NOIA: meno tempo d'inattività e barra Festa non altissima
        let inactivity = now.timeIntervalSince(lastActionAt ?? lastTick)
        if inactivity > 100 && happiness < 65 { return .noia }

        return .neutro
    }

    var moodColors: [Color] {
        switch mood {
        case .felice:      return [.green, .mint]
        case .noia:        return [.gray, .indigo.opacity(0.6)]
        case .rabbia:      return [.red, .orange]
        case .stanchezza:  return [.indigo, .blue.opacity(0.4)]
        case .critico:     return [.red, .black]
        case .neutro:      return [.purple, .blue]
        }
    }

    var moodTitle: String {
        switch mood {
        case .felice: return "Felice"
        case .noia: return "Noia"
        case .rabbia: return "Rabbia"
        case .stanchezza: return "Stanchezza"
        case .critico: return "Critico"
        case .neutro: return "Neutro"
        }
    }

    var moodSymbol: String {
        switch mood {
        case .felice: return "sun.max.fill"
        case .noia: return "hourglass"
        case .rabbia: return "flame.fill"
        case .stanchezza: return "zzz"
        case .critico: return "heart.slash.fill"
        case .neutro: return "circle"
        }
    }
    
    /// Nome dello sprite dinamico basato sul mood corrente
    var moodSpriteName: String {
        switch mood {
        case .felice:       return "pavone_felice"
        case .noia:         return "pavone_noia"
        case .rabbia:       return "pavone_arrabbiato"
        case .stanchezza:   return "pavone_assonnato"
        case .critico:      return "pavone_triste"
        case .neutro:       return "pavone_neutro"
        }
    }

    // MARK: - Perk multipliers (in base all'umore)
    private var xpMultiplier: Double {
        switch mood { case .felice: return 1.10; case .noia: return 1.0; case .rabbia: return 1.0; case .stanchezza: return 0.95; case .critico: return 0.9; case .neutro: return 1.0 }
    }
    private var passivePavoLireSeconds: Int {
        switch mood { case .felice: return 15; case .critico: return 30; default: return 20 }
    }
    private enum ActionKind { case feed, coffee, meet, clean }
    private func effectMultiplier(_ kind: ActionKind) -> Double {
        switch (mood, kind) {
        case (.rabbia, .feed), (.rabbia, .coffee): return 1.10
        case (.stanchezza, .coffee): return 1.15
        case (.noia, .meet): return 1.10
        default: return 1.0
        }
    }

    // MARK: - Valori che si abbassano (decay bilanciato, foreground/background)
    func tick(now: Date = Date()) {
        // === Linear timekeeping ===
        let raw = now.timeIntervalSince(lastTickDate)
        lastTickDate = now
        // Clamp extreme jumps (e.g., debugger pauses) to avoid huge spikes
        let delta = max(0, min(raw, 5.0))
        secondAccumulator += delta

        // Convert accumulated fractional time into whole-second ticks
        let wholeSeconds = Int(secondAccumulator)
        if wholeSeconds > 0 {
            ageSeconds &+= wholeSeconds
            secondAccumulator -= TimeInterval(wholeSeconds)
        }

        // Guadagno passivo PavoLire (ridotto in foreground)
        let minute = Calendar.current.component(.minute, from: now)
        if minute != rateWindowMinute {
            rateWindowMinute = minute
            PavoLireThisMinute = 0
        }
        PavoLireBucket += delta
        var spm = TimeInterval(passivePavoLireSeconds) // secondi per 1 PavoLire base (dipende dall'umore)
        // Se l'app è in foreground, rallenta il rate e abbassa il tetto/minuto
        if isForeground {
            spm *= 2.5               // 2.5x più lenti a guadagnare quando aperta
            spm /= max(1.0, form.coinRateMul)
        }
        let minuteCap = isForeground ? 1 : maxPavoLirePerMinute
        while PavoLireBucket >= spm && PavoLireThisMinute < minuteCap {
            PavoLire += 1
            PavoLireThisMinute += 1
            PavoLireBucket -= spm
        }

        // MARK: - Valori che si abbassano (decay bilanciato, foreground/background)
        let decayMul: Double = isForeground ? 1.0 : 0.4    // app aperta = normale; app chiusa = ~2.5x più lento

        // Obiettivi: 100→0 a app aperta in X ore
        let satietyPerSec   = 100.0 / (7.0  * 3600.0)  // Sete  ~7h (più rapida)
        let energyPerSec    = 100.0 / (9.0  * 3600.0)  // Energia ~9h (leggermente più rapida)
        let hygienePerSec   = 100.0 / (7.0  * 3600.0)  // Chill ~7h (più rapida)

        var sRate = satietyPerSec
        var eRate = energyPerSec
        var hRate = hygienePerSec

        // Booster (dimezza i decay finché attivo)
        if let until = boostUntil, until > now {
            sRate *= 0.5; eRate *= 0.5; hRate *= 0.5
        }

        // Perk di livello: -2% decay per livello (fino a -30%)
        let levelMul = max(0.7, 1.0 - 0.02 * Double(level))
        sRate *= levelMul; eRate *= levelMul; hRate *= levelMul
        sRate *= form.decayMul; eRate *= form.decayMul; hRate *= form.decayMul
        
        // Boost solo in foreground (app aperta): target ~30 min Sete/Chill, ~36 min Energia
        if isForeground {
            sRate *= 14.0   // 7h → ~30 min
            hRate *= 14.0   // 7h → ~30 min
            eRate *= 15.0   // 9h → ~36 min
        }

        // Micro-tweak per umore
        switch mood {
        case .felice:
            sRate *= 0.95; eRate *= 0.95; hRate *= 0.95
        case .stanchezza:
            eRate *= 1.15
        case .noia:
            // leggera perdita autonoma quando annoiato
            happiness = clamp(happiness - 0.004 * delta * decayMul, maxV: statCap)
        default:
            break
        }

        // Applica i decay (scalati quando l'app è chiusa)
        satiety = clamp(satiety - sRate * delta * decayMul, maxV: statCap)
        energy  = clamp(energy  - eRate  * delta * decayMul, maxV: statCap)
        hygiene = clamp(hygiene - hRate  * delta * decayMul, maxV: statCap)

        // Felicità si allinea alla media delle altre
        let targetH = (energy + hygiene + satiety) / 3
        happiness = clamp(lerp(from: happiness, to: targetH, t: 0.070), maxV: statCap)

        // Vita: se una stat è critica drena; altrimenti rigenera.
        let penalty = criticalDrain()
        let goodStats = satiety > 0.6 * statCap && energy > 0.6 * statCap && hygiene > 0.6 * statCap && happiness > 0.6 * statCap
        let regenRate: Double = goodStats ? 0.06 : 0.03
        let lifeDelta: Double = (penalty > 0) ? -penalty : regenRate
        life = clamp(life + lifeDelta * delta)
        // Notifica se Sete bassa
        maybeNotifyLowSatiety(now: now)

        lastTick = now
        save()
    }

    private func criticalDrain() -> Double {
        let t = 0.15 * statCap
        var d: Double = 0
        if satiety < t { d += (t - satiety) * 0.012 }
        if energy  < t { d += (t - energy)  * 0.012 }
        if hygiene < t { d += (t - hygiene) * 0.01 }
        if happiness < t { d += (t - happiness) * 0.012 }
        return d
    }

    // MARK: - Helper antispammone
    private func prune(_ arr: inout [Date], now: Date = Date(), window: TimeInterval) { arr.removeAll { now.timeIntervalSince($0) > window } }
    private func countInWindow(_ arr: [Date], now: Date = Date(), window: TimeInterval) -> Int { arr.filter { now.timeIntervalSince($0) <= window }.count }

    // Remaining-time helpers and hints
    private func timeRemaining(since last: Date?, cooldown: TimeInterval, now: Date = Date()) -> TimeInterval {
        guard let last else { return 0 }
        return max(0, cooldown - now.timeIntervalSince(last))
    }
    private func windowRemaining(_ arr: [Date], limit: Int, window: TimeInterval, now: Date = Date()) -> TimeInterval {
        let recent = arr.filter { now.timeIntervalSince($0) <= window }.sorted(by: { $0 < $1 })
        guard recent.count >= limit, let earliest = recent.first else { return 0 }
        return max(0, window - now.timeIntervalSince(earliest))
    }

    func feedRemaining() -> TimeInterval {
        let now = Date(); prune(&feedTimes, now: now, window: Balance.satietyWindow)
        let cool = timeRemaining(since: lastFed, cooldown: Balance.satietyCooldown, now: now)
        let win  = windowRemaining(feedTimes, limit: Balance.satietyLimit, window: Balance.satietyWindow, now: now)
        let rem  = max(cool, win)
        // hard cap: mai oltre cooldown base × cap multiplier
        return min(rem, Balance.satietyCooldown * Balance.cooldownCapMultiplier)
    }
    func coffeeRemaining() -> TimeInterval {
        let now = Date(); prune(&coffeeTimes, now: now, window: Balance.coffeeWindow)
        let cool = timeRemaining(since: lastSlept, cooldown: Balance.coffeeCooldown, now: now)
        let win  = windowRemaining(coffeeTimes, limit: Balance.coffeeLimit, window: Balance.coffeeWindow, now: now)
        let rem  = max(cool, win)
        // hard cap: mai oltre cooldown base × cap multiplier
        return min(rem, Balance.coffeeCooldown * Balance.cooldownCapMultiplier)
    }
    func meetRemaining() -> TimeInterval {
        let now = Date(); prune(&meetTimes, now: now, window: Balance.meetWindow)
        let cool = timeRemaining(since: lastPlayed, cooldown: Balance.meetCooldown, now: now)
        let win  = windowRemaining(meetTimes, limit: Balance.meetLimit, window: Balance.meetWindow, now: now)
        let rem  = max(cool, win)
        return min(rem, Balance.meetCooldown * Balance.cooldownCapMultiplier)
    }
    func cleanRemaining() -> TimeInterval {
        let now = Date(); prune(&cleanTimes, now: now, window: Balance.cleanWindow)
        let cool = timeRemaining(since: lastCleaned, cooldown: Balance.cleanCooldown, now: now)
        let win  = windowRemaining(cleanTimes, limit: Balance.cleanLimit, window: Balance.cleanWindow, now: now)
        let rem  = max(cool, win)
        return min(rem, Balance.cleanCooldown * Balance.cooldownCapMultiplier)
    }

    private func mmss(_ seconds: TimeInterval) -> String {
        let s = Int(ceil(max(0, seconds)))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    var canFeedNow: Bool { feedRemaining() <= 0 }
    var canCoffeeNow: Bool { coffeeRemaining() <= 0 }
    var canMeetNow: Bool { meetRemaining() <= 0 }
    var canCleanNow: Bool { cleanRemaining() <= 0 }

    private func addXP(_ amount: Int) {
        let preLevel = level
        let preForm  = form

        // Se già al livello massimo, segna comunque fine‑run ed esci
        if preLevel >= maxLevel {
            hasFinishedRun = true
            return
        }

        let inc = Int(round(Double(amount) * xpMultiplier))
        xp = max(0, xp + inc)

        // Hard‑cap: non oltrepassare il costo cumulativo per il LV 5
        let capXP = totalCostToReachLevel(maxLevel)
        if xp >= capXP {
            xp = capXP
        }

        save()

        let postLevel = level
        let postForm  = form

        if postLevel > preLevel {
            NotificationCenter.default.post(name: Notification.Name("El-PavoReal.levelUp"),
                                            object: nil, userInfo: ["level": postLevel])
        }
        if postForm != preForm {
            NotificationCenter.default.post(name: Notification.Name("El-PavoReal.evolved"),
                                            object: nil, userInfo: ["name": postForm.displayName])
        }

        // Fine‑gioco al raggiungimento del LV 5
        if postLevel >= maxLevel {
            hasFinishedRun = true
            NotificationCenter.default.post(name: Notification.Name("El-PavoReal.gameFinished"), object: nil)
        }
    }

    // MARK: - Actions
    func feedNutellino() {
        guard canFeedNow else { return }
        hapticIfEnabled(.soft)
        feedTimes.append(Date())
        lastFed = Date()
        let mul = effectMultiplier(.feed)
        satiety = clamp(satiety + 22 * mul, maxV: statCap)
        happiness = clamp(happiness + 6 * mul, maxV: statCap)
        addXP(5)
        feedNextReadyAt = Date().timeIntervalSince1970 + feedCooldownNutellino
        save()
    }

    func coffeeBreak() {
        guard canCoffeeNow else { return }
        hapticIfEnabled(.rigid)
        coffeeTimes.append(Date())
        lastSlept = Date()
        let mul = effectMultiplier(.coffee)
        energy = clamp(energy + 24 * mul, maxV: statCap)
        satiety = clamp(satiety - 3 * mul, maxV: statCap)
        addXP(4)
        save()
    }

    func orientaSuMeet() {
        guard canMeetNow else { return }
        hapticIfEnabled(.light)
        meetTimes.append(Date())
        lastPlayed = Date()
        let mul = effectMultiplier(.meet)
        happiness = clamp(happiness + 12 * mul, maxV: statCap)
        PavoLire += 2 // appuntamenti remunerativi in PavoLire
        addXP(8)
        save()
    }

    func pulisciScrivania() {
        guard canCleanNow else { return }
        hapticIfEnabled(.medium)
        cleanTimes.append(Date())
        lastCleaned = Date()
        let mul = effectMultiplier(.clean)
        hygiene = clamp(hygiene + 26 * mul, maxV: statCap)
        addXP(5)
        save()
    }
    // Hard reset: azzera stato e preferenze chiave del pet
    func resetAll() {
        life = 75
        satiety = 60
        energy = 55
        hygiene = 60
        happiness = 65
        ageSeconds = 0
        lastTick = Date()
        PavoLire = 50
        lastFed = nil
        xp=0
        lastPlayed = nil
        lastSlept = nil
        lastCleaned = nil
        boostUntil = nil
        lastLowSatietyNotify = nil
        feedNextReadyAt = 0
        feedTimes.removeAll(); coffeeTimes.removeAll(); meetTimes.removeAll(); cleanTimes.removeAll()
        UserDefaults.standard.removeObject(forKey: saveKey)
        save()
    }

    func clearCooldowns() {
        lastFed = nil
        lastPlayed = nil
        lastSlept = nil
        lastCleaned = nil
        feedTimes.removeAll()
        coffeeTimes.removeAll()
        meetTimes.removeAll()
        cleanTimes.removeAll()
        save()
    }


    // BOOSTER: Sigla del Pavo
    func bomberCandyBoost(seconds: Double = 300) {
        if PavoLire >= 35 {
            PavoLire -= 35
            boostUntil = Date().addingTimeInterval(seconds)
            self.activeBoosterItemTitle = "Canta la SIGLA!"
            self.activeBoosterItemSymbol = "bolt.heart.fill"
            save()
        }
    }

    // SHOP generic
    func buy(item: ShopItem) {
        let effectivePrice = price(for: item)
        guard PavoLire >= effectivePrice else { return }
        PavoLire -= effectivePrice
        switch item.effect {
        case .heal(let stat, let amount):
            applyHeal(stat: stat, amount: amount)
        case .booster(let seconds):
            boostUntil = Date().addingTimeInterval(seconds)
            setActiveBooster(from: item)
        }
        save()
    }

    private func applyHeal(stat: HealStat, amount: Double) {
        switch stat {
        case .life: life = clamp(life + amount)
        case .satiety: satiety = clamp(satiety + amount, maxV: statCap)
        case .energy: energy = clamp(energy + amount, maxV: statCap)
        case .hygiene: hygiene = clamp(hygiene + amount, maxV: statCap)
        case .happiness: happiness = clamp(happiness + amount, maxV: statCap)
        }
    }

    private func canUse(_ last: Date?, cooldown: TimeInterval) -> Bool {
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= cooldown
    }

    // MARK: - Helpers
    private func clamp(_ v: Double, _ minV: Double = 0, maxV: Double = 100) -> Double { min(max(v, minV), maxV) }
    private func lerp(from a: Double, to b: Double, t: Double) -> Double { a + (b - a) * t }

    
    // MARK: - Dynamic pricing per livello
    /// Moltiplicatore prezzo che cresce dolcemente con il livello (≈ +4% per livello)
    func priceMultiplier(forLevel level: Int) -> Double { pow(1.04, Double(max(0, level))) }

    /// Prezzo effettivo per un item, tenendo conto del livello corrente
    func price(for item: ShopItem) -> Int {
        let p = Double(item.cost) * priceMultiplier(forLevel: level)
        return max(1, Int(round(p)))
    }
    
    // MARK: - Notifications
    private func maybeNotifyLowSatiety(now: Date) {
        guard satiety < 0.25 * statCap else { return }
        if !UserDefaults.standard.bool(forKey: "El-PavoReal.notificationsEnabled") { return }
        if let last = lastLowSatietyNotify, now.timeIntervalSince(last) < 1800 { return } // 30 min cooldown
        lastLowSatietyNotify = now
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Il pavone ha preso un Gin Tonic!"
            content.body = "Entra a controllare se è tutto ok! 💪"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let req = UNNotificationRequest(identifier: "lowSatiety_\(now.timeIntervalSince1970)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req)
        }
    }

    private func hapticIfEnabled(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        if hapticsEnabled { haptic(style) }
    }

    // MARK: - Persistence
    private struct SaveState: Codable {
        let life: Double, satiety: Double, energy: Double, hygiene: Double, happiness: Double
        let ageSeconds: Int, lastTick: Date, PavoLire: Int
        let lastFed: Date?, lastPlayed: Date?, lastSlept: Date?, lastCleaned: Date?
        let boostUntil: Date?
        let lastLowSatietyNotify: Date?
        let xp: Int
        let activeBoosterItemTitle: String?
        let activeBoosterItemSymbol: String?

        enum CodingKeys: String, CodingKey { case life, satiety, energy, hygiene, happiness, ageSeconds, lastTick, PavoLire, lastFed, lastPlayed, lastSlept, lastCleaned, boostUntil, lastLowSatietyNotify, xp, activeBoosterItemTitle, activeBoosterItemSymbol }
        init(life: Double, satiety: Double, energy: Double, hygiene: Double, happiness: Double, ageSeconds: Int, lastTick: Date, PavoLire: Int, lastFed: Date?, lastPlayed: Date?, lastSlept: Date?, lastCleaned: Date?, boostUntil: Date?, lastLowSatietyNotify: Date?, xp: Int, activeBoosterItemTitle: String?, activeBoosterItemSymbol: String?) {
            self.life = life; self.satiety = satiety; self.energy = energy; self.hygiene = hygiene; self.happiness = happiness
            self.ageSeconds = ageSeconds; self.lastTick = lastTick; self.PavoLire = PavoLire
            self.lastFed = lastFed; self.lastPlayed = lastPlayed; self.lastSlept = lastSlept; self.lastCleaned = lastCleaned
            self.boostUntil = boostUntil; self.lastLowSatietyNotify = lastLowSatietyNotify; self.xp = xp
            self.activeBoosterItemTitle = activeBoosterItemTitle; self.activeBoosterItemSymbol = activeBoosterItemSymbol
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            life = try c.decode(Double.self, forKey: .life)
            satiety = try c.decode(Double.self, forKey: .satiety)
            energy = try c.decode(Double.self, forKey: .energy)
            hygiene = try c.decode(Double.self, forKey: .hygiene)
            happiness = try c.decode(Double.self, forKey: .happiness)
            ageSeconds = try c.decode(Int.self, forKey: .ageSeconds)
            lastTick = try c.decode(Date.self, forKey: .lastTick)
            PavoLire = try c.decode(Int.self, forKey: .PavoLire)
            lastFed = try c.decodeIfPresent(Date.self, forKey: .lastFed)
            lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
            lastSlept = try c.decodeIfPresent(Date.self, forKey: .lastSlept)
            lastCleaned = try c.decodeIfPresent(Date.self, forKey: .lastCleaned)
            boostUntil = try c.decodeIfPresent(Date.self, forKey: .boostUntil)
            lastLowSatietyNotify = try c.decodeIfPresent(Date.self, forKey: .lastLowSatietyNotify)
            xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
            activeBoosterItemTitle = try c.decodeIfPresent(String.self, forKey: .activeBoosterItemTitle)
            activeBoosterItemSymbol = try c.decodeIfPresent(String.self, forKey: .activeBoosterItemSymbol)
        }
    }

    private func save() {
        let s = SaveState(
            life: life, satiety: satiety, energy: energy, hygiene: hygiene, happiness: happiness,
            ageSeconds: ageSeconds, lastTick: lastTick, PavoLire: PavoLire,
            lastFed: lastFed, lastPlayed: lastPlayed, lastSlept: lastSlept, lastCleaned: lastCleaned,
            boostUntil: boostUntil, lastLowSatietyNotify: lastLowSatietyNotify, xp: xp,
            activeBoosterItemTitle: activeBoosterItemTitle, activeBoosterItemSymbol: activeBoosterItemSymbol
        )
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: saveKey) }
    }
}
// Shop theming (superfici solide, niente blur)
private let shopSurface = Color.white.opacity(0.06)
private let shopStroke  = Color.white.opacity(0.12)

// MARK: - Shop Models
enum HealStat: String { case life, satiety, energy, hygiene, happiness }
struct ShopItem: Identifiable { let id = UUID(); let title: String; let cost: Int; let effect: Effect; let symbol: String; let colors: [Color]
    enum Effect { case heal(stat: HealStat, amount: Double); case booster(seconds: Double) }
}

let defaultShopItems: [ShopItem] = [
    // DRINKS & SHOT (Energia) - Rosa/Viola
    .init(title: "Shot (+12 Energia)",          cost: 10, effect: .heal(stat: .energy,    amount: 12), symbol: "bolt.fill",          colors: [.pink, .purple]),
    .init(title: "Giro di Shot (+28 Energia)",  cost: 24, effect: .heal(stat: .energy,    amount: 28), symbol: "bolt.circle.fill",   colors: [.pink, .purple]),
    .init(title: "Gin Tonic (+25 Energia)",     cost: 22, effect: .heal(stat: .energy,    amount: 25), symbol: "bolt.fill",          colors: [.pink, .purple]),
    .init(title: "Negroni (+35 Energia)",       cost: 30, effect: .heal(stat: .energy,    amount: 35), symbol: "bolt.fill",          colors: [.pink, .purple]),
    .init(title: "Due Drink (+40 Energia)",     cost: 36, effect: .heal(stat: .energy,    amount: 40), symbol: "bolt.fill",          colors: [.pink, .purple]),

    // RECOVERY / WATER (Sete) - Verde/Mint
    .init(title: "Acqua Fresca (+30 Sete)",     cost: 12, effect: .heal(stat: .satiety,   amount: 30), symbol: "wineglass.fill",     colors: [.green, .mint]),

    // EXPERIENCE / HAPPINESS (Festa) - Giallo/Arancio
    .init(title: "Saltellare con Fabio (+35 Festa)", cost: 34, effect: .heal(stat: .happiness, amount: 35), symbol: "music.mic", colors: [.yellow, .orange]),

    // ACCESS & FAST LANE - Seguono le loro categorie
    .init(title: "Bracciale Privé (+30 Festa)", cost: 38, effect: .heal(stat: .happiness, amount: 30), symbol: "lock.open.fill",    colors: [.yellow, .orange]),
    .init(title: "Salta La Fila (+24 Energia)", cost: 26, effect: .heal(stat: .energy,    amount: 24), symbol: "figure.walk",       colors: [.pink, .purple]),
    .init(title: "Ticket Uscita (+30 Chill)",   cost: 20, effect: .heal(stat: .hygiene,   amount: 30), symbol: "ticket.fill",       colors: [.blue, .cyan]),

    // LEGENDARIO (Booster) - Viola/Rosa
    .init(title: "Cambusa col Socchi (10m)",    cost: 95, effect: .booster(seconds: 600), symbol: "crown.fill",           colors: [.purple, .pink])
]

let extraShopItems: [ShopItem] = [
    // — ACCESSORI & GADGET OFFERTI — (Festa) - Giallo/Arancio
    .init(title: "Occhiali Pavo-Real (+14 Festa)",  cost: 16, effect: .heal(stat: .happiness, amount: 14), symbol: "eyeglasses",        colors: [.yellow, .orange]),
    .init(title: "Collana Pavo-Real (+10 Festa)",   cost: 14, effect: .heal(stat: .happiness, amount: 10), symbol: "sparkles",         colors: [.yellow, .orange]),
    .init(title: "Braccialetti Pavo-Real (+8 Festa)", cost: 12, effect: .heal(stat: .happiness, amount: 8), symbol: "link",            colors: [.yellow, .orange]),

    // — SERVIZI & ACCESSI —
    .init(title: "Ticket Guardaroba (+28 Chill)",   cost: 14, effect: .heal(stat: .hygiene,   amount: 28), symbol: "tag.fill",         colors: [.blue, .cyan]),
    .init(title: "Entra in Console (+30 Festa)",    cost: 48, effect: .heal(stat: .happiness, amount: 30), symbol: "music.note.list",  colors: [.yellow, .orange]),
    .init(title: "Tavolo in Pista (+40 Festa)",     cost: 60, effect: .heal(stat: .happiness, amount: 40), symbol: "person.3.fill",    colors: [.yellow, .orange]),

    // — BOOST & SPECIAL —
    .init(title: "Minigioco al Bar (5m)",           cost: 35, effect: .booster(seconds: 300), symbol: "gamecontroller.fill", colors: [.purple, .pink]),
    .init(title: "Tavolo nel Privé (20m)",          cost: 120, effect: .booster(seconds: 1200), symbol: "lock.open.fill",   colors: [.yellow, .orange]),
    .init(title: "SIGLA: El-PavoReal (1h)",         cost: 280, effect: .booster(seconds: 3600), symbol: "megaphone.fill",   colors: [.yellow, .orange])
]

// MARK: - Settings model
class SettingsModel: ObservableObject {
    @AppStorage("El-PavoReal.hapticsEnabled") var hapticsEnabled: Bool = true
    @AppStorage("El-PavoReal.eventChance") var eventChance: Double = 0.08
    @AppStorage("El-PavoReal.compactPadding") var compactPadding: Bool = true
    @AppStorage("El-PavoReal.reduceMotion") var reduceMotion: Bool = false
    @AppStorage("user_gender_preference") var userGenderPreference: String = "maschio"
}

// MARK: - Helper Components for New Tabs

struct InfoSection2<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            
            content
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

struct CountdownCard: View {
    @State private var timeRemaining = "2 giorni, 14 ore"
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Prossimo H-ZOO")
                .font(.headline.bold())
                .foregroundStyle(.white)
            
            Text(timeRemaining)
                .font(.title2.bold())
                .foregroundStyle(.orange)
            
            Text("Venerdì 21:00")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

struct EventSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            
            content
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

struct EventTimeSlot: View {
    let time: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.caption.bold())
                .foregroundStyle(.orange)
                .frame(width: 50, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SpecialCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.3), in: Circle())
            
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            
            Text(description)
                .font(.caption.bold())
                .foregroundStyle(color)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Componenti per El PavoReal & H-ZOO

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PavoEventCard: View {
    let title: String
    let date: String
    let time: String
    let description: String
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(accentColor)
            }
            
            Text(time)
                .font(.caption.weight(.medium))
                .foregroundStyle(accentColor)
            
            Text(description)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

struct DrinkCard: View {
    let name: String
    let price: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color(red: 0.8, green: 0.6, blue: 0.3))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(price)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}

struct AccessRule: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.pink)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
}

struct MerchCard: View {
    let title: String
    let price: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.pink)
                .frame(height: 60)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(price)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.pink)
            }
        }
        .frame(width: 120)
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.pink.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.3), in: Circle())
            
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}


// MARK: - H-ZOO Countdown ViewModel
class HZooCountdownViewModel: ObservableObject {
    @Published var days = 0
    @Published var hours = 0
    @Published var minutes = 0
    @Published var seconds = 0
    @Published var isEventActive = false
    @Published var showLadiesFreeBadge = false
    @Published var showSiglaQuote = false // 1:30-2:00
    @Published var elapsedMinutes = 0
    @Published var ladiesCountdown = ""
    @Published var nextEventDateString = ""
    @Published var nextEventFullDateString = "" // "Venerdì 10 Ottobre"
    @Published var nextEventNumber = 1 // "#1"
    @Published var accessibilityLabel = ""
    
    private var timer: Timer?
    private let cal = HZooConfig.calendar
    
    init() {
        recalculate()
        startTimer()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recalculate()
        }
    }
    
    func recalculate() {
        let now = Date()
        
        // Calcola la prossima serata venerdì 23:00
        let nextEventDate = calculateNextEvent(from: now)
        
        // Verifica se la serata è in corso (venerdì 23:00 - sabato 05:00)
        let eventStart = getEventStartTime(for: now)
        let eventEnd = getEventEndTime(for: now)
        
        if now >= eventStart && now < eventEnd {
            // Serata in corso
            isEventActive = true
            let elapsed = Int(now.timeIntervalSince(eventStart))
            elapsedMinutes = elapsed / 60
            
            // Verifica badge omaggio donna (fino alle 00:30 del sabato)
            let ladiesDeadline = getLadiesDeadline(for: now)
            if now < ladiesDeadline {
                showLadiesFreeBadge = true
                let remaining = Int(ladiesDeadline.timeIntervalSince(now))
                let mins = (remaining / 60) % 60
                let secs = remaining % 60
                ladiesCountdown = String(format: "%02d:%02d", mins, secs)
            } else {
                showLadiesFreeBadge = false
            }
            
            // Verifica micro-quote sigla (sabato 1:30-2:00)
            let nowComponents = cal.dateComponents([.hour, .minute], from: now)
            let currentHour = nowComponents.hour ?? 0
            let currentMinute = nowComponents.minute ?? 0
            let currentWeekday = cal.component(.weekday, from: now)
            
            // Sabato (7) tra 1:30 e 2:00
            if currentWeekday == 7 && currentHour == 1 && currentMinute >= 30 {
                showSiglaQuote = true
            } else if currentWeekday == 7 && currentHour == 2 && currentMinute == 0 {
                showSiglaQuote = true
            } else {
                showSiglaQuote = false
            }
            
            accessibilityLabel = "Serata in corso. Trascorsi \(elapsedMinutes) minuti"
        } else {
            // Countdown al prossimo evento
            isEventActive = false
            showLadiesFreeBadge = false
            showSiglaQuote = false
            
            let interval = Int(nextEventDate.timeIntervalSince(now))
            days = interval / 86400
            hours = (interval % 86400) / 3600
            minutes = (interval % 3600) / 60
            seconds = interval % 60
            
            // Formatta data per display (senza giorno della settimana)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "it_IT")
            formatter.timeZone = HZooConfig.timezone
            formatter.dateFormat = "d MMM · HH:mm"
            nextEventDateString = formatter.string(from: nextEventDate)
            
            // Formatta data estesa (senza giorno della settimana)
            let fullFormatter = DateFormatter()
            fullFormatter.locale = Locale(identifier: "it_IT")
            fullFormatter.timeZone = HZooConfig.timezone
            fullFormatter.dateFormat = "d MMMM"
            nextEventFullDateString = fullFormatter.string(from: nextEventDate).capitalized
            
            // Calcola numero serata
            nextEventNumber = HZooConfig.eventNumber(for: nextEventDate)
            
            accessibilityLabel = "Mancano \(days) giorni, \(hours) ore, \(minutes) minuti al prossimo H-ZOO"
        }
    }
    
    func calculateNextEvent(from date: Date) -> Date {
        var components = cal.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        
        let currentWeekday = components.weekday ?? 1
        let currentHour = components.hour ?? 0
        let currentMinute = components.minute ?? 0
        
        // Venerdì è weekday 6 nel gregoriano (1=Dom, 2=Lun, ..., 6=Ven, 7=Sab)
        let fridayWeekday = 6
        
        var targetDate: Date
        
        if currentWeekday == fridayWeekday {
            // Oggi è venerdì
            if currentHour < HZooConfig.eventStartHour || (currentHour == HZooConfig.eventStartHour && currentMinute < HZooConfig.eventStartMinute) {
                // Prima delle 23:00 → target oggi
                components.hour = HZooConfig.eventStartHour
                components.minute = HZooConfig.eventStartMinute
                components.second = 0
                targetDate = cal.date(from: components)!
            } else {
                // Dopo le 23:00 → prossimo venerdì
                targetDate = nextFriday(after: date)
            }
        } else {
            // Non è venerdì → trova il prossimo venerdì
            targetDate = nextFriday(after: date)
        }
        
        return targetDate
    }
    
    private func nextFriday(after date: Date) -> Date {
        var components = DateComponents()
        components.weekday = 6 // Venerdì
        components.hour = HZooConfig.eventStartHour
        components.minute = HZooConfig.eventStartMinute
        components.second = 0
        
        let nextDate = cal.nextDate(after: date, matching: components, matchingPolicy: .nextTime)!
        return nextDate
    }
    
    private func getEventStartTime(for date: Date) -> Date {
        var components = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        let currentWeekday = components.weekday ?? 1
        
        // Se oggi è sabato mattina presto (prima delle 05:00), l'evento è iniziato venerdì sera
        if currentWeekday == 7 { // Sabato
            let hour = cal.component(.hour, from: date)
            if hour < HZooConfig.eventEndHour {
                // Torna a venerdì sera
                components.day! -= 1
            } else {
                // Evento finito, cerca venerdì scorso per evitare match
                return date.addingTimeInterval(-100000)
            }
        } else if currentWeekday != 6 {
            // Non venerdì/sabato → nessun evento attivo
            return date.addingTimeInterval(-100000)
        }
        
        components.hour = HZooConfig.eventStartHour
        components.minute = HZooConfig.eventStartMinute
        components.second = 0
        return cal.date(from: components) ?? date
    }
    
    private func getEventEndTime(for date: Date) -> Date {
        let startTime = getEventStartTime(for: date)
        guard startTime < date else { return date }
        
        // L'evento finisce sabato mattina alle 05:00
        var endComponents = cal.dateComponents([.year, .month, .day], from: startTime)
        endComponents.day! += 1  // Passa a sabato
        endComponents.hour = HZooConfig.eventEndHour
        endComponents.minute = 0
        endComponents.second = 0
        
        return cal.date(from: endComponents) ?? date
    }
    
    private func getLadiesDeadline(for date: Date) -> Date {
        let startTime = getEventStartTime(for: date)
        guard startTime < date else { return date }
        
        // Scadenza sabato 00:30
        var deadlineComponents = cal.dateComponents([.year, .month, .day], from: startTime)
        deadlineComponents.day! += 1  // Passa a sabato
        deadlineComponents.hour = HZooConfig.ladiesDeadlineHour
        deadlineComponents.minute = HZooConfig.ladiesDeadlineMinute
        deadlineComponents.second = 0
        
        return cal.date(from: deadlineComponents) ?? date
    }
}

// MARK: - 🎬 Remote Video ViewModel (GitHub Pages)
class RemoteVideoViewModel: ObservableObject {
    @Published var aftermovieVideos: [RemoteVideo] = []
    @Published var tiktokVideos: [RemoteVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let urlSession = URLSession.shared
    
    func loadVideos() {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: HZooConfig.remoteVideosURL) else {
            errorMessage = "URL non valido"
            isLoading = false
            return
        }
        
        urlSession.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Errore di rete: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "Nessun dato ricevuto"
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(RemoteVideoResponse.self, from: data)
                    self?.aftermovieVideos = response.aftermovie
                    self?.tiktokVideos = response.tiktok
                } catch {
                    self?.errorMessage = "Errore nel parsing JSON: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func refreshVideos() {
        loadVideos()
    }
}

// MARK: - 🦩 H-ZOO Home Tab (Countdown & Info Serata)
struct HomeTabView: View {
    @StateObject private var countdownVM = HZooCountdownViewModel()
    @StateObject private var settings = SettingsModel()
    @StateObject private var remoteVideoVM = RemoteVideoViewModel()
    @EnvironmentObject var minigameManager: MinigameManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var selectedVideo: LocalVideo?
    @State private var selectedRemoteVideo: RemoteVideo?
    @State private var showRemoteVideoList = false
    @State private var remoteVideoListType: LocalVideo.VideoType = .aftermovie
    @State private var scrollOffset: CGFloat = 0
    
    // MARK: - Scaling Header Variables
    @State private var contentFrame: CGRect = .zero
    
    private let maxHeaderHeight: CGFloat = 200
    private let minHeaderHeight: CGFloat = 100
    
    // MARK: - Scaling Header Functions
    private func getOffsetForHeader() -> CGFloat {
        let offset = abs(scrollOffset)
        let extraSpace = maxHeaderHeight - minHeaderHeight
        
        if offset < extraSpace {
            return 0
        }
        return offset - extraSpace
    }
    
    private func getHeaderHeight() -> CGFloat {
        let offset = abs(scrollOffset)
        let scalingRange: CGFloat = 100
        
        if offset < scalingRange {
            return maxHeaderHeight - (offset * (maxHeaderHeight - minHeaderHeight) / scalingRange)
        }
        return minHeaderHeight
    }
    
    private func getHeaderScale() -> CGFloat {
        let offset = abs(scrollOffset)
        let scalingRange: CGFloat = 100
        
        if offset < scalingRange {
            let scale = 1.0 - (offset / scalingRange) * 0.3 // Scala da 1.0 a 0.7
            return max(0.7, scale)
        }
        return 0.7
    }
    
    private var contentOffset: CGFloat {
        let offset = abs(scrollOffset)
        let extraSpace = maxHeaderHeight - minHeaderHeight
        
        if offset < extraSpace {
            return 0
        }
        return offset - extraSpace
    }
    @State private var timerGlow = false
    @State private var showLocationPermissionAlert = false
    @Environment(\.scenePhase) private var scenePhase
    
    // Debug flags (passed from ContentView)
    @Binding var debugTestBanner: Bool
    @Binding var debugTestSigla: Bool
    @Binding var debugTestMinigame: Bool
    @Binding var debugTestSerata: Bool
    @Binding var debugTestSerataOmaggio: Bool
    
    // Messaggio dinamico basato su genere iOS
    private var dynamicMotivationalMessage: String {
        let gender = settings.userGenderPreference == "femmina" ? "pronta" : "pronto"
        return "🎉 \(gender) ad alzare la voce? 🦚"
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    // Contenuto principale
                    VStack(spacing: 20) {
                    // Hero Section
                    heroSection
                        .padding(.top, 8)
                        .padding(.top, 44) // Safe area per navigation bar
                        
                        // Evento Questo Venerdì (scaling header)
                        thisWeekEventSection
                            .scaleEffect(getHeaderScale(), anchor: .top)
                            .frame(height: getHeaderHeight())
                            .clipped()
                        
                        
                        // Micro-quote (solo 1:30-2:00 durante serata o debug)
                        if countdownVM.showSiglaQuote || debugTestSigla {
                            siglaQuoteSection
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Minigame placeholder (durante serata)
                        if countdownVM.isEventActive {
                            minigameSection
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        
                        // Countdown o Stato Serata (solo se non c'è sigla attiva)
                        if !countdownVM.showSiglaQuote && !debugTestSigla {
                            countdownSection
                        }
                        
                        // NUOVO: Gioco della Serata (solo durante l'evento o debug)
                        if (countdownVM.isEventActive || debugTestMinigame), let eventGame = minigameManager.currentEventGame {
                            eventGameCard(eventGame)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // KPI Quick Actions
                        kpiQuickActionsSection
                        
                        // Instagram Feed
                        instagramSection
                        
                        // Social Media
                        contactsSection
                        
                        // Preparati per il Prossimo Venerdì
                        nextWeekEventSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: countdownVM.isEventActive)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: countdownVM.showSiglaQuote)
                
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("logoBianco")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 32)
                        .offset(y: -8)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                countdownVM.recalculate()
            }
        }
        .onAppear {
            trackEvent("view_home")
            remoteVideoVM.loadVideos()
        }
        .sheet(item: $selectedVideo) { video in
            LocalVideoPlayerView(video: video)
        }
        .sheet(isPresented: $showRemoteVideoList) {
            RemoteVideoListView(
                videos: remoteVideoListType == .aftermovie ? remoteVideoVM.aftermovieVideos : remoteVideoVM.tiktokVideos,
                type: remoteVideoListType,
                selectedVideo: $selectedRemoteVideo
            )
        }
        .fullScreenCover(item: $selectedRemoteVideo) { video in
            RemoteVideoPlayerView(video: video)
        }
    }
    
    
    // MARK: - Hero
    private var heroSection: some View {
        VStack(spacing: 8) {
            Image("hzoo_bianco")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 60)
                .shadow(color: HZooConfig.primaryNeon.opacity(0.3), radius: 8, x: 0, y: 4)
            
            Text("Il venerdì del PavoReal")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -20)
    }
    
    
    // MARK: - Sigla Quote (1:30-2:00)
    private var siglaQuoteSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundStyle(HZooConfig.accentCyan)
                Text("È L'ORA DELLA SIGLA!")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HZooConfig.textWhite.opacity(0.7))
            }
            
            Text("SIGLAAAA! Alza la voce e canta insieme a noiii")
                .font(.headline)
                .foregroundStyle(HZooConfig.textWhite)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HZooConfig.accentCyan.opacity(0.1))
        )
    }
    
    // MARK: - Minigame Serata (Dinamico)
    private var minigameSection: some View {
        HStack(spacing: 12) {
            // Icona dinamica o default
            if let eventGame = minigameManager.currentEventGame {
                Text(eventGame.icon)
                    .font(.system(size: 32))
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundStyle(HZooConfig.accentCyan)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Gioco di Stasera")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HZooConfig.textWhite.opacity(0.7))
                
                // Titolo dinamico
                Text(minigameManager.currentEventGame?.title ?? "Beerpong del Pavone!")
                    .font(.headline)
                    .foregroundStyle(HZooConfig.textWhite)
            }
            
            Spacer()
            
            // Orario
            if let eventGame = minigameManager.currentEventGame {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(HZooConfig.accentCyan)
                    Text(eventGame.startTime)
                        .font(.caption.bold())
                        .foregroundStyle(HZooConfig.textWhite)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HZooConfig.accentCyan.opacity(0.1))
        )
    }
    
    // MARK: - Evento Questo Venerdì
    private var thisWeekEventSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                // Titolo dinamico
                if countdownVM.isEventActive || debugTestSerata || debugTestSerataOmaggio {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(HZooConfig.primaryNeon)
                            .frame(width: 10, height: 10)
                            .modifier(PulsingDot())
                        
                        Text("SERATA IN CORSO")
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(HZooConfig.primaryNeon)
                        
                        Spacer()
                    }
                } else {
                    Text("QUESTO VENERDÌ")
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                HStack(spacing: 8) {
                    Text("H-ZOO #\(countdownVM.nextEventNumber)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HZooConfig.eventColor(for: countdownVM.nextEventNumber))
                    
                    Text("·")
                        .foregroundStyle(.quaternary)
                    
                    Text(countdownVM.nextEventFullDateString)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Info rapide - adattate per serata in corso
            VStack(spacing: 12) {
                if countdownVM.isEventActive || debugTestSerata || debugTestSerataOmaggio {
                    // Durante la serata: solo info essenziali
                    quickInfoRow(icon: "eurosign.circle.fill", text: "♂ \(HZooConfig.priceMan) · ♀ \(HZooConfig.priceLadyBefore) entro 00:30", color: .green)
                    quickInfoRow(icon: "mappin.circle.fill", text: "\(HZooConfig.venueName) \(HZooConfig.venueLocation)", color: .orange)
                    
                    // Omaggio donna sotto il luogo (solo se attivo)
                    if countdownVM.showLadiesFreeBadge || debugTestSerataOmaggio {
                        quickInfoRow(icon: "sparkles", text: "Omaggio donna scade tra \(debugTestSerataOmaggio ? "01:00" : countdownVM.ladiesCountdown)", color: HZooConfig.accentCyan)
                    }
                } else {
                    // Prima della serata: tutte le info
                    quickInfoRow(icon: "clock.fill", text: "Start ore 23:00", color: HZooConfig.accentCyan)
                    quickInfoRow(icon: "eurosign.circle.fill", text: "♂ \(HZooConfig.priceMan) · ♀ \(HZooConfig.priceLadyBefore) entro 00:30", color: .green)
                    quickInfoRow(icon: "mappin.circle.fill", text: "\(HZooConfig.venueName) \(HZooConfig.venueLocation)", color: .orange)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    (countdownVM.isEventActive || debugTestSerata || debugTestSerataOmaggio) 
                    ? HZooConfig.primaryNeon.opacity(0.1) 
                    : HZooConfig.eventColor(for: countdownVM.nextEventNumber).opacity(0.06)
                )
                .shadow(
                    color: (countdownVM.isEventActive || debugTestSerata || debugTestSerataOmaggio) 
                    ? HZooConfig.primaryNeon.opacity(0.2) 
                    : HZooConfig.eventColor(for: countdownVM.nextEventNumber).opacity(0.1), 
                    radius: 16, x: 0, y: 8
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: (countdownVM.isEventActive || debugTestSerata || debugTestSerataOmaggio) 
                        ? [HZooConfig.primaryNeon.opacity(0.5), HZooConfig.primaryNeon.opacity(0.2)]
                        : [HZooConfig.eventColor(for: countdownVM.nextEventNumber).opacity(0.3), HZooConfig.eventColor(for: countdownVM.nextEventNumber).opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Prossimo Venerdì
    private var nextWeekEventSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREPARATI PER IL PROSSIMO")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    HStack(spacing: 8) {
                        Text("H-ZOO #\(countdownVM.nextEventNumber + 1)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(HZooConfig.eventColor(for: countdownVM.nextEventNumber + 1))
                        
                        Circle()
                            .fill(HZooConfig.textWhite.opacity(0.3))
                            .frame(width: 4, height: 4)
                        
                        // Calcola il prossimo venerdì dopo quello corrente
                        Text(nextWeekDateString)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
                
                Spacer()
            }
            
            Text("Impossibile perdere la prossima serata!")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(HZooConfig.eventColor(for: countdownVM.nextEventNumber + 1).opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(HZooConfig.eventColor(for: countdownVM.nextEventNumber + 1).opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Video Remote (Aftermovie & TikTok)
    private var instagramSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "video.fill")
                    .font(.title2)
                    .foregroundStyle(HZooConfig.primaryNeon)
                
                Text("Dai Social")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                
                Spacer()
            }
            
            // Pulsanti per aprire le liste dei video
            HStack(spacing: 12) {
                remoteVideoButton(
                    title: "AFTERMOVIE",
                    icon: "film.fill",
                    videos: remoteVideoVM.aftermovieVideos,
                    type: .aftermovie
                )
                
                remoteVideoButton(
                    title: "TIKTOK",
                    icon: "play.rectangle.fill", 
                    videos: remoteVideoVM.tiktokVideos,
                    type: .tiktok
                )
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "1a1a1a"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(HZooConfig.primaryNeon.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func videoCard(video: LocalVideo) -> some View {
        Button(action: {
            haptic(.medium)
            selectedVideo = video
        }) {
            VStack(spacing: 0) {
                // Thumbnail con play overlay
                ZStack {
                    if let thumbnail = UIImage(named: video.thumbnailName) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 180)
                            .clipped()
                    } else {
                        // Fallback con icona video
                        Rectangle()
                            .fill(Color.black.opacity(0.8))
                            .frame(height: 180)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: video.type == .aftermovie ? "film.fill" : "play.rectangle.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(HZooConfig.primaryNeon)
                                    
                                    Text(video.type == .aftermovie ? "AFTERMOVIE" : "TIKTOK")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(HZooConfig.primaryNeon.opacity(0.2))
                                        )
                                }
                            }
                    }
                    
                    // Play button overlay
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Titolo video
                Text(video.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "1a1a1a"))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(HZooConfig.primaryNeon.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Remote Video Functions
    private func remoteVideoButton(
        title: String,
        icon: String,
        videos: [RemoteVideo],
        type: LocalVideo.VideoType
    ) -> some View {
        Button(action: {
            haptic(.medium)
            remoteVideoListType = type
            showRemoteVideoList = true
        }) {
            VStack(spacing: 0) {
                // Thumbnail con play overlay
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 180)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: icon)
                                    .font(.system(size: 40))
                                    .foregroundStyle(HZooConfig.primaryNeon)
                                
                                Text(title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(HZooConfig.primaryNeon.opacity(0.2))
                                    )
                                
                                // Badge con numero di video
                                if !videos.isEmpty {
                                    Text("\(videos.count) episodi")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.black.opacity(0.6))
                                        )
                                }
                            }
                        }
                    
                    // Play button overlay
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Titolo video
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "1a1a1a"))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(HZooConfig.primaryNeon.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func quickInfoRow(icon: String, text: String, color: Color = HZooConfig.accentCyan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 20, alignment: .center)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
    
    private var nextWeekDateString: String {
        let calendar = HZooConfig.calendar
        let nextEvent = countdownVM.calculateNextEvent(from: Date())
        
        // Aggiungi 7 giorni per il prossimo venerdì
        guard let weekAfter = calendar.date(byAdding: .day, value: 7, to: nextEvent) else {
            return "Prossimo venerdì"
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = HZooConfig.timezone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: weekAfter).capitalized
    }
    
    // MARK: - Countdown (compatto)
    private var countdownSection: some View {
        VStack(spacing: 12) {
            if !countdownVM.isEventActive {
                // Countdown normale
                VStack(spacing: 16) {
                    Text("PROSSIMO H-ZOO")
                        .font(.caption.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        
                    HStack(spacing: 4) {
                        countdownUnit(value: countdownVM.days, label: "G")
                        separatorDot
                        countdownUnit(value: countdownVM.hours, label: "H")
                        separatorDot
                        countdownUnit(value: countdownVM.minutes, label: "M")
                        separatorDot
                        countdownUnit(value: countdownVM.seconds, label: "S")
                    }
                    
                    Text(dynamicMotivationalMessage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "1a1a1a"))
                .shadow(
                    color: timerGlow ? HZooConfig.primaryNeon.opacity(0.3) : Color.clear,
                    radius: timerGlow ? 20 : 0,
                    x: 0,
                    y: 0
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                timerGlow = true
            }
        }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(countdownVM.accessibilityLabel)
    }
    
    private var separatorDot: some View {
        Circle()
            .fill(HZooConfig.primaryNeon.opacity(0.4))
            .frame(width: 4, height: 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
    }
    
    private func countdownUnit(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
    
    // MARK: - Gioco della Serata Card
    private func eventGameCard(_ game: EventGame) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header con icona
            HStack(spacing: 12) {
                Text(game.icon)
                    .font(.system(size: 50))
                    .frame(width: 70, height: 70)
                    .background(
                        LinearGradient(
                            colors: [HZooConfig.primaryNeon.opacity(0.2), HZooConfig.accentCyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("GIOCO DELLA SERATA")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HZooConfig.primaryNeon)
                        .tracking(1)
                    
                    Text(game.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                
                Spacer()
            }
            
            // Descrizione
            Text(game.description)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            
            // Info Grid
            VStack(spacing: 8) {
                EventGameInfoRow(icon: "clock.fill", label: "Orario", value: game.startTime)
                EventGameInfoRow(icon: "mappin.circle.fill", label: "Dove", value: game.location)
                EventGameInfoRow(icon: "trophy.fill", label: "Premio", value: game.prizes)
            }
        }
        .padding(20)
        .background(Color(hex: "1a1a1a"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [HZooConfig.primaryNeon.opacity(0.3), HZooConfig.accentCyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: HZooConfig.primaryNeon.opacity(0.15), radius: 20, x: 0, y: 10)
    }
    
    
    // MARK: - KPI Quick Actions
    private var kpiQuickActionsSection: some View {
        HStack(spacing: 12) {
            kpiActionCard(
                icon: "wineglass",
                title: "Tavolo",
                subtitle: "Prenota ora",
                action: {
                    haptic(.medium)
                    trackEvent("tap_prenota_from_home")
                    // Navigate to Tavolo tab
                    NotificationCenter.default.post(name: .switchToTab, object: 1)
                }
            )
            
            kpiActionCard(
                icon: "eurosign.circle",
                title: "Prezzi",
                subtitle: "Ingresso & drink",
                action: {
                    haptic(.light)
                    trackEvent("tap_prezzi")
                    // Navigate to Prezzi tab
                    NotificationCenter.default.post(name: .switchToTab, object: 2)
                }
            )
            
            kpiActionCard(
                icon: "map",
                title: "Arrivo",
                subtitle: "Come arrivare",
                action: {
                    haptic(.light)
                    trackEvent("tap_maps")
                    openMaps()
                }
            )
        }
    }
    
    private func kpiActionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HZooConfig.accentCyan)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "1a1a1a"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Social Media
    private var contactsSection: some View {
        HStack(spacing: 12) {
            socialButton(icon: "instagram", text: "Instagram", color: Color(hex: "833AB4"), isCustomIcon: true) {
                haptic(.light)
                trackEvent("tap_instagram")
                if let url = URL(string: HZooConfig.instagramURL) {
                    UIApplication.shared.open(url)
                }
            }
            
            socialButton(icon: "tiktok", text: "TikTok", color: Color(hex: "2a2a2a"), isCustomIcon: true) {
                haptic(.light)
                trackEvent("tap_tiktok")
                print("🔗 Tentativo apertura TikTok: \(HZooConfig.tiktokURL)")
                if let url = URL(string: HZooConfig.tiktokURL) {
                    UIApplication.shared.open(url) { success in
                        print("📱 TikTok aperto: \(success)")
                    }
                } else {
                    print("❌ URL TikTok non valido")
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func socialButton(icon: String, text: String, color: Color, isCustomIcon: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isCustomIcon {
                    // Icona SVG personalizzata (bianca)
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.white)
                } else {
                    // Icona SF Symbol
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
                
                Text(text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func openMaps() {
        let address = HZooConfig.venueFullAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?address=\(address)") {
            UIApplication.shared.open(url)
        }
    }
}


// MARK: - Custom Button Style (iOS 26-like)
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pulsing Dot Animation
private struct PulsingDot: ViewModifier {
    @State private var pulse = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.3 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: - 🎫 Prenota Tavolo Tab
// Helper per EventGame Info Row
private struct EventGameInfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(HZooConfig.accentCyan)
                .frame(width: 20)
            
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PrenotaTabView: View {
    @State private var showComingSoon = false
    @State private var scrollOffset: CGFloat = 0
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)
                
                VStack(spacing: 32) {
                    
                    // Tipologie di Tavoli
                    VStack(alignment: .leading, spacing: 16) {
                        Text("🪑 Tipologie di Tavoli")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(HZooConfig.textWhite)
                        
                        VStack(spacing: 12) {
                            tableTypeRow(icon: "👑", title: "VIP", location: "Palco", priority: 1)
                            tableTypeRow(icon: "🎛️", title: "SUPER", location: "Console", priority: 2)
                            tableTypeRow(icon: "✨", title: "WOW", location: "Palchi laterali", priority: 3)
                            tableTypeRow(icon: "🎵", title: "Classici", location: "Pista e balconata", priority: 4)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(hex: "1a1a1a"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(HZooConfig.textWhite.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Condizioni e Regole
                    VStack(alignment: .leading, spacing: 16) {
                        Text("📋 Condizioni e Regole")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(HZooConfig.textWhite)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            conditionRow(text: "Nati entro l'anno 2004 (21 anni compiuti)")
                            conditionRow(text: "Documento di identità originale obbligatorio")
                            conditionRow(text: "Prenotazione anticipata richiesta")
                            conditionRow(text: "Pagamento in loco alla prenotazione")
                            conditionRow(text: "Ingresso prioritario per i prenotati")
                            conditionRow(text: "La direzione si riserva diritto di selezione")
                            conditionRow(text: "No fotocopie o screenshot del documento")
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(hex: "1a1a1a"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(HZooConfig.accentCyan.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // CTA Principale
                    VStack(spacing: 12) {
                        Button {
                            haptic(.medium)
                            trackEvent("tap_prenota_ora")
                            showComingSoon = true
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Prenota Ora")
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [HZooConfig.primaryNeon, HZooConfig.primaryNeon.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: HZooConfig.primaryNeon.opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                        
                        HStack(spacing: 12) {
                            contactButton(icon: "phone.fill", title: "Chiama", color: .green) {
                                haptic(.light)
                                trackEvent("tap_infoline_prenota")
                                if let url = URL(string: "tel:\(HZooConfig.phoneNumber)") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            
                            contactButton(icon: "message.fill", title: "WhatsApp", color: Color(hex: "25D366")) {
                                haptic(.light)
                                trackEvent("tap_whatsapp_prenota")
                                let text = "Ciao! Vorrei prenotare un tavolo H-ZOO per venerdì prossimo"
                                if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                   let url = URL(string: "https://wa.me/\(HZooConfig.whatsappNumber)?text=\(encoded)") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    
                    // KPI Tavoli (se disponibile)
                    if let tablesLeft = HZooConfig.tablesLeft {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "table.furniture.fill")
                                    .foregroundStyle(HZooConfig.accentCyan)
                                Text("Tavoli Rimasti: \(tablesLeft)")
                                    .font(.headline)
                                    .foregroundStyle(HZooConfig.textWhite)
                            }
                            
                            Text("Prenota ora per garantire il tuo posto")
                                .font(.caption)
                                .foregroundStyle(HZooConfig.textWhite.opacity(0.6))
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(HZooConfig.accentCyan.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(HZooConfig.accentCyan.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .background(HZooConfig.backgroundDark.ignoresSafeArea())
            .navigationTitle("Prenota un tavolo")
            .navigationBarTitleDisplayMode(.large)
             .toolbar {
                ToolbarItem(placement: .principal) {
                    if scrollOffset > -50 {
                        Image("logoBianco")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 32)
                            .offset(y: -8)
                    }
                }
            }
            .onAppear {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance = appearance
            }
            .sheet(isPresented: $showComingSoon) {
                ComingSoonView()
            }
        }
        .onAppear {
            trackEvent("view_prenota")
        }
    }
    
    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HZooConfig.textWhite)
                
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(HZooConfig.textWhite.opacity(0.6))
            }
            
            Spacer()
        }
    }
    
    private func contactButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color)
            .cornerRadius(12)
            .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
    
    private func ruleRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(HZooConfig.accentCyan)
                .padding(.top, 2)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(HZooConfig.textWhite.opacity(0.85))
        }
    }
    
    private func tableTypeRow(icon: String, title: String, location: String, priority: Int) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HZooConfig.textWhite)
                    
                    Spacer()
                    
                    Text("#\(priority)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HZooConfig.primaryNeon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(HZooConfig.primaryNeon.opacity(0.1))
                        )
                }
                
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(HZooConfig.textWhite.opacity(0.7))
            }
        }
    }
    
    private func conditionRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(HZooConfig.accentCyan)
                .padding(.top, 2)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(HZooConfig.textWhite.opacity(0.85))
        }
    }
}

// MARK: - 🚀 Coming Soon View
struct ComingSoonView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "hourglass")
                    .font(.system(size: 80))
                    .foregroundStyle(HZooConfig.accentCyan)
                    .symbolEffect(.pulse, options: .repeating)
                
                Text("Prenotazione Online")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(HZooConfig.textWhite)
                
                Text("In Arrivo Presto")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HZooConfig.primaryNeon)
                
                VStack(spacing: 12) {
                    Text("La prenotazione online sarà disponibile a breve.")
                        .multilineTextAlignment(.center)
                    
                    Text("Nel frattempo, contattaci via WhatsApp o telefono per prenotare il tuo tavolo!")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundStyle(HZooConfig.textWhite.opacity(0.7))
                }
                .padding(.horizontal, 32)
                
                VStack(spacing: 12) {
                    Button {
                        haptic(.light)
                        let text = "Ciao! Vorrei prenotare un tavolo H-ZOO per venerdì prossimo"
                        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://wa.me/\(HZooConfig.whatsappNumber)?text=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("WhatsApp")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "25D366"))
                        .cornerRadius(12)
                    }
                    
                    Button {
                        haptic(.light)
                        if let url = URL(string: "tel:\(HZooConfig.phoneNumber)") {
                            UIApplication.shared.open(url)
                        }
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "phone.fill")
                            Text("Chiama")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HZooConfig.backgroundDark.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HZooConfig.textWhite.opacity(0.6))
                    }
                }
            }
        }
    }
}

// Rimuovo vecchie sezioni non più usate
/*
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Logo con effetto neon
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.pink.opacity(0.6), .purple.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .pink.opacity(pulseAnimation ? 0.4 : 0.2), radius: pulseAnimation ? 20 : 10)
                    .frame(height: 200)
                
                VStack(spacing: 16) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.pink)
                        .shadow(color: .pink.opacity(0.8), radius: 10)
                    
                    Text("H‑ZOO")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .tracking(4)
                        .shadow(color: .pink.opacity(0.5), radius: 10)
                    
                    Text("VENERDÌ NOTTE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .tracking(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
    }
    
    private var accessWarningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.pink)
                Text("Regole di Ingresso")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                AccessRule(icon: "18.circle.fill", text: "Solo Over 21 (nati fino al 2004)")
                AccessRule(icon: "person.badge.shield.checkmark.fill", text: "Selezione all'ingresso")
                AccessRule(icon: "doc.text.fill", text: "Documento originale obbligatorio")
                AccessRule(icon: "xmark.circle.fill", text: "No fotocopie o screenshot")
                AccessRule(icon: "clock.fill", text: "Apertura: 23:00 - 06:00")
            }
            .padding(16)
            .background(.pink.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.pink.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }
    
    private var countdownSection: some View {
        VStack(spacing: 12) {
            Text("PROSSIMO H-ZOO")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(2)
            
            Text("Venerdì 23:00")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pink, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("2 giorni, 14 ore")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.pink.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    private var programmaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Programma Serata", icon: "music.note.list")
            
            VStack(spacing: 12) {
                EventTimeSlot(time: "23:00", title: "Apertura", description: "Ingresso e primi drink")
                EventTimeSlot(time: "00:00", title: "Warm Up", description: "Musica e atmosfera")
                EventTimeSlot(time: "01:00", title: "Peak Time", description: "Pista al massimo")
                EventTimeSlot(time: "03:00", title: "After Hours", description: "Chiusura alle 06:00")
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var storiesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Weekend Vibes", icon: "photo.on.rectangle")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<6) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.title)
                                    .foregroundStyle(.pink.opacity(0.5))
                            )
                            .frame(width: 120, height: 180)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(.pink.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var shopSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Merch H-ZOO", icon: "bag")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    MerchCard(title: "T-Shirt", price: "25€", icon: "tshirt")
                    MerchCard(title: "Felpa", price: "45€", icon: "figure.walk")
                    MerchCard(title: "Cap", price: "20€", icon: "crown")
                    MerchCard(title: "Bracciale", price: "10€", icon: "waveform")
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
*/

// MARK: - Minigame Tab (Il gioco attuale)
struct MinigameTabView: View {
    @EnvironmentObject var vm: PetViewModel
    @EnvironmentObject var minigameManager: MinigameManager
    @EnvironmentObject var locationManager: LocationManager
    
    // Layout constants
    private let contentWidth: CGFloat = 392
    private let gridSpacing: CGFloat = 14
    @State private var evolveName: String = ""
    @State private var showEvolveSheet: Bool = false
    @State private var confettiFire: Int = 0

    // Layout
    @AppStorage("El-PavoReal.compactPadding") private var compactPadding: Bool = true
    @AppStorage("El-PavoReal.reduceMotion") private var reduceMotion: Bool = false
    @AppStorage("El-PavoReal.notificationsEnabled") private var notificationsEnabled: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var ageTimer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()
    @AppStorage("El-PavoReal.ageFormat") private var ageFormat: Int = 0   // 0=mm:ss, 1=hh:mm
    @AppStorage("El-PavoReal.inAppBanners") private var inAppBanners: Bool = true
    @AppStorage("El-PavoReal.lastBackgroundDate") private var lastBackgroundDate: Double = 0

    @State private var eventOverlayQueue: [EventOverlayItem] = []
    @State private var currentEventOverlay: EventOverlayItem? = nil
    
    // Toast Notification System
    @State private var toastQueue: [ToastItem] = []
    @State private var currentToasts: [ToastItem] = []

    private func enqueueEventOverlay(_ item: EventOverlayItem) {
        eventOverlayQueue.append(item)
        if currentEventOverlay == nil { presentNextEventOverlay() }
    }
    private func presentNextEventOverlay() {
        if currentEventOverlay == nil, !eventOverlayQueue.isEmpty {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                currentEventOverlay = eventOverlayQueue.removeFirst()
            }
        }
    }
    private func dismissCurrentEventOverlay() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            currentEventOverlay = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { presentNextEventOverlay() }
    }
    
    // MARK: - Toast Notification Functions
    private func showToast(_ text: String, symbol: String, colors: [Color], duration: TimeInterval = 2.5) {
        let toast = ToastItem(title: text, icon: symbol, colors: colors, duration: duration)
        
        // Se abbiamo già 3 toast attive, rimuovi la più vecchia
        if currentToasts.count >= 3 {
            currentToasts.removeFirst()
        }
        
        currentToasts.append(toast)
    }
    
    private func dismissToast(_ toast: ToastItem) {
        currentToasts.removeAll { $0.id == toast.id }
    }
    
    @State private var bobbing = false
    @State private var pulse = false
    @State private var showDeathScreen: Bool = false
    @State private var showLifeInfo: Bool = false
    
    @State private var showShop = false
    @State private var showTutorial = false
    @State private var showSettings = false
    @State private var showEventLog = false
    @State private var showObiettivi = false
    @State private var showDailySlot = false
    @State private var showPavoLireInfo = false
    @State private var eventLog: [LoggedEvent] = []
    @AppStorage("El-PavoReal.seenTutorial") private var seenTutorial: Bool = false
    @AppStorage("El-PavoReal.lastActive") private var lastActiveTS: Double = Date().timeIntervalSince1970
    @AppStorage("El-PavoReal.lastDailySlotDate") private var lastDailySlotDate: String = ""
    @AppStorage("El-PavoReal.dailySlotTries") private var dailySlotTries: Int = 0
    @AppStorage("El-PavoReal.slotWonToday") private var slotWonToday: Bool = false

    // Eventi random
    @AppStorage("El-PavoReal.eventChance") private var eventChance: Double = 0.08
    @State private var eventTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // In-app event banners queue
    @State private var eventBanners: [EventBannerData] = []

    // Notifiche
    @State private var askedNotifications = false

    private func computeOfflinePavoLire(now: TimeInterval = Date().timeIntervalSince1970) -> Int {
        guard lastExitTS > 0 else { return 0 }
        let elapsed = max(0, now - lastExitTS)
        let gained = Int((elapsed / offlineBaseSecondsPerPavoLire) * offlineRate)
        return min(max(0, gained), offlineCap)
    }
    
    // MARK: Mini-gioco: Privé Rush RIMOSSO
    
    // MARK: - 🎰 Daily Slot System
    private func canPlaySlotToday() -> Bool {
        // Controlla se siamo nella finestra oraria 01:00 - 03:00 (sabato notte)
        guard isSlotTimeWindow() else { return false }
        
        // Controlla se siamo vicini al locale (geofencing)
        guard locationManager.isNearVenue else { return false }
        
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        if lastDailySlotDate != today {
            // Nuovo giorno: reset tentativi e vittoria
            dailySlotTries = 0
            slotWonToday = false
            lastDailySlotDate = today
        }
        return dailySlotTries < 10 && !slotWonToday
    }
    
    /// Controlla se siamo nella finestra oraria per giocare (01:00 - 03:00 del sabato)
    private func isSlotTimeWindow() -> Bool {
        let now = Date()
        let calendar = HZooConfig.calendar
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        
        // Sabato (weekday 7) dalle 01:00 alle 03:00
        // (È la notte del venerdì H-ZOO)
        return weekday == 7 && hour >= 1 && hour < 3
    }
    
    /// Ottieni tentativi rimanenti in base al tipo di minigame
    private func getRemainingTries(for gameType: MinigameConfig.MinigameType = .slotMachine) -> Int {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        
        let maxTries: Int
        switch gameType {
        case .slotMachine:
            maxTries = 10 // Slot: 10 tentativi
        case .roulette, .scratchCard:
            maxTries = 1  // Roulette e Gratta e Vinci: 1 tentativo
        case .none:
            maxTries = 0
        }
        
        if lastDailySlotDate != today {
            return maxTries // Nuovo giorno
        }
        if slotWonToday {
            return 0 // Ha già vinto oggi
        }
        return max(0, maxTries - dailySlotTries)
    }
    
    
    private func applySlotPrize(_ prize: SlotPrize) {
        switch prize {
        case .coins(let amount):
            vm.PavoLire += amount
            enqueueEventOverlay(EventOverlayItem(title: "JACKPOT! 🎰", icon: "sterlingsign.circle.fill", tone: .positive, lines: ["+\(amount) PavoLire!"], autoDismiss: false, duration: 3.0))
        case .xp(let amount):
            vm.xp += amount
            enqueueEventOverlay(EventOverlayItem(title: "BONUS XP! ⭐", icon: "star.fill", tone: .positive, lines: ["+\(amount) XP guadagnati!"], autoDismiss: false, duration: 3.0))
        case .booster(let minutes):
            vm.boostUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
            vm.activeBoosterItemTitle = "Slot Machine"
            vm.activeBoosterItemSymbol = "gamecontroller.fill"
            enqueueEventOverlay(EventOverlayItem(title: "BOOSTER! ⚡", icon: "bolt.heart.fill", tone: .positive, lines: ["Decadimenti dimezzati per \(minutes) min!"], autoDismiss: false, duration: 3.0))
        case .statBoost:
            vm.satiety = min(vm.statCap, vm.satiety + 30)
            vm.energy = min(vm.statCap, vm.energy + 30)
            enqueueEventOverlay(EventOverlayItem(title: "ENERGIA! ✨", icon: "sparkles", tone: .positive, lines: ["+30 a entrambe!"], autoDismiss: false, duration: 3.0))
        }
    }
    
    // MARK: - 🍸 Quick Pick Menus (Long-Press Actions)
    @State private var quickPickKind: QuickPickKind? = nil
    private enum QuickPickKind { case drink, shot, relax, sigla }
    
    /// Helper per modificare stats usando KeyPath
    private func bump(_ keyPath: ReferenceWritableKeyPath<PetViewModel, Double>, _ delta: Double) {
        vm.bump(keyPath, delta)
    }
    
    /// Menu: Scegli bevuta (Gin Tonic, Vodka Lemon, Negroni, Acqua Fresca)
    private func chooseDrink(_ name: String) {
        // Controlla cooldown "Bevuta"
        if isLocked("El-PavoReal.drinkNextReadyAt") {
            haptic(.heavy)
            return
        }
        
        haptic(.soft)
        vm.feedNutellino()
        switch name {
        case "Gin Tonic":
            bump(\PetViewModel.energy, 5);  bump(\PetViewModel.satiety, 3)
        case "Vodka Lemon":
            bump(\PetViewModel.energy, 6);  bump(\PetViewModel.satiety, 2)
        case "Negroni":
            bump(\PetViewModel.energy, 8);  bump(\PetViewModel.satiety, 1)
        case "Acqua Fresca":
            bump(\PetViewModel.satiety, 10); bump(\PetViewModel.energy, 1)
        default: break
        }
        
        // Reset cooldown Bevuta
        setDeadline("El-PavoReal.drinkNextReadyAt", seconds: 60 * 5)
        
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "wineglass.fill", tone: .positive, lines: ["Bevuta servita!"], autoDismiss: true, duration: 2.0))
    }
    
    /// Menu: Scegli shot (Tequila, Jägerbomb, Sambuca, Rum e Lime)
    private func chooseShot(_ name: String) {
        // Controlla cooldown "Shot"
        if isLocked("El-PavoReal.coffeeNextReadyAt") {
            haptic(.heavy)
            return
        }
        
        haptic(.soft)
        vm.coffeeBreak()
        switch name {
        case "Tequila Bum Bum": bump(\PetViewModel.energy, 12)
        case "Jägerbomb":       bump(\PetViewModel.energy, 14)
        case "Sambuca":         bump(\PetViewModel.energy, 10)
        case "Rum e Lime":      bump(\PetViewModel.energy, 11)
        default: break
        }
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "bolt.fill", tone: .positive, lines: ["Shot fatto!"], autoDismiss: true, duration: 2.0))
    }
    
    /// Menu: Scegli relax (Respiro, Stretching, Pausa, Reset)
    private func chooseRelax(_ name: String) {
        // Controlla cooldown "Rilassati"
        if isLocked("El-PavoReal.cleanNextReadyAt") {
            haptic(.heavy)
            return
        }
        
        haptic(.soft)
        vm.pulisciScrivania()
        switch name {
        case "Respiro profondo":    bump(\PetViewModel.hygiene, 6)
        case "Stretching":          bump(\PetViewModel.hygiene, 8)
        case "Due minuti in pausa": bump(\PetViewModel.hygiene, 5); bump(\PetViewModel.energy, 2)
        case "Reset mentale":       bump(\PetViewModel.hygiene, 7)
        default: break
        }
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "sparkles", tone: .positive, lines: ["Reset mentale!"], autoDismiss: true, duration: 2.0))
    }
    
    /// Menu: Scegli ingresso (Pista, SIGLA, Giro, Selfie)
    private func chooseSigla(_ name: String) {
        // Controlla cooldown "SIGLA!"
        if isLocked("El-PavoReal.meetNextReadyAt") {
            haptic(.heavy)
            return
        }
        
        haptic(.soft)
        vm.orientaSuMeet()
        switch name {
        case "Ingresso in pista": bump(\PetViewModel.happiness, 10)
        case "Canta la SIGLA!":   bump(\PetViewModel.happiness, 12)
        case "Giro in pista":     bump(\PetViewModel.happiness, 8); bump(\PetViewModel.energy, 2)
        case "Selfie con Pavo":   bump(\PetViewModel.happiness, 6); vm.PavoLire += 2
        default: break
        }
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "party.popper.fill", tone: .positive, lines: ["Vai in pista!"], autoDismiss: true, duration: 2.0))
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            background
            
            // DYNAMIC CONTENT - Routing basato su minigame attivo
            dynamicMinigameContent

            // Shop
            .sheet(isPresented: $showShop) {
                ShopView(items: defaultShopItems + extraShopItems, PavoLire: $vm.PavoLire) { item in
                    let spent = vm.price(for: item)
                    AchievementsCenter.shared.recordPavoLireSpent(spent)
                    vm.buy(item: item)
                    if case .booster = item.effect {
                        // Banner coerente con l'oggetto comprato
                        pushBanner(
                            text: "Booster attivo: \(item.title)",
                            symbol: item.symbol,
                            colors: item.colors
                        )
                    }
                }
                .environmentObject(vm)
                .presentationBackground(Color.black.opacity(0.45))
            }
            // Settings
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(vm)
                    .presentationBackground(Color.black.opacity(0.45))
            }
            // Daily Slot
            .sheet(isPresented: $showDailySlot) {
                DailySlotView(onSpin: { prize in
                    applySlotPrize(prize)
                })
                .environmentObject(vm)
                .presentationBackground(Color.black.opacity(0.6))
            }
            // Eventi
            .sheet(isPresented: $showEventLog) {
                EventiSheet(log: $eventLog)
                    .environmentObject(vm)
                    .presentationBackground(Color.black.opacity(0.45))
            }
            // Obiettivi
            .sheet(isPresented: $showObiettivi) {
                ObiettiviSheet()
                    .environmentObject(vm)
                    .presentationBackground(Color.black.opacity(0.45))
            }
            // PavoLire Info
            .sheet(isPresented: $showPavoLireInfo) {
                PavoLireInfoView()
                    .environmentObject(vm)
                    .presentationBackground(Color.black.opacity(0.45))
            }
            // Tutorial
            .fullScreenCover(isPresented: $showTutorial) { 
                TutorialView(onClose: { 
                    showTutorial = false
                    UserDefaults.standard.set(true, forKey: "El-PavoReal.seenMinigameTutorial")
                }) 
            }
            // Life Info
            .sheet(isPresented: $showLifeInfo) {
                LifeInfoSheet()
                    .environmentObject(vm)
                    .presentationBackground(Color.black.opacity(0.45))
            }

            // In-app banners stack
            VStack(spacing: 8) {
                ForEach(eventBanners) { banner in
                    EventBanner(data: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 16)
            .zIndex(10)
        }
        .onAppear {
            vm.isForeground = true
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { bobbing = true }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            }
            // Tutorial al primo accesso alla sezione Minigame
            if showTutorialOnFirstVisit {
                showTutorial = true
            }
            requestNotificationsIfNeeded()
        }
        .onAppear {
            if vm.life <= 0 { showDeathScreen = true }
        }
        .onChange(of: vm.life) { _, newV in
            if newV <= 0 { showDeathScreen = true
                AchievementsCenter.shared.recordDeath()}
        }
        .fullScreenCover(isPresented: $showDeathScreen) {
            DeathScreen {
                vm.resetAll()          // azzera davvero tutto (lo usi già nelle Impostazioni)
                showDeathScreen = false
            }
            .environmentObject(vm)
        }
        
        .onReceive(eventTimer) { _ in maybeTriggerRandomEvent() }
        .onReceive(ageTimer) { date in
            vm.tick(now: date)
        }
        .onAppear {
            // App appena apparsa: applica eventuale progresso offline
            let now  = Date()
            let last = Date(timeIntervalSince1970: lastActiveTS)
            let dt   = now.timeIntervalSince(last)
            if dt > 5 {                      // ignora rientri rapidissimi
                applyOfflineProgress(seconds: dt)
            }
            lastActiveTS = now.timeIntervalSince1970
        }
        .confirmationDialog("Scegli un'opzione", isPresented: Binding(get: { quickPickKind != nil }, set: { if !$0 { quickPickKind = nil } }), titleVisibility: .visible) {
            if quickPickKind == .drink {
                Button("Negroni") { chooseDrink("Negroni") }
                Button("Gin Tonic") { chooseDrink("Gin Tonic") }
                Button("Vodka Lemon") { chooseDrink("Vodka Lemon") }
            } else if quickPickKind == .shot {
                Button("Tequila") { chooseShot("Tequila") }
                Button("Vodka") { chooseShot("Vodka") }
                Button("Amaro") { chooseShot("Amaro") }
            } else if quickPickKind == .relax {
                Button("Pisolino") { chooseRelax("Pisolino") }
                Button("Divanetto") { chooseRelax("Divanetto") }
                Button("Sigaretta") { chooseRelax("Sigaretta") }
            } else if quickPickKind == .sigla {
                Button("Alza la voce") { chooseSigla("Alza la voce") }
                Button("Sgombra la mente") { chooseSigla("Sgombra la mente") }
                Button("Sogna!") { chooseSigla("Sogna!") }
            }
        }
        .environmentObject(vm)
        .onChange(of: scenePhase) { _, newPhase in
            vm.isForeground = (newPhase == .active)

            let now = Date().timeIntervalSince1970
            switch newPhase {
            case .active:
                // cancella promemoria pendenti
                UNUserNotificationCenter.current().removePendingNotificationRequests(
                    withIdentifiers: ["checkin","lowSatietyBg","lowEnergyBg"]
                )
                // applica progresso offline sulle stat
                let last = Date(timeIntervalSince1970: lastActiveTS)
                let dt   = Date().timeIntervalSince(last)
                if dt > 5 { applyOfflineProgress(seconds: dt) }
                lastActiveTS = now
                // P£ offline
                let gained = computeOfflinePavoLire(now: now)
                if gained > 0 {
                    vm.PavoLire += gained
                    pushBanner(
                        text: "P£ offline +\(gained)",
                        symbol: "sterlingsign.circle.fill",
                        colors: [.blue, .cyan]
                    )
                }
                lastExitTS = now
                lastBackgroundDate = 0
            case .inactive, .background:
                lastExitTS = now
                lastActiveTS = now
                scheduleBackgroundNotifications()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("El-PavoReal.levelUp"))) { note in
            if let lv = note.userInfo?["level"] as? Int {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                confettiFire &+= 1
                pushBanner(text: "Livello \(lv)!", symbol: "star.fill", colors: [.green, .mint])
                // postOverlayEvent rimosso - pushBanner già lo chiama internamente
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("El-PavoReal.evolved"))) { note in
            if let name = note.userInfo?["name"] as? String {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                confettiFire &+= 1
                evolveName = name
                showEvolveSheet = true
                pushBanner(text: "Evoluzione: \(name)", symbol: "crown.fill", colors: [.yellow, .orange])
                // postOverlayEvent rimosso - pushBanner già lo chiama internamente
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("El-PavoReal.eventOverlay"))) { (note: Notification) in
            let title = note.userInfo?["title"] as? String ?? "Evento"
            let icon  = note.userInfo?["icon"]  as? String ?? "sparkles"
            let toneStr = (note.userInfo?["tone"] as? String)?.lowercased() ?? "system"
            let tone: EventTone = (toneStr == "positive") ? .positive : (toneStr == "negative" ? .negative : .system)
            let lines = note.userInfo?["lines"] as? [String] ?? []
            enqueueEventOverlay(EventOverlayItem(title: title, icon: icon, tone: tone, lines: lines, autoDismiss: false, duration: 3.0))
        }
        .overlay(alignment: .top) {
            // Toast Notifications (non-invasive)
            VStack(spacing: 8) {
                ForEach(currentToasts) { toast in
                    ToastView(item: toast) {
                        dismissToast(toast)
                    }
                }
            }
            .padding(.top, 60) // Sotto la Dynamic Island
            .zIndex(50)
        }
        .overlay(alignment: .center) {
            // Full-screen overlays per eventi importanti
            if let it = currentEventOverlay {
                EventOverlayView(item: it) { dismissCurrentEventOverlay() }
                    .zIndex(100)
            }
        }
        // Privé Rush RIMOSSO
    }
    
    private func ageText(_ seconds: Int) -> String {
        switch ageFormat {
        case 1:
            let h = seconds / 3600
            let m = (seconds / 60) % 60
            if h < 24 {
                return String(format: "%02dh %02dm", h, m)
            } else {
                let d = h / 24
                let hr = h % 24
                return String(format: "%02dgg %02dh %02dm", d, hr, m)
            }
        default:
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%02dm %02ds", m, s)
        }
    }

    // Format a cooldown (seconds) as "m:ss"; return empty string when not on cooldown
    private func formatCooldown(_ t: TimeInterval) -> String {
        let clamped = max(0, t)
        guard clamped > 0 else { return "" }
        let s = Int(ceil(clamped))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    // --- Absolute cooldown helpers (per-action) ---
    private func deadline(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
    private func setDeadline(_ key: String, seconds: TimeInterval) {
        UserDefaults.standard.set(Date().timeIntervalSince1970 + seconds, forKey: key)
    }
    private func remainingDeadline(_ key: String) -> TimeInterval {
        max(0, deadline(key) - Date().timeIntervalSince1970)
    }
    private func isLocked(_ key: String) -> Bool {
        Date().timeIntervalSince1970 < deadline(key)
    }
    // --- End helpers ---

    // Booster name persistence (optional, used if the VM does not expose a name)
    @AppStorage("El-PavoReal.boostName") private var storedBoostName: String = ""

    /// Returns the best available booster name by probing common properties on the ViewModel
    /// and falling back to a stored value or a default label.
    private func resolvedBoostName() -> String {
        // Try common string properties first (no compile‑time dependency on VM shape)
        let candidates = ["boostName", "boosterName", "activeBoostName", "activeBoosterName", "boostTitle"]
        let mirror = Mirror(reflecting: vm)
        for child in mirror.children {
            if let label = child.label, candidates.contains(label) {
                if let value = child.value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        // Fallback to UserDefaults if your VM writes the current booster there
        if !storedBoostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedBoostName
        }
        // Final hard‑coded fallback (keeps old behaviour if nothing else available)
        return "SIGLA! Alza la voce!"
    }
    
    // Offline PavoLire accumulation
    @AppStorage("El-PavoReal.lastExitTS") private var lastExitTS: Double = 0
    private let offlineBaseSecondsPerPavoLire: Double = 30    // più lento in offline
    private let offlineRate: Double = 0.4                  // 40% del rate live quando l'app è chiusa
    private let offlineCap: Int = 20                       // tetto basso per singola sessione
    
    // MARK: - Event Center (Eventi + Obiettivi)

    private struct EventLogList: View {
        @Binding var log: [LoggedEvent]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if log.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.headline)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nessun evento").font(.headline)
                                Text("Gli imprevisti compariranno qui.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    } else {
                        ForEach(log.sorted(by: { $0.date > $1.date })) { e in
                            EventLogRow(text: e.text, date: e.date, symbol: e.symbol, colors: e.colors)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Eventi Sheet
    struct EventiSheet: View {
        @EnvironmentObject var vm: PetViewModel
        @Binding var log: [LoggedEvent]

        var body: some View {
            VStack(spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Eventi")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 20)
                    Text("Qui trovi tutti gli imprevisti e eventi casuali registrati durante il gioco.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Content
                EventLogList(log: $log)
            }
            .background(Color.black.opacity(0.45).ignoresSafeArea())
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Obiettivi Sheet
    struct ObiettiviSheet: View {
        @EnvironmentObject var vm: PetViewModel

        var body: some View {
            AchievementsTab()
                .environmentObject(vm)
                .background(Color.black.opacity(0.45).ignoresSafeArea())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // Conditions supported by the achievement system
    private enum AchievementCondition {
        case PavoLireSpent(Int)
        case level(Int)
        case ageDays(Double)              // days, can be fractional (e.g., 1/24 = 1 hour)
        case allStatsAtLeast(Double)      // threshold 0…100 for satiety/energy/hygiene/happiness
        case lifeFull
        // Counters to wire later
        case miniGameSuccesses(Int)
        case miniGameDeliveredTotal(Int)
        case feeds(Int)
        case coffees(Int)
        case cleans(Int)
        case meets(Int)
        case deaths(Int)
    }

    // Achievements: unified definition used by AchievementsCatalog
    private struct AchievementDef: Identifiable {
        let id: String
        let icon: String
        let title: String
        let desc: String
        let condition: AchievementCondition
        let colors: [Color]
    }

    // MARK: - Achievements Catalog
    private enum AchievementsCatalog {
        static let all: [AchievementDef] = [
            // Spesa PavoLire (resta valida)
            AchievementDef(id: "spend_1",    icon: "cart.fill",                 title: "Primo acquisto",    desc: "Spendi le prime P£.",            condition: .PavoLireSpent(1),    colors: [.blue, .cyan]),
            AchievementDef(id: "spend_10",   icon: "cart.fill",                 title: "Cliente abituale",  desc: "Spendi 10 £.",                  condition: .PavoLireSpent(10),   colors: [.blue, .cyan]),
            AchievementDef(id: "spend_50",   icon: "cart.fill.badge.plus",      title: "Mani bucate",         desc: "Spendi 50 £.",                  condition: .PavoLireSpent(50),   colors: [.blue, .cyan]),
            AchievementDef(id: "spend_100",  icon: "cart.badge.plus",           title: "Grande spender",    desc: "Spendi 100 £.",                 condition: .PavoLireSpent(100),  colors: [.blue, .cyan]),
            AchievementDef(id: "spend_250",  icon: "cart.fill.badge.plus",      title: "Carrello pieno",    desc: "Spendi 250 £.",                 condition: .PavoLireSpent(250),  colors: [.blue, .cyan]),
            AchievementDef(id: "spend_500",  icon: "creditcard.fill",           title: "Big spender",       desc: "Spendi 500 £.",                 condition: .PavoLireSpent(500),  colors: [.blue, .cyan]),
            AchievementDef(id: "spend_1000", icon: "creditcard.fill",           title: "Fuori budget",      desc: "Spendi 1000 £.",                condition: .PavoLireSpent(1000), colors: [.blue, .cyan]),

            // Ingressi al Pavo (riusa .meets come contatore)
            AchievementDef(id: "entry_1",   icon: "ticket.fill",                 title: "Prima entrata",       desc: "Entra al Pavo la prima volta.",   condition: .meets(1),   colors: [.yellow, .orange]),
            AchievementDef(id: "entry_5",   icon: "ticket.fill",                 title: "Conosci la porta",    desc: "5 ingressi al Pavo.",              condition: .meets(5),   colors: [.yellow, .orange]),
            AchievementDef(id: "entry_10",  icon: "ticket.fill",                 title: "Cliente fisso",       desc: "10 ingressi al Pavo.",             condition: .meets(10),  colors: [.yellow, .orange]),
            AchievementDef(id: "entry_25",  icon: "ticket.fill",                 title: "Frequentatore",       desc: "25 ingressi al Pavo.",             condition: .meets(25),  colors: [.yellow, .orange]),
            AchievementDef(id: "entry_50",  icon: "ticket.fill",                 title: "VIP della notte",     desc: "50 ingressi al Pavo.",             condition: .meets(50),  colors: [.yellow, .orange]),
            AchievementDef(id: "entry_100", icon: "ticket.fill",                 title: "Leggenda del Pavo",   desc: "100 ingressi al Pavo.",            condition: .meets(100), colors: [.yellow, .orange]),

            // Drink bevuti (riusa .coffees come contatore generico Drink)
            AchievementDef(id: "drink_1",    icon: "wineglass.fill",             title: "Aperitivo",           desc: "Bevi il tuo primo drink.",         condition: .coffees(1),   colors: [.indigo, .blue]),
            AchievementDef(id: "drink_5",    icon: "wineglass.fill",             title: "Degustatore",         desc: "5 drink bevuti.",                   condition: .coffees(5),   colors: [.indigo, .blue]),
            AchievementDef(id: "drink_10",   icon: "wineglass.fill",             title: "Bevitore esperto",    desc: "10 drink bevuti.",                  condition: .coffees(10),  colors: [.indigo, .blue]),
            AchievementDef(id: "drink_25",   icon: "wineglass.fill",             title: "Sommelier del Pavo",  desc: "25 drink bevuti.",                  condition: .coffees(25),  colors: [.indigo, .blue]),
            AchievementDef(id: "drink_50",   icon: "wineglass.fill",             title: "Bancone amico",       desc: "50 drink bevuti.",                  condition: .coffees(50),  colors: [.indigo, .blue]),
            AchievementDef(id: "drink_100",  icon: "wineglass.fill",             title: "Barista dentro",      desc: "100 drink bevuti.",                 condition: .coffees(100), colors: [.indigo, .blue]),

            // Shot fatti (riusa .feeds come contatore Shot)
            AchievementDef(id: "shot_1",   icon: "bolt.fill",                    title: "Primo shot",          desc: "Fai il primo shot.",                 condition: .feeds(1),   colors: [.pink, .purple]),
            AchievementDef(id: "shot_5",   icon: "bolt.fill",                    title: "Scaldamotori",        desc: "5 shot fatti.",                     condition: .feeds(5),   colors: [.pink, .purple]),
            AchievementDef(id: "shot_10",  icon: "bolt.circle.fill",             title: "Shot‑lover",          desc: "10 shot fatti.",                    condition: .feeds(10),  colors: [.pink, .purple]),
            AchievementDef(id: "shot_25",  icon: "bolt.circle.fill",             title: "Chupito King",        desc: "25 shot fatti.",                    condition: .feeds(25),  colors: [.pink, .purple]),
            AchievementDef(id: "shot_50",  icon: "bolt.heart.fill",              title: "Barman’s friend",     desc: "50 shot fatti.",                    condition: .feeds(50),  colors: [.pink, .purple]),

            // Sigle cantate (riusa .cleans come contatore Sigla)
            AchievementDef(id: "anthem_1",   icon: "megaphone.fill",             title: "Prima SIGLA",         desc: "Canta la SIGLA una volta.",         condition: .cleans(1),   colors: [.yellow, .orange]),
            AchievementDef(id: "anthem_5",   icon: "megaphone.fill",             title: "Coro del Pavo",       desc: "Canta la SIGLA 5 volte.",           condition: .cleans(5),   colors: [.yellow, .orange]),
            AchievementDef(id: "anthem_10",  icon: "megaphone.fill",             title: "Voce della notte",    desc: "Canta la SIGLA 10 volte.",          condition: .cleans(10),  colors: [.yellow, .orange]),
            AchievementDef(id: "anthem_25",  icon: "megaphone.fill",             title: "Coro ufficiale",      desc: "Canta la SIGLA 25 volte.",          condition: .cleans(25),  colors: [.yellow, .orange]),
            AchievementDef(id: "anthem_50",  icon: "megaphone.fill",             title: "Inno del Pavo",       desc: "Canta la SIGLA 50 volte.",          condition: .cleans(50),  colors: [.yellow, .orange]),

            // Livelli e longevità (restano utili)
            AchievementDef(id: "lv_1",  icon: "star.fill",      title: "Pulcino",        desc: "Raggiungi il livello 1.", condition: .level(1),  colors: [.green, .mint]),
            AchievementDef(id: "lv_2",  icon: "sparkles",       title: "Giovane Coda",   desc: "Raggiungi il livello 2.", condition: .level(2),  colors: [.green, .mint]),
            AchievementDef(id: "lv_3",  icon: "crown",          title: "Pavetto",        desc: "Raggiungi il livello 3.", condition: .level(3),  colors: [.green, .mint]),
            AchievementDef(id: "lv_4",  icon: "crown.fill",     title: "Reale",          desc: "Raggiungi il livello 4.", condition: .level(4),  colors: [.green, .mint]),
            AchievementDef(id: "lv_5",  icon: "crown.fill",     title: "Il Pavo-Real",   desc: "Raggiungi il livello 5.", condition: .level(5),  colors: [.green, .mint]),
            AchievementDef(id: "age_1d", icon: "calendar",                       title: "Giorno 1",            desc: "Tieni in vita per 1 giorno.",       condition: .ageDays(1),  colors: [.purple, .indigo]),
            AchievementDef(id: "age_7d", icon: "calendar.badge.exclamationmark", title: "Settimana!",          desc: "Tieni in vita per 7 giorni.",       condition: .ageDays(7),  colors: [.purple, .indigo]),
            AchievementDef(id: "age_30d",icon: "calendar.circle.fill",           title: "Mese epico",          desc: "Tieni in vita per 30 giorni.",      condition: .ageDays(30), colors: [.purple, .indigo]),

            // Curiosità
            AchievementDef(id: "death_1",  icon: "heart.slash.fill",             title: "Ops…",                desc: "Il Pavone è morto (una volta).",    condition: .deaths(1),  colors: [.gray, .black])
        ]
    }

// Lightweight confetti placeholder (so overlay compiles)
private struct ConfettiBurst: View {
    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                Text(["🎉","🎊","✨","⭐️"][i % 4])
                    .font(.title2)
                    .opacity(0.9)
                    .rotationEffect(.degrees(Double(i * 12)))
                    .offset(x: CGFloat((i % 7) * 12 - 36), y: CGFloat(i * 4 - 24))
            }
        }
        .allowsHitTesting(false)
        .transition(.scale.combined(with: .opacity))
    }
}

    // MARK: - Achievements Engine (fresh)
    private final class AchievementsCenter: ObservableObject {
        static let shared = AchievementsCenter()

        // Persistent storage keys
        private let unlockedKey = "El-PavoReal.ach.unlocked.v1"
        private let countersKey = "El-PavoReal.ach.counters.v1"
        private let lastDeathKey = "El-PavoReal.ach.lastDeathTS"

        // Counters persisted
        struct Counters: Codable {
            var PavoLireSpent: Int = 0
            var miniDeliveredTotal: Int = 0
            var miniSuccesses: Int = 0
            var feeds: Int = 0
            var coffees: Int = 0
            var cleans: Int = 0
            var meets: Int = 0
            var deaths: Int = 0
        }

        @Published private(set) var unlocked: Set<String>
        private(set) var counters: Counters

        private weak var vmRef: PetViewModel?

        private init() {
            if let data = UserDefaults.standard.data(forKey: unlockedKey),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                self.unlocked = Set(arr)
            } else { self.unlocked = [] }

            if let data = UserDefaults.standard.data(forKey: countersKey),
               let c = try? JSONDecoder().decode(Counters.self, from: data) {
                self.counters = c
            } else { self.counters = Counters() }
        }

        // MARK: Attach & persist
        func attach(vm: PetViewModel) { self.vmRef = vm }
        private func persist() {
            if let data = try? JSONEncoder().encode(Array(unlocked)) {
                UserDefaults.standard.set(data, forKey: unlockedKey)
            }
            if let data = try? JSONEncoder().encode(counters) {
                UserDefaults.standard.set(data, forKey: countersKey)
            }
        }

        // MARK: Queries
        func isUnlocked(_ id: String) -> Bool { unlocked.contains(id) }

        // MARK: Progress math
        private func pct(_ cur: Int, _ goal: Int) -> Double { goal <= 0 ? 1 : min(1, Double(cur)/Double(goal)) }
        func progressFraction(for c: AchievementCondition, vm: PetViewModel) -> Double {
            switch c {
            case .PavoLireSpent(let t): return pct(counters.PavoLireSpent, t)
            case .level(let t): return pct(vm.level, t)
            case .ageDays(let days):
                let need = max(1, Int(days * 86_400))
                return pct(vm.ageSeconds, need)
            case .allStatsAtLeast(let thr):
                let minv = [vm.satiety, vm.energy, vm.hygiene, vm.happiness].min() ?? 0
                return min(1, minv / max(1, thr))
            case .lifeFull:
                return vm.life >= 100 ? 1 : vm.life / 100.0
            case .miniGameSuccesses(let t): return pct(counters.miniSuccesses, t)
            case .miniGameDeliveredTotal(let t): return pct(counters.miniDeliveredTotal, t)
            case .feeds(let t): return pct(counters.feeds, t)
            case .coffees(let t): return pct(counters.coffees, t)
            case .cleans(let t): return pct(counters.cleans, t)
            case .meets(let t): return pct(counters.meets, t)
            case .deaths(let t): return pct(counters.deaths, t)
            }
        }

        private func conditionSatisfied(_ c: AchievementCondition, vm: PetViewModel) -> Bool {
            switch c {
            case .PavoLireSpent(let t): return counters.PavoLireSpent >= t
            case .level(let t): return vm.level >= t
            case .ageDays(let days): return Double(vm.ageSeconds) >= days * 86_400.0
            case .allStatsAtLeast(let thr):
                let v = Double(thr)
                return vm.satiety >= v && vm.energy >= v && vm.hygiene >= v && vm.happiness >= v
            case .lifeFull: return vm.life >= 100
            case .miniGameSuccesses(let t): return counters.miniSuccesses >= t
            case .miniGameDeliveredTotal(let t): return counters.miniDeliveredTotal >= t
            case .feeds(let t): return counters.feeds >= t
            case .coffees(let t): return counters.coffees >= t
            case .cleans(let t): return counters.cleans >= t
            case .meets(let t): return counters.meets >= t
            case .deaths(let t): return counters.deaths >= t
            }
        }

        // MARK: Evaluate & unlock
        func evaluateAll(vm: PetViewModel) {
            for a in AchievementsCatalog.all where !unlocked.contains(a.id) {
                if conditionSatisfied(a.condition, vm: vm) {
                    unlocked.insert(a.id); persist(); objectWillChange.send()
                    NotificationCenter.default.post(name: Notification.Name("El-PavoReal.achievementUnlocked"), object: a.id)
                }
            }
        }

        // MARK: Recorders (call from game events)
        func recordPavoLireSpent(_ v: Int) { guard v > 0 else { return }; counters.PavoLireSpent &+= v; persist(); if let vmRef { evaluateAll(vm: vmRef) } }
        func recordMiniGame(success: Bool, delivered: Int) { if success { counters.miniSuccesses &+= 1 }; counters.miniDeliveredTotal &+= max(0, delivered); persist(); if let vmRef { evaluateAll(vm: vmRef) } }
        func recordDeath() {
            let now = Date().timeIntervalSince1970
            let last = UserDefaults.standard.double(forKey: lastDeathKey)
            if now - last < 5 { return } // debounce
            UserDefaults.standard.set(now, forKey: lastDeathKey)
            counters.deaths &+= 1; persist(); if let vmRef { evaluateAll(vm: vmRef) }
        }
        func recordFeed()   { counters.feeds   &+= 1; persist(); if let vmRef { evaluateAll(vm: vmRef) } }
        func recordCoffee() { counters.coffees &+= 1; persist(); if let vmRef { evaluateAll(vm: vmRef) } }
        func recordClean()  { counters.cleans  &+= 1; persist(); if let vmRef { evaluateAll(vm: vmRef) } }
        func recordMeet()   { counters.meets   &+= 1; persist(); if let vmRef { evaluateAll(vm: vmRef) } }
    }

    // MARK: - Achievements UI (brand new)
    private struct AchievementsTab: View {
        @EnvironmentObject var vm: PetViewModel
        @ObservedObject private var center = AchievementsCenter.shared
        @State private var selected: AchievementDef? = nil
        @State private var showConfetti = false
        @State private var filter: Filter = .all

        private enum Filter: String, CaseIterable { case all = "Tutti", todo = "Da sbloccare", done = "Sbloccati" }
        private let cols = [GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 12)]

        private var total: Int { AchievementsCatalog.all.count }
        private var done: Int { center.unlocked.count }
        private var overall: Double { total == 0 ? 0 : Double(done)/Double(total) }

        private var data: [AchievementDef] {
            switch filter {
            case .all:  return AchievementsCatalog.all
            case .todo: return AchievementsCatalog.all.filter { !center.isUnlocked($0.id) }
            case .done: return AchievementsCatalog.all.filter { center.isUnlocked($0.id) }
            }
        }

        var body: some View {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Obiettivi")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 20)
                    
                    Text("Completa gli obiettivi per sbloccare ricompense e funzionalità.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                    
                    // Progress
                    HStack {
                        ProgressView(value: overall)
                            .tint(.white)
                            .scaleEffect(y: 1.5)
                        
                        Text("\(done)/\(total)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.leading, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                // Filter
                Picker("Filtro", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Grid
                ScrollView(showsIndicators: true) {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(data) { a in
                            let p = center.progressFraction(for: a.condition, vm: vm)
                            let u = center.isUnlocked(a.id)
                            AchBadge(achievement: a, unlocked: u, progress: p)
                                .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selected = a } }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .onAppear { AchievementsCenter.shared.attach(vm: vm); AchievementsCenter.shared.evaluateAll(vm: vm) }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("El-PavoReal.achievementUnlocked"))) { _ in
                withAnimation { showConfetti = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showConfetti = false }
            }
            .overlay { if showConfetti { ConfettiBurst() } }
            .sheet(item: $selected) { a in
                AchDetailSheet(a: a,
                               progress: AchievementsCenter.shared.progressFraction(for: a.condition, vm: vm),
                               unlocked: AchievementsCenter.shared.isUnlocked(a.id))
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private struct AchBadge: View {
        let achievement: AchievementDef
        let unlocked: Bool
        let progress: Double
        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient(colors: achievement.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                        .frame(width: 80, height: 80)
                        .saturation(unlocked ? 1 : 0)
                        .opacity(unlocked ? 1 : 0.55)
                        .scaleEffect(unlocked ? 1.0 : 0.95)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: unlocked)
                    Image(systemName: achievement.icon).font(.title2).foregroundStyle(.white).opacity(unlocked ? 1 : 0.65)
                    if !unlocked {
                        Circle()
                            .trim(from: 0, to: CGFloat(max(0.08, min(1.0, progress))))
                            .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .fill(.white.opacity(0.75))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 90, height: 90)
                            .allowsHitTesting(false)
                    }
                }
                Text(achievement.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(unlocked ? "Sbloccato" : "\(Int(round(progress*100)))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .frame(height: 160)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    private struct AchDetailSheet: View {
        let a: AchievementDef
        let progress: Double
        let unlocked: Bool
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            NavigationStack {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            ZStack { 
                                Circle().fill(LinearGradient(colors: a.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 60, height: 60)
                                Image(systemName: a.icon)
                                    .font(.title2)
                                    .foregroundStyle(.white) 
                            }
                            VStack(alignment: .leading, spacing: 4) { 
                                Text(a.title)
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                Text(a.desc)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: min(1, progress))
                                .tint(.white)
                                .scaleEffect(y: 1.5)
                            Text(unlocked ? "✅ Completato" : "Progresso: \(Int(progress*100))%")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Come sbloccarlo")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(hintText)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                    }
                    .padding(20)
                }
                .toolbar { 
                    ToolbarItem(placement: .topBarTrailing) { 
                        Button { dismiss() } label: { 
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.8))
                        } 
                    } 
                }
                .navigationTitle("Dettagli obiettivo")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        private var hintText: String {
            switch a.condition {
            case .PavoLireSpent: return "Spendi P£ al Bar: drink, acqua, accessi o booster."
            case .level: return "Gioca e completa azioni per salire di livello."
            case .ageDays: return "Tieni in vita il pet giorno dopo giorno."
            case .allStatsAtLeast: return "Porta tutte le statistiche sopra la soglia e mantienile."
            case .lifeFull: return "Porta la Vita a 100%."
            case .miniGameDeliveredTotal: return "Nel mini-gioco consegna più shot al Privé possibile."
            case .miniGameSuccesses: return "Completa il mini-gioco (Privé Rush) con successo più volte."
            case .deaths: return "Succede… poi si rinasce 😉"
            case .feeds: return "Fai uno shot al Bar."
            case .coffees: return "Prendi un drink al Bar."
            case .cleans: return "Canta la SIGLA: El Pavo‑Rèal."
            case .meets: return "Conta gli ingressi al Pavo (entra più volte)."
            }
        }
    }
    

    // MARK: - BG
    private var background: some View {
        ZStack {
            RadialGradient(colors: [Color(#colorLiteral(red:0.06, green:0.07, blue:0.2, alpha:1)), Color(#colorLiteral(red:0.02, green:0.02, blue:0.06, alpha:1))], center: .center, startRadius: 80, endRadius: 800)
                .ignoresSafeArea()
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Canvas { ctx, _ in
                    for i in 0..<36 {
                        let x = CGFloat((i*73)%Int(w+100))
                        let y = CGFloat((i*111)%Int(h+120))
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.white.opacity(0.08)))
                    }
                }
            }.allowsHitTesting(false)
            LinearGradient(colors: vm.moodColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(vm.mood == .critico ? 0.28 : (vm.mood == .felice ? 0.22 : 0.14))
                .blendMode(.plusLighter)
                .ignoresSafeArea()
        }
    }

    // MARK: - State for End Game
    @State private var showEndGame = false
    @State private var clubOpenDate: Date = {
        // Data di riapertura: cambiala a piacere
        Date().addingTimeInterval(14*24*60*60)
    }()
    @State private var showLevelInfo = false

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Spacer()
                
                // PavoLire: sempre visibile
                Button {
                    showPavoLireInfo = true
                } label: {
                    CoinBadge(value: vm.PavoLire)
                }
                .buttonStyle(.plain)
                
                // Shop, Eventi, Obiettivi, Impostazioni sempre visibili
                HStack(spacing: 12) {
                    Button { 
                        showShop = true
                    } label: {
                        Image(systemName: "cart")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial.opacity(0.3), in: Circle())
                    
                    Button { 
                        showEventLog = true
                    } label: {
                        Image(systemName: "clock")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial.opacity(0.3), in: Circle())
                    
                    Button { 
                        showObiettivi = true
                    } label: {
                        Image(systemName: "target")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial.opacity(0.3), in: Circle())
                    
                    Button { 
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial.opacity(0.3), in: Circle())
                }
            }
            HStack(spacing: 10) {
                LevelBadge(level: vm.level, onTap: { haptic(.soft); showLevelInfo = true })
                XPBar(progress: vm.xpProgress)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showLevelInfo) {
            LevelInfoSheet()
                .environmentObject(vm)
        }
    }
    
    // MARK: - Warning banner
    private var warningBanner: some View {
        Group {
            if isCritical {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").imageScale(.large)
                    Text(criticalMessage).font(.callout).bold().lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .red.opacity(0.45), radius: 12, x: 0, y: 6)
                )
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .foregroundStyle(.white)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var isCritical: Bool {
        vm.life < 20 ||
        vm.satiety   < 0.15 * vm.statCap ||
        vm.energy    < 0.15 * vm.statCap ||
        vm.hygiene   < 0.15 * vm.statCap ||
        vm.happiness < 0.15 * vm.statCap
    }

    private var criticalMessage: String {
        if vm.life < 20 { return "Sta male… aiutalo subito" }
        if vm.satiety   < 0.15 * vm.statCap { return "Non beve da troppo!" }
        if vm.hygiene   < 0.15 * vm.statCap { return "Devo rilassarmi!" }
        if vm.energy    < 0.15 * vm.statCap { return "Sono stanchissimo!" }
        if vm.happiness < 0.15 * vm.statCap { return "Voglio far festa!" }
        return ""
    }

    // MARK: - Sprite
    private var sprite: some View {
        ZStack {
            let auraSize: CGFloat = compactPadding ? 220 : 240 * CGFloat(vm.form.auraScale)
            let photoMaxH: CGFloat = compactPadding ? 200 : 220
            let photoMaxW: CGFloat = contentWidth - (compactPadding ? 90 : 100)
            let mc = vm.moodColors
            let auraColors = [ (mc.first ?? .cyan).opacity(0.35), (mc.last ?? .purple).opacity(0.35), Color.blue.opacity(0.28), (mc.first ?? .cyan).opacity(0.35) ]
            Circle()
                .fill(AngularGradient(colors: auraColors, center: .center))
                .blur(radius: 24)
                .frame(width: auraSize, height: auraSize)
                .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.06 : 0.98))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            Image(vm.moodSpriteName)
                .resizable().scaledToFit()
                .frame(maxWidth: photoMaxW, maxHeight: photoMaxH)
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
                .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.02 : 0.98)) // Pulsazione leggera
                .offset(y: reduceMotion ? 0 : (bobbing ? -4 : 4))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: bobbing)
                .overlay(alignment: .topTrailing) { heartsBadge }
                .animation(.easeInOut(duration: 0.3), value: vm.mood) // Transizione smooth tra sprite
        }
        .padding(.vertical, 4)
        .overlay(alignment: .top) {
            if vm.form.showsCrown {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .shadow(radius: 6)
                    .offset(y: -6)
            }
        }
    }

    private var heartsBadge: some View {
        let hearts = max(0, min(5, Int(ceil(vm.life / 20)) ))
        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < hearts ? "heart.fill" : "heart")
                        .foregroundStyle(i < hearts ? .red : .white.opacity(0.6))
                }
            }
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))

            if vm.life < 20 {
                HStack(spacing: 6) {
                    Image(systemName: "cross.case.fill")
                    Text("Medikit/Check‑up")
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture { showLifeInfo = true }
        .accessibilityLabel("Cuori: \(hearts) su 5")
    }

    // MARK: - Gauges (tile grid 2×2)
    private var gauges: some View {
        VStack(spacing: compactPadding ? 10 : 12) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill").foregroundStyle(.white)
                Text("Statistiche").font(.subheadline.bold()).foregroundStyle(.white)
                Spacer(minLength: 8)
                MoodBadge(title: vm.moodTitle, symbol: vm.moodSymbol, colors: vm.moodColors)
                    .environmentObject(vm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(symbol: "drop.fill",        title: "Sete",    progress: vm.satiety / vm.statCap,   color: .green,   value: Int(vm.satiety.rounded()))
                StatTile(symbol: "bolt.fill",        title: "Energia", progress: vm.energy  / vm.statCap,   color: .purple,  value: Int(vm.energy.rounded()))
                StatTile(symbol: "sparkles",         title: "Chill",   progress: vm.hygiene / vm.statCap,   color: .blue,    value: Int(vm.hygiene.rounded()))
                StatTile(symbol: "party.popper",     title: "Festa",   progress: vm.happiness / vm.statCap, color: .orange,    value: Int(vm.happiness.rounded()))
            }
        }
    }

fileprivate struct StatTile: View {
    let symbol: String
    let title: String
    let progress: Double
    let color: Color
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.white)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text("\(value)")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            CapsuleGauge(progress: max(0, min(1, progress)), color: color)
                .frame(height: 10)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}


    // MARK: - Actions (tematizzate)
    private var actions: some View {
        let cols = [GridItem(.flexible(), spacing: gridSpacing), GridItem(.flexible(), spacing: gridSpacing)]
        return LazyVGrid(columns: cols, spacing: gridSpacing) {
            // ROW 1 — alto sx: Nutellino, alto dx: Shot (Energia)
            GameButton(
                title: "Bevuta",
                system: "wineglass.fill",
                gradient: GradientTokens.satiety,
                isDisabled: isLocked("El-PavoReal.feedNextReadyAt"),
                hint: vm.feedHint,
                remainingText: { formatCooldown(remainingDeadline("El-PavoReal.feedNextReadyAt")) }
            ) {
                vm.feedNutellino()
                AchievementsCenter.shared.recordFeed()
                setDeadline("El-PavoReal.feedNextReadyAt", seconds: 120) // 4 min
                showQuickToast("Drink bevuto! +22 Sete", 
                               symbol: "wineglass.fill", 
                               colors: GradientTokens.satiety)
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if !isLocked("El-PavoReal.drinkNextReadyAt") {
                    quickPickKind = .drink
                    haptic(.medium)
                }
            }

            GameButton(
                title: "Shot",
                system: "bolt.fill",
                gradient: [.pink, .purple],
                isDisabled: isLocked("El-PavoReal.coffeeNextReadyAt"),
                hint: vm.coffeeHint,
                remainingText: { formatCooldown(remainingDeadline("El-PavoReal.coffeeNextReadyAt")) }
            ) {
                vm.coffeeBreak()
                AchievementsCenter.shared.recordCoffee()
                setDeadline("El-PavoReal.coffeeNextReadyAt", seconds: 90) // 3 min
                showQuickToast("Shot al bancone! +24 Energia", 
                               symbol: "bolt.fill", 
                               colors: [.pink, .purple])
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if !isLocked("El-PavoReal.coffeeNextReadyAt") {
                    quickPickKind = .shot
                    haptic(.medium)
                }
            }

            // ROW 2 — basso sx: Pulisci, basso dx: Ingresso su Meet
            GameButton(
                title: "Rilassati",
                system: "sparkles",
                gradient: [.teal, .blue],
                isDisabled: isLocked("El-PavoReal.cleanNextReadyAt"),
                hint: vm.cleanHint,
                remainingText: { formatCooldown(remainingDeadline("El-PavoReal.cleanNextReadyAt")) }
            ) {
                vm.pulisciScrivania()
                AchievementsCenter.shared.recordClean()
                setDeadline("El-PavoReal.cleanNextReadyAt", seconds: 120) // 2 min
                showQuickToast("Reset mentale! +26 Chill", 
                               symbol: "sparkles", 
                               colors: [.teal, .blue])
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if !isLocked("El-PavoReal.cleanNextReadyAt") {
                    quickPickKind = .relax
                    haptic(.medium)
                }
            }

            GameButton(
                title: "SIGLA!",
                system: "music.microphone",
                gradient: [.yellow, .orange],
                isDisabled: isLocked("El-PavoReal.meetNextReadyAt"),
                hint: vm.meetHint,
                remainingText: { formatCooldown(remainingDeadline("El-PavoReal.meetNextReadyAt")) }
            ) {
                vm.orientaSuMeet()
                AchievementsCenter.shared.recordMeet()
                setDeadline("El-PavoReal.meetNextReadyAt", seconds: 200) // 5 min
                showQuickToast("Alza la voce e canta insieme a noi! +2 P£", 
                               symbol: "music.microphone", 
                               colors: [.yellow, .orange])
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if !isLocked("El-PavoReal.meetNextReadyAt") {
                    quickPickKind = .sigla
                    haptic(.medium)
                }
            }
        }
        .padding(.top, compactPadding ? 8 : 14)
    }

    // MARK: - Footer
    private var footer: some View {
        VStack(spacing: 8) {
            // Booster banner
        HStack {
            Spacer()
            if let until = vm.boostUntil, until > Date() {
                let name = resolvedBoostName()
                let remaining = formatCooldown(until.timeIntervalSinceNow)
                CapsuleLabel(text: remaining.isEmpty ? "Booster attivo: \(name)" : "Booster attivo: \(name) · \(remaining)")
                }
            }
            
            // Daily Spin button
            if canPlaySlotToday() {
                Button {
                    haptic(.soft)
                    showDailySlot = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundStyle(.yellow)
                        Text("Slot Machine!")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    Text("(\(getRemainingTries())/10 tentativi)")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, compactPadding ? 20 : 24)
        .onReceive(vm.$hasFinishedRun) { finished in
            if finished { showEndGame = true }
        }
        .onAppear {
            if vm.hasFinishedRun || vm.level >= 5 { showEndGame = true }
        }
        .sheet(isPresented: $showEndGame) {
            EndGameSheet(openDate: clubOpenDate) {
                vm.resetAll()          // ← usa il tuo reset già esistente sul ViewModel
                showEndGame = false
            }
        }
    }

    // MARK: - 🎲 Random Events System
    /// Triggera eventi casuali (positivi/negativi) durante il gioco
    private func maybeTriggerRandomEvent() {
        // Probabilità base (clamp 0…1)
        let chance = max(0.0, min(1.0, eventChance))
        guard Double.random(in: 0...1) < chance else { return }
        // Mini-gioco Privé Rush RIMOSSO
        let events: [GameEvent] = [
            .positive("Giro omaggi dal bar: +6 Festa, +4 Sete, +3 PavoLire", {
                vm.happiness = min(vm.statCap, vm.happiness + 6)
                vm.satiety   = min(vm.statCap, vm.satiety + 4)
                vm.PavoLire += 3
            }, "gift.fill", [.yellow, .orange]),

            .positive("DJ mette la tua hit: +12 Festa, +6 Energia", {
                vm.happiness = min(vm.statCap, vm.happiness + 12)
                vm.energy    = min(vm.statCap, vm.energy + 6)
            }, "music.note.list", [.pink, .purple]),

            .positive("Si sale nel privé senza bracciale: +10 Festa, +3 PavoLire", {
                vm.happiness = min(vm.statCap, vm.happiness + 10)
                vm.PavoLire += 3
            }, "lock.open.fill", [.green, .mint]),

            .negative("Beccato senza bracciale: −10 Festa, −6 PavoLire", {
                vm.happiness = max(0, vm.happiness - 10)
                vm.PavoLire  = max(0, vm.PavoLire - 6)
            }, "exclamationmark.shield.fill", [.orange, .red]),

            .positive("Festa in cambusa: +8 Energia, +8 Festa", {
                vm.energy    = min(vm.statCap, vm.energy + 8)
                vm.happiness = min(vm.statCap, vm.happiness + 8)
            }, "party.popper", [.teal, .blue]),

            .negative("Qualcuno vomita vicino: −10 Festa, −6 Chill", {
                vm.happiness = max(0, vm.happiness - 10)
                vm.hygiene   = max(0, vm.hygiene - 6)
            }, "exclamationmark.triangle.fill", [.orange, .red]),

            .negative("Perdi il drink nella calca: −6 Sete, −2 PavoLire", {
                vm.satiety  = max(0, vm.satiety - 6)
                vm.PavoLire = max(0, vm.PavoLire - 2)
            }, "wineglass.fill", [.orange, .red]),

            .positive("Selfie col Pavone: +6 Festa, +2 PavoLire", {
                vm.happiness = min(vm.statCap, vm.happiness + 6)
                vm.PavoLire += 2
            }, "camera.fill", [.yellow, .orange]),

            .negative("Shot pagato due volte: −4 PavoLire", {
                vm.PavoLire = max(0, vm.PavoLire - 4)
            }, "creditcard.trianglebadge.exclamationmark.fill", [.orange, .red]),

            .positive("Giro offerto dagli amici: +10 Sete, +6 Festa", {
                vm.satiety   = min(vm.statCap, vm.satiety + 10)
                vm.happiness = min(vm.statCap, vm.happiness + 6)
            }, "person.3.fill", [.yellow, .orange]),

            .negative("Fila al bagno interminabile: −8 Energia, −6 Festa", {
                vm.energy    = max(0, vm.energy - 8)
                vm.happiness = max(0, vm.happiness - 6)
            }, "clock.badge.exclamationmark", [.orange, .red]),

                .positive("Barista di fiducia: extra shot! +12 Energia, +4 Festa", {
                    vm.energy    = min(vm.statCap, vm.energy + 12)
                    vm.happiness = min(vm.statCap, vm.happiness + 4)
                }, "bolt.fill", [.pink, .purple]),

            .negative("Amico sparisce con il tuo drink: −8 Sete, −2 Festa", {
                vm.satiety   = max(0, vm.satiety - 8)
                vm.happiness = max(0, vm.happiness - 2)
            }, "questionmark.circle.fill", [.orange, .red]),

            .positive("Ballo sul cubo: +10 Festa, +3 PavoLire", {
                vm.happiness = min(vm.statCap, vm.happiness + 10)
                vm.PavoLire += 3
            }, "flame.fill", [.pink, .purple]),

            .negative("Lite in pista: −6 Festa", {
                vm.happiness = max(0, vm.happiness - 6)
            }, "exclamationmark.triangle.fill", [.orange, .red]),

            .positive("Il DJ ti dedica un drop: +8 Festa", {
                vm.happiness = min(vm.statCap, vm.happiness + 8)
            }, "speaker.wave.2.fill", [.pink, .purple]),

            .negative("Troppi chupiti: −10 Energia, −6 Chill", {
                vm.energy  = max(0, vm.energy - 10)
                vm.hygiene = max(0, vm.hygiene - 6)
            }, "bolt.fill", [.orange, .red])
        ]
        if let ev = events.randomElement() {
            ev.apply()
            pushBanner(text: ev.text, symbol: ev.symbol, colors: ev.colors, log: true)
        }
    }

    // Banner queue helper (overlay-based)
    private func pushBanner(text: String, symbol: String, colors: [Color], log: Bool = false) {
        // Mappa i vecchi banner all'overlay full‑screen (con blur)
        let hasPositive = colors.contains(where: { $0 == .green || $0 == .mint || $0 == .yellow })
        let hasNegative = colors.contains(where: { $0 == .red || $0 == .orange })
        let tone: String = hasNegative && !hasPositive ? "negative"
                         : (hasPositive && !hasNegative ? "positive" : "system")

        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        let title = parts.first ?? raw
        let lines: [String] = {
            guard parts.count > 1 else { return [] }
            return parts[1]
                .replacingOccurrences(of: "−", with: "-")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }()

        // Mostra overlay full screen
        postOverlayEvent(title: title, icon: symbol, tone: tone, lines: lines)
    }
    
    // MARK: - Notifiche Non Invasive per Azioni Principali
    private func showQuickToast(_ text: String, symbol: String, colors: [Color]) {
        // Usa il nuovo sistema toast non invasivo
        showToast(text, symbol: symbol, colors: colors, duration: 2.0)
    }

// MARK: - Helper Components for New Tabs

struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.3), in: Circle())
            
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

struct CountdownCard: View {
    @State private var timeRemaining = "2 giorni, 14 ore"
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Prossimo H-ZOO")
                .font(.headline.bold())
                .foregroundStyle(.white)
            
            Text(timeRemaining)
                .font(.title2.bold())
                .foregroundStyle(.orange)
            
            Text("Venerdì 21:00")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

struct EventSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            
            content
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

struct EventTimeSlot: View {
    let time: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.caption.bold())
                .foregroundStyle(.orange)
                .frame(width: 50, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SpecialCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.3), in: Circle())
            
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            
            Text(description)
                .font(.caption.bold())
                .foregroundStyle(color)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }

// MARK: - End Game Sheet
private struct EndGameSheet: View {
    let openDate: Date
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .full
        return f.string(from: openDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.5), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.top, 12)
                    Text("Grazie di aver giocato!")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Il Pavo aprirà il \(formattedDate).")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 24)
                    Button {
                        onReset()
                        dismiss()
                    } label: {
                        Text("Resetta e riparti da zero")
                            .font(.headline)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Fine gioco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") } } }
        }
    }
}

    
    // Applica progresso offline minuto per minuto: decay, vita, PavoLire e età.
    private func applyOfflineProgress(seconds: TimeInterval) {
        guard seconds > 1 else { return }
        let offlinePavoLireSessionCap = 20 // tetto PavoLire passivi per singola sessione offline

        // Base per-second rates (allineati al tick live) + moltiplicatore offline (più lento)
        let satietyPerSec: Double = 100.0 / (8.0  * 3600.0)
        let energyPerSec:  Double = 100.0 / (10.0 * 3600.0)
        let hygienePerSec: Double = 100.0 / (12.0 * 3600.0)
        let offlineDecayMul: Double = 0.25   // offline = 4× più lento del foreground
        let cap = vm.statCap

        var remaining = Int(seconds)
        var processedSeconds: Int = 0
        var PavoLireBucket: Double = 0

        while remaining > 0 {
            let step = min(60, remaining)
            processedSeconds += step

            // Decay naturali (coerenti col tick live, ma più lenti offline)
            vm.satiety = max(0, min(cap, vm.satiety - satietyPerSec * Double(step) * offlineDecayMul))
            vm.energy  = max(0, min(cap, vm.energy  -  energyPerSec * Double(step) * offlineDecayMul))
            vm.hygiene = max(0, min(cap, vm.hygiene - hygienePerSec * Double(step) * offlineDecayMul))

            // Felicità: riallineo verso la media (come nel tick) ma scalato offline
            let targetH = (vm.energy + vm.hygiene + vm.satiety) / 3
            vm.happiness = max(0, min(cap, vm.happiness + (targetH - vm.happiness) * 0.045 * Double(step) * offlineDecayMul))

            // Vita offline: stessa logica del tick ma scalata offline
            let critT = 0.15 * cap
            var penalty: Double = 0
            if vm.satiety < critT { penalty += (critT - vm.satiety) * 0.012 }
            if vm.energy  < critT { penalty += (critT - vm.energy)  * 0.012 }
            if vm.hygiene < critT { penalty += (critT - vm.hygiene) * 0.010 }
            if vm.happiness < critT { penalty += (critT - vm.happiness) * 0.012 }

            if penalty > 0 {
                vm.life = max(0, vm.life - penalty * Double(step) * offlineDecayMul)
            } else {
                let goodStats = vm.satiety > 0.6 * cap && vm.energy > 0.6 * cap && vm.hygiene > 0.6 * cap && vm.happiness > 0.6 * cap
                let regen: Double = goodStats ? 0.06 : 0.03
                vm.life = min(100, vm.life + regen * Double(step) * offlineDecayMul)
            }

            // PavoLire passivi (ridotti + soft cap + penalità AFK)
            let moodState = computedMood(for: vm)
            // base più lenti
            let baseSPM: Double = {
                switch moodState {
                case .felice:     return 28
                case .rabbia:     return 32
                case .neutro:     return 36
                case .stanchezza: return 44
                case .noia:       return 48
                case .critico:    return 60
                }
            }()
            // penalità se hai già molti PavoLire (soft cap): da 0→+2x quando > 50 M
            let softCap = 1.0 + min(2.0, max(0.0, Double(vm.PavoLire - 50)) / 250.0)
            // penalità AFK progressiva: +1x ogni 30m, max +3x
            let afkPenalty = 1.0 + min(3.0, Double(processedSeconds) / 1800.0)
            let effSPM = baseSPM * softCap * afkPenalty
            PavoLireBucket += Double(step) / effSPM

            vm.ageSeconds += step
            remaining -= step
            if vm.life <= 0 { break }
        }

        // Se è morto offline, segnala lo stato (hook opzionale)
        if vm.life <= 0 {
            // TODO: aggancia qui la tua logica di "morte" (es. flag vm.isDead = true o presentazione sheet)
            // Lasciamo solo un banner non-bloccante per evitare crash se il VM non espone handleDeath().
            pushBanner(text: "Mentre eri via... il Pavone è morto!", symbol: "heart.slash.fill", colors: [.red, .black])
        }

        // Concedi PavoLire offline con tetto per sessione
        let grant = min(offlinePavoLireSessionCap, Int(PavoLireBucket))
        if grant > 0 {
            vm.PavoLire += grant
        }

        save()
    }

    // piccoli stub sicuri — se il tuo VM non li ha già, lasciali, altrimenti puoi rimuoverli
    private func save() { /* no-op: persistenza gestita altrove */ }
    
    // MARK: - Local notifications (background helpers)
    private func scheduleLocal(id: String, title: String, body: String, after seconds: TimeInterval) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        // one-shot; iOS consegna in background se l'utente ha dato il permesso
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, seconds), repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - 🔔 Background Notifications
    /// Schedula notifiche quando l'app va in background
    private func scheduleBackgroundNotifications() {
        guard notificationsEnabled else { return }

        // evita duplicati / ripulisci vecchi ID
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["checkin","lowSatietyBg","criticallyLowBg","fastDropBg","stateSpeedBg","slotTimeNotif"]
        )
        
        // NUOVO: Notifica per slot machine (01:00-03:00 sabato)
        scheduleSlotTimeNotification()

        let cap = vm.statCap
        let lows = [vm.satiety, vm.energy, vm.hygiene, vm.happiness]
        let lowCount = lows.filter { $0 < 0.35 * cap }.count

        // 1) È troppo tempo che non entro → check-in a ~75 minuti
        scheduleLocal(
            id: "checkin",
            title: "Tutto ok?",
            body: "È un po’ che non entri. Dai un’occhiata al Pavone.",
            after: 75 * 60
        )

        // 2) Stato che fa scendere più velocemente (es. stanchezza/noia/critico)
        if vm.mood == .stanchezza || vm.mood == .noia || vm.mood == .critico {
            scheduleLocal(
                id: "stateSpeedBg",
                title: "Consumi più veloci",
                body: "Il Pavone è in modalità \(vm.moodTitle.lowercased()). Potrebbe scendere più in fretta.",
                after: 30 * 60
            )
        }

        // 3) Scende troppo veloce: più statistiche già basse
        if lowCount >= 2 {
            scheduleLocal(
                id: "fastDropBg",
                title: "Attenzione!",
                body: "Diverse statistiche sono basse. Non lasciar morire il Pavone!",
                after: 30 * 60
            )
        }

        // 4) Sono critico e sto per morire
        if vm.life < 30 || lows.contains(where: { $0 < 0.15 * cap }) {
            scheduleLocal(
                id: "criticallyLowBg",
                title: "Critico: rischio KO!",
                body: "Il Pavone è messo male. Entra subito e curalo.",
                after: 10 * 60
            )
        }
    }

    /// Schedula notifica per slot machine (sabato 00:55)
    private func scheduleSlotTimeNotification() {
        let now = Date()
        let calendar = HZooConfig.calendar
        
        // Calcola il prossimo sabato alle 00:55
        var components = DateComponents()
        components.weekday = 7 // Sabato
        components.hour = 0
        components.minute = 55
        components.timeZone = HZooConfig.timezone
        
        guard let nextDate = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else { return }
        
        let timeInterval = nextDate.timeIntervalSinceNow
        guard timeInterval > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🎰 È l'ora della Slot Machine!"
        content.body = "Hai 10 tentativi per vincere la maglietta H-ZOO! Entra ora 🎁"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: "slotTimeNotif", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
        print("🔔 Notifica slot schedulata per: \(nextDate)")
    }
    
    // MARK: - Notifications permission
    private func requestNotificationsIfNeeded() {
        guard notificationsEnabled, !askedNotifications else { return }
        askedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
    
    // MARK: - Tutorial al primo accesso
    private var showTutorialOnFirstVisit: Bool {
        !UserDefaults.standard.bool(forKey: "El-PavoReal.seenMinigameTutorial")
    }
    
    // MARK: - Dynamic Content Views
    
    /// Router principale per minigame
    @ViewBuilder
    private var dynamicMinigameContent: some View {
        if let currentGame = minigameManager.currentMinigame {
            switch currentGame.type {
            case .slotMachine:
                slotMachineContent
            case .roulette:
                rouletteContent
            case .scratchCard:
                scratchCardContent
            case .none:
                noMinigameContent
            }
        } else {
            // Fallback: mostra slot machine di default mentre carica
            slotMachineContent
        }
    }
    
    /// Slot Machine (current default)
    private var slotMachineContent: some View {
        VStack(spacing: compactPadding ? 12 : 20) {
            header
            warningBanner
            sprite
            gauges
            actions
            footer
        }
        .frame(maxWidth: contentWidth, alignment: .center)
        .padding(.top, 26)
        .padding(.horizontal, compactPadding ? 16 : 24)
        .padding(.bottom, compactPadding ? 6 : 10)
    }
    
    /// Roulette (future minigame)
    private var rouletteContent: some View {
        VStack(spacing: 20) {
            Text("🎰 Roulette Pavo")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            
            Text("Prossimamente disponibile!")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
            
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 100))
                .foregroundStyle(HZooConfig.primaryNeon)
                .padding(.top, 40)
            
            Text("Questo minigame sarà attivo nelle prossime settimane")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
        .padding()
    }
    
    /// Scratch Card (future minigame)
    private var scratchCardContent: some View {
        VStack(spacing: 20) {
            Text("🎫 Gratta e Vinci")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            
            Text("Prossimamente disponibile!")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
            
            Image(systemName: "ticket.fill")
                .font(.system(size: 100))
                .foregroundStyle(HZooConfig.primaryNeon)
                .padding(.top, 40)
            
            Text("Questo minigame sarà attivo nelle prossime settimane")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
        .padding()
    }
    
    /// No Minigame (pause week)
    private var noMinigameContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 100))
                .foregroundStyle(.cyan)
                .padding(.bottom, 20)
            
            Text("Settimana di Pausa")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            
            Text("Il Pavo si sta riposando 🦚")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 30)
            
            VStack(alignment: .leading, spacing: 12) {
                MinigameInfoRow(icon: "calendar", text: "Torna venerdì prossimo per un nuovo minigame!")
                MinigameInfoRow(icon: "sparkles", text: "Nel frattempo, continua ad accumulare Pavo Lire")
                MinigameInfoRow(icon: "bell.fill", text: "Riceverai una notifica quando sarà attivo")
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 80)
    }
}

// Helper per NoMinigame view
private struct MinigameInfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(HZooConfig.primaryNeon)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Helper Views & Models
struct LevelBadge: View { let level: Int; var onTap: (() -> Void)? = nil
    private var levelName: String {
        switch max(0, min(5, level)) {
        case 0: return "Pulcino"          // LV 0
        case 1: return "Giovane Pavo"     // LV 1
        case 2: return "Pavetto"          // LV 2
        case 3: return "Grande Pavo"            // LV 3
        case 4: return "Pavo Supremo"            // LV 4
        case 5: return "Il PavoReal"     // LV 5
        default: return "Pulcino"
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            Text("LV \(max(1, min(level, 5)))")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
            Text("· \(levelName)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .opacity(0.95)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                .shadow(color: .pink.opacity(0.6), radius: 10)
        )
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

private struct LevelInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: PetViewModel

    private let names = [
        0: "Pulcino",
        1: "Giovane Pavo",
        2: "Pavetto",
        3: "Grande Pavo",
        4: "Pavo Supremo",
        5: "Il PavoReal"
    ]

    private var curLevel: Int { max(0, min(5, vm.level)) }
    private var shownLevel: Int { max(1, min(5, vm.level)) }
    private var curName: String { names[curLevel] ?? "Pulcino" }

    private var prevInfo: (num: Int, name: String)? {
        guard curLevel > 0 else { return nil }
        let n = curLevel - 1
        return (max(1, n), names[n] ?? "Pulcino")
    }
    private var nextInfo: (num: Int, name: String)? {
        guard curLevel < 5 else { return nil }
        let n = curLevel + 1
        return (max(1, n), names[n] ?? "")
    }

    private func statCap(at level: Int) -> Int {
        let v = min(100, 60 + Double(level) * 5)
        return Int(v.rounded())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.5), .purple.opacity(0.5)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                Color.black.opacity(0.35).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 44, height: 44)
                                Text("LV \(shownLevel)").font(.subheadline.bold()).foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(curName).font(.title3.bold()).foregroundStyle(.white)
                                Text("Dettagli del livello").font(.footnote).foregroundStyle(.white.opacity(0.9))
                            }
                        }

                        InfoSection(title: "Cosa cambia ora") {
                            InfoBulletRow(text: "Cap massimo statistiche: \(statCap(at: curLevel))")
                            InfoBulletRow(text: "Forma attuale: \(vm.form.displayName)")
                            InfoBulletRow(text: vm.level >= 5 ? "Fine gioco raggiunta: puoi resettare e ricominciare" : "Prosegui per sbloccare il prossimo livello")
                        }

                        if let next = nextInfo {
                            InfoSection(title: "Prossimo livello") {
                                InfoBulletRow(text: "LV \(next.num) · \(next.name)")
                                let nextCap = statCap(at: min(5, curLevel+1))
                                InfoBulletRow(text: "Cap statistiche a \(nextCap)")
                                InfoBulletRow(text: "Avanza giocando: azioni e minigiochi danno XP")
                            }
                        }

                        if let prev = prevInfo {
                            InfoSection(title: "Livello precedente") {
                                InfoBulletRow(text: "LV \(prev.num) · \(prev.name)")
                            }
                        }

                        InfoSection(title: "Progresso") {
                            StatBarTile(title: "XP", symbol: "chart.bar.fill", progress: vm.xpProgress, colors: [.pink, .purple], value: nil)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Livello \(shownLevel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") } } }
        }
    }
}

struct MoodBadge: View {
    let title: String
    let symbol: String
    let colors: [Color]
    @State private var showInfo = false
    @EnvironmentObject var vm: PetViewModel
    
    

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: 10, height: 10)
            Image(systemName: symbol).font(.caption2)
            Text(title).font(.caption.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .foregroundStyle(.white)
        .contentShape(Capsule())
        .onTapGesture { showInfo = true }
        .sheet(isPresented: $showInfo) {
            MoodInfoSheet()
                .environmentObject(vm)
        }
    }
}


struct CapsuleLabel: View { let text: String
    var body: some View {
        Text(text)
            .font(.caption).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .foregroundStyle(.white)
    }
}

// MARK: - Mood model, helper & info sheet
private enum MoodState: String { case felice, stanchezza, rabbia, noia, critico, neutro }

private func computedMood(for vm: PetViewModel) -> MoodState {
    let minStat = min(vm.satiety, vm.energy, vm.hygiene, vm.happiness)
    let avgStat = (vm.satiety + vm.energy + vm.hygiene + vm.happiness) / 4.0

    // Priorità 1: CRITICO (emergenza assoluta)
    if vm.life < 20 || minStat < 12 { return .critico }

    // Priorità 2: FELICE (tutto va bene)
    if (minStat >= 65 && vm.life >= 55) || (avgStat >= 72 && vm.life >= 50) {
        return .felice
    }

    // Priorità 3: RABBIA (felicità molto bassa)
    if vm.happiness < 30 { return .rabbia }

    // Priorità 4: STANCHEZZA (energia bassa)
    if vm.energy < 32 { return .stanchezza }

    // Priorità 5: NOIA (felicità bassa ma non disperata + altre stats non buone)
    if vm.happiness < 35 && avgStat < 50 { return .noia }

    // Default: NEUTRO
    return .neutro
}

private struct MoodDescriptor {
    let title: String
    let symbol: String
    let colors: [Color]
    let effects: [String]
    let advice: [String]
}

private func moodDescriptor(for state: MoodState) -> MoodDescriptor {
    switch state {
    case .felice:
        return .init(
            title: "Felice",
            symbol: "party.popper",
            colors: [.pink, .purple],
            effects: [
                "Il Pavo va alla grande!",
                "XP extra guadagnati",
                "Atmosfera più luminosa"
            ],
            advice: [
                "Mantieni tutte le stat alte (sopra 70)",
                "Ballare e fare ingressi lo tengono su",
                "Ricordati anche di bere acqua"
            ]
        )
    case .stanchezza:
        return .init(
            title: "Stanchezza",
            symbol: "bolt.slash.fill",
            colors: [.purple.opacity(0.7), .indigo.opacity(0.7)],
            effects: [
                "L'energia cala più in fretta",
                "Meno monete guadagnate"
            ],
            advice: [
                "Fai uno Shot per riprenderti",
                "Alterna con un bicchiere d'acqua",
                "Concediti una pausa per rilassarti"
            ]
        )
    case .rabbia:
        return .init(
            title: "Rabbia",
            symbol: "flame.fill",
            colors: [.red, .orange],
            effects: [
                "Drink e Shot fanno un po' più effetto",
                "Interfaccia accesa e agitata"
            ],
            advice: [
                "Mangia qualcosa o bevi per calmarti",
                "Vai a fare un giro in pista",
                "Metti un accessorio Pavo‑Real per fare festa"
            ]
        )
    case .noia:
        return .init(
            title: "Noia",
            symbol: "hourglass",
            colors: [.gray, .blue.opacity(0.6)],
            effects: [
                "La Festa cala lentamente",
                "Monete più lente"
            ],
            advice: [
                "Canta la SIGLA (El Pavo‑Rèal)",
                "Fai un Ingresso al locale",
                "Attiva un booster o un minigioco per smuovere la serata"
            ]
        )
    case .critico:
        return .init(
            title: "Critico",
            symbol: "heart.slash.fill",
            colors: [.red, .black],
            effects: [
                "La Vita può scendere velocemente",
                "Monete molto rallentate",
                "UI di emergenza"
            ],
            advice: [
                "Serve un Medikit o Check‑up subito",
                "Alza almeno due statistiche sopra 25",
                "Unisci Spuntino + Shot per rianimarti"
            ]
        )
    case .neutro:
        return .init(
            title: "Neutro",
            symbol: "circle",
            colors: [.white.opacity(0.8), .gray],
            effects: [
                "Valori abbastanza stabili",
                "Monete nella media"
            ],
            advice: [
                "Punta gradualmente a superare 70",
                "Occhio a Chill e Festa, non trascurarle"
            ]
        )
    }
}

// MARK: - Life Info Sheet (top-level)
private struct LifeInfoSheet: View {
    @EnvironmentObject var vm: PetViewModel

    private func drainBreakdown() -> [(label: String, ratePerSec: Double, icon: String)] {
        var items: [(String, Double, String)] = []
        if vm.satiety < 20 { items.append(("Sete bassa", (20 - vm.satiety) * 0.012, "birthday.cake.fill")) }
        if vm.energy  < 20 { items.append(("Energia bassa",  (20 - vm.energy)  * 0.012, "bolt.fill")) }
        if vm.hygiene < 20 { items.append(("Chill bassa",  (20 - vm.hygiene) * 0.010, "sparkles")) }
        if vm.happiness < 20 { items.append(("Festa bassa", (20 - vm.happiness) * 0.012, "face.smiling")) }
        return items
    }

    private func minutes(_ value: Double) -> String {
        guard value.isFinite && value > 0 else { return "—" }
        let m = Int(ceil(value))
        return "\(m)m"
    }

    var body: some View {
        let drains = drainBreakdown()
        let totalDrain = drains.reduce(0) { $0 + $1.ratePerSec }
        let allHigh = vm.satiety > 60 && vm.energy > 60 && vm.hygiene > 60 && vm.happiness > 60
        let regenPerSec: Double = totalDrain > 0 ? 0 : (allHigh ? 0.06 : 0.03)
        let netPerMin = (regenPerSec - totalDrain) * 60.0

        NavigationStack {
            ZStack {
                LinearGradient(colors: [.red.opacity(0.22), .orange.opacity(0.18), .purple.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                Color.black.opacity(0.50).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header card
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "heart.fill").foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Salute & Vita").font(.title3.bold()).foregroundStyle(.white)
                                Text("Stato attuale, cause e rimedi rapidi")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))

                        // Metric pills
                        HStack(spacing: 10) {
                            CapsuleLabel(text: String(format: "Vita: %.0f/100", vm.life))
                            CapsuleLabel(text: String(format: "%@/min", netPerMin >= 0 ? String(format: "+%.1f", netPerMin) : String(format: "%.1f", netPerMin)))
                            if totalDrain > 0 {
                                let minToZero = vm.life / max(0.0001, totalDrain*60)
                                CapsuleLabel(text: "KO in ~\(minutes(minToZero))")
                            } else if regenPerSec > 0 {
                                let minToFull = (100 - vm.life) / (regenPerSec*60)
                                CapsuleLabel(text: "Full in ~\(minutes(minToFull))")
                            }
                        }

                        // Stato chiaro
                        InfoSection(title: "Stato attuale") {
                            InfoBulletRow(text: vm.life < 30 ? "⚠️ Critico: rischio KO" : (vm.life < 60 ? "In bilico: presta attenzione" : "Stabile"))
                            InfoBulletRow(text: netPerMin >= 0 ? "Va meglio: recupero graduale" : "Sta calando: serve una mano")
                        }

                        // Cause principali con valori/min
                        InfoSection(title: "Cause principali") {
                            if drains.isEmpty {
                                InfoBulletRow(text: "Nessuna: tutte le statistiche sono ≥ 20")
                            } else {
                                ForEach(0..<drains.count, id: \.self) { i in
                                    let d = drains[i]
                                    InfoBulletRow(text: d.label)
                                }
                            }
                        }

                        // Azioni consigliate (immediate)
                        InfoSection(title: "Cosa fare adesso") {
                            let pills: [(String,String)] = {
                                var arr: [(String,String)] = []
                                if vm.life < 45      { arr.append(("cross.case.fill", "Fai un controllo rapido")) }
                                if vm.satiety < 40   { arr.append(("wineglass.fill", "Fatti una bevuta (rinfresca e riparti)")) }
                                if vm.energy < 40    { arr.append(("bolt.fill", "Fai uno Shot o una pausa")) }
                                if vm.hygiene < 40   { arr.append(("sparkles", "Prenditi un momento per rilassarti")) }
                                if vm.happiness < 45 { arr.append(("party.popper.fill", "Vai a divertirti in pista o canta la SIGLA!")) }
                                return arr
                            }()

                            if pills.isEmpty {
                                InfoPill(icon: "sun.max.fill", text: "Rilassati 😌 — è tutto sotto controllo")
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(pills.prefix(6), id: \.0) { p in
                                        InfoPill(icon: p.0, text: p.1)
                                    }
                                }
                            }
                        }
                        // Consigli avanzati
                        InfoSection(title: "Consigli pro") {
                            InfoBulletRow(text: "Tieni almeno due indicatori in zona verde: così ti rigeneri più in fretta")
                            InfoBulletRow(text: "Non lasciare che troppe voci finiscano in rosso: la Vita scenderà più velocemente")
                            InfoBulletRow(text: "Attiva i booster quando sai che giocherai un po’: riducono il consumo delle statistiche")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 680)
                }
            }
            .navigationTitle("Info Vita")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
private struct MoodInfoSheet: View {
    @EnvironmentObject var vm: PetViewModel
    var body: some View {
        let state = computedMood(for: vm)
        let desc  = moodDescriptor(for: state)
        NavigationStack {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: desc.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 52, height: 52)
                                Image(systemName: desc.symbol).foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(desc.title).font(.title3.bold()).foregroundStyle(.white)
                                Text("Umore corrente e impatti di gioco")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))

                        // Effetti attivi
                        InfoSection(title: "Effetti attivi") {
                            ForEach(desc.effects, id: \.self) { InfoBulletRow(text: $0) }
                        }

                        // Suggerimenti rapidi
                        InfoSection(title: "Suggerimenti rapidi") {
                            let pills: [(String,String)] = {
                                var arr: [(String,String)] = []
                                if vm.life < 45      { arr.append(("cross.case.fill", "Occhio alla vita!")) }
                                if vm.satiety < 40   { arr.append(("wineglass.fill", "Fatti una bevuta (rinfresca e riparti)")) }
                                if vm.energy < 40    { arr.append(("bolt.fill", "Fai uno Shot o una pausa")) }
                                if vm.hygiene < 40   { arr.append(("sparkles", "Prenditi un momento per rilassarti")) }
                                if vm.happiness < 45 { arr.append(("party.popper.fill", "Vai a divertirti in pista o canta la SIGLA!")) }
                                return arr
                            }()

                            if pills.isEmpty {
                                InfoPill(icon: "sun.max.fill", text: "Tutto ok 😌 — continua così")
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(pills, id: \.0) { p in
                                        InfoPill(icon: p.0, text: p.1)
                                    }
                                }
                            }
                        }

                        // Come migliorarlo
                        InfoSection(title: "Come migliorarlo") {
                            if desc.advice.isEmpty {
                                InfoBulletRow(text: "Rilassati 😌 — va tutto bene così. Mantieni il ritmo.")
                            } else {
                                ForEach(desc.advice, id: \.self) { InfoBulletRow(text: $0) }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 680)
                }
            }
            .navigationTitle("Info stato")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension GradientTokens {
    /// Azzurro/blu per i PavoLire (usato nel bollino moneta)
    static let PavoLireGradient: [Color] = [.blue, .cyan]
}

struct CoinBadge: View {
    let value: Int
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .cyan],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                Text("P£")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text("\(value)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .foregroundStyle(.white)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Capsule())
    }
}

struct EventBannerData: Identifiable, Equatable { let id: UUID; let text: String; let symbol: String; let colors: [Color] }

struct LoggedEvent: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
    let symbol: String
    let colors: [Color]
}

// MARK: - Mini-game: Privé Rush RIMOSSO
// Il codice del Privé Rush è stato rimosso completamente

// MARK: - Event Log (row nuova)

private struct EventLogRow: View {
    let text: String          // es: "Pausa fatta in orario: che benessere! +12 Energia, +6 Festa"
    let date: Date            // timestamp dell’evento
    let symbol: String        // es: "arrow.2.circlepath" (fallback se non lo hai: "sparkles")
    let colors: [Color]       // gradient badge, es: [.teal, .cyan]

    var body: some View {
        let parts = splitEventText(text)
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors.isEmpty ? [.purple, .pink] : colors,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                    Image(systemName: symbol.isEmpty ? "sparkles" : symbol)
                        .foregroundStyle(.white)
                        .font(.subheadline)
                }

                Text(parts.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 8)
            }

            if !parts.effects.isEmpty {
                // pill per ogni effetto
                FlowVStack(spacing: 6) {
                    ForEach(parts.effects, id: \.self) { e in
                        EffectPill(text: e)
                    }
                }
            }

            // time stamp
            InfoPill(icon: "clock", text: timeString(date))
                .foregroundStyle(.white)
        }
        .padding(12)
        .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
    }

    // separa titolo da impatti (cerca il primo +/− che introduce davvero gli effetti)
    private func splitEventText(_ t: String) -> (title: String, effects: [String]) {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Trova un +/− che sia preceduto da spazio/virgola/\n o inizio stringa e seguito da una cifra: evita i trattini interni (es. FI-PI-LI)
        var splitIdx: String.Index? = nil
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "+" || ch == "−" || ch == "-" { // gestisci sia minus Unicode che hyphen ASCII
                let prev = (i > s.startIndex) ? s[s.index(before: i)] : " "
                let next = s.index(after: i) < s.endIndex ? s[s.index(after: i)] : " "
                let prevIsSep = prev.isWhitespace || prev == "," || prev == ":"
                let nextIsDigit = next.isNumber
                if prevIsSep && nextIsDigit {
                    splitIdx = i
                    break
                }
            }
            i = s.index(after: i)
        }
        guard let idx = splitIdx else {
            return (title: s, effects: [])
        }
        let head = String(s[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(s[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = tail
            .replacingOccurrences(of: "−", with: "-")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (title: head, effects: chunks)
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// pill colorata per + / −
private struct EffectPill: View {
    let text: String
    private var isNegative: Bool { text.contains("-") }
    private var iconName: String {
        // heuristics: prendo la statistica dal testo
        let lower = text.lowercased()
        if lower.contains("energia") { return "bolt.fill" }
        if lower.contains("Festa") || lower.contains("felic") { return "face.smiling" }
        if lower.contains("saziet") { return "birthday.cake.fill" }
        if lower.contains("Chill") { return "sparkles" }
        if lower.contains("vita") || lower.contains("cuore") { return "heart.fill" }
        return isNegative ? "arrow.down" : "arrow.up"
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName).imageScale(.small)
            Text(text)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            LinearGradient(colors: isNegative ? [.red, .orange] : [.green, .mint],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .foregroundStyle(.white)
    }
}

// semplice “flow” a capi multipli (contiene le pill e va a capo da solo)
private struct FlowVStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content
    var body: some View {
        // basta un VStack perché ogni pill è piccola; se vuoi un flow vero, si può fare, ma qui restiamo leggeri.
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EventLogView: View {
    @Binding var log: [LoggedEvent]

    private let cal = Calendar.current
    private var grouped: [(day: Date, events: [LoggedEvent])] {
        let dict = Dictionary(grouping: log) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, (dict[$0] ?? []).sorted(by: { $0.date > $1.date })) }
    }

    private func dayTitle(_ day: Date) -> String {
        if cal.isDateInToday(day) { return "Oggi" }
        if cal.isDateInYesterday(day) { return "Ieri" }
        let df = DateFormatter()
        df.locale = .current
        df.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return df.string(from: day)
    }

    // --- Inserted helper builders ---
    @ViewBuilder
    private var listContent: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if log.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    EmptyEventCard(
                        title: "Nessun evento",
                        subtitle: "Gli imprevisti compariranno qui."
                    )
                }
                .padding(.vertical, 8)
            } else {
                ForEach(grouped, id: \.day) { section in
                    sectionView(section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: (day: Date, events: [LoggedEvent])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayTitle(section.day))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 2)

            VStack(spacing: 8) {
                ForEach(section.events) { e in
                    EventLogRow(
                        text: e.text,
                        date: e.date,
                        symbol: e.symbol,
                        colors: e.colors
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
            }
        }
    }
    // --- End inserted helper builders ---

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.35), .purple.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                Color.black.opacity(0.45).ignoresSafeArea()

                ScrollView {
                    listContent
                        .padding(.vertical, 16)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Eventi casuali")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !log.isEmpty { Button("Svuota") { log.removeAll() } }
                }
            }
        }
    }
}

private struct EventCard: View {
    let event: LoggedEvent
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: event.colors,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: event.symbol)
                    .font(.caption)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 8)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            // Stripe colorata a sinistra
            LinearGradient(colors: event.colors, startPoint: .top, endPoint: .bottom)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct EventBanner: View { let data: EventBannerData
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: data.colors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 36, height: 36)
                Image(systemName: data.symbol).foregroundStyle(.white)
            }
            Text(data.text).font(.subheadline).foregroundStyle(.white)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Stat Rows & Gauges
private struct StatRow: View {
    let symbol: String
    let title: String
    let value: Double
    let cap: Double
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.white)
                    .font(.caption.bold())
                    .lineLimit(1)
                CapsuleGauge(progress: value / cap, color: color)
                    .frame(height: 10)
            }
            .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int(value)) su \(Int(cap))"))
        .font(.subheadline)
    }
}


private struct CapsuleGauge: View {
    let progress: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [color.opacity(0.9), .white.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, w * max(0, min(1, progress))))
                    .shadow(color: color.opacity(0.6), radius: 8)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}

private struct XPRow: View {
    let progress: Double
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .frame(width: 20)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text("Esperienza")
                    .foregroundStyle(.white)
                    .font(.caption.bold())
                    .lineLimit(1)
                XPBar(progress: progress)
                    .frame(height: 10)
            }
            .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Esperienza"))
        .accessibilityValue(Text("\(Int(progress * 100)) percento"))
        .font(.subheadline)
    }
}

private struct RingRow: View {
    let title: String
    let icon: String
    let value: Double
    let cap: Double
    let colors: [Color]
    let size: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                    .frame(width: size, height: size)
                let pct = max(0, min(1, value / max(1, cap)))
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
                Image(systemName: icon).font(.caption2).foregroundStyle(.white)
            }
            Text(title).foregroundStyle(.white).font(.subheadline)
            Spacer(minLength: 12)
            CapsuleGauge(progress: value / cap, color: colors.last ?? .white)
                .frame(height: 10)
                .layoutPriority(1)
            CapsuleLabel(text: "\(Int(value)) / \(Int(cap))")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int(value)) su \(Int(cap))"))
    }
}

private struct XPPerkCardSmall: View {
    let level: Int
    let progress: Double
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill").foregroundStyle(.white)
            Text("Livello \(level)").font(.subheadline).foregroundStyle(.white)
            XPBar(progress: progress)
                .frame(height: 8)
            CapsuleLabel(text: "cap +\(level*5) • decay -\(min(30, level*2))%")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct GameButton: View {
    let title: String
    let system: String
    let gradient: [Color]
    var isDisabled: Bool = false
    var hint: String? = nil
    var remainingText: (() -> String)? = nil
    var action: () -> Void
    var height: CGFloat = 60

    @State private var wiggle = false
    @State private var showHint = false
    @AppStorage("El-PavoReal.cooldownHints") private var cooldownHints: Bool = true

    // helper formattazione mm:ss  <— NUOVO
    private func mmss(_ seconds: TimeInterval) -> String {
        let s = Int(ceil(max(0, seconds)))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: system).font(.title3)
                    Text(title)
                        .font(.caption).bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: gradient.last?.opacity(0.55) ?? .black.opacity(0.35), radius: 10, x: 0, y: 6)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .modifier(PressEffect())
            .disabled(isDisabled)
            .rotationEffect(.degrees(wiggle ? 3 : 0))
            .animation(.spring(response: 0.18, dampingFraction: 0.35).repeatCount(wiggle ? 3 : 0, autoreverses: true), value: wiggle)
            .overlay(alignment: .bottomTrailing) {
                if isDisabled, let remainingText {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let txt = remainingText()
                        if !txt.isEmpty {
                            Text(txt)
                                .font(.caption2).bold().monospacedDigit()
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                    }
                }
            }
            
            if isDisabled && cooldownHints, let hint, showHint {
                HintBubble(text: hint)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, -8)
            }

            if isDisabled && cooldownHints {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
                    .onTapGesture {
                        haptic(.light)
                        wiggle = true
                        withAnimation(.easeInOut) { showHint = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation(.easeInOut) { showHint = false }
                            wiggle = false
                        }
                    }
            }
        }
        .opacity(isDisabled ? 0.55 : 1)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }
}

private struct HintBubble: View { let text: String
    var body: some View {
        Text(text)
            .font(.caption2).bold().monospacedDigit()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .foregroundStyle(.white)
            .shadow(radius: 6)
    }
}

private struct XPBar: View { let progress: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * progress)
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
    }
}

private struct StatRingTile: View {
    let title: String
    let icon: String
    let value: Double
    let cap: Double
    let gradient: [Color]
    let size: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 10)
                    .frame(width: size, height: size)
                let pct = max(0, min(1, value / max(1, cap)))
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
                    .shadow(color: gradient.last?.opacity(0.6) ?? .clear, radius: 6)
                VStack(spacing: 4) {
                    Image(systemName: icon).foregroundStyle(.white)
                    Text("\(Int(value)) / \(Int(cap))")
                        .font(.caption).monospacedDigit().foregroundStyle(.white)
                }
            }
            Text(title).font(.footnote).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(Int(value)) su \(Int(cap))"))
    }
}

private struct XPPerkCard: View {
    let level: Int
    let progress: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill").foregroundStyle(.white)
                Text("Livello \(level)").font(.subheadline).bold().foregroundStyle(.white)
                Spacer()
                CapsuleLabel(text: "Perk: cap +\(level * 5), decay -\(min(30, level*2))%")
            }
            XPBar(progress: progress)
                .frame(height: 10)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Tutorial (Onboarding 2.0)
private struct TutorialView: View {
    @State private var page = 0
    var onClose: () -> Void

    private let total = 6
    private let themes: [[Color]] = [
        [.pink, .purple],
        [.teal, .blue],
        [.indigo, .blue],
        [.orange, .red],
        [.green, .mint],
        [.pink, .orange]
    ]
    private var theme: [Color] { themes[max(0, min(page, themes.count-1))] }

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.first!.opacity(0.35), .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header: dots + skip
                HStack(spacing: 8) {
                    PageDots(count: total, current: page)
                    Spacer()
                    Button("Salta") { onClose() }
                        .font(.footnote.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                // Pages
                TabView(selection: $page) {
                    // 0 – Welcome
                    OnboardingPage(icon: "party.popper",
                                   title: "Benvenuto al Pavo Real",
                                   subtitle: "Questo è il Pavone, la mascotte del locale. Fagli vivere la serata: tieni alte le sue statistiche e divertiti!") {
                        VStack(spacing: 10) {
                            FeatureRow(icon: "party.popper", title: "Cura & serata", bullets: [
                                "Tieni alte Sete, Energia, Chill, Festa",
                                "Se scendono troppo, cala la Vita"
                            ])
                            FeatureRow(icon: "cart.fill", title: "Azioni & Bar", bullets: [
                                "Fai Ingresso, Shot e Spuntini per XP e P£",
                                "Spendi le P£: drink, Privé, Tavoli, gadget"
                            ])
                            FeatureRow(icon: "crown.fill", title: "Umore & livelli", bullets: [
                                "Umori positivi (Felice) danno bonus XP e P£",
                                "I livelli alzano cap e riducono i decadimenti"
                            ])
                        }
                        .allowsHitTesting(false)
                    }
                    .tag(0)

                    // 1 – Statistiche
                    OnboardingPage(icon: "chart.bar.fill",
                                   title: "Statistiche",
                                   subtitle: "Le stat del Pavone al Pavo‑Rèal: se scendono troppo, cala la Vita.") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatBarTile(title: "Sete",    symbol: "wineglass.fill",     progress: 0.85, colors: [.green, .mint])
                            StatBarTile(title: "Energia", symbol: "bolt.fill",          progress: 0.62, colors: [.pink, .purple])
                            StatBarTile(title: "Chill",   symbol: "sparkles",           progress: 0.74, colors: [.teal, .blue])
                            StatBarTile(title: "Festa",   symbol: "party.popper.fill",  progress: 0.70, colors: [.yellow, .orange])
                        }
                        .allowsHitTesting(false)
                    }
                    .tag(1)

                    // 2 – Azioni & cooldown
                    OnboardingPage(icon: "wand.and.stars",
                                   title: "Azioni & cooldown",
                                   subtitle: "Ogni azione ha tempi di ricarica. Tocca i pulsanti disattivati per un suggerimento.") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            GameButton(title: "Sete",      system: "wineglass.fill",  gradient: [.green, .mint],       isDisabled: true, hint: "Tra 0:45", remainingText: { "0:45" }) {}
                            GameButton(title: "Rilassati", system: "sparkles",        gradient: [.teal, .blue],        isDisabled: true, hint: "Tra 0:20", remainingText: { "0:20" }) {}
                            GameButton(title: "Shot",      system: "bolt.fill",       gradient: [.pink, .purple],      isDisabled: true, hint: "Max ogni 8m", remainingText: { "1:00" }) {}
                            GameButton(title: "Festa",  system: "party.popper.fill",        gradient: [.red, .orange],       isDisabled: true, hint: "Max ogni 6m", remainingText: { "1:00" }) {}
                        }
                        .allowsHitTesting(false)
                    }
                    .tag(2)

                    // 3 – Umore & perk
                    OnboardingPage(icon: "party.popper",
                                   title: "Umore & perk",
                                   subtitle: "Le emozioni cambiano UI e gameplay: bonus XP, P£ ed efficacia azioni.") {
                        VStack(spacing: 12) {
                            SectionCard(title: "Stato attuale") {
                                MoodRow(title: "Neutro",
                                        symbol: "circle.dotted.circle",
                                        colors: [.gray.opacity(0.8), .gray.opacity(0.6)],
                                        bullets: ["Ricompense std", "Nessun mod."])
                            }

                            SectionCard(title: "Stati principali") {
                                VStack(spacing: 10) {
                                    MoodRow(title: "Felice", symbol: "party.popper", colors: [.pink, .purple], bullets: ["+10% XP", "P£ più rapide (≈1/14s)"])
                                    MoodRow(title: "Stanchezza", symbol: "bolt.slash.fill", colors: [.purple, .indigo], bullets: ["Decay EN +20%", "Shot più efficaci"])
                                    MoodRow(title: "Rabbia", symbol: "flame.fill", colors: [.red, .orange], bullets: ["Shot/Drink +efficacia", "UI d’allerta"])
                                    MoodRow(title: "Noia", symbol: "hourglass", colors: [.gray, .blue.opacity(0.6)], bullets: ["Festa ↓ lenta", "Ingressi +10%"])
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .tag(3)

                    // 4 – Bar
                    OnboardingPage(icon: "cart.fill",
                                   title: "Bar",
                                   subtitle: "Spendi le P£ in drink, tavoli e boost.") {
                        VStack(spacing: 14) {
                            // In evidenza – carosello simile a FeaturedItemCard
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ShopGhostFeaturedCard(title: "Shot", subtitle: "+25 Energia", price: 22, symbol: "bolt.fill", colors: GradientTokens.coffee)
                                    ShopGhostFeaturedCard(title: "Tavolo nel Privé (20m)", subtitle: "Booster: decadimenti dimezzati", price: 120, symbol: "lock.open.fill", colors: [.green, .mint])
                                    ShopGhostFeaturedCard(title: "Occhiali Pavo-Real", subtitle: "+14 Festa", price: 16, symbol: "eyeglasses", colors: [.yellow, .orange])
                                }
                                .padding(.horizontal, 6)
                            }
                            .allowsHitTesting(false)

                            // Lista verticale – simile a ShopRow
                            VStack(spacing: 10) {
                                ShopGhostRow(title: "Acqua Fresca", subtitle: "+30 Sete", price: 12, symbol: "drop.fill", colors: [.cyan, .blue])
                                ShopGhostRow(title: "Bracciale Privé", subtitle: "+30 Festa", price: 38, symbol: "lock.open.fill", colors: [.green, .mint])
                                ShopGhostRow(title: "Negroni", subtitle: "+35 Energia", price: 30, symbol: "wineglass.fill", colors: [.red, .orange])
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .tag(4)

                    // 5 – Vita & Livelli
                    OnboardingPage(icon: "heart.fill",
                                   title: "Vita & livelli",
                                   subtitle: "La Vita cala se le statistiche sono basse. L'XP ti fa salire di livello: aumenta i cap e riduce i decadimenti.") {
                        VStack(spacing: 12) {
                            ExplainBlock(
                                icon: "heart.fill",
                                title: "Vita",
                                text: "Se le 4 statistiche scendono troppo, la Vita cala. Se arriva a zero, il tuo El-PavoReal muore. Puoi ripristinarla con cure e riposo.",
                                progress: 0.75,
                                colors: [.orange, .red]
                            )
                            ExplainBlock(
                                icon: "star.fill",
                                title: "Esperienza & livelli",
                                text: "Guadagni XP con le azioni e con umori positivi. Ogni livello aumenta i cap delle statistiche e riduce i decadimenti.",
                                progress: 0.45,
                                colors: [.pink, .purple]
                            )
                        }
                    }
                    .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Footer: back / progress / next
                HStack(spacing: 10) {
                    if page > 0 {
                        Button {
                            withAnimation { page = max(0, page - 1) }
                        } label: {
                            Label("Indietro", systemImage: "chevron.left")
                                .font(.footnote.bold())
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("\(page+1)/\(total)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button {
                        withAnimation {
                            if page < total - 1 { page += 1 } else { onClose() }
                        }
                    } label: {
                        Label(page < total - 1 ? "Avanti" : "Inizia",
                              systemImage: page < total - 1 ? "chevron.right" : "play.fill")
                            .font(.footnote.bold())
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinearGradient(colors: [.white, .white.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom)
            }
        }
        .animation(.easeInOut, value: page)
    }
}

// Page container
private struct OnboardingPage<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 12) {
            ZstackIcon(symbol: icon)
                .padding(.top, 16)
                .padding(.bottom, 2)
            VStack(spacing: 6) {
                Text(title).font(.title.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)

            VStack(spacing: 10) { content }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 24)
    }
}

// Dots
private struct PageDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? .white : .white.opacity(0.25))
                    .frame(width: i == current ? 22 : 8, height: 6)
            }
        }
    }
}

// Icon ring (rinominato e ripulito)
private struct ZstackIcon: View { let symbol: String
    @State private var rotate = false
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: 86, height: 86)
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.9)
                        .stroke(AngularGradient(gradient: Gradient(colors: [.pink, .purple, .blue, .mint, .yellow, .pink]), center: .center), lineWidth: 6)
                        .rotationEffect(.degrees(rotate ? 360 : 0))
                        .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: rotate)
                )
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.white)
        }
        .onAppear { rotate = true }
    }
}

// Piccola lista puntata
private struct BulletList: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { t in
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").imageScale(.small).foregroundStyle(.white.opacity(0.9))
                    Text(t).font(.footnote).foregroundStyle(.white.opacity(0.95))
                }
            }
        }
    }
}

// Small feature tile for the welcome grid
private struct FeatureCard: View {
    let icon: String
    let title: String
    let bullets: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(.white)
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Spacer()
            }
            ForEach(bullets, id: \.self) { t in
                Text(t)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let bullets: [String]
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 32, height: 32)
                Image(systemName: icon).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { t in
                        Text(t)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }
}

// Compact tip card (highlight)
private struct TipCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.max.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.caption.bold())
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }
}

// Perk row sintetica
private struct PerkRow: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let bullets: [String]
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: symbol).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                ForEach(bullets, id: \.self) { b in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.white.opacity(0.95))
                        Text(b).font(.caption2).foregroundStyle(.white.opacity(0.95))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Mood UI (tutorial)
private struct MoodBannerCard: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let description: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct PerkCapsule: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).bold()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .foregroundStyle(.white)
    }
}

private struct MoodPreviewCard: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let bullets: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: symbol).foregroundStyle(.white)
                }
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets, id: \.self) { b in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.white.opacity(0.95))
                        Text(b).font(.caption).foregroundStyle(.white.opacity(0.95))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Section container (tutorial)
private struct SectionCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline).foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }
}

private struct MoodRow: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let bullets: [String]
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: symbol).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(bullets, id: \.self) { b in
                        Text(b)
                            .font(.caption).bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Event notifications (compact)
private struct EventToastCompact: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 26, height: 26)
                Image(systemName: icon).imageScale(.small).foregroundStyle(.white)
            }
            Text(title).font(.footnote.bold()).foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

private struct EventRowCompact: View {
    let icon: String
    let title: String
    let tags: [String]
    let time: String
    enum Tone { case positive, negative, system }
    var tone: Tone? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icona
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 28, height: 28)
                Image(systemName: icon).imageScale(.medium).foregroundStyle(.white)
            }

            // Testi
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    Spacer()
                    Text(time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }

                if !tags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(tags, id: \.self) { t in
                            EventChip(text: t)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            ZStack(alignment: .leading) {
                // left accent stripe by tone
                if let tone {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    Rectangle()
                        .fill(
                            LinearGradient(colors: {
                                switch tone {
                                case .positive: [.green, .mint]
                                case .negative: [.red, .orange]
                                case .system:   [.gray.opacity(0.6), .gray.opacity(0.3)]
                                }
                            }(), startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
        )
    }
}

// MARK: - Event Overlay (full-screen, queued)
private enum EventTone { case positive, negative, system }

private struct EventOverlayItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tone: EventTone
    let lines: [String]
    let autoDismiss: Bool
    let duration: TimeInterval
    
    init(title: String, icon: String, tone: EventTone, lines: [String] = [], autoDismiss: Bool = false, duration: TimeInterval = 3.0) {
        self.title = title
        self.icon = icon
        self.tone = tone
        self.lines = lines
        self.autoDismiss = autoDismiss
        self.duration = duration
    }
}

// MARK: - Toast Notification System
struct ToastItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let colors: [Color]
    let duration: TimeInterval
    
    init(title: String, icon: String, colors: [Color], duration: TimeInterval = 2.5) {
        self.title = title
        self.icon = icon
        self.colors = colors
        self.duration = duration
    }
}

private struct EventOverlayView: View {
    let item: EventOverlayItem
    var onDismiss: () -> Void

    private var colors: [Color] {
        switch item.tone {
        case .positive: return [.green, .mint]
        case .negative: return [.red, .orange]
        case .system:   return [.gray.opacity(0.7), .gray.opacity(0.4)]
        }
    }

    var body: some View {
        ZStack {
            // Dim + blur
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.15).blur(radius: 12).ignoresSafeArea())

            // Card
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 68, height: 68)
                    Image(systemName: item.icon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(item.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal)

                if !item.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(item.lines, id: \.self) { l in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill").font(.caption2)
                                Text(l).font(.footnote)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        }
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal)
                }

                if !item.autoDismiss {
                    Button(action: onDismiss) {
                        Text("Ok, ricevuto")
                            .font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 16)
            .padding(24)
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                let gen = UINotificationFeedbackGenerator(); gen.prepare()
                switch item.tone {
                case .positive: gen.notificationOccurred(.success)
                case .negative: gen.notificationOccurred(.warning)
                case .system:   gen.notificationOccurred(.warning)
                }
                
                // Auto-dismiss per notifiche non invasive
                if item.autoDismiss {
                    DispatchQueue.main.asyncAfter(deadline: .now() + item.duration) {
                        onDismiss()
                    }
                }
            }
        }
        .allowsHitTesting(true) // blocca il tocco sotto
    }
}

// MARK: - Toast View (Non-invasive notifications)
private struct ToastView: View {
    let item: ToastItem
    var onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            // Text
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isVisible = true
            }
            
            // Auto-dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + item.duration) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible = false
                }
                
                // Rimuovi dalla coda dopo l'animazione
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }
}

private struct EventSectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}


private struct EventSearchBar: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.9))
            TextField("Cerca eventi", text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct EventChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .foregroundStyle(.white)
    }
}

private struct FilterChip: View {
    let text: String
    var isSelected: Bool = false
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                isSelected
                ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(Color.white.opacity(0.08))
            , in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .foregroundStyle(.white)
    }
}

// Compact empty-state card for Event list
private struct EmptyEventCard: View {
    var title: String = "Nessun evento recente"
    var subtitle: String = "Appena accade qualcosa, lo vedrai qui."
    var actionTitle: String? = nil
    var actionIcon: String = "sparkles"
    var onAction: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.white)
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

// (Opzionale) nuovo EventLog compatto, se vuoi sostituire quello attuale
private struct EventLogPreview: View {
    @State var items: [(icon: String, title: String, tags: [String], time: String)] = [
        ("gamecontroller.fill", "Mini", ["gioco avviato"], "18:12"),
        ("snowflake", "Un bel Negroni al Bar", ["+16 Sete", "+4 Festa"], "18:11")
    ]
    @State private var filter: Int = 0 // 0 tutti, 1 +, 2 -, 3 sistema
    @State private var query: String = ""
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.purple.opacity(0.35), .indigo.opacity(0.35)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                Color.black.opacity(0.45).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Filtri
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button { filter = 0 } label: { FilterChip(text: "Tutti", isSelected: filter == 0) }.buttonStyle(.plain)
                                Button { filter = 1 } label: { FilterChip(text: "+ Positivi", isSelected: filter == 1) }.buttonStyle(.plain)
                                Button { filter = 2 } label: { FilterChip(text: "– Negativi", isSelected: filter == 2) }.buttonStyle(.plain)
                                Button { filter = 3 } label: { FilterChip(text: "Sistema", isSelected: filter == 3) }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }

                        // Search
                        EventSearchBar(text: $query)

                        // Intestazione (oggi)
                        EventSectionHeader(title: "Oggi")

                        // Lista eventi
                        LazyVStack(alignment: .leading, spacing: 10) {
                            let filtered = items.filter { it in
                                // filtro testo
                                (query.isEmpty || it.title.localizedCaseInsensitiveContains(query) || it.tags.joined(separator: " ").localizedCaseInsensitiveContains(query))
                                // filtro tono
                                && {
                                    switch filter {
                                    case 1: return it.tags.contains { $0.hasPrefix("+") }
                                    case 2: return it.tags.contains { $0.hasPrefix("-") || $0.contains("−") }
                                    case 3: return !it.tags.contains { $0.hasPrefix("+") } && !it.tags.contains { $0.hasPrefix("-") || $0.contains("−") }
                                    default: return true
                                    }
                                }()
                            }

                            ForEach(filtered, id: \.title) { it in
                                let tone: EventRowCompact.Tone = {
                                    if it.tags.contains(where: { $0.hasPrefix("+") }) { return .positive }
                                    if it.tags.contains(where: { $0.hasPrefix("-") || $0.contains("−") }) { return .negative }
                                    return .system
                                }()
                                EventRowCompact(icon: it.icon, title: it.title, tags: it.tags, time: it.time, tone: tone)
                            }

                            // Stato vuoto
                            if filtered.isEmpty {
                                EmptyEventCard(
                                    title: "Nessun evento recente",
                                    subtitle: "Appena accade qualcosa, lo vedrai qui."
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Eventi casuali")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Explainer blocks (tutorial)
private struct ExplainBlock: View {
    let icon: String
    let title: String
    let text: String
    let progress: Double
    let colors: [Color]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 32, height: 32)
                    Image(systemName: icon).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            let barColors: [Color] = {
                switch title {
                case "Sete":    return [.green, .mint]
                case "Energia": return [.pink, .purple]
                case "Chill":   return [.teal, .blue]
                case "Festa":   return [.yellow, .orange]
                default:         return colors
                }
            }()
            DemoBar(progress: progress, colors: barColors)
                .frame(height: 12)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct DemoBar: View {
    let progress: Double
    let colors: [Color]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pct = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * pct)
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
    }
}

private struct StatBarTile: View {
    let title: String
    let symbol: String
    let progress: Double
    let colors: [Color]
    /// Numero opzionale da mostrare a destra del titolo (solo Home).
    /// Lascia `nil` per non mostrare nulla (es. nel tutorial o altrove).
    var value: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.white)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                let shown = value ?? Int(round(progress * 100))
                Text("\(shown)")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            DemoBar(progress: progress, colors: colors)
                .frame(height: 12)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }
}

// Mini card per anteprima shop
private struct ShopPreviewCard: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Spacer()
            }
            .foregroundStyle(.white)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
        .padding()
        .frame(width: 180, height: 100)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }
}

// Ghost cards per il tutorial (aspetto uguale allo shop, ma non interattive)
private struct ShopGhostFeaturedCard: View {
    let title: String
    let subtitle: String
    let price: Int
    let symbol: String
    let colors: [Color]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 36, height: 36)
                    Image(systemName: symbol).foregroundStyle(.white)
                }
                Text(title)
                    .font(.subheadline).bold().foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
            Spacer(minLength: 0)
            CoinBadge(value: price)
        }
        .padding(12)
        .frame(width: 206, height: 124, alignment: .leading)
        .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
    }
}

private struct ShopGhostRow: View {
    let title: String
    let subtitle: String
    let price: Int
    let symbol: String
    let colors: [Color]
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CoinBadge(value: price)
        }
        .padding(12)
        .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
    }
}

// Shared gradient tokens
private enum GradientTokens {
    static let satiety: [Color] = [.green, .mint]      // Sete
    static let coffee:  [Color] = [.pink, .purple]     // Energia (Shot)
    static let meet:    [Color] = [.yellow, .orange]   // Ingressi / SIGLA
    static let hygiene: [Color] = [.teal, .blue]       // Chill
    static let life:    [Color] = [.red, .orange]      // Vita
    static let PavoLire:   Color   = .blue                 // Valuta PavoLire (azzurro)  ← AGGIUNTA
}

// MARK: - Shop
private struct ShopView: View {
    let items: [ShopItem]
    @Binding var PavoLire: Int
    var onBuy: (ShopItem) -> Void
    @State private var showPavoLireInfo: Bool = false
    @EnvironmentObject var vm: PetViewModel
    
    // Stato UI
    @State private var selected: ShopCategory = .all
    @State private var purchasedToast: String? = nil
    @State private var query: String = ""
    @State private var showAffordableOnly: Bool = true
    @State private var sort: SortOption = .recommended
    @State private var noFundsToast: Bool = false
    @State private var balancePulse: Bool = false
    @State private var wiggleBalance: Bool = false
    @State private var costFlash: Int? = nil
    @State private var inspecting: ShopItem? = nil
    // Style tokens (flat, no blur)
    static let cardFill   = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.16)
    
    enum ShopCategory: String, CaseIterable, Identifiable {
        case all = "Tutti", boost = "Boost", cura = "Cura", snack = "Snack & Drink", mood = "Mood", speciali = "Speciali"
        var id: String { rawValue }
    }
    enum SortOption: String, CaseIterable { case recommended = "Consigliati", priceLow = "Prezzo ↑", priceHigh = "Prezzo ↓" }
    
    private var featuredItems: [ShopItem] { Array(items.sorted { $0.cost > $1.cost }.prefix(5)) }
    
    private func purpose(for item: ShopItem) -> String {
        switch item.effect {
        case .heal(let stat, let amount):
            switch stat {
            case .satiety: return "+\(Int(amount)) Sete"
            case .energy: return "+\(Int(amount)) Energia"
            case .hygiene: return "+\(Int(amount)) Chill"
            case .happiness: return "+\(Int(amount)) Festa"
            case .life: return "+\(Int(amount)) Vita"
            }
        case .booster(let seconds):
            return "Booster \(Int(seconds/60)) min (decadimenti dimezzati)"
        }
    }
    
    private func colors(for item: ShopItem) -> [Color] {
        // Override per nome (titolo) — tutto minuscolo
        let t = item.title.lowercased()

        // Speciali & anthem
        if t.contains("sigla") { return [.yellow, .orange] }
        if t.contains("console") { return [.indigo, .blue] }

        // Accessi & tavoli
        if t.contains("ingresso") || t.contains("ticket") { return [.yellow, .orange] }
        if t.contains("privé") || t.contains("prive") { return [.green, .mint] }
        if t.contains("tavolo") || t.contains("pista") { return [.yellow, .orange] }

        // Drink & shot - TUTTI energia = rosa/viola
        if t.contains("shot") { return [.pink, .purple] }
        if t.contains("negroni") || t.contains("gin tonic") || t.contains("drink") { return [.pink, .purple] }

        // Recovery & chill
        if t.contains("chill") || t.contains("reset") || t.contains("guardaroba") { return [.teal, .blue] }
        if t.contains("acqua") { return [.cyan, .blue] }

        // Festa / esperienza - happiness = giallo/arancio
        if t.contains("festa") || t.contains("fabio") || t.contains("ballare") { return [.yellow, .orange] }

        // Cibo/spuntini → Sete
        if t.contains("spuntino") || t.contains("bevuta") || t.contains("sete") { return GradientTokens.satiety }

        // Override per semantica (stat)
        switch item.effect {
        case .heal(let stat, _):
            switch stat {
            case .satiety:   return GradientTokens.satiety
            case .energy:    return GradientTokens.coffee     // ora fucsia/viola per Shot
            case .happiness: return GradientTokens.meet       // ora giallo/arancio per Ingressi/Festa
            case .hygiene:   return GradientTokens.hygiene    // teal/blu
            case .life:      return GradientTokens.life
            }
        case .booster:
            return [.purple, .pink]
        }
    }



    
    private var byCategory: [ShopCategory: [ShopItem]] {
        var dict: [ShopCategory: [ShopItem]] = [:]

        // Categorie principali per semantica
        dict[.boost] = items.filter {
            if case .booster = $0.effect { return true } else { return false }
        }
        dict[.cura] = items.filter {
            if case .heal(let stat, _) = $0.effect, stat == .life || stat == .hygiene { return true } else { return false }
        }
        dict[.snack] = items.filter {
            if case .heal(let stat, _) = $0.effect, stat == .satiety || stat == .energy { return true } else { return false }
        }

        // Categorie: Mood per semantica (niente keyword vecchie)
        dict[.mood] = items.filter {
            if case .heal(let stat, _) = $0.effect, stat == .happiness { return true }
            return false
        }

        // Speciali = tutto il resto non già preso
        let usedIds = Set(((dict[.boost] ?? []) + (dict[.cura] ?? []) + (dict[.snack] ?? []) + (dict[.mood] ?? [])).map { $0.id })
        dict[.speciali] = items.filter { !usedIds.contains($0.id) }

        return dict
    }
    
    private var filtered: [ShopItem] {
        var list: [ShopItem]
        if selected == .all {
            list = items
        } else {
            list = byCategory[selected] ?? []
        }
        if !query.isEmpty { list = list.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .recommended: break
        case .priceLow:  list.sort { vm.price(for: $0) < vm.price(for: $1) }
        case .priceHigh: list.sort { vm.price(for: $0) > vm.price(for: $1) }
        }
        if showAffordableOnly {
            list = list.filter { vm.price(for: $0) <= PavoLire }
        }
        return list
    }
    
    private func explainLines(for item: ShopItem) -> [String] {
        switch item.effect {
        case .heal(let stat, _):
            switch stat {
            case .life:
                return [
                    "Ripristina Vita (i cuori sotto la foto).",
                    "Usalo quando vedi il badge “Medikit/Check-up”.",
                    "Non aumenta Sete/Energia/Chill/Festa: serve a evitare la morte."
                ]
            case .satiety:
                return [
                    "Alza la Sete: riduce il rischio Sete e quindi il calo di Vita.",
                    "Consigliato quando compare l’avviso di Sete."
                ]
            case .energy:
                return [
                    "Alza l’Energia: contrasta la stanchezza e rende più efficaci alcune azioni.",
                    "Utile prima di scendere in pista."
                ]
            case .hygiene:
                return [
                    "Alza il Chill: migliora l’umore e rallenta il decadimento della Vita."
                ]
            case .happiness:
                return [
                    "Alza la Festa: facilita lo stato Felice (bonus XP e PavoLire)."
                ]
            }
        case .booster(let seconds):
            return [
                "Booster per \(Int(seconds/60)) minuti.",
                "Dimezza i decadimenti delle statistiche per tutta la durata."
            ]
        }
    }
    
    private func attemptBuy(_ item: ShopItem) {
        let effectivePrice = vm.price(for: item)
        if PavoLire >= effectivePrice {
            noFundsToast = false
            haptic(.soft)
            onBuy(item)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                balancePulse = true
                purchasedToast = "Acquistato: \(item.title)"
            }
            costFlash = effectivePrice
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { balancePulse = false }
                costFlash = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut) { purchasedToast = nil }
            }
        } else {
            purchasedToast = nil
            haptic(.rigid)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) { wiggleBalance.toggle() }
            noFundsToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) { wiggleBalance.toggle() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut) { noFundsToast = false }
            }
        }
    }
    
    // MARK: - ShopView sections (split to help the type-checker)
    @ViewBuilder
    private func backgroundLayer() -> some View {
        Color.black.opacity(0.45).ignoresSafeArea()
    }

    @ViewBuilder
    private func headerSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wineglass.fill").foregroundStyle(.white)
                Text("La Cambusa").font(.title3.bold()).foregroundStyle(.white)
            }
            Text("Il bar del PavoReal: P£ in cambio di bevute, shot e boost. I consigliati sono sopra, poi filtra per categoria.")
                .font(.footnote).foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").imageScale(.small)
                    Text("Tocca l'icona P£ in alto per capire come funzionano.")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func featuredSection() -> some View {
        if !featuredItems.isEmpty {
            Text("In evidenza")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featuredItems) { item in
                        FeaturedItemCard(
                            item: item,
                            subtitle: purpose(for: item),
                            onTap: {
                                attemptBuy(item)
                                haptic(.medium)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { purchasedToast = "Acquistato: \(item.title)" }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(.easeOut) { purchasedToast = nil } }
                            },
                            fillWidth: false,
                            colorsOverride: colors(for: item)
                        )
                        .frame(width: 220)
                        .opacity(PavoLire < vm.price(for: item) ? 0.75 : 1)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func categoryAndSortSection() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShopCategory.allCases) { cat in
                    CategoryChip(title: displayName(for: cat), isSelected: selected == cat) { selected = cat }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
        }
        FilterBar(sort: $sort, affordableOnly: $showAffordableOnly)
            .padding(.horizontal, 16)
    }

    private func displayName(for cat: ShopCategory) -> String {
        switch cat {
        case .snack: return "Bevute"
        case .boost: return "Shot"
        case .cura: return "Cure"
        case .mood: return "Umore"
        case .speciali: return "Speciali"
        default: return cat.rawValue
        }
    }

    @ViewBuilder
    private func listSection() -> some View {
        VStack(spacing: 10) {
            ForEach(filtered) { item in
                ShopRow(
                    item: item,
                    purpose: purpose(for: item),
                    canAfford: PavoLire >= vm.price(for: item),
                    onInfo: { inspecting = item },
                    onBuy: { attemptBuy(item) },
                    colorsOverride: colors(for: item)
                )
                .opacity(PavoLire < vm.price(for: item) ? 0.6 : 1)
            }

            if showAffordableOnly && filtered.isEmpty {
                NoPurchasesAdviceCard(affordableOnly: $showAffordableOnly, onShowInfo: { showPavoLireInfo = true })
                    .padding(.top, 6)
            } else if filtered.isEmpty {
                EmptyCategoryCard()
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func toastLayer() -> some View {
        if let toast = purchasedToast {
            PurchaseToast(text: toast)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
        } else if noFundsToast {
            NoFundsToast(text: "P£ insufficienti")
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                backgroundLayer()

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headerSection()
                        featuredSection()
                        categoryAndSortSection()
                        listSection()
                    }
                }

                // Toasts
                toastLayer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Negozio")
            .toolbarColorScheme(.dark)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Cerca al bar"))
            .onChange(of: PavoLire) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { balancePulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { balancePulse = false }
                }
            }
            .sheet(isPresented: $showPavoLireInfo) {
                PavoLireInfoView()
                    .environmentObject(vm)
            }
            .sheet(item: $inspecting) { item in
                ItemInfoSheet(item: item,
                              purpose: purpose(for: item),
                              lines: explainLines(for: item))
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                vm.isForeground = true
            }
            .onChange(of: scenePhase) { _, newPhase in
                vm.isForeground = (newPhase == .active)
            }
        }
    }
    
    private struct ShopTile: View {
        let item: ShopItem
        let purpose: String
        var onBuy: () -> Void
        @State private var appear = false
        @EnvironmentObject var vm: PetViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 40, height: 40)
                        Image(systemName: item.symbol).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline).bold().foregroundStyle(.white)
                        Text(purpose).font(.caption).foregroundStyle(.white.opacity(0.9))
                    }
                }
                HStack {
                    CoinBadge(value: vm.price(for: item))
                    Spacer()
                    Button("Compra", action: onBuy)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { appear = true } }
        }
    }
    
struct ShopRow: View {
        let item: ShopItem
        let purpose: String
        let canAfford: Bool
        var onInfo: (() -> Void)? = nil
        var onBuy: () -> Void
        var colorsOverride: [Color]? = nil
    @EnvironmentObject var vm: PetViewModel
        @State private var appear = false
        
    private var displayTitle: String {
        let t = item.title
        if let open = t.firstIndex(of: "("), let close = t.lastIndex(of: ")"), open < close {
            return String(t[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }
    
        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                // Icona
                ZStack {
                    Circle()
                    .fill(LinearGradient(colors: colorsOverride ?? item.colors,
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                    Image(systemName: item.symbol).foregroundStyle(.white)
                }
                
                // Testi (titolo + purpose) — robusti a titoli lunghi
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(displayTitle)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(2)                 // fino a 2 righe
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.75)     // scala se serve
                            .layoutPriority(2)
                        
                        if let onInfo {
                            Button(action: onInfo) {
                                Image(systemName: "info.circle.fill")
                                    .imageScale(.small)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Info su \(item.title)")
                        }
                    }
                    
                    Text(purpose)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Prezzo + CTA
                HStack(spacing: 8) {
                    CoinBadge(value: vm.price(for: item))
                    Button(action: onBuy) {
                        Text("Compra")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .fixedSize()                              // impedisce l'andata a capo
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white, in: Capsule())        // capsula bianca
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)                              // niente stile di sistema (evita squeeze)
                    .disabled(!canAfford)
                    .opacity(canAfford ? 1 : 0.65)
                }
            }
            .padding(12)
            .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
            .onAppear { withAnimation(.easeOut(duration: 0.3)) { appear = true } }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(item.title), costo \(item.cost) P£"))
        }
    }
    
    private struct PurchaseToast: View { let text: String
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.white)
                Text(text).bold().foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(ShopView.cardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(ShopView.cardStroke, lineWidth: 1))
        }
    }
    
    private struct NoFundsToast: View { let text: String
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                Text(text).bold().foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
    }
    
    private struct NoPurchasesAdviceCard: View {
        @Binding var affordableOnly: Bool
        var onShowInfo: () -> Void
        @EnvironmentObject var vm: PetViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.green, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 18, height: 18)
                        Text("P£")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                    Text("Nessun prodotto acquistabile").font(.headline).foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                Text("Ti mancano P£. Ecco alcune cose veloci che puoi fare:")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                // Riga 1: Mostra tutti + Info
                HStack(spacing: 8) {
                    Button { affordableOnly = false } label: {
                        Label("Mostra tutti", systemImage: "line.3.horizontal.decrease")
                            .font(.subheadline)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button(action: onShowInfo) {
                        Label("Cosa sono le PavoLire?", systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                // Riga 2: Azione ingressi (compatta)
                if vm.canMeetNow {
                    Button {
                        vm.orientaSuMeet()
                        haptic(.soft)
                    } label: {
                        Label("+2 Ingressi", systemImage: "video.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Label("Ingressi in cooldown", systemImage: "video.slash.fill")
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
        }
    }
    
    private struct EmptyCategoryCard: View {
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white)
                Text("Nessun prodotto in questa categoria").foregroundStyle(.white)
            }
            .padding(12)
            .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
        }
    }
    
    private struct PavoLireInfoSheet: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var vm: PetViewModel
        
        var body: some View {
            NavigationStack {
                ZStack {
                    LinearGradient(colors: [.purple.opacity(0.35), .indigo.opacity(0.35)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.green, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 48, height: 48)
                                    Text("P£")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Le PavoLire (P£)").font(.title3.bold()).foregroundStyle(.white)
                                    Text("Moneta di gioco usata al Bar per bevute, shot e cure.")
                                        .font(.footnote).foregroundStyle(.white.opacity(0.9))
                                }
                            }
                            
                            InfoSection(title: "Cosa sono") {
                                InfoBulletRow(text: "Valuta soft: non si compra con denaro reale.")
                                InfoBulletRow(text: "Serve per acquistare bevute (Sete/Energia), cure (Vita/Chill) e shot (decadimenti dimezzati).")
                            }
                            
                            InfoSection(title: "Come si ottengono") {
                                InfoPill(icon: "sun.max.fill", text: "Felice: ~1 P£ ogni 15s")
                                InfoPill(icon: "circle", text: "Neutro: ~1 P£ ogni 20s")
                                InfoPill(icon: "heart.slash.fill", text: "Critico: ~1 P£ ogni 30s")
                                InfoBulletRow(text: "Azioni pagate: es. Drink +2 P£.")
                                InfoBulletRow(text: "Eventi positivi (feedback studente, iscrizione chiusa) possono dare PavoLire extra.")
                            }
                            
                            InfoSection(title: "Come aiutano") {
                                InfoBulletRow(text: "Bevute ripristinano Sete/Energia.")
                                InfoBulletRow(text: "Cure aumentano Vita/Chill.")
                                InfoBulletRow(text: "Shot riducono i decadimenti per alcuni minuti.")
                            }
                            
                            InfoSection(title: "Suggerimenti") {
                                InfoBulletRow(text: "Mantieni l’umore Felice per massimizzare i PavoLire passivi.")
                                InfoBulletRow(text: "Compra in evidenza quando sei a corto: hanno impatto forte.")
                                InfoBulletRow(text: "I cooldown delle azioni impediscono lo spam: usa il tempo con strategia.")
                            }
                        }
                        .padding(16)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Label("Chiudi", systemImage: "xmark.circle.fill") }
                    }
                }
                .navigationTitle("Info PavoLire")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    
    private struct InfoSection<Content: View>: View {
        let title: String
        @ViewBuilder var content: Content
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 8) { content }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }
        }
    }
    
    private struct InfoBulletRow: View {
        let text: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.white.opacity(0.95))
                Text(text).font(.footnote).foregroundStyle(.white.opacity(0.95))
            }
        }
    }
    
private struct InfoPill: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).imageScale(.small)
            Text(text)
                .font(.caption)
                .lineLimit(nil)                              // niente “...”
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .foregroundStyle(.white)
    }
}

private struct StatNumberChip: View {
    let icon: String
    let value: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(value)")
                .font(.caption2.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Valore: \(value)"))
    }
}

private struct StatsInlineGroup: View {
    @EnvironmentObject var vm: PetViewModel
    var body: some View {
        HStack(spacing: 6) {
            StatNumberChip(icon: "wineglass.fill",     value: Int(vm.satiety.rounded()))   // Sete
            StatNumberChip(icon: "bolt.fill",          value: Int(vm.energy.rounded()))    // Energia
            StatNumberChip(icon: "sparkles",           value: Int(vm.hygiene.rounded()))   // Chill
            StatNumberChip(icon: "party.popper.fill",  value: Int(vm.happiness.rounded())) // Festa
        }
    }
}
    
struct FeaturedItemCard: View {
    let item: ShopItem
    var subtitle: String
    var onTap: () -> Void
    var fillWidth: Bool = false
    var colorsOverride: [Color]? = nil
    @EnvironmentObject var vm: PetViewModel

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                        .fill(LinearGradient(colors: colorsOverride ?? item.colors,
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        Image(systemName: item.symbol).foregroundStyle(.white)
                    }
                    Text(item.title)
                        .font(.subheadline).bold().foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    CoinBadge(value: vm.price(for: item))
                }
            }
            .padding(16)
            .frame(width: fillWidth ? nil : 224, height: 144, alignment: .leading)
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
            .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
    
    private struct CategoryChip: View {
        let title: String
        var isSelected: Bool
        var action: () -> Void
        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption).bold()
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        (isSelected
                         ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                         : AnyShapeStyle(Color.white.opacity(0.08))
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    
    private struct FilterBar: View {
        @Binding var sort: ShopView.SortOption
        @Binding var affordableOnly: Bool
        var body: some View {
            HStack(spacing: 8) {
                // Toggle chip: Solo acquistabili
                Button(action: { affordableOnly.toggle() }) {
                    Label(affordableOnly ? "Solo acquistabili" : "Tutti i prodotti", systemImage: affordableOnly ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                // Sort menu (immutato)
                Menu {
                    Picker("Ordina", selection: $sort) {
                        ForEach(ShopView.SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
            }
        }
    }
    
    private struct ConfettiBurst: View {
        let fire: Int
        @State private var start: Date = .now
        private let duration: Double = 1.5

        var body: some View {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSince(start)
                    guard t < duration else { return }

                    let n = 80
                    let cx = size.width / 2
                    let cy = size.height / 3
                    let palette: [Color] = [.yellow, .orange, .pink, .green, .mint, .blue, .purple]

                    for i in 0..<n {
                        // pseudo-random deterministico da (fire, i)
                        let seed = Double((fire &* 97) &+ (i &* 139))
                        let r1 = abs(sin(seed * 12.9898))      // 0..1
                        let r2 = abs(sin((seed+1) * 78.233))   // 0..1
                        let r3 = abs(sin((seed+2) * 37.719))   // 0..1

                        let angle = r1 * (.pi * 2)
                        let speed = 90.0 + 160.0 * r2
                        let vx = cos(angle) * speed
                        let vy = sin(angle) * speed - 60.0
                        let g: Double = 220.0

                        let x = cx + vx * t
                        let y = cy + vy * t + 0.5 * g * t * t

                        let col = palette[Int(r3 * Double(palette.count)) % palette.count]
                            .opacity(max(0, 1 - t / duration))

                        var gctx = ctx
                        gctx.translateBy(x: x, y: y)
                        gctx.rotate(by: .radians(angle))
                        let rect = CGRect(x: -2 - r3, y: -6 - r2 * 3,
                                          width: 4 + r3 * 2, height: 12 + r2 * 6)
                        gctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(col))
                    }
                }
            }
            .onChange(of: fire) { _, _ in start = .now } // reset animazione
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 🎰 Daily Slot View
private enum SlotPrize {
    case coins(Int)
    case xp(Int)
    case booster(Int) // minuti
    case statBoost
    
    var description: String {
        switch self {
        case .coins(let amount): return "+\(amount) P£"
        case .xp(let amount): return "+\(amount) XP"
        case .booster(let min): return "Booster \(min)m"
        case .statBoost: return "+30 Energia/Sete"
        }
    }
    
    var icon: String {
        switch self {
        case .coins: return "sterlingsign.circle.fill"
        case .xp: return "star.fill"
        case .booster: return "bolt.heart.fill"
        case .statBoost: return "sparkles"
        }
    }
}

private enum SlotIcon: String, CaseIterable {
    case coin = "sterlingsign.circle.fill"
    case star = "star.fill"
    case heart = "heart.fill"
    case bolt = "bolt.heart.fill"
    case sparkles = "sparkles"
    case gift = "gift.fill"
    
    var prize: SlotPrize? {
        switch self {
        case .coin: return .coins(50)
        case .star: return .xp(30)
        case .heart: return .statBoost
        case .bolt: return .booster(15)
        case .sparkles: return .coins(100)
        case .gift: return .xp(50)
        }
    }
}

private struct DailySlotView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: PetViewModel
    var onSpin: (SlotPrize) -> Void
    
    @AppStorage("El-PavoReal.dailySlotTries") private var dailySlotTries: Int = 0
    @AppStorage("El-PavoReal.slotWonToday") private var slotWonToday: Bool = false
    
    @State private var reels: [SlotIcon] = [.coin, .star, .heart]
    @State private var isSpinning = false
    @State private var prize: SlotPrize?
    @State private var showQRCode = false
    @State private var reelOffsets: [CGFloat] = [0, 0, 0]
    
    private let icons = SlotIcon.allCases
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.4), .purple.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("🎰 Slot Machine")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    
                    Text("3 icone identiche = LA MAGLIETTA!")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                    
                    // La Slot Machine
                    VStack(spacing: 16) {
                        // I 3 Rulli
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { reelIndex in
                                SlotReel(
                                    icon: reels[reelIndex],
                                    offset: reelOffsets[reelIndex],
                                    isSpinning: isSpinning
                                )
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
                        
                        // Bottone Gira
                        if !isSpinning && !slotWonToday && dailySlotTries < 10 {
                            Button {
                                spin()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.title2)
                                    Text("TENTA LA FORTUNA!")
                                        .font(.headline.bold())
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32).padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Capsule()
                                )
                                .shadow(color: .orange.opacity(0.5), radius: 12, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Girando i rulli...")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    
                    // Risultato
                    if prize != nil {
                        VStack(spacing: 16) {
                            if reels[0] == reels[1] && reels[1] == reels[2] {
                                VStack(spacing: 12) {
                                    Text("🎉 JACKPOT! 🎉")
                                        .font(.title.bold())
                                        .foregroundStyle(.yellow)
                                    
                                    Text("🏆 HAI VINTO LA MAGLIETTA! 🏆")
                                        .font(.headline.bold())
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            
                            HStack(spacing: 10) {
                                Image(systemName: "tshirt.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                Text("Premio:")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Text("Maglietta El-PavoReal")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                            
                            if showQRCode {
                                QRCodeView()
                                    .padding(.top, 8)
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blue.opacity(0.5), lineWidth: 2))
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func spin() {
        guard !isSpinning else { return }
        isSpinning = true
        haptic(.medium)
        
        // OGNI GIRO = 1 TENTATIVO (lo decremento subito)
        dailySlotTries += 1
        
        // Reset rulli e animazione continua
        reels = [icons.randomElement()!, icons.randomElement()!, icons.randomElement()!]
        
        // Animazione continua dei rulli per 2 secondi
        let spinDuration = 2.0
        let updateInterval = 0.1
        
        var timeElapsed = 0.0
        let _ = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            timeElapsed += updateInterval
            
            // Aggiorna i rulli con icone casuali durante lo spin
            withAnimation(.easeInOut(duration: updateInterval)) {
                reels = [icons.randomElement()!, icons.randomElement()!, icons.randomElement()!]
            }
            
            if timeElapsed >= spinDuration {
                timer.invalidate()
                
                // Scegli risultato finale: 1% di vincita (1 su 100)
                let isWin = Double.random(in: 0...1) < vm.slotWinChance // 0.01 = 1%
                
                if isWin {
                    // Vittoria: scegli un'icona casuale e mettila su tutti e 3 i rulli
                    let winningIcon = icons.randomElement()!
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        reels = [winningIcon, winningIcon, winningIcon]
                    }
                    prize = winningIcon.prize
                    
                    // SEGNA LA VITTORIA: disattiva slot fino al prossimo giorno
                    slotWonToday = true
                    
                    haptic(.heavy) // Haptic forte per la vittoria
                    print("🎰 JACKPOT MAGLIETTA! \(winningIcon.rawValue)")
                    
                    // Mostra QR Code per ritirare maglietta
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showQRCode = true
                    }
                } else {
                    // Sconfitta: rulli diversi
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        reels = [
                            icons.randomElement()!,
                            icons.randomElement()!,
                            icons.randomElement()!
                        ]
                    }
                    prize = nil
                    
                    haptic(.light) // Haptic leggero per la sconfitta
                    print("🎰 Try again!")
                }
                
                isSpinning = false
                
                // Se vittoria, assegna premio ma NON chiudere (mostra QR)
                if isWin, let prize = prize {
                    onSpin(prize)
                    // NON chiudere automaticamente - mostra QR code
                }
            }
        }
    }
}

private struct QRCodeView: View {
    @State private var qrCodeImage: UIImage?
    
    var body: some View {
        VStack(spacing: 12) {
            // QR Code reale generato
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
                    .frame(width: 140, height: 140)
                
                if let qrCodeImage = qrCodeImage {
                    Image(uiImage: qrCodeImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                } else {
                    VStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Generando QR...")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black, lineWidth: 2))
            
            Text("Mostra questo QR alla cassa")
                .font(.caption.bold())
                .foregroundStyle(.white)
            
            Text("per ritirare la tua maglietta!")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .onAppear {
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        // Genera un ID unico per questa vittoria
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomID = Int.random(in: 1000...9999)
        let qrData = "ELPAVOREAL_MAGLIETTA_\(timestamp)_\(randomID)"
        
        // Genera QR Code usando Core Image
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(qrData.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return }
        
        // Scala l'immagine per renderla più nitida
        let scaleX = 200.0 / outputImage.extent.size.width
        let scaleY = 200.0 / outputImage.extent.size.height
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Converti in UIImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return }
        
        DispatchQueue.main.async {
            self.qrCodeImage = UIImage(cgImage: cgImage)
        }
    }
}

private struct SlotReel: View {
    let icon: SlotIcon
    let offset: CGFloat
    let isSpinning: Bool
    
    var body: some View {
        VStack {
            Image(systemName: icon.rawValue)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(iconColor)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .offset(y: offset)
                .animation(.easeInOut(duration: 0.3), value: offset)
        }
        .frame(width: 80, height: 80)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .scaleEffect(isSpinning ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSpinning)
    }
    
    private var iconColor: Color {
        switch icon {
        case .coin: return .yellow
        case .star: return .orange
        case .heart: return .pink
        case .bolt: return .blue
        case .sparkles: return .purple
        case .gift: return .green
        }
    }
}

// MARK: - 💰 PavoLire Info View
private struct PavoLireInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: PetViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.4), .cyan.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                Color.black.opacity(0.45).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: 80, height: 80)
                                Text("P£")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            
                            Text("PavoLire")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            
                            Text("La valuta del Pavoreal")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        
                        // Saldo attuale
                        VStack(spacing: 16) {
                            Text("Saldo Attuale")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .frame(width: 32, height: 32)
                                    Text("P£")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                
                                Text("\(vm.PavoLire) P£")
                                    .font(.title.bold())
                                    .foregroundStyle(.white)
                            }
                            .padding(20)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
                        }
                        
                        // Come guadagnare
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Come Guadagnare PavoLire")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            
                            VStack(spacing: 12) {
                                InfoRow(icon: "gamecontroller.fill", text: "Gioca con il tuo Pavo", detail: "+10-20 P£")
                                InfoRow(icon: "cup.and.saucer.fill", text: "Nutri e dai da bere", detail: "+5-15 P£")
                                InfoRow(icon: "moon.zzz.fill", text: "Fai dormire il Pavone", detail: "+8-12 P£")
                                InfoRow(icon: "sparkles", text: "Ruota della Fortuna", detail: "+30-60 P£")
                                InfoRow(icon: "clock.fill", text: "Progresso offline", detail: "Fino a 50 P£")
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        
                        // Come spendere
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Come Spendere PavoLire")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            
                            VStack(spacing: 12) {
                                InfoRow(icon: "cart.fill", text: "Shop - Item e Boost", detail: "50-200 P£")
                                InfoRow(icon: "heart.fill", text: "Resuscita il Pavone", detail: "100 P£")
                                InfoRow(icon: "star.fill", text: "Sblocca Achievement", detail: "Varie quantità")
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        
                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("PavoLire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String
    let detail: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            
            Spacer()
            
            Text(detail)
                .font(.caption.bold())
                .foregroundStyle(.cyan)
        }
    }
}

// MARK: - 🛠️ Settings Components
private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 24)
                
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                
                Spacer()
            }
            
            content
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let system: String
    @Binding var isOn: Bool
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .cyan))
        }
    }
}

private struct SettingsNavRow: View {
    let title: String
    let system: String
    let tint: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: system)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(12)
            .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        }
    }
    
struct DeathScreen: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var vm: PetViewModel
        var onRestart: () -> Void
        
        var body: some View {
            ZStack {
                LinearGradient(colors: [.black, .red.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "heart.slash.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                    Text("È morto.")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("Il Pavone non ce l’ha fatta. Per continuare devi ricominciare da zero.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal)
                    
                    Button {
                        // Hard reset: azzera il livello e tutto il resto
                        vm.resetAll()
                        onRestart() // Esegue la pulizia aggiuntiva, come chiudere la sheet
                    } label: {
                        Text("Ricomincia da zero")
                            .font(.headline)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .interactiveDismissDisabled(true) // non si può chiudere senza restart
        }
    }
    
struct SettingsView: View {
    @EnvironmentObject var vm: PetViewModel
    @StateObject private var settings = SettingsModel()

    // Persisted options
    @AppStorage("El-PavoReal.notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("El-PavoReal.eventChance")         private var eventChance: Double = 0.35
    @AppStorage("El-PavoReal.cooldownHints")       private var cooldownHints: Bool = true
    // @AppStorage("El-PavoReal.uiDensity")           private var uiDensity: Int = 1 // 0 compatto, 1 standard, 2 ampio

    @State private var showResetAlert = false
    @State private var showDefaultsAlert = false
    @State private var requestedNotif = false
    @State private var showTutorial = false
    @State private var showDebugTools = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.purple.opacity(0.35), .indigo.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                Color.black.opacity(0.45).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - Header
                    VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 60, height: 60)
                                    Image(systemName: "gearshape.2.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Impostazioni")
                                        .font(.title.bold())
                                        .foregroundStyle(.white)
                                    Text("Personalizza la tua esperienza")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                
                                Spacer()
                            }
                            .padding(20)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        }

                        // MARK: - Gameplay
                        SettingsSection(title: "Gameplay", icon: "gamecontroller.fill") {
                            VStack(spacing: 12) {
                                SettingsToggleRow(
                                    title: "Suggerimenti cooldown",
                                    system: "hourglass.circle.fill",
                                              isOn: $cooldownHints,
                                    subtitle: "Mostra tempi di attesa sui pulsanti"
                                )
                                
                                Divider()
                                    .background(.white.opacity(0.2))

                            HStack {
                                    Image(systemName: "sparkles")
                                        .font(.title3)
                                        .foregroundStyle(.yellow)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Eventi Casuali")
                                            .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                        Text("Massima frequenza attiva")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }

                        // MARK: - Preferenze Utente RIMOSSA
                        // Il genere viene rilevato automaticamente dalle impostazioni iOS del device

                        // MARK: - Notifiche
                        SettingsSection(title: "Notifiche", icon: "bell.badge.fill") {
                            VStack(spacing: 12) {
                                SettingsToggleRow(
                                    title: "Notifiche push",
                                    system: "bell.fill",
                                    isOn: $notificationsEnabled,
                                    subtitle: "Ricevi promemoria per prenderti cura del Pavone"
                                )
                            }
                        }

                        // MARK: - Strumenti
                        SettingsSection(title: "Strumenti", icon: "wrench.and.screwdriver.fill") {
                            VStack(spacing: 8) {
                                SettingsNavRow(
                                    title: "Tutorial",
                                    system: "book.pages.fill",
                                    tint: .mint
                                ) {
                                    showTutorial = true
                                }
                                
                                Divider()
                                    .background(.white.opacity(0.2))
                                
                                // MARK: - Debug Tools (collapsable)
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        showDebugTools.toggle()
                                    }
                                    haptic(.soft)
                                } label: {
                                    HStack {
                                        Image(systemName: "ladybug.fill")
                                            .font(.title3)
                                            .foregroundStyle(.orange)
                                            .frame(width: 24)
                                        
                                        Text("Debug Tools")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.white)
                                        
                                        Spacer()
                                        
                                        Image(systemName: showDebugTools ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    .padding(12)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                
                                if showDebugTools {
                                    VStack(spacing: 12) {
                                        // DEBUG: Slider probabilità slot
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: "percent")
                                                    .font(.title3)
                                                    .foregroundStyle(.purple)
                                                    .frame(width: 24)
                                                
                                                Text("Probabilità Vittoria Slot")
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                                
                                                Spacer()
                                                
                                                Text("\(Int(vm.slotWinChance * 100))%")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.purple)
                                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                                    .background(.ultraThinMaterial, in: Capsule())
                                            }
                                            
                                            Slider(value: $vm.slotWinChance, in: 0.01...0.5, step: 0.01)
                                                .tint(.purple)
                                            
                                            Text("1% = normale, 50% = test facile")
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.7))
                                        }
                                        .padding(12)
                                        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                        
                                        SettingsNavRow(
                                            title: "Reset Slot",
                                            system: "arrow.clockwise.circle.fill",
                                            tint: .purple
                                        ) {
                                            UserDefaults.standard.set("", forKey: "El-PavoReal.lastDailySlotDate")
                                            UserDefaults.standard.set(0, forKey: "El-PavoReal.dailySlotTries")
                                            UserDefaults.standard.set(false, forKey: "El-PavoReal.slotWonToday")
                                            vm.slotWinChance = 0.01 // Reset a 1%
                                            haptic(.soft)
                                        }
                                        
                                        // DEBUG: Test mood sprites
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: "theatermasks.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(.pink)
                                                    .frame(width: 24)
                                                
                                                Text("Test Mood Sprites")
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                            }
                                            .padding(.bottom, 4)
                                            
                                            VStack(spacing: 8) {
                                                Button {
                                                    vm.happiness = 75
                                                    vm.satiety = 75
                                                    vm.energy = 75
                                                    vm.hygiene = 75
                                                    vm.life = 75
                                                    haptic(.soft)
                                                } label: {
                                                    HStack {
                                                        Text("😊 Felice")
                                                        Spacer()
                                                        Text("pavone_felice").font(.caption2).foregroundStyle(.gray)
                                                    }
                                                    .padding(12)
                                                    .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button {
                                                    vm.energy = 25
                                                    haptic(.soft)
                                                } label: {
                                                    HStack {
                                                        Text("😴 Stanchezza")
                                                        Spacer()
                                                        Text("pavone_assonnato").font(.caption2).foregroundStyle(.gray)
                                                    }
                                                    .padding(12)
                                                    .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button {
                                                    vm.happiness = 25
                                                    vm.satiety = 25
                                                    haptic(.soft)
                                                } label: {
                                                    HStack {
                                                        Text("😠 Rabbia")
                                                        Spacer()
                                                        Text("pavone_arrabbiato").font(.caption2).foregroundStyle(.gray)
                                                    }
                                                    .padding(12)
                                                    .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button {
                                                    vm.happiness = 35
                                                    vm.energy = 55
                                                    vm.satiety = 55
                                                    haptic(.soft)
                                                } label: {
                                                    HStack {
                                                        Text("😑 Noia")
                                                        Spacer()
                                                        Text("pavone_noia").font(.caption2).foregroundStyle(.gray)
                                                    }
                                                    .padding(12)
                                                    .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button {
                                                    vm.life = 10
                                                    vm.satiety = 10
                                                    haptic(.soft)
                                                } label: {
                                                    HStack {
                                                        Text("😔 Critico/Triste")
                                                        Spacer()
                                                        Text("pavone_triste").font(.caption2).foregroundStyle(.gray)
                                                    }
                                                    .padding(12)
                                                    .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button {
                                                    vm.happiness = 50
                                                    vm.satiety = 50
                                                    vm.energy = 50
                                                    vm.hygiene = 50
                                                    vm.life = 50
                                                    haptic(.soft)
                                                } label: {
                                                    HStack {
                                                        Text("😐 Neutro")
                                                        Spacer()
                                                        Text("pavone_neutro").font(.caption2).foregroundStyle(.gray)
                                                    }
                                                    .padding(12)
                                                    .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(12)
                                        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                        
                                        SettingsNavRow(
                                            title: "Ripristina Default",
                                            system: "arrow.counterclockwise.circle.fill",
                                            tint: .orange
                                        ) {
                                            showDefaultsAlert = true
                                        }
                                        .alert("Ripristinare i valori di default?", isPresented: $showDefaultsAlert) {
                                            Button("Annulla", role: .cancel) {}
                                            Button("Ripristina", role: .destructive) {
                                                eventChance = 0.35
                                                cooldownHints = true
                                                haptic(.medium)
                                            }
                                        } message: {
                                            Text("Reimposta le preferenze di gioco e interfaccia.")
                                        }
                                        
                                        SettingsNavRow(
                                            title: "Resuscita il Pavone",
                                            system: "heart.text.square.fill",
                                            tint: .red
                                        ) {
                                            showResetAlert = true
                                        }
                                        .alert("Resuscitare e ribilanciare?", isPresented: $showResetAlert) {
                                            Button("Annulla", role: .cancel) {}
                                            Button("Conferma", role: .destructive) {
                                                withAnimation {
                                                    vm.life = 100
                                                    vm.satiety = max(vm.satiety, 60)
                                                    vm.energy = max(vm.energy, 60)
                                                    vm.hygiene = max(vm.hygiene, 60)
                                                    vm.happiness = max(vm.happiness, 60)
                                                }
                                                haptic(.heavy)
                                            }
                                        } message: {
                                            Text("Porta la Vita a 100 e riallinea le statistiche se sono troppo basse.")
                                        }
                                    }
                                    .padding(.top, 8)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showTutorial) {
                TutorialView(onClose: { showTutorial = false })
                    .environmentObject(vm)
            }
            .onAppear { if eventChance < 0.35 { eventChance = 0.35 } }
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 48, height: 48)
                Image(systemName: "gearshape.2.fill").font(.title2).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("E PAVO PAVO PAVO!")
                    .font(.title3.bold()).foregroundStyle(.white)
                    .lineLimit(1)
                Text("Personalizza gameplay, notifiche e aspetto")
                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding(12)
        .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
    }

        private var footer: some View {
            VStack(spacing: 6) {
                Text("Versione 1.0 • Build interna TestFlight")
                    .font(.caption2).foregroundStyle(.white.opacity(0.85))
                Text("Le modifiche hanno effetto immediato.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    
    // MARK: Building blocks (scoped per evitare conflitti globali)
        private struct SCard<Content: View>: View {
            let title: String
            let icon: String
            @ViewBuilder var content: Content
            var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: icon).foregroundStyle(.white)
                        Text(title).font(.headline).foregroundStyle(.white)
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 12) { content }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
                .padding(12)
                .background(ShopView.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShopView.cardStroke, lineWidth: 1))
            }
        }

        private struct SettingsToggleRow: View {
            let title: String
            let system: String
            @Binding var isOn: Bool
            var subtitle: String? = nil
            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: system).foregroundStyle(.white)
                        Toggle(title, isOn: $isOn)
                            .toggleStyle(.switch)
                            .foregroundStyle(.white)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.leading, 26)
                    }
                }
            }
        }

        private struct SettingsHeaderRow: View {
            let title: String
            let system: String
            var body: some View {
                HStack(spacing: 8) {
                    Image(systemName: system).foregroundStyle(.white)
                    Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                    Spacer()
                }
            }
        }

        private struct SettingsNavRow: View {
            let title: String
            let system: String
            var tint: Color = .white
            var action: () -> Void
            var body: some View {
                Button(action: action) {
                    HStack(spacing: 10) {
                        Image(systemName: system).foregroundStyle(.white)
                        Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint, tint.opacity(0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(PetViewModel())
    }
}

private struct ItemInfoSheet: View {
    let item: ShopItem
    let purpose: String
    let lines: [String]
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: item.colors,
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Image(systemName: item.symbol).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading) {
                        Text(item.title).font(.headline).foregroundStyle(.white)
                        Text(purpose).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    }
                }
                Divider().background(.white.opacity(0.2))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines, id: \.self) { l in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark.seal.fill").font(.caption2)
                            Text(l).font(.footnote)
                        }
                        .foregroundStyle(.white)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(
                LinearGradient(colors: [.indigo.opacity(0.5), .purple.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
    }
}
}

// Fade ai bordi sinistro e destro per liste orizzontali lunghe
private extension View {
    /// Fade ai bordi sinistro e destro per liste orizzontali lunghe
    func horizontalEdgeFades(_ width: CGFloat = 18) -> some View {
        self
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.45), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.45)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
                .allowsHitTesting(false)
            }
    }
}

// MARK: - 🔧 PetViewModel Extensions

// MARK: Cooldown Hints
extension PetViewModel {
    /// Hint testuale per il cooldown Bevuta
    var feedHint: String { 
        let r = feedRemaining()
        return r > 0 ? "Spuntino tra \(mmss(r)) (max \(Balance.satietyLimit)/10m)" : "Pronto" 
    }
    
    /// Hint testuale per il cooldown Shot
    var coffeeHint: String { 
        let r = coffeeRemaining()
        return r > 0 ? "Shot tra \(mmss(r)) (max \(Balance.coffeeLimit)/10m)" : "Pronto" 
    }
    
    /// Hint testuale per il cooldown Ingresso
    var meetHint: String { 
        let r = meetRemaining()
        return r > 0 ? "Ingresso tra \(mmss(r))" : "Pronto" 
    }
    
    /// Hint testuale per il cooldown Rilassati
    var cleanHint: String { 
        let r = cleanRemaining()
        return r > 0 ? "Rilassati tra \(mmss(r))" : "Pronto" 
    }
}

// MARK: KeyPath Bump Helper
extension PetViewModel {
    /// Incrementa in modo sicuro una statistica Double tramite key path, clampando 0...statCap
    func bump(_ keyPath: ReferenceWritableKeyPath<PetViewModel, Double>, _ delta: Double) {
        let cap = Double(statCap)
        let current = self[keyPath: keyPath]
        self[keyPath: keyPath] = min(cap, max(0, current + delta))
    }
}

// MARK: Safe Reset
extension PetViewModel {
    /// Reset per un nuovo run (conservativo)
    func resetForNewRun() {
        self.PavoLire = 0
        self.ageSeconds = 0
        self.life = 100
        self.satiety = min(self.statCap, max(50, self.satiety))
        self.energy = min(self.statCap, max(50, self.energy))
        self.hygiene = min(self.statCap, max(50, self.hygiene))
        self.happiness = min(self.statCap, max(50, self.happiness))
        // Azzeriamo XP senza rompere l'invariante del livello
        self.xp = 0
        self.hasFinishedRun = false
        }
    }

// MARK: - Main ContentView
struct ContentView: View {
    @StateObject private var vm = PetViewModel()
    @State private var selectedTab = 0
    @EnvironmentObject var minigameManager: MinigameManager
    @EnvironmentObject var locationManager: LocationManager
    
    // Debug menu states
    @State private var showDebugMenu = false
    @State private var debugTestBanner = false
    @State private var debugTestSigla = false
    @State private var debugTestMinigame = false
    @State private var debugTestSerata = false
    @State private var debugTestSerataOmaggio = false
    @State private var debugClickCount = 0
    @State private var debugClickTimer: Timer?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // H-ZOO Tab
            HomeTabView(
                debugTestBanner: $debugTestBanner,
                debugTestSigla: $debugTestSigla,
                debugTestMinigame: $debugTestMinigame,
                debugTestSerata: $debugTestSerata,
                debugTestSerataOmaggio: $debugTestSerataOmaggio
            )
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("H-ZOO")
                }
                .tag(0)
                .onTapGesture {
                    handleDebugClick()
                }
            
            // Tavolo Tab
            PrenotaTabView()
                .tabItem {
                    Image(systemName: "wineglass")
                    Text("Tavolo")
                }
                .tag(1)
            
            // Prezzi Tab
            PrezziView()
                .tabItem {
                    Image(systemName: "eurosign.circle.fill")
                    Text("Prezzi")
                }
                .tag(2)
            
            // Pavogotchi Tab (era MinigameTabView)
            MinigameTabView()
                .tabItem {
                    Image(systemName: "gamecontroller.fill")
                    Text("Minigame")
                }
                .tag(3)
            
        }
        .environmentObject(vm)
        .environmentObject(minigameManager)
        .environmentObject(locationManager)
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
            if let tabIndex = notification.userInfo?["tab"] as? Int {
                selectedTab = tabIndex
            }
        }
        .sheet(isPresented: $showDebugMenu) {
            DebugMenuView(
                debugTestBanner: $debugTestBanner,
                debugTestSigla: $debugTestSigla,
                debugTestMinigame: $debugTestMinigame,
                debugTestSerata: $debugTestSerata,
                debugTestSerataOmaggio: $debugTestSerataOmaggio
            )
            .environmentObject(vm)
            .environmentObject(minigameManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserEnteredVenue"))) { _ in
            // Utente entrato nel locale - abilita funzionalità
            print("📍 Utente entrato nel locale!")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserExitedVenue"))) { _ in
            // Utente uscito dal locale - disabilita funzionalità
            print("📍 Utente uscito dal locale!")
        }
        .onDisappear {
            // Cleanup timer quando si chiude la view
            debugClickTimer?.invalidate()
            debugClickTimer = nil
        }
    }
    
    // MARK: - Debug Click Handler
    private func handleDebugClick() {
        debugClickCount += 1
        
        // Reset timer se esiste
        debugClickTimer?.invalidate()
        
        if debugClickCount >= 10 {
            // 10 click raggiunti - apri debug menu
            showDebugMenu = true
            debugClickCount = 0
            haptic(.heavy)
        } else {
            // Haptic feedback per ogni click
            haptic(.light)
            
            // Timer per reset automatico dopo 2 secondi
            debugClickTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                debugClickCount = 0
            }
        }
    }
}


// MARK: - Prezzi View (Originale Meravigliosa)
struct PrezziView: View {
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)
                
                VStack(spacing: 24) {
                    
                    // Prezzi Ingresso
                    VStack(alignment: .leading, spacing: 16) {
                        Text("💸 Ingresso")
                            .font(.headline)
                            .foregroundStyle(HZooConfig.textWhite)
                        
                        VStack(spacing: 12) {
                            priceRow(icon: "👔", title: "Uomo", price: HZooConfig.priceMan, detail: "Valido tutta la notte")
                            priceRow(icon: "👗", title: "Donna", price: "Omaggio", detail: "Omaggio entro le 00:30, poi 15€")
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "1a1a1a"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(HZooConfig.textWhite.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Servizi
                    VStack(alignment: .leading, spacing: 16) {
                        Text("🎫 Servizi")
                            .font(.headline)
                            .foregroundStyle(HZooConfig.textWhite)
                        
                        VStack(spacing: 12) {
                            priceRow(icon: "🧥", title: "Guardaroba", price: HZooConfig.priceCoatCheck, detail: "Obbligatorio per giacche e borse")
                            priceRow(icon: "🍸", title: "Consumazione", price: HZooConfig.priceDrink, detail: "Drink e cocktail")
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "1a1a1a"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(HZooConfig.textWhite.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Note
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Info Utili", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundStyle(HZooConfig.accentCyan)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            noteRow(text: "Pagamenti: contanti e carte")
                            noteRow(text: "Ingresso non rimborsabile")
                            noteRow(text: "Prezzi soggetti a variazioni per eventi speciali")
                        }
                        .padding(16)
                        .background(Color(hex: "1a1a1a"))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Prezzi")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if scrollOffset > -50 {
                        Image("logoBianco")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 32)
                            .offset(y: -8)
                    }
                }
            }
            .onAppear {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance = appearance
            }
        }
        .onAppear {
            trackEvent("view_prezzi")
        }
    }
    
    private func priceRow(icon: String, title: String, price: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HZooConfig.textWhite)
                
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(HZooConfig.textWhite.opacity(0.6))
            }
            
            Spacer()
            
            Text(price)
                .font(.title3.weight(.bold))
                .foregroundStyle(HZooConfig.primaryNeon)
        }
    }
    
    private func noteRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(HZooConfig.accentCyan)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(HZooConfig.textWhite.opacity(0.85))
        }
    }
}

// MARK: - Impostazioni View
struct ImpostazioniView: View {
    @EnvironmentObject var locationManager: LocationManager
    @State private var showLocationPermissionAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.gray)
                        
                        Text("Impostazioni")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                        
                        Text("Personalizza la tua esperienza")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 20)
                    
                    // Permessi
                    ImpostazioniSection(title: "🔐 Permessi", icon: "lock.fill") {
                        // Posizione
                        ImpostazioneRow(
                            title: "Posizione",
                            subtitle: locationManager.authorizationStatus == .authorizedWhenInUse ? "Autorizzato" : "Non autorizzato",
                            icon: "location.fill",
                            color: locationManager.authorizationStatus == .authorizedWhenInUse ? .green : .red,
                            action: {
                                locationManager.requestLocationPermission()
                            }
                        )
                        
                        // Notifiche
                        ImpostazioneRow(
                            title: "Notifiche",
                            subtitle: "Abilita per ricevere promemoria",
                            icon: "bell.fill",
                            color: .blue,
                            action: {
                                // Richiedi permessi notifiche
                            }
                        )
                    }
                    
                    // Geofencing
                    ImpostazioniSection(title: "📍 Geofencing", icon: "location.circle.fill") {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: locationManager.isNearVenue ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(locationManager.isNearVenue ? .green : .red)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Stato Posizione")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    
                                    Text(locationManager.isNearVenue ? "Vicino al locale" : "Lontano dal locale")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                
                                Spacer()
                            }
                            
                            if locationManager.distanceToVenue > 0 {
                                HStack {
                                    Image(systemName: "ruler")
                                        .foregroundStyle(.cyan)
                                    
                                    Text("Distanza: \(Int(locationManager.distanceToVenue)) metri")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.7))
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    // Info App
                    ImpostazioniSection(title: "ℹ️ Info", icon: "info.circle.fill") {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "app.badge")
                                    .foregroundStyle(.cyan)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("El-PavoReal")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    
                                    Text("Versione 1.0 • Build TestFlight")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .navigationBarHidden(true)
        }
    }
}


// MARK: - Helper Views per Impostazioni
private struct ImpostazioniSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                    .font(.title2)
                
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                
                Spacer()
            }
            
            content
        }
        .padding(20)
        .background(Color(hex: "1a1a1a"))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

private struct ImpostazioneRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(16)
            .background(Color(hex: "1a1a1a"))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Debug Menu View
struct DebugMenuView: View {
    @Binding var debugTestBanner: Bool
    @Binding var debugTestSigla: Bool
    @Binding var debugTestMinigame: Bool
    @Binding var debugTestSerata: Bool
    @Binding var debugTestSerataOmaggio: Bool
    
    @EnvironmentObject var vm: PetViewModel
    @EnvironmentObject var minigameManager: MinigameManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var bannerTimer: Timer?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "ladybug.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.orange)
                            
                            Text("Debug Menu")
                                .font(.title.bold())
                                .foregroundStyle(.white)
                            
                            Text("Strumenti di sviluppo per testare le funzionalità")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Debug Actions
                        VStack(spacing: 16) {
                            DebugButton(
                                title: "Test Banner Omaggio Donna",
                                subtitle: "Mostra banner per 1 minuto",
                                icon: "sparkles",
                                color: .pink,
                                isActive: debugTestBanner
                            ) {
                                testBanner()
                            }
                            
                            DebugButton(
                                title: "Test Sigla",
                                subtitle: "Attiva micro-quote sigla",
                                icon: "music.note",
                                color: .blue,
                                isActive: debugTestSigla
                            ) {
                                testSigla()
                            }
                            
                            DebugButton(
                                title: "Test Minigame",
                                subtitle: "Attiva minigame di serata",
                                icon: "gamecontroller.fill",
                                color: .purple,
                                isActive: debugTestMinigame
                            ) {
                                testMinigame()
                            }
                            
                            DebugButton(
                                title: "Test Banner Serata",
                                subtitle: "Mostra banner 'IN SERATA' in alto",
                                icon: "party.popper.fill",
                                color: .orange,
                                isActive: debugTestSerata
                            ) {
                                testSerata()
                            }
                            
                            DebugButton(
                                title: "Test Omaggio Donna Serata",
                                subtitle: "Omaggio donna durante serata attiva",
                                icon: "heart.fill",
                                color: .pink,
                                isActive: debugTestSerataOmaggio
                            ) {
                                testSerataOmaggio()
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Info
                        VStack(spacing: 8) {
                            Text("ℹ️ Informazioni")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            
                            Text("Questi test eludono le logiche normali dell'app per permettere il debug durante lo sviluppo.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .onDisappear {
            // Cleanup timers quando si chiude il menu
            bannerTimer?.invalidate()
            bannerTimer = nil
        }
    }
    
    private func testBanner() {
        debugTestBanner.toggle()
        
        if debugTestBanner {
            // Attiva banner per 1 minuto
            bannerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
                DispatchQueue.main.async {
                    debugTestBanner = false
                }
            }
            haptic(.medium)
        } else {
            // Disattiva immediatamente
            bannerTimer?.invalidate()
            bannerTimer = nil
            haptic(.light)
        }
    }
    
    private func testSigla() {
        debugTestSigla.toggle()
        haptic(.medium)
    }
    
    private func testMinigame() {
        debugTestMinigame.toggle()
        haptic(.medium)
    }
    
    private func testSerata() {
        debugTestSerata.toggle()
        haptic(.medium)
    }
    
    private func testSerataOmaggio() {
        debugTestSerataOmaggio.toggle()
        haptic(.medium)
    }
}

// MARK: - Debug Button Component
private struct DebugButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isActive ? color : color.opacity(0.3))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isActive ? .white : color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isActive ? color : .white.opacity(0.5))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isActive ? color.opacity(0.1) : Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isActive ? color : Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 🎬 Remote Video Views
struct RemoteVideoListView: View {
    let videos: [RemoteVideo]
    let type: LocalVideo.VideoType
    @Binding var selectedVideo: RemoteVideo?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                
                if videos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: type == .aftermovie ? "film.fill" : "play.rectangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(HZooConfig.primaryNeon.opacity(0.6))
                        
                        Text("Nessun video disponibile")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        
                        Text("I nuovi video saranno disponibili presto!")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(videos) { video in
                                RemoteVideoRow(video: video, selectedVideo: $selectedVideo)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle(type == .aftermovie ? "AFTERMOVIE" : "TIKTOK")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

struct RemoteVideoRow: View {
    let video: RemoteVideo
    @Binding var selectedVideo: RemoteVideo?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button(action: {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                selectedVideo = video
            }
        }) {
            HStack(spacing: 12) {
                // Thumbnail
                AsyncImage(url: URL(string: video.thumbnail)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .overlay {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title)
                                .foregroundStyle(HZooConfig.primaryNeon.opacity(0.6))
                        }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    
                    Text(video.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                    
                    HStack(spacing: 12) {
                        Label(video.date, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Label(video.duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Play button
                Circle()
                    .fill(HZooConfig.primaryNeon.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.callout)
                            .foregroundStyle(HZooConfig.primaryNeon)
                    }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RemoteVideoPlayerView: View {
    let video: RemoteVideo
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Caricamento video...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle(video.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") {
                        player?.pause()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                if let url = URL(string: video.videoUrl) {
                    player = AVPlayer(url: url)
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }
}

