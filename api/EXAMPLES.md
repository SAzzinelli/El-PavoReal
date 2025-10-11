# 🎮 Esempi di Configurazione Minigame

## 📋 Template Base

```json
{
  "version": 1,
  "last_updated": "2025-10-11T10:00:00Z",
  "minigames": [
    // Aggiungi qui i tuoi minigame
  ]
}
```

## 🎰 Slot Machine

```json
{
  "id": "slot_machine_v1",
  "title": "Slot Machine Pavo",
  "subtitle": "Gira e vinci Pavo Lire!",
  "active_from": "2025-10-03",
  "active_until": "2025-10-24",
  "enabled": true,
  "event_numbers": [1, 2, 3],
  "type": "slot_machine",
  "config": {
    "icons": ["🍋", "🍊", "🍇", "🍒", "💎"],
    "bet_amount": 10,
    "jackpot_multiplier": 50,
    "double_multiplier": 5,
    "single_multiplier": 2
  }
}
```

**Parametri Slot Machine:**
- `icons`: Array di emoji per i simboli della slot
- `bet_amount`: Costo per giocata in Pavo Lire
- `jackpot_multiplier`: Moltiplicatore per 3 simboli uguali
- `double_multiplier`: Moltiplicatore per 2 simboli uguali
- `single_multiplier`: Moltiplicatore per 1 simbolo speciale

## 🎲 Roulette

```json
{
  "id": "roulette_v1",
  "title": "Roulette Pavo",
  "subtitle": "Scegli il tuo numero fortunato!",
  "active_from": "2025-10-25",
  "active_until": "2025-11-14",
  "enabled": true,
  "event_numbers": [4, 5, 6],
  "type": "roulette",
  "config": {
    "min_bet": 5,
    "max_bet": 100,
    "payout_multiplier": 35
  }
}
```

**Parametri Roulette:**
- `min_bet`: Puntata minima in Pavo Lire
- `max_bet`: Puntata massima in Pavo Lire
- `payout_multiplier`: Moltiplicatore per numero vincente (tipicamente 35x)

## 🎫 Gratta e Vinci

```json
{
  "id": "scratch_card_v1",
  "title": "Gratta e Vinci Pavo",
  "subtitle": "Gratta le carte e scopri i premi!",
  "active_from": "2025-11-22",
  "active_until": "2025-12-12",
  "enabled": true,
  "event_numbers": [8, 9, 10],
  "type": "scratch_card",
  "config": {
    "card_cost": 20,
    "prizes": [0, 10, 50, 100, 500]
  }
}
```

**Parametri Scratch Card:**
- `card_cost`: Costo della carta in Pavo Lire
- `prizes`: Array di possibili premi (0 = perdi)

## 🚫 Nessun Minigame (Pausa)

```json
{
  "id": "no_game_break",
  "title": null,
  "subtitle": null,
  "active_from": "2025-11-15",
  "active_until": "2025-11-21",
  "enabled": false,
  "event_numbers": [7],
  "type": "none",
  "config": {}
}
```

**Quando usare:**
- Settimane di pausa
- Manutenzione
- Eventi speciali senza minigame
- Testing

## 📅 Calcolo Event Numbers

H-ZOO #1 = 3 ottobre 2025 (venerdì)
H-ZOO #2 = 10 ottobre 2025 (venerdì successivo)
H-ZOO #3 = 17 ottobre 2025
...e così via.

**Ogni venerdì incrementa di 1.**

### Esempio: Ottobre 2025
- #1: 3 ottobre (prima serata)
- #2: 10 ottobre
- #3: 17 ottobre
- #4: 24 ottobre
- #5: 31 ottobre

### Esempio: Novembre 2025
- #5: 31 ottobre (ultimo venerdì ottobre)
- #6: 7 novembre
- #7: 14 novembre
- #8: 21 novembre
- #9: 28 novembre

## 🔄 Scenari Comuni

### 1. Stesso Minigame per 3 Settimane
```json
{
  "event_numbers": [1, 2, 3],
  "active_from": "2025-10-03",
  "active_until": "2025-10-24"
}
```

### 2. Alternare Minigame Ogni Settimana
```json
[
  {
    "id": "slot_week_1",
    "event_numbers": [1],
    "active_from": "2025-10-03",
    "active_until": "2025-10-09",
    "type": "slot_machine"
  },
  {
    "id": "roulette_week_2",
    "event_numbers": [2],
    "active_from": "2025-10-10",
    "active_until": "2025-10-16",
    "type": "roulette"
  }
]
```

### 3. Una Serata Sì, Una No
```json
[
  {
    "id": "slot_active",
    "event_numbers": [1, 3, 5, 7],
    "type": "slot_machine",
    "enabled": true
  },
  {
    "id": "pause",
    "event_numbers": [2, 4, 6, 8],
    "type": "none",
    "enabled": false
  }
]
```

### 4. Minigame Stagionale
```json
{
  "id": "halloween_special",
  "title": "Halloween Slot 🎃",
  "event_numbers": [5],
  "active_from": "2025-10-31",
  "active_until": "2025-11-06",
  "type": "slot_machine",
  "config": {
    "icons": ["🎃", "👻", "🦇", "🕷️", "💀"]
  }
}
```

## ⚠️ Best Practices

1. **Incrementa sempre `version`** quando fai modifiche importanti
2. **Usa ID univoci** per ogni minigame (es. `slot_v1`, `slot_v2`)
3. **Non sovrapporre `event_numbers`** tra minigame diversi
4. **Testa il JSON** con un validator prima del push
5. **Aggiorna `last_updated`** con timestamp corrente
6. **Mantieni backup** delle configurazioni precedenti

## 🧪 Test del JSON

Prima di fare push, valida il JSON:
```bash
python3 -m json.tool api/minigames.json
```

Oppure online: https://jsonlint.com/

## 📊 Monitoraggio

Nei log dell'app vedrai:
```
🎮 MinigameManager: Fetching da https://...
✅ MinigameManager: Config aggiornata (v1)
🎮 Minigame attivo: Slot Machine Pavo (tipo: slot_machine)
```

In caso di errori:
```
❌ MinigameManager: Errore fetch - ...
❌ MinigameManager: Parsing fallito - ...
```

