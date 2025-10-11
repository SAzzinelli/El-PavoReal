# 🎯 Guida: Giochi della Serata

## 📋 Cos'è?

I **Giochi della Serata** sono eventi fisici che organizzi ogni venerdì (beer pong, tiro con l'arco, karaoke, ecc.).

L'app mostra automaticamente il gioco giusto in base alla serata H-ZOO!

---

## 🎮 Configurazione Attuale

| Serata | Gioco | Orario | Location | Premio |
|--------|-------|--------|----------|--------|
| #1 | Beer Pong 🍺 | 23:30 | Area Gaming | Drink gratis |
| #2 | Tiro con l'Arco 🎯 | 00:00 | Zona Outdoor | Shot + badge IG |
| #3 | Halloween Challenge 🎃 | 23:45 | Main Floor | Bottiglia omaggio |
| #4 | Karaoke Battle 🎤 | 00:30 | Stage Principale | Playlist + drink |
| #5 | Limbo Contest 🕺 | 01:00 | Dance Floor | Ingresso gratis prossima serata |

---

## ✏️ Come Modificare

### **1. Cambiare un Gioco Esistente**

Apri `api/minigames.json` e modifica la sezione `event_games`:

```json
{
  "id": "beerpong_week1",
  "title": "Beer Pong 🍺",
  "description": "Sfida i tuoi amici al classico beer pong!",
  "icon": "🍺",
  "event_numbers": [1],
  "prizes": "Drink gratis per il vincitore",
  "start_time": "23:30",
  "location": "Area Gaming"
}
```

**Campi modificabili:**
- `title`: Nome del gioco con emoji
- `description`: Descrizione breve (1-2 righe)
- `icon`: Emoji principale (apparirà grande nella card)
- `event_numbers`: Numeri serate (es. `[1]` = serata #1, `[2, 3]` = serate #2 e #3)
- `prizes`: Premio per il vincitore
- `start_time`: Orario inizio (formato 24h, es. "23:30")
- `location`: Dove si svolge

---

## 🎨 Idee Giochi

### 🍺 Classici
- Beer Pong
- Flip Cup
- Kings Cup
- Quarters

### 🎯 Skill-Based
- Tiro con l'Arco
- Freccette
- Tiro al canestro
- Mini Golf

### 🎤 Performance
- Karaoke
- Ballo Limbo
- Gara di ballo
- Lip Sync Battle

### 🎃 A Tema
- Halloween: Escape Room horror, costume contest
- Natale: Secret Santa, ugly sweater contest
- Estate: Water games, beach volley

### 🎲 Random
- Roulette della Fortuna
- Bingo
- Tombola
- Scavenger Hunt

---

## 📅 Esempi Pratici

### **Aggiungere un Nuovo Gioco per Serata #6**

```json
{
  "id": "flip_cup_week6",
  "title": "Flip Cup Tournament 🥤",
  "description": "Gara a squadre: bevi e gira il bicchiere!",
  "icon": "🥤",
  "event_numbers": [6],
  "prizes": "Bottiglia premium tavolo vincitore",
  "start_time": "00:15",
  "location": "Bar Area"
}
```

### **Stesso Gioco per 2 Settimane**

```json
{
  "id": "beer_pong_weeks_7_8",
  "title": "Beer Pong Championship 🏆",
  "description": "Torneo su 2 settimane con finale!",
  "icon": "🏆",
  "event_numbers": [7, 8],
  "prizes": "Gran premio finale + foto sul profilo IG",
  "start_time": "23:30",
  "location": "Area Gaming"
}
```

### **Evento Speciale Halloween**

```json
{
  "id": "halloween_special",
  "title": "Costume Contest 🎃👻",
  "description": "Miglior costume vince premi esclusivi!",
  "icon": "🎃",
  "event_numbers": [5],
  "prizes": "Ingresso omaggio x2 + tavolo riservato",
  "start_time": "00:00",
  "location": "Main Stage"
}
```

### **Nessun Gioco Questa Settimana**

Semplicemente non aggiungere quella serata nei `event_numbers` o rimuovi il blocco JSON.

---

## 🎯 Template Vuoto

Copia e compila:

```json
{
  "id": "NOME_UNIVOCO",
  "title": "NOME GIOCO + EMOJI",
  "description": "Descrizione breve del gioco",
  "icon": "EMOJI",
  "event_numbers": [NUMERO_SERATA],
  "prizes": "Cosa vince il vincitore",
  "start_time": "HH:MM",
  "location": "Dove si svolge"
}
```

---

## 🔄 Come Applicare le Modifiche

### **Step 1: Modifica il JSON**
```bash
open /Users/simone/Desktop/El-PavoReal/api/minigames.json
```

### **Step 2: Salva e Pubblica**
```bash
cd /Users/simone/Desktop/El-PavoReal
git add api/minigames.json
git commit -m "🎯 Update giochi serata"
git push
```

### **Step 3: L'App Si Aggiorna**
- Automaticamente entro 24h
- O chiudi/riapri l'app per forzare il refresh

---

## 🎨 Emoji Consigliate

### Sport & Giochi
🍺 🥤 🎯 🏹 🎱 🎲 🃏 🎰 🏀 ⚽ 🏐 🎳

### Musica & Performance
🎤 🎸 🎹 🎵 🎶 🎭 💃 🕺

### Feste & Celebrazioni
🎉 🎊 🎈 🎁 🎂 🍾 🥂 🍻

### Temi Stagionali
🎃 👻 🦇 (Halloween)
🎄 🎅 ⛄ (Natale)
🌴 ☀️ 🏖️ (Estate)
💘 💝 (San Valentino)

### Premi & Vincite
🏆 🥇 🥈 🥉 👑 💎 ⭐

---

## 📱 Come Appare nell'App

La card del gioco mostra:

```
┌─────────────────────────────────────────┐
│  🍺                GIOCO DELLA SERATA    │
│                   Beer Pong 🍺           │
│                                          │
│  Sfida i tuoi amici al beer pong!       │
│                                          │
│  🕐 Orario:  23:30                      │
│  📍 Dove:     Area Gaming               │
│  🏆 Premio:   Drink gratis              │
└─────────────────────────────────────────┘
```

---

## ❓ FAQ

### **Posso avere più giochi nella stessa serata?**
Sì! Basta creare 2 entry con lo stesso `event_numbers`:
```json
[
  { "id": "game1", "event_numbers": [1], ... },
  { "id": "game2", "event_numbers": [1], ... }
]
```
Ma attualmente l'app mostra solo **il primo** trovato. Se serve, posso aggiungere uno slider per mostrarne multipli.

### **Posso programmare giochi per 10 settimane in anticipo?**
Sì! Aggiungi tutti i giochi che vuoi, l'app mostrerà automaticamente quello giusto.

### **Posso modificare il JSON mentre la serata è in corso?**
Sì! Gli utenti vedranno le modifiche entro pochi minuti (o al prossimo refresh dell'app).

### **Cosa succede se dimentico di configurare una serata?**
Nessun problema! La card semplicemente non apparirà nell'app.

---

## 🚀 Pronto ad Usarlo!

1. ✅ JSON configurato con 5 giochi di esempio
2. ✅ Card stilizzata nell'app
3. ✅ Aggiornamento automatico
4. ✅ Sistema pronto per infinite serate

**Modifica `api/minigames.json` e fai push per cambiare i giochi!** 🎮

