//  ContentView.swift
//  El-PavoReal
//  v5.0 –  Multi-Tab App: Home, H-ZOO, Minigame
//  v4.1 –  Themed: Levels, In-App Events, Tutorial+, Shop (PavoLire), Settings, Better Layout
//  Fixed: duplicate symbols, removed |> / clampTo, consistent Tutorial API
//  Created by Simone Azzinelli on 23/08/25.

import SwiftUI
import Combine
import UIKit
import UserNotifications


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
    @Published var slotWinChance: Double = 0.01
    
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
struct SettingsModel {
    @AppStorage("El-PavoReal.hapticsEnabled") var hapticsEnabled: Bool = true
    @AppStorage("El-PavoReal.eventChance") var eventChance: Double = 0.08
    @AppStorage("El-PavoReal.compactPadding") var compactPadding: Bool = true
    @AppStorage("El-PavoReal.reduceMotion") var reduceMotion: Bool = false
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

// MARK: - Main App with Tabs
struct ContentView: View {
    @StateObject private var vm = PetViewModel()
    @State private var selectedTab = 2 // Solo Minigame per ora
    
    var body: some View {
        // TEMPORANEO: Solo Minigame attivo, altre tab disabilitate ma non eliminate
        TabView(selection: $selectedTab) {
            // Tab 1: Home - DISABILITATA
            /*
            HomeTabView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            */
            
            // Tab 2: H-ZOO - DISABILITATA
            /*
            HZooTabView()
                .tabItem {
                    Image(systemName: "party.popper.fill")
                    Text("H-ZOO")
                }
                .tag(1)
            */
            
            // Tab 3: Minigame - ATTIVO
            MinigameTabView()
                .environmentObject(vm)
                .tabItem {
                    Image(systemName: "gamecontroller.fill")
                    Text("Minigame")
                }
                .tag(2)
        }
        .accentColor(.white)
    }
}

// MARK: - 🦚 El PavoReal Tab (Locale principale - Eleganza & After Dinner)
struct HomeTabView: View {
    var body: some View {
        NavigationStack {
            List {
                // Hero Section
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "bird.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.purple)
                        
                        Text("EL PAVO‑REAL")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .tracking(1.5)
                        
                        Text("After Dinner Club")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)
                
                // Prossime Serate
                Section("Prossime Serate") {
                    NavigationLink {
                        Text("Dettagli Sabato Night")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sabato Night")
                                .font(.headline)
                            Text("Ogni Sabato • 22:00 - 05:00")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        Text("Dettagli Domenica Aperitivo")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Domenica Aperitivo")
                                .font(.headline)
                            Text("Ogni Domenica • 18:00 - 23:00")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Gallery
                Section("Gallery") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 150, height: 100)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundStyle(.gray)
                                    )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                }
                
                // Drink Menu
                Section("Drink Menu") {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading) {
                            Text("Signature Cocktail")
                            Text("15€")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("Premium Spirits")
                            Text("12€")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Champagne Selection")
                            Text("80€")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Info & Contatti
                Section("Info & Contatti") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("El Pavo‑Real è l'after dinner club che ridefinisce la nightlife elegante. Atmosfera esclusiva, cocktail d'autore e musica selezionata.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                        Text("Via Milano, 123 - Milano")
                    }
                    
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.green)
                        Text("+39 02 1234 5678")
                    }
                    
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.blue)
                        Text("info@el-pavoreal.com")
                    }
                }
            }
            .navigationTitle("El Pavo‑Real")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - 🦩 H-ZOO Tab (Venerdì Selvaggio - Over 21)
