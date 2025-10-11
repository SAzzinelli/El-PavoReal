# 🦩 H-ZOO — El-PavoReal v6.0 - TestFlight Release

## ✨ **NOVITÀ PRINCIPALI**

### 🦩 **App H-ZOO Completa - Nuove Tab Attive!**

L'app ora include **3 tab completamente funzionanti**:

#### 1️⃣ **H-ZOO Home** — Countdown & Info Serata
- **Countdown intelligente** al prossimo venerdì alle 23:00 (timezone Europe/Rome)
- Stati dinamici:
  - **Countdown normale**: giorni, ore, minuti, secondi al prossimo evento
  - **Serata in corso**: quando è venerdì 23:00 - sabato 05:00
  - **Badge omaggio donna**: timer dedicato fino alle 00:30 del sabato
- Info prezzi completa: uomo, donna, guardaroba, drink
- KPI opzionali: ora di picco, occupazione, tavoli rimasti, meteo
- Quick actions: prenota, info prezzi, come arrivare (Apple Maps)
- Collegamenti social: telefono, WhatsApp, Instagram

#### 2️⃣ **Prenota Tavolo** — Sistema Prenotazione
- Form prenotazione tavolo completo
- Condizioni ingresso chiare e dettagliate
- CTA principale "Prenota Ora" → Coming Soon view
- Contatti diretti: chiamata e WhatsApp precompilato
- House rules: 18+, dress code, selezione ingresso
- Display tavoli rimasti (se configurato)

#### 3️⃣ **Minigame** — Il Gioco del Pavone (invariato)
- Tutto il sistema di gioco precedente rimane attivo
- Slot machine, mood sprites, shop, achievements
- PavoLire system, long press actions
- Tutorial e settings completi

---

### 🎨 **Stile Dark/Neon Club**
- Palette notturna: sfondo #0b0b0c
- Colori neon: fucsia #ff2d95 (primario), cyan #00ffd1 (accento)
- Card con blur/glass effect e bordi subtle
- Micro-animazioni sobrie (pulse, fade, scale)
- Supporto completo Dynamic Type e VoiceOver

---

### ⚙️ **Sistema di Configurazione Centralizzato**
Tutti i parametri H-ZOO configurabili da un'unica sezione `HZooConfig`:
- Info evento (nome, luogo, orari)
- Prezzi (uomo, donna, guardaroba, drink)
- Contatti (telefono, WhatsApp, Instagram)
- KPI opzionali (picco, occupazione, tavoli, meteo)
- Palette colori
- Timezone Europe/Rome con gestione ora legale

---

### 🕐 **Logica Countdown Intelligente**

Il countdown rispetta perfettamente il timezone Europe/Rome:
- **Lunedì-Giovedì**: countdown al prossimo venerdì 23:00
- **Venerdì prima delle 23:00**: countdown a oggi 23:00
- **Venerdì dopo le 23:00**: stato "serata in corso" + countdown al prossimo venerdì
- **Sabato 00:00-00:30**: badge "omaggio donna scade tra XX:XX"
- **Sabato 00:31-05:00**: solo "serata in corso" (badge omaggio sparito)
- **Sabato dopo le 05:00**: torna al countdown per venerdì prossimo
- **Riallineamento automatico** quando l'app torna in foreground (no drift)

---

### 📱 **Funzionalità Link Esterni**
- **Telefono**: tap-to-call con numero configurabile
- **WhatsApp**: link con testo precompilato ("Vorrei prenotare un tavolo H-ZOO...")
- **Instagram**: apertura profilo
- **Apple Maps**: navigazione verso il locale

---

## 🎮 **COSA C'È DI NUOVO (v5.0 - Minigame)**

### ✨ **Nuove Funzionalità Principali**

#### 🎰 **Slot Machine Giornaliera**
- 10 tentativi al giorno per vincere una **maglietta fisica** El-PavoReal!
- QR code reale generato alla vittoria (ritirabile in cassa)
- Probabilità di vincita: 1% (personalizzabile in debug)
- Animazione fluida dei 3 rulli
- Reset automatico ogni giorno alle 00:00

