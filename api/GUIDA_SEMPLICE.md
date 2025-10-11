# 🎮 Guida Semplice: Come Modificare i Minigame

## 📋 Cosa Puoi Cambiare

### 1️⃣ **Emoji della Slot Machine**
```json
"icons": ["🦚", "🍸", "💎", "🎉", "🔥"]
```
Cambia con quello che vuoi! Esempi:
- **Natale**: `["🎄", "🎅", "⛄", "🎁", "⭐"]`
- **Halloween**: `["🎃", "👻", "🦇", "🕷️", "💀"]`
- **Estate**: `["☀️", "🏖️", "🍹", "🌴", "🌊"]`
- **Pavoreal**: `["🦚", "🍸", "💎", "🎉", "🔥"]` ✅ (attuale)

### 2️⃣ **Costo per Giocata**
```json
"bet_amount": 10
```
- `10` = costa 10 Pavo Lire per giocata (attuale)
- Puoi mettere `5`, `20`, `50`, etc.

### 3️⃣ **Premi**
```json
"jackpot_multiplier": 50,    // 3 simboli uguali = vinci 50x
"double_multiplier": 5,      // 2 simboli uguali = vinci 5x
"single_multiplier": 2       // 1 simbolo speciale = vinci 2x
```

Esempio: Se scommetti 10 Lire e fai jackpot (3 simboli):
- Vinci: 10 × 50 = **500 Pavo Lire!** 💰

### 4️⃣ **Quando è Attivo**
```json
"active_from": "2025-10-03",
"active_until": "2025-10-24"
```
Formato: `YYYY-MM-DD`

### 5️⃣ **Quali Serate**
```json
"event_numbers": [1, 2, 3]
```
- `[1]` = solo serata #1
- `[1, 2, 3]` = serate #1, #2, #3
- `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]` = prime 10 serate

---

## 🚀 Come Applicare le Modifiche

### **Step 1: Modifica il File**
```bash
# Apri il file
open /Users/simone/Desktop/El-PavoReal/api/minigames.json

# Oppure usa un editor di testo (TextEdit, VSCode, etc.)
```

### **Step 2: Salva e Fai Commit**
```bash
cd /Users/simone/Desktop/El-PavoReal
git add api/minigames.json
git commit -m "🎮 Update minigame config"
git push
```

### **Step 3: Aspetta 1-2 Minuti**
GitHub Pages pubblica automaticamente il file aggiornato.

### **Step 4: L'App si Aggiorna**
- **Automatico**: Entro 24 ore
- **Manuale**: Chiudi e riapri l'app

---

## 📱 Configurazioni Pronte

Ho creato 3 configurazioni pronte per te:

### **1. Solo Slot Machine (Sempre Attiva)**
File: `minigames_simple.json`
- Solo slot machine
- Attiva per tutte le serate
- Nessuna pausa

### **2. Alternare Attivo/Pausa**
File: `minigames_alternating.json`
- Settimana 1: Slot attiva ✅
- Settimana 2: Pausa 😴
- Settimana 3: Slot attiva ✅
- Settimana 4: Pausa 😴

### **3. Configurazione Attuale (Con Roulette e Gratta e Vinci)**
File: `minigames.json`
- Serate 1-3: Slot Machine
- Serate 4-6: Roulette (placeholder)
- Serata 7: Pausa
- Serate 8-10: Gratta e Vinci (placeholder)

---

## 🎯 Quale Vuoi Usare?

### **Per Usare "Solo Slot Machine":**
```bash
cd /Users/simone/Desktop/El-PavoReal/api
cp minigames_simple.json minigames.json
git add minigames.json
git commit -m "🎮 Use simple slot machine config"
git push
```

### **Per Usare "Alternata":**
```bash
cd /Users/simone/Desktop/El-PavoReal/api
cp minigames_alternating.json minigames.json
git add minigames.json
git commit -m "🎮 Use alternating config"
git push
```

### **Per Tenere Quella Attuale:**
Niente da fare! È già configurata ✅

---

## 🔥 Quick Tips

### **Cambiare Solo le Emoji (Veloce)**
1. Apri `minigames.json`
2. Cerca la riga con `"icons"`
3. Cambia le emoji
4. Salva, commit, push

### **Disabilitare Minigame Questa Settimana**
1. Trova il minigame con `"event_numbers": [X]` (X = numero serata corrente)
2. Cambia `"enabled": true` → `"enabled": false`
3. Salva, commit, push

### **Cambiare Date**
Usa il formato `YYYY-MM-DD`:
- `2025-10-03` = 3 ottobre 2025
- `2025-12-25` = 25 dicembre 2025 (Natale!)

---

## ❓ Quale Configurazione Vuoi?

Dimmi quale preferisci e te la attivo subito:

1. **Solo Slot Machine (sempre attiva)** ← Più semplice
2. **Alternata (1 sì, 1 no)**
3. **Attuale (con roulette/gratta e vinci futuri)**
4. **Custom (dimmi cosa vuoi e la creo)**

Oppure dimmi cosa vuoi modificare (emoji, prezzi, date, etc.) e ti aiuto! 🚀