struct HZooTabView: View {
    var body: some View {
        NavigationStack {
            List {
                // Hero Section
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.pink)
                        
                        Text("H‑ZOO")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .tracking(2)
                        
                        Text("VENERDÌ NOTTE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)
                
                // ⚠️ Regole Ingresso
                Section {
                    Label("Solo Over 21 (nati fino al 2004)", systemImage: "18.circle.fill")
                    Label("Selezione all'ingresso", systemImage: "person.badge.shield.checkmark.fill")
                    Label("Documento originale obbligatorio", systemImage: "doc.text.fill")
                    Label("No fotocopie o screenshot", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Label("Apertura: 23:00 - 06:00", systemImage: "clock.fill")
                } header: {
                    Label("Regole di Ingresso", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.pink)
                }
                
                // Countdown
                Section("Prossimo H-ZOO") {
                    VStack(spacing: 8) {
                        Text("Venerdì 23:00")
                            .font(.title2.bold())
                        Text("2 giorni, 14 ore")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                
                // Programma Serata
                Section("Programma Serata") {
                    HStack {
                        Text("23:00")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.pink)
                            .frame(width: 50, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apertura")
                                .font(.subheadline.bold())
                            Text("Ingresso e primi drink")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("00:00")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.pink)
                            .frame(width: 50, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Warm Up")
                                .font(.subheadline.bold())
                            Text("Musica e atmosfera")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("01:00")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.pink)
                            .frame(width: 50, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Peak Time")
                                .font(.subheadline.bold())
                            Text("Pista al massimo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("03:00")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.pink)
                            .frame(width: 50, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("After Hours")
                                .font(.subheadline.bold())
                            Text("Chiusura alle 06:00")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Weekend Vibes
                Section("Weekend Vibes") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<6) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 100, height: 150)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .foregroundStyle(.gray)
                                    )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                }
                
                // Merch
                Section("Merch H-ZOO") {
                    HStack {
                        Image(systemName: "tshirt.fill")
                            .foregroundStyle(.pink)
                        VStack(alignment: .leading) {
                            Text("T-Shirt")
                            Text("25€")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    HStack {
                        Image(systemName: "figure.walk")
                            .foregroundStyle(.pink)
                        VStack(alignment: .leading) {
                            Text("Felpa")
                            Text("45€")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.pink)
                        VStack(alignment: .leading) {
                            Text("Cap")
                            Text("20€")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("H‑ZOO")
            .navigationBarTitleDisplayMode(.large)
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
    
    @State private var bobbing = false
    @State private var pulse = false
    @State private var showDeathScreen: Bool = false
    @State private var showLifeInfo: Bool = false
    
    @State private var showShop = false
    @State private var showTutorial = false
    @State private var showSettings = false
    @State private var showEventLog = false
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
    
    // MARK: Mini-gioco: scheduling casuale (Privé Rush)
    @State private var showMiniGame = false
    @State private var lastMiniGameAt: Date = .distantPast
    private let miniGameMinInterval: TimeInterval = 180  // almeno 3 minuti fra due minigiochi
    private let miniGameTick = Timer.publish(every: 45, on: .main, in: .common).autoconnect()
    
    // MARK: - 🎰 Daily Slot System
    private func canPlaySlotToday() -> Bool {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        if lastDailySlotDate != today {
            // Nuovo giorno: reset tentativi e vittoria
            dailySlotTries = 0
            slotWonToday = false
            lastDailySlotDate = today
        }
        return dailySlotTries < 10 && !slotWonToday
    }
    
    private func getRemainingTries() -> Int {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        if lastDailySlotDate != today {
            return 10 // Nuovo giorno
        }
        if slotWonToday {
            return 0 // Ha già vinto oggi
        }
        return max(0, 10 - dailySlotTries)
    }
    
    
    private func applySlotPrize(_ prize: SlotPrize) {
        switch prize {
        case .coins(let amount):
            vm.PavoLire += amount
            enqueueEventOverlay(EventOverlayItem(title: "JACKPOT! 🎰", icon: "dollarsign.circle.fill", tone: .positive, lines: ["+\(amount) PavoLire!"]))
        case .xp(let amount):
            vm.xp += amount
            enqueueEventOverlay(EventOverlayItem(title: "BONUS XP! ⭐", icon: "star.fill", tone: .positive, lines: ["+\(amount) XP guadagnati!"]))
        case .booster(let minutes):
            vm.boostUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
            vm.activeBoosterItemTitle = "Slot Machine"
            vm.activeBoosterItemSymbol = "gamecontroller.fill"
            enqueueEventOverlay(EventOverlayItem(title: "BOOSTER! ⚡", icon: "bolt.heart.fill", tone: .positive, lines: ["Decadimenti dimezzati per \(minutes) min!"]))
        case .statBoost:
            vm.satiety = min(vm.statCap, vm.satiety + 30)
            vm.energy = min(vm.statCap, vm.energy + 30)
            enqueueEventOverlay(EventOverlayItem(title: "ENERGIA! ✨", icon: "sparkles", tone: .positive, lines: ["+30 a entrambe!"]))
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
        
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "wineglass.fill", tone: .positive, lines: ["Bevuta servita!"]))
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
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "bolt.fill", tone: .positive, lines: ["Shot fatto!"]))
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
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "sparkles", tone: .positive, lines: ["Reset mentale!"]))
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
        enqueueEventOverlay(EventOverlayItem(title: name, icon: "party.popper.fill", tone: .positive, lines: ["Vai in pista!"]))
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            background

            // CONTENT
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
            // EventiLog
            .sheet(isPresented: $showEventLog) {
                EventCenterSheet(log: $eventLog)
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
            .fullScreenCover(isPresented: $showTutorial) { TutorialView(onClose: { showTutorial = false; seenTutorial = true }) }
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
            if !seenTutorial { showTutorial = true }
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
                Button("Gin Tonic") { chooseDrink("Gin Tonic") }
                Button("Vodka Lemon") { chooseDrink("Vodka Lemon") }
                Button("Negroni") { chooseDrink("Negroni") }
                Button("Acqua Fresca") { chooseDrink("Acqua Fresca") }
            } else if quickPickKind == .shot {
                Button("Tequila Bum Bum") { chooseShot("Tequila Bum Bum") }
                Button("Jägerbomb") { chooseShot("Jägerbomb") }
                Button("Sambuca") { chooseShot("Sambuca") }
                Button("Rum e Lime") { chooseShot("Rum e Lime") }
            } else if quickPickKind == .relax {
                Button("Respiro") { chooseRelax("Respiro") }
                Button("Stretching") { chooseRelax("Stretching") }
                Button("Pausa") { chooseRelax("Pausa") }
                Button("Reset") { chooseRelax("Reset") }
            } else if quickPickKind == .sigla {
                Button("Sigla Originale") { chooseSigla("Sigla Originale") }
                Button("Sigla Acustica") { chooseSigla("Sigla Acustica") }
                Button("Sigla Rock") { chooseSigla("Sigla Rock") }
                Button("Sigla Pop") { chooseSigla("Sigla Pop") }
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
            enqueueEventOverlay(EventOverlayItem(title: title, icon: icon, tone: tone, lines: lines))
        }
        .overlay(alignment: .center) {
            if let it = currentEventOverlay {
                EventOverlayView(item: it) { dismissCurrentEventOverlay() }
                    .zIndex(100)
            }
        }
        // Avvio casuale ad ogni tick (rispetta un intervallo minimo)
        .onReceive(miniGameTick) { _ in
            if Date().timeIntervalSince(lastMiniGameAt) >= miniGameMinInterval {
                maybeTriggerRandomEvent() // qui dentro settiamo showMiniGame = true con una probabilità
            }
        }

        // Fallback: trigger manuale via notifica
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("El-PavoReal.miniGame"))) { _ in
            showMiniGame = true
        }

        // Presentazione full-screen del mini-gioco
        .fullScreenCover(isPresented: $showMiniGame) {
            PriveRushView(vm: vm) { delivered, success in
                let text = success
                    ? "Privé Rush riuscito! Consegne: \(delivered)"
                    : "Privé Rush fallito… Consegne: \(delivered)"
                pushBanner(text: text,
                           symbol: success ? "lock.open.fill" : "exclamationmark.triangle.fill",
                           colors: success ? [.green, .mint] : [.orange, .red])
                showMiniGame = false
            }
            .ignoresSafeArea()
        }
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

    struct EventCenterSheet: View {
        @EnvironmentObject var vm: PetViewModel
        @Binding var log: [LoggedEvent]
        @State private var tab: Int = 0

        var body: some View {
            VStack(spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Centro eventi")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 20)
                    Text("Qui trovi gli imprevisti recenti e tutti gli obiettivi da sbloccare. Gli eventi vengono registrati durante il gioco: gli obiettivi si completano automaticamente quando soddisfi i requisiti.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Switcher
                Picker("Sezione", selection: $tab) {
                    Text("Eventi").tag(0)
                    Text("Obiettivi").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                // Content
                Group {
                    if tab == 0 {
                        EventLogList(log: $log)
                    } else {
                        AchievementsTab()
                            .environmentObject(vm)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
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
        private let cols = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

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
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "medal.fill").foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Obiettivi").font(.title2.bold()).foregroundStyle(.white)
                        Text("Sblocca badge giocando: mini-giochi, cura e progressi quotidiani.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("\(done)/\(total)").monospacedDigit().bold()
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: overall).tint(.white)
                    Text("Completati \(done) su \(total)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.85))
                }

                Picker("Filtro", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)

                ScrollView(showsIndicators: true) {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(data) { a in
                            let p = center.progressFraction(for: a.condition, vm: vm)
                            let u = center.isUnlocked(a.id)
                            AchBadge(achievement: a, unlocked: u, progress: p)
                                .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selected = a } }
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxHeight: 440)
            }
            .padding(16)
            .background(shopSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(shopStroke, lineWidth: 1))
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
                        .frame(width: 82, height: 82)
                        .saturation(unlocked ? 1 : 0)
                        .opacity(unlocked ? 1 : 0.55)
                        .scaleEffect(unlocked ? 1.0 : 0.95)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: unlocked)
                    Image(systemName: achievement.icon).font(.title2).foregroundStyle(.white).opacity(unlocked ? 1 : 0.65)
                    if !unlocked {
                        Circle()
                            .trim(from: 0, to: CGFloat(max(0.08, min(1.0, progress))))
                            .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .fill(.white.opacity(0.75))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 90, height: 90)
                            .allowsHitTesting(false)
                    }
                }
                Text(achievement.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(unlocked ? "Sbloccato" : "Progresso: \(Int(round(progress*100)))%")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .frame(height: 176)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
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
                    ScrollView { VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ZStack { Circle().fill(LinearGradient(colors: a.colors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 48, height: 48); Image(systemName: a.icon).foregroundStyle(.white) }
                            VStack(alignment: .leading, spacing: 4) { Text(a.title).font(.title3.bold()).foregroundStyle(.white); Text(a.desc).font(.footnote).foregroundStyle(.white.opacity(0.9)) }
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: min(1, progress)).tint(.white)
                            Text(unlocked ? "Completato" : "Progresso: \(Int(progress*100))%")
                                .font(.caption).foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Come sbloccarlo").font(.headline).foregroundStyle(.white)
                            Text(hintText).font(.footnote).foregroundStyle(.white.opacity(0.9))
                        }
                    }.padding(16) }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") } } }
                .navigationTitle("Dettagli obiettivo").navigationBarTitleDisplayMode(.inline)
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
                Text("El-PavoReal")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                // PavoLire: icona + numero, clickable
                Button {
                    showPavoLireInfo = true
                } label: {
                CoinBadge(value: vm.PavoLire)
                }
                .buttonStyle(.plain)

                // Icone toolbar con sfondo circolare leggero
                Button { showShop = true } label: {
                    Image(systemName: "cart")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial.opacity(0.3), in: Circle())

                Button { showEventLog = true } label: {
                    Image(systemName: "clock")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial.opacity(0.3), in: Circle())

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial.opacity(0.3), in: Circle())
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
                pushBanner(text: "Drink bevuto! +22 Sete",
                           symbol: "wineglass.fill",
                           colors: GradientTokens.satiety)
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if isLocked("El-PavoReal.drinkNextReadyAt") {
                    haptic(.heavy)
                } else {
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
                pushBanner(text: "Shot al bancone! +24 Energia",
                           symbol: "bolt.fill",
                           colors: [.pink, .purple])
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if isLocked("El-PavoReal.coffeeNextReadyAt") {
                    haptic(.heavy)
                } else {
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
                pushBanner(text: "Reset mentale! +26 Chill",
                           symbol: "sparkles",
                           colors: [.teal, .blue])
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if isLocked("El-PavoReal.cleanNextReadyAt") {
                    haptic(.heavy)
                } else {
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
                pushBanner(text: "Alza la voce e canta insieme a noi! +2 P£",
                           symbol: "music.microphone",
                           colors: [.yellow, .orange])
            }
            .onLongPressGesture {
                // Solo se NON c'è cooldown attivo
                if isLocked("El-PavoReal.meetNextReadyAt") {
                    haptic(.heavy)
                } else {
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
        .padding(.top, compactPadding ? 8 : 12)
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
        // Rispetta un intervallo minimo fra minigiochi
        guard Date().timeIntervalSince(lastMiniGameAt) >= miniGameMinInterval else { return }
        // Probabilità base (clamp 0…1)
        let chance = max(0.0, min(1.0, eventChance))
        guard Double.random(in: 0...1) < chance else { return }
        // 1 su 5: parte il mini-gioco (Privé Rush)
        if Int.random(in: 0..<5) == 0 {
            lastMiniGameAt = Date()
            postOverlayEvent(
                title: "Mini-gioco: Privé Rush",
                icon: "lock.open.fill",
                tone: "system",
                lines: ["Consegna drink nel Privé!", "Hai 45 secondi"]
            )
            showMiniGame = true
            return
        }
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

        // Registra nel Centro Eventi
        if log {
            eventLog.append(LoggedEvent(date: Date(), text: text, symbol: symbol, colors: colors))
        }
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
            withIdentifiers: ["checkin","lowSatietyBg","criticallyLowBg","fastDropBg","stateSpeedBg"]
        )

        let cap = vm.statCap
        let lows = [vm.satiety, vm.energy, vm.hygiene, vm.happiness]
        let lowCount = lows.filter { $0 < 0.35 * cap }.count

        // 1) È troppo tempo che non entro → check-in a ~75 minuti
        scheduleLocal(
            id: "checkin",
            title: "Tutto ok su El-PavoReal?",
            body: "È un po’ che non entri. Dai un’occhiata al Pavone.",
            after: 75 * 60
        )

        // 2) Stato che fa scendere più velocemente (es. stanchezza/noia/critico)
        if vm.mood == .stanchezza || vm.mood == .noia || vm.mood == .critico {
            scheduleLocal(
                id: "stateSpeedBg",
                title: "Consumi più veloci",
                body: "Il Pavone è in mood \(vm.moodTitle.lowercased()). Potrebbe scendere più in fretta.",
                after: 30 * 60
            )
        }

        // 3) Scende troppo veloce: più statistiche già basse
        if lowCount >= 2 {
            scheduleLocal(
                id: "fastDropBg",
                title: "Sta calando velocemente",
                body: "Più statistiche sono basse. Rientra a dare una mano.",
                after: 30 * 60
            )
        }

        // 4) Sono critico e sto per morire
        if vm.life < 30 || lows.contains(where: { $0 < 0.15 * cap }) {
            scheduleLocal(
                id: "criticallyLowBg",
                title: "Critico: rischio KO",
                body: "Il Pavone è messo male. Entra subito e curalo.",
                after: 10 * 60
            )
        }
    }

    
    // MARK: - Notifications permission
    private func requestNotificationsIfNeeded() {
        guard notificationsEnabled, !askedNotifications else { return }
        askedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
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

    if vm.life < 20 || minStat < 12 { return .critico }

    if (minStat >= 65 && vm.life >= 55) || (avgStat >= 72 && vm.life >= 50) {
        return .felice
    }

    if vm.energy < 32 { return .stanchezza }
    if vm.happiness < 28 && (vm.satiety < 35 || vm.hygiene < 35) { return .rabbia }

    // Offline non ha una misura affidabile di inattività: usa una soglia semplice sulla Festa
    if vm.happiness < 55 { return .noia }

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

// MARK: - Mini-game: Privé Rush (new)
struct PriveRushView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PetViewModel
    var successThreshold: Int = 6
    private let duration: Int = 45
    private let cols: Int = 8
    private let rows: Int = 12

    struct Cell: Hashable { var x: Int; var y: Int }

    @State private var timeLeft: Int = 45
    @State private var player = Cell(x: 1, y: 10)
    @State private var goal   = Cell(x: 6, y: 1)
    @State private var pickups: Set<Cell> = []
    @State private var carried: Int = 0
    @State private var delivered: Int = 0
    @State private var finished: Bool = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let onFinish: (_ delivered: Int, _ success: Bool) -> Void

    var body: some View {
        ZStack {
            // Sfondo standard (non home): scuro + indigo
            LinearGradient(colors: [.black, .indigo.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Arena
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = min(geo.size.height, geo.size.width * 1.2)
                    let cw = w / CGFloat(cols)
                    let ch = h / CGFloat(rows)

                    ZStack {
                        // Griglia
                        Path { p in
                            for x in 0...cols {
                                p.move(to: CGPoint(x: CGFloat(x)*cw, y: 0))
                                p.addLine(to: CGPoint(x: CGFloat(x)*cw, y: h))
                            }
                            for y in 0...rows {
                                p.move(to: CGPoint(x: 0, y: CGFloat(y)*ch))
                                p.addLine(to: CGPoint(x: w, y: CGFloat(y)*ch))
                            }
                        }
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)

                        // Goal (Privé)
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(.yellow)
                            .shadow(color: .yellow.opacity(0.7), radius: 8)
                            .position(pos(goal, cw, ch))

                        // Pickups (Shot)
                        ForEach(Array(pickups), id: \.self) { cell in
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.pink)
                                .shadow(color: .pink.opacity(0.8), radius: 8)
                                .position(pos(cell, cw, ch))
                        }

                        // Player (token del Pavone)
                        ZStack {
                            Circle().fill(.white.opacity(0.2)).frame(width: min(cw,ch)*0.9, height: min(cw,ch)*0.9)
                            Image(systemName: "party.popper").foregroundStyle(.white)
                        }
                        .position(pos(player, cw, ch))
                    }
                    .contentShape(Rectangle())
                    .frame(height: h)
                }

                Spacer(minLength: 0)

                // D‑Pad a croce + bottone centrale "Consegna"
                DPadCrossControl(
                    onUp:      { step(dx:  0, dy: -1) },
                    onLeft:    { step(dx: -1, dy:  0) },
                    onRight:   { step(dx:  1, dy:  0) },
                    onDown:    { step(dx:  0, dy:  1) },
                    onConfirm: { confirmDelivery() }
                )
                .safeAreaPadding(.bottom, 12)
            }
            .padding(.horizontal, 16)
        }
        .onAppear { reset() }
        .onReceive(ticker) { _ in
            guard !finished else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                if timeLeft > 0 { timeLeft -= 1 } else { finish() }
            }
        }
        .interactiveDismissDisabled(true)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                Text("PRIVÉ RUSH!")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Spacer()
                CapsuleLabel(text: "Tempo: \(timeLeft)s")
                CapsuleLabel(text: "Consegne: \(delivered)/\(successThreshold)")
                CapsuleLabel(text: "In mano: \(carried)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5), alignment: .bottom)
        }
    }

    // MARK: Helpers
    private func pos(_ c: Cell, _ cw: CGFloat, _ ch: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(c.x) + 0.5) * cw, y: (CGFloat(c.y) + 0.5) * ch)
    }

    private func reset() {
        timeLeft = duration
        carried = 0
        delivered = 0
        player = Cell(x: 1, y: rows-2)
        goal   = Cell(x: cols-2, y: 1)
        pickups = []
        var used: Set<Cell> = [player, goal]
        while pickups.count < 9 {
            let c = Cell(x: Int.random(in: 0..<cols), y: Int.random(in: 0..<rows))
            if !used.contains(c) { pickups.insert(c); used.insert(c) }
        }
    }

    private func step(dx: Int, dy: Int) {
        guard !finished else { return }
        let nx = max(0, min(cols-1, player.x + dx))
        let ny = max(0, min(rows-1, player.y + dy))
        let next = Cell(x: nx, y: ny)
        player = next
        if pickups.contains(next) { pickups.remove(next); carried += 1 }
        if next == goal && carried > 0 { delivered += carried; carried = 0 }
        if delivered >= successThreshold { finish() }
    }

    private func confirmDelivery() {
        guard !finished else { return }
        if player == goal && carried > 0 {
            delivered += carried
            carried = 0
            if delivered >= successThreshold { finish() }
        }
    }

    private func finish() {
        finished = true
        let success = delivered >= successThreshold
        if success {
            vm.happiness = min(vm.statCap, vm.happiness + 10)
            vm.PavoLire += delivered
        } else {
            vm.happiness = max(0, vm.happiness - 6)
            vm.energy    = max(0, vm.energy - 4)
        }
        onFinish(delivered, success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
    }
}

// Controllo D‑Pad a croce (grandi hit‑area + bottone centrale)
private struct DPadCrossControl: View {
    var onUp: () -> Void
    var onLeft: () -> Void
    var onRight: () -> Void
    var onDown: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 230, height: 230)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))