#### 🎨 **Sprite Dinamici per Mood**
Il tuo pavone cambia aspetto in base all'umore:
- 😊 **Felice** - Tutto va alla grande
- 😢 **Triste** - Statistiche critiche
- 😡 **Arrabbiato** - Troppe azioni negative
- 😴 **Assonnato** - Bassa energia
- 😐 **Annoiato** - Scarsa felicità
- 😶 **Neutro** - Stato normale

#### 💰 **Sistema PavoLire Espanso**
- Info sheet dedicata con guide e consigli
- Badge cliccabile con gradiente blu/cyan
- 15 achievement legati alle PavoLire
- Sistema di guadagno offline migliorato

#### 🎯 **Long Press Quick Actions**
Tieni premuto i bottoni principali per azioni rapide:
- **Bevuta** → Scegli tra Gin Tonic, Vodka Lemon, Negroni, Acqua
- **Shot** → Tequila, Jägerbomb, Sambuca, Rum e Lime
- **Rilassati** → Respiro, Stretching, Pausa, Reset
- **SIGLA!** → Pista, Canta, Giro, Selfie

---

### 🛠️ **Miglioramenti**

#### **UI/UX**
- 🎨 Splash screen animato con logo El-PavoReal
- 🌈 Gradiente PavoLire cambiato da verde a blu
- 💫 Animazione pulsazione leggera sul personaggio
- 🎯 Icone Shop/Eventi/Settings con sfondo circolare subtle
- 📱 Titolo "Negozio" in stile iOS nativo (grande, bold, sinistra)

#### **Shop**
- 🛒 40+ item disponibili
- 🎨 Colori corretti per categoria:
  - Energia (Drink) → Rosa/Viola
  - Sazietà (Food) → Verde/Menta
  - Felicità (Eventi) → Giallo/Arancio
  - Chill (Servizi) → Blu/Cyan
  - Booster → Viola/Rosa
- 🔍 Barra di ricerca integrata

#### **Settings**
- 🎛️ Design moderno con sezioni organizzate
- 🐛 Debug slider per probabilità slot (0.01 - 0.50)
- 🧪 Test mood sprites in-app
- 🔄 Reset slot e statistiche debug

#### **Performance**
- ⚡ Decadimento ottimizzato (Sete/Chill: ~30 min, Energia: ~36 min in foreground)
- 🕐 Tracking background migliorato
- 💾 Persistenza affidabile con UserDefaults
- 🔔 Notifiche background più intelligenti

---

### 🐛 **Bug Fix**

- ✅ Colori Chill corretti ovunque (blu/cyan)
- ✅ Long press ora rispetta cooldown (no azioni duplicate)
- ✅ Alert duplicati rimossi (level up, evolution)
- ✅ PavoLire alerts con colori corretti
- ✅ Shop item colors coerenti con categorie
- ✅ Asset catalog warnings risolti
- ✅ Crash build errors risolti
- ✅ Titolo "Negozio" sopra search bar

---

### 📐 **Architettura**

#### **Struttura Multi-Tab** (Preparata per espansione futura)
1. **🏠 Home** - Info locale, KPI, presentazione *(disabilitata temporaneamente)*
2. **🦩 H-ZOO** - Serata del venerdì, eventi, merch *(disabilitata temporaneamente)*
3. **🎮 Minigame** - Gioco del pavone **ATTIVO**

#### **Codice Organizzato**
- Struttura MVVM pulita
- Componenti riutilizzabili
- Extensions per logica complessa
- MARK sections per navigazione rapida

---

## 🎯 **Come Testare**

### **Priorità Massima (Nuove Funzionalità v6.0):**

#### 🦩 **H-ZOO Home Tab**
1. Apri l'app → verifica che parta sulla tab "H-ZOO"
2. Controlla il countdown:
   - Se non è venerdì: deve mostrare giorni/ore/minuti/secondi al prossimo venerdì 23:00
   - La data sotto deve essere corretta (es. "Ven 17 Ott · 23:00")
3. Verifica quick actions:
   - Tap "Prenota" → deve aprire la tab Prenota in sheet
   - Tap "Arrivo" → deve aprire Apple Maps
4. Controlla i KPI (se visibili):
   - Ora di picco, occupazione, tavoli rimasti, meteo
