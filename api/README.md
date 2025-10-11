# 🎮 Minigames API

Questa cartella contiene la configurazione dinamica dei minigame per l'app El-PavoReal.

## 📡 URL Pubblico

Una volta attivato GitHub Pages, il JSON sarà accessibile a:
```
https://<tuo-username>.github.io/El-PavoReal/api/minigames.json
```

## 📝 Struttura JSON

### Campi Principali
- `version`: Versione del formato (per retrocompatibilità)
- `last_updated`: Timestamp ultimo aggiornamento
- `minigames`: Array di configurazioni minigame

### Configurazione Minigame
- `id`: Identificatore unico
- `title`: Nome del minigame (null se disabilitato)
- `subtitle`: Descrizione breve
- `active_from`: Data inizio (YYYY-MM-DD)
- `active_until`: Data fine (YYYY-MM-DD)
- `enabled`: true/false
- `event_numbers`: Array numeri H-ZOO (es. [1, 2, 3])
- `type`: Tipo minigame (`slot_machine`, `roulette`, `scratch_card`, `none`)
- `config`: Configurazione specifica del minigame

## 🔄 Come Aggiornare

1. Modifica `minigames.json`
2. Commit e push
3. L'app aggiornerà automaticamente al prossimo fetch (ogni 24h o all'avvio)

## 📅 Esempio: Disabilitare Minigame per una Settimana

```json
{
  "id": "no_game_week",
  "title": null,
  "enabled": false,
  "active_from": "2025-11-15",
  "active_until": "2025-11-21",
  "event_numbers": [7],
  "type": "none"
}
```

## 🎯 Tipi Minigame Disponibili

- `slot_machine`: Slot machine classica
- `roulette`: Roulette numerica
- `scratch_card`: Gratta e vinci
- `none`: Nessun minigame (settimana di pausa)

