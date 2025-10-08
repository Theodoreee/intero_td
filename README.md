# intero_td

# 🏥 Plateforme Epitanie – TD1 MOS/NOS

Projet d’introduction au MOS/NOS pour le module santé.  
Ce projet met en place une base de données PostgreSQL avec un backend Node.js minimal permettant d’exécuter des requêtes `SELECT` sur le schéma MOS/NOS, et un front HTML simple pour naviguer dans les données.

---

## 🚀 Lancement rapide

### 1️⃣ Prérequis
- Node.js ≥ 18  
- PostgreSQL ≥ 15  
- (Optionnel) Docker si tu veux tout lancer sans installer Postgres

---

### 2️⃣ Démarrer la base de données

#### **Option A : avec Docker (recommandé)**
```bash
docker run --name pg-td1 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres \
  -p 5432:5432 -d postgres:16
```

Option B : avec PostgreSQL local

Assure-toi que le service est démarré :

```
sudo systemctl start postgresql
```

et que tu peux te connecter :

```
psql -h 127.0.0.1 -U postgres -c "SELECT version();"
```

### 3️⃣ Lancer le serveur backend

Installe les dépendances :

```
cd backend
npm install
```

Lance le serveur :

```
DB_HOST=127.0.0.1 \
DB_USER=postgres \
DB_PASS=postgres \
DB_NAME=epitanie \
DB_SCHEMA_FILE=./db.sql \
node server.js
```

💡 Le serveur :
    
    crée la base si elle n’existe pas,
    applique automatiquement le schéma MOS/NOS,
    démarre l’API sur http://localhost:5000/api/sql

### 4️⃣ Tester une requête

Dans un terminal :

```
curl -X POST http://localhost:5000/api/sql \
  -H "Content-Type: application/json" \
  -d '{"sql":"SELECT id, nom, prenom FROM patient LIMIT 5;"}'
  ```

### 5️⃣ Lancer le front (SQL viewer)

Ouvre simplement le fichier :

```
frontend/index.html
```

dans ton navigateur.

Tu pourras taper une requête SQL (SELECT …) et voir le résultat sous forme de tableau.

### 🗂️ Structure du projet

```
epitanie-td1/
├─ backend/
│  ├─ server.js         # API Node.js (Express + Postgres)
│  ├─ db.sql            # Schéma MOS/NOS complet + seeds
│  ├─ package.json
│  └─ .gitignore
│
└─ frontend/
   └─ index.html        # Interface minimaliste pour exécuter des requêtes
```

### 🧹 Commandes utiles

Nettoyer les conteneurs Docker :

```
docker rm -f $(docker ps -aq)
docker system prune -a --volumes -f
```

Réinitialiser la base :

```
psql -h 127.0.0.1 -U postgres -c "DROP DATABASE IF EXISTS epitanie;"
```

## Auteur : Théodore Vaunois - Timothée Viossat

EPITA – TD MOS/NOS 2025