5. Tap sui social buttons (telefono/WhatsApp/Instagram)
6. **Accessibility**: attiva VoiceOver e verifica che il countdown sia leggibile

#### 📅 **Prenota Tab**
1. Vai alla tab "Prenota" (seconda)
2. Verifica prezzi e condizioni
3. Tap "Prenota Ora" → deve apparire la Coming Soon view
4. Dalla Coming Soon, tap WhatsApp → verifica testo precompilato
5. Tap "Chiama" → verifica numero telefono
6. Chiudi la Coming Soon e torna indietro
7. Prova i bottoni "Chiama" e "WhatsApp" diretti

#### 🕐 **Test Countdown Stati Speciali** (importante!)
Per testare completamente, modifica temporaneamente l'orario del sistema:
1. **Venerdì ore 22:00** → countdown deve puntare a oggi 23:00
2. **Venerdì ore 23:15** → deve mostrare "SERATA IN CORSO" + badge omaggio donna
3. **Sabato ore 00:15** → "SERATA IN CORSO" + badge omaggio (scade tra ~15min)
4. **Sabato ore 00:35** → "SERATA IN CORSO" senza badge omaggio
5. **Sabato ore 05:30** → countdown al venerdì successivo
6. **Background test**: chiudi l'app, aspetta 10s, riapri → countdown deve riallinearsi

---

### **Priorità Alta (Minigame v5.0):**
1. 🎰 **Slot Machine**
   - Vai in Settings → Reset Slot (Debug)
   - Torna al gioco → Footer → "Slot Machine!"
   - Gira i rulli 10 volte
   - Verifica che al win appaia il QR code

2. 🎨 **Mood Sprites**
   - Vai in Settings → Test Mood Sprites
   - Prova tutti i mood e verifica che lo sprite cambi
   - Torna al gioco e gioca normalmente
   - Verifica cambio automatico mood

3. 🎯 **Long Press Quick Actions**
   - Tieni premuto "Bevuta" (disponibile)
   - Scegli un'opzione dal menu
   - Aspetta cooldown (5 min)
   - Riprova long press → deve dare haptic heavy e STOP
   - Riprova dal menu → deve bloccarsi e NON dare premi

### **Priorità Media:**
4. 💰 **PavoLire System**
   - Clicca sul badge PavoLire in alto
   - Leggi info sheet
   - Compra item nello shop
   - Verifica guadagno offline

5. 🛒 **Shop**
   - Cerca "Chill" nella barra
   - Verifica colori BLU/CYAN per tutti item Chill
   - Prova altri item e verifica colori categoria

### **Priorità Bassa:**
6. 🏆 **Achievements & Eventi**
7. ⚙️ **Settings & Debug Tools**
8. 📚 **Tutorial**

---

## 🐛 **Bug Noti**

Nessuno al momento! 🎉

---

## 🔜 **Prossime Versioni**

- 🦚 Tab "El Pavo-Real" (Info locale, eventi, gallery)
- 🦩 Tab "H-ZOO" (Serata venerdì, regole ingresso, countdown)
- 📸 Gallery foto integrate
- 🎫 Sistema prenotazioni
- 👥 Profilo utente e badge fedeltà
- 🗺️ Mappa locale

---

## 📊 **Statistiche Sviluppo**

- **Righe di codice:** ~8,300
- **File Swift:** 2 (ContentView, Splash)
- **Assets:** 15+ imagesets
- **Features:** 20+
- **Tempo sviluppo:** 2 sessioni intensive

---

## 🙏 **Feedback Richiesto**

1. La slot machine è divertente? Probabilità ok?
2. I mood sprites sono chiari e riconoscibili?
3. Long press è intuitivo o serve tutorial?
4. Shop è facile da navigare?
5. Colori delle stat sono coerenti?
6. Performance su device fisico?

---

## 📱 **Info Build**

- **Versione:** 6.0
- **Build:** 1
- **Target iOS:** 18.0+
- **Dispositivi:** iPhone, iPad
- **Orientamento:** Portrait
- **Novità v6.0:** 3 tab attive (H-ZOO Home, Prenota, Minigame)
- **Timezone:** Europe/Rome con gestione automatica ora legale

---

**Grazie per il testing! 🎉**

*Sviluppato con ❤️ per El-PavoReal*





