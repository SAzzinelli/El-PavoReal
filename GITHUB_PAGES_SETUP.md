# 🚀 Setup GitHub Pages per Minigame Dinamici

## 📋 Prerequisiti
- Repository GitHub esistente: `El-PavoReal`
- File `api/minigames.json` già creato

## 🔧 Step 1: Attiva GitHub Pages

1. Vai su GitHub.com → tua repository `El-PavoReal`
2. Click su **Settings** (⚙️)
3. Nel menu laterale sinistro, click su **Pages**
4. Sotto **Source**, seleziona:
   - Branch: `main` (o `master`)
   - Folder: `/ (root)`
5. Click su **Save**
6. Aspetta 1-2 minuti, poi ricarica la pagina
7. Dovresti vedere: "Your site is published at `https://<username>.github.io/El-PavoReal/`"

## 📝 Step 2: Aggiorna URL nel Codice

Apri il file `El-PavoReal/ContentView.swift` e cerca questa riga (circa riga 109):

```swift
private let remoteURL = "https://<TUO-USERNAME>.github.io/El-PavoReal/api/minigames.json"
```

**Sostituisci `<TUO-USERNAME>` con il tuo username GitHub.**

Esempio:
```swift
private let remoteURL = "https://simoneazzinelli.github.io/El-PavoReal/api/minigames.json"
```

## ✅ Step 3: Commit e Push

```bash
cd /Users/simone/Desktop/El-PavoReal
git add api/
git add El-PavoReal/ContentView.swift
git add El-PavoReal/El-PavoReal.swift
git commit -m "✨ Add dynamic minigames system with GitHub Pages"
git push origin main
```

## 🧪 Step 4: Testa il JSON

Dopo 1-2 minuti dal push, apri nel browser:
```
https://<tuo-username>.github.io/El-PavoReal/api/minigames.json
```

Dovresti vedere il JSON con i minigame configurati.

## 📱 Step 5: Testa l'App

1. Rebuilda l'app con Xcode
2. Lancia l'app su simulatore/device
3. Controlla i log della console:
   - ✅ `🎮 MinigameManager: Fetching da https://...`
   - ✅ `✅ MinigameManager: Config aggiornata (v1)`
   - ✅ `🎮 Minigame attivo: Slot Machine Pavo (tipo: slot_machine)`

4. Vai sulla tab **Minigame**
5. Dovresti vedere il minigame attivo (slot machine per le prime 3 serate)

## 🔄 Come Aggiornare i Minigame

1. Modifica `api/minigames.json` localmente
2. Cambia date, aggiungi nuovi minigame, o disabilita settimane
3. Commit e push:
   ```bash
   git add api/minigames.json
   git commit -m "🎮 Update minigames config"
   git push
   ```
4. L'app aggiornerà automaticamente al prossimo fetch (max 24h)

## 🎯 Esempi di Configurazione

### Disabilitare minigame per 1 settimana
```json
{
  "id": "no_game_week5",
  "title": null,
  "subtitle": null,
  "active_from": "2025-10-31",
  "active_until": "2025-11-06",
  "enabled": false,
  "event_numbers": [5],
  "type": "none",
  "config": {}
}
```

### Aggiungere nuova roulette
```json
{
  "id": "roulette_v1",
  "title": "Roulette Pavo",
  "subtitle": "Scegli il tuo numero fortunato!",
  "active_from": "2025-11-07",
  "active_until": "2025-11-27",
  "enabled": true,
  "event_numbers": [6, 7, 8],
  "type": "roulette",
  "config": {
    "min_bet": 5,
    "max_bet": 100,
    "payout_multiplier": 35
  }
}
```

## 🐛 Troubleshooting

### ❌ App non carica il JSON
- Verifica che GitHub Pages sia attivo
- Controlla che l'URL nel codice sia corretto (username, branch)
- Aspetta 2-3 minuti dopo il push per la pubblicazione
- Prova a forzare il refresh: `MinigameManager.shared.forceRefresh()` nelle impostazioni

### ❌ JSON non si aggiorna nell'app
- Cache 24h: aspetta o forza refresh
- Verifica che `version` sia incrementato nel JSON
- Controlla i log della console per errori di parsing

### ❌ Minigame sbagliato mostrato
- Verifica che `event_numbers` corrisponda alla settimana corrente
- Controlla la data `active_from` / `active_until`
- Debug: stampa `HZooConfig.eventNumber(for: Date())` per vedere il numero evento corrente

## 🎉 Fatto!

Ora hai un sistema di minigame dinamici completamente funzionante:
- ✅ JSON remoto su GitHub Pages (gratis)
- ✅ Cache locale con fallback offline
- ✅ Aggiornamento automatico ogni 24h
- ✅ Routing dinamico tra slot machine, roulette, scratch card, no-game
- ✅ Gestione settimane di pausa
- ✅ Controllo totale senza rebuild dell'app

Quando vuoi cambiare minigame, modifica solo il JSON e fai push! 🚀

