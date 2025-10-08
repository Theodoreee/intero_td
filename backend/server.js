// npm i express cors pg
const express = require("express");
const cors = require("cors");
const { Client, Pool } = require("pg");
const fs = require("fs");
const path = require("path");

// ---------- Config ----------
const DB_HOST = process.env.DB_HOST || "127.0.0.1";
const DB_PORT = +(process.env.DB_PORT || 5432);
const DB_USER = process.env.DB_USER || "postgres";
const DB_PASS = process.env.DB_PASS || "postgres";
const DB_NAME = process.env.DB_NAME || "db";
const SCHEMA_FILE = process.env.DB_SCHEMA_FILE || path.resolve(__dirname, "db.sql");
const API_PORT = +(process.env.PORT || 5000);

// Connexions "admin" (db=postgres) et "app" (db=epitanie)
const adminConfig = { host: DB_HOST, port: DB_PORT, user: DB_USER, password: DB_PASS, database: "postgres" };
const appConfig = { host: DB_HOST, port: DB_PORT, user: DB_USER, password: DB_PASS, database: DB_NAME };

// ---------- Helpers démarrage ----------
async function waitForPostgres(timeoutMs = 20000, intervalMs = 500) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        try {
            const c = new Client(adminConfig);
            await c.connect();
            await c.query("SELECT 1");
            await c.end();
            return;
        } catch (e) {
            await new Promise(r => setTimeout(r, intervalMs));
        }
    }
    throw new Error("PostgreSQL injoignable (timeout). Vérifie service/ports/MDP.");
}

async function ensureDatabase() {
    // 1) create DB if not exists
    const admin = new Client(adminConfig);
    await admin.connect();
    const exists = await admin.query("SELECT 1 FROM pg_database WHERE datname=$1", [DB_NAME]);
    if (exists.rowCount === 0) {
        console.log(`Création de la base ${DB_NAME}…`);
        await admin.query(`CREATE DATABASE ${DB_NAME}`);
    }
    await admin.end();

    // 2) apply schema if first time (idempotent)
    const app = new Client(appConfig);
    await app.connect();

    // marqueur simple pour éviter de ré-appliquer
    await app.query(`
    CREATE TABLE IF NOT EXISTS _td1_schema_applied (
      id boolean PRIMARY KEY DEFAULT TRUE,
      applied_at timestamptz NOT NULL DEFAULT now()
    );
  `);

    const applied = await app.query("SELECT 1 FROM _td1_schema_applied LIMIT 1");
    if (applied.rowCount === 0) {
        if (!fs.existsSync(SCHEMA_FILE)) {
            throw new Error(`Fichier de schéma introuvable: ${SCHEMA_FILE}`);
        }
        const sql = fs.readFileSync(SCHEMA_FILE, "utf8");
        console.log("→ Application du schéma MOS/NOS + seeds…");
        await app.query(sql);
        await app.query("INSERT INTO _td1_schema_applied(id) VALUES (TRUE)");
        console.log("Schéma appliqué.");
    } else {
        console.log("Schéma déjà appliqué (skip).");
    }
    await app.end();
}

async function start() {
    console.log("Attente PostgreSQL…");
    await waitForPostgres();
    await ensureDatabase();

    // Pool appli (DB_NAME)
    const pool = new Pool(appConfig);

    // ---------- API ----------
    const app = express();
    app.use(cors());
    app.use(express.json());

    // SELECT-only endpoint
    app.post("/api/sql", async (req, res) => {
        const sql = String(req.body?.sql || "");
        if (!/^\s*select\b/i.test(sql)) {
            return res.status(400).json({ error: "Uniquement des requêtes SELECT autorisées." });
        }
        try {
            const { rows } = await pool.query(sql);
            res.json({ rows });
        } catch (err) {
            res.status(400).json({ error: err.message });
        }
    });

    app.get("/", (_req, res) => {
        res.send(`<h2>Epitanie TD1 API</h2><p>POST /api/sql { "sql": "SELECT * FROM patient;" }</p>`);
    });

    app.listen(API_PORT, () => {
        console.log(`API prête sur http://localhost:${API_PORT}/api/sql`);
    });
}

start().catch(err => {
    console.error("Échec de démarrage:", err.message);
    process.exit(1);
});