            VStack(spacing: 12) {
                Button(action: onUp) { dpadButton(system: "arrow.up") }
                HStack(spacing: 12) {
                    Button(action: onLeft)  { dpadButton(system: "arrow.left") }
                    Button(action: onConfirm) {
                        ZStack {
                            Circle().fill(.white).frame(width: 68, height: 68)
                            Image(systemName: "checkmark")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .buttonStyle(.plain)
                    Button(action: onRight) { dpadButton(system: "arrow.right") }
                }
                Button(action: onDown) { dpadButton(system: "arrow.down") }
            }
        }
    }

    private func dpadButton(system: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .frame(width: 58, height: 58)
            Image(systemName: system)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

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

                Button(action: onDismiss) {
                    Text("Ok, ricevuto")
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                .padding(.top, 2)
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
            }
        }
        .allowsHitTesting(true) // blocca il tocco sotto
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
        case .coins: return "dollarsign.circle.fill"
        case .xp: return "star.fill"
        case .booster: return "bolt.heart.fill"
        case .statBoost: return "sparkles"
        }
    }
}

private enum SlotIcon: String, CaseIterable {
    case coin = "dollarsign.circle.fill"
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
                
                // Scegli risultato finale: probabilità dinamica (default 1%)
                let isWin = Double.random(in: 0...1) < vm.slotWinChance
                
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
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            
                            Text("PavoLire")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            
                            Text("La valuta del tuo Pavo")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        
                        // Saldo attuale
                        VStack(spacing: 16) {
                            Text("Saldo Attuale")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(
                                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                
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
                                InfoRow(icon: "moon.zzz.fill", text: "Fai dormire il Pavo", detail: "+8-12 P£")
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
                                InfoRow(icon: "heart.fill", text: "Resuscita il Pavo", detail: "100 P£")
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

    // Persisted options
    @AppStorage("El-PavoReal.notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("El-PavoReal.eventChance")         private var eventChance: Double = 0.35
    @AppStorage("El-PavoReal.cooldownHints")       private var cooldownHints: Bool = true
    // @AppStorage("El-PavoReal.uiDensity")           private var uiDensity: Int = 1 // 0 compatto, 1 standard, 2 ampio

    @State private var showResetAlert = false
    @State private var showDefaultsAlert = false
    @State private var requestedNotif = false
    @State private var showTutorial = false

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

                        // MARK: - Notifiche
                        SettingsSection(title: "Notifiche", icon: "bell.badge.fill") {
                            VStack(spacing: 12) {
                                SettingsToggleRow(
                                    title: "Notifiche push",
                                    system: "bell.fill",
                                    isOn: $notificationsEnabled,
                                    subtitle: "Ricevi avvisi quando il Pavo ha bisogno"
                                )
                                
                                if !requestedNotif {
                                Button {
                                    requestedNotif = true
                                    UNUserNotificationCenter.current()
                                        .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
                                        haptic(.medium)
                                } label: {
                                        HStack {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundStyle(.blue)
                                            Text("Richiedi permessi")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Image(systemName: "arrow.right")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        }
                                        .padding(12)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.blue.opacity(0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                } else {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text("Permessi richiesti")
                                            .font(.subheadline)
                                .foregroundStyle(.white)
                                Spacer()
                                    }
                                    .padding(12)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
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
                                
                            // DEBUG: Slider probabilità slot
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "percent")
                                        .font(.title3)
                                        .foregroundStyle(.purple)
                                        .frame(width: 24)
                                    
                                    Text("Probabilità Vittoria")
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
                                
                                Text("Debug: 1% = normale, 50% = test facile")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(12)
                            .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            
                            SettingsNavRow(
                                title: "Reset Slot (Debug)",
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
                            SettingsSection(title: "Test Mood Sprites", icon: "theatermasks.fill") {
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
                        }

                        // MARK: - Info App
                        SettingsSection(title: "ℹ️ Informazioni", icon: "info.circle.fill") {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "app.badge")
                                        .font(.title3)
                                        .foregroundStyle(.cyan)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("El-PavoReal")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.white)
                                        Text("Versione 1.0 • Build TestFlight")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                }
                                
                                Divider()
                                    .background(.white.opacity(0.2))
                                
                                HStack {
                                    Image(systemName: "heart.fill")
                                        .font(.title3)
                                        .foregroundStyle(.pink)
                                        .frame(width: 24)
                                    
                                    Text("Con amore per il pavone")
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
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
