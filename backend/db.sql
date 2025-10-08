-- ===========================================================
--  Epitanie TD1 – Base MOS/NOS (PostgreSQL)
--  Schéma + vues + seeds (idempotent autant que possible)
-- ===========================================================

-- =========================
-- = 1) NOS (Référentiels) =
-- =========================
CREATE TABLE IF NOT EXISTS tre_profession (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_diplome (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_mode_exercice (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_type_identifiant_structure (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_type_entite_juridique (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_role_cercle (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_type_rdv (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_type_doc (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tre_type_analyse (
  code    TEXT PRIMARY KEY,
  libelle TEXT NOT NULL
);

-- JDV (exemple de sous-ensemble)
CREATE TABLE IF NOT EXISTS jdv_profession_autorisee (
  code TEXT PRIMARY KEY REFERENCES tre_profession(code)
);

-- ==============================
-- = 2) MOS (Socle Annuaire)    =
-- ==============================
CREATE TABLE IF NOT EXISTS entite_juridique (
  id             BIGSERIAL PRIMARY KEY,
  siret          TEXT UNIQUE NOT NULL,
  raison_sociale TEXT NOT NULL,
  type_code      TEXT NOT NULL REFERENCES tre_type_entite_juridique(code)
);

CREATE TABLE IF NOT EXISTS structure (
  id                      BIGSERIAL PRIMARY KEY,
  nom                     TEXT NOT NULL,
  type_identifiant_code   TEXT NOT NULL REFERENCES tre_type_identifiant_structure(code),
  identifiant             TEXT NOT NULL,
  entite_juridique_id     BIGINT REFERENCES entite_juridique(id) ON DELETE SET NULL,
  UNIQUE(type_identifiant_code, identifiant)
);
CREATE INDEX IF NOT EXISTS ix_structure_ej ON structure(entite_juridique_id);

CREATE TABLE IF NOT EXISTS professionnel (
  id              BIGSERIAL PRIMARY KEY,
  rpps            TEXT UNIQUE NOT NULL,
  nom             TEXT NOT NULL,
  prenom          TEXT NOT NULL,
  profession_code TEXT NOT NULL REFERENCES tre_profession(code),
  diplome_code    TEXT NOT NULL REFERENCES tre_diplome(code)
);

CREATE TABLE IF NOT EXISTS situation_exercice (
  id                  BIGSERIAL PRIMARY KEY,
  professionnel_id    BIGINT NOT NULL REFERENCES professionnel(id) ON DELETE CASCADE,
  structure_id        BIGINT NOT NULL REFERENCES structure(id) ON DELETE CASCADE,
  mode_exercice_code  TEXT   NOT NULL REFERENCES tre_mode_exercice(code),
  date_debut          DATE   NOT NULL,
  date_fin            DATE,
  CHECK (date_fin IS NULL OR date_fin >= date_debut)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_sit_ex_active
  ON situation_exercice(professionnel_id, structure_id)
  WHERE date_fin IS NULL;
CREATE INDEX IF NOT EXISTS ix_sit_ex_pro ON situation_exercice(professionnel_id);
CREATE INDEX IF NOT EXISTS ix_sit_ex_struct ON situation_exercice(structure_id);

-- ==============================
-- = 3) MOS (Patient & Soin)    =
-- ==============================
CREATE TABLE IF NOT EXISTS patient (
  id              BIGSERIAL PRIMARY KEY,
  ins             TEXT UNIQUE,
  nom             TEXT NOT NULL,
  prenom          TEXT NOT NULL,
  date_naissance  DATE
);

CREATE TABLE IF NOT EXISTS pathologie (
  id      BIGSERIAL PRIMARY KEY,
  code    TEXT NOT NULL,
  libelle TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_pathologie_code ON pathologie(code);

-- Relation patient ↔ professionnel (± pathologie), rôle NOS
CREATE TABLE IF NOT EXISTS cercle_de_soin (
  id               BIGSERIAL PRIMARY KEY,
  patient_id       BIGINT NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
  professionnel_id BIGINT NOT NULL REFERENCES professionnel(id) ON DELETE CASCADE,
  pathologie_id    BIGINT REFERENCES pathologie(id) ON DELETE SET NULL,
  role_code        TEXT NOT NULL REFERENCES tre_role_cercle(code),
  date_debut       DATE NOT NULL,
  date_fin         DATE,
  CHECK (date_fin IS NULL OR date_fin >= date_debut),
  UNIQUE(patient_id, professionnel_id, pathologie_id, role_code, date_debut)
);
CREATE INDEX IF NOT EXISTS ix_cds_patient ON cercle_de_soin(patient_id);
CREATE INDEX IF NOT EXISTS ix_cds_pro ON cercle_de_soin(professionnel_id);

-- ==============================
-- = 4) MOS (Agenda & Réunions) =
-- ==============================
CREATE TABLE IF NOT EXISTS rendez_vous (
  id                BIGSERIAL PRIMARY KEY,
  structure_id      BIGINT REFERENCES structure(id) ON DELETE SET NULL,
  type_rdv_code     TEXT NOT NULL REFERENCES tre_type_rdv(code),
  date_heure_debut  TIMESTAMPTZ NOT NULL,
  date_heure_fin    TIMESTAMPTZ NOT NULL,
  lieu              TEXT,
  objet             TEXT,
  CHECK (date_heure_fin > date_heure_debut)
);
CREATE INDEX IF NOT EXISTS ix_rdv_struct ON rendez_vous(structure_id);
CREATE INDEX IF NOT EXISTS ix_rdv_debut ON rendez_vous(date_heure_debut);

-- Participants
CREATE TABLE IF NOT EXISTS rdv_patient (
  rdv_id     BIGINT REFERENCES rendez_vous(id) ON DELETE CASCADE,
  patient_id BIGINT REFERENCES patient(id) ON DELETE CASCADE,
  PRIMARY KEY (rdv_id, patient_id)
);

CREATE TABLE IF NOT EXISTS rdv_professionnel (
  rdv_id           BIGINT REFERENCES rendez_vous(id) ON DELETE CASCADE,
  professionnel_id BIGINT REFERENCES professionnel(id) ON DELETE CASCADE,
  PRIMARY KEY (rdv_id, professionnel_id)
);

-- ==============================
-- = 5) MOS (Documents & Msg)   =
-- ==============================
CREATE TABLE IF NOT EXISTS document (
  id                  BIGSERIAL PRIMARY KEY,
  patient_id          BIGINT REFERENCES patient(id) ON DELETE CASCADE,
  auteur_prof_id      BIGINT REFERENCES professionnel(id) ON DELETE SET NULL,
  auteur_struct_id    BIGINT REFERENCES structure(id) ON DELETE SET NULL,
  type_document_code  TEXT NOT NULL REFERENCES tre_type_doc(code),
  uri                 TEXT NOT NULL,
  titre               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_doc_patient ON document(patient_id);
CREATE INDEX IF NOT EXISTS ix_doc_created ON document(created_at);

CREATE TABLE IF NOT EXISTS msg_thread (
  id         BIGSERIAL PRIMARY KEY,
  sujet      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS message (
  id               BIGSERIAL PRIMARY KEY,
  thread_id        BIGINT NOT NULL REFERENCES msg_thread(id) ON DELETE CASCADE,
  sender_role      TEXT NOT NULL CHECK (sender_role IN ('professionnel','patient','secretaire')),
  sender_pro_id    BIGINT REFERENCES professionnel(id) ON DELETE SET NULL,
  sender_patient_id BIGINT REFERENCES patient(id) ON DELETE SET NULL,
  contenu          TEXT NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Correction : PK simple + contraintes + indexes uniques partiels
DROP TABLE IF EXISTS message_destinataire CASCADE;
CREATE TABLE message_destinataire (
  id           BIGSERIAL PRIMARY KEY,
  message_id   BIGINT NOT NULL REFERENCES message(id) ON DELETE CASCADE,
  role         TEXT NOT NULL CHECK (role IN ('professionnel','patient')),
  pro_id       BIGINT REFERENCES professionnel(id) ON DELETE CASCADE,
  patient_id   BIGINT REFERENCES patient(id) ON DELETE CASCADE,
  lu           BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT one_target CHECK (
    (role='professionnel' AND pro_id IS NOT NULL AND patient_id IS NULL)
    OR
    (role='patient' AND patient_id IS NOT NULL AND pro_id IS NULL)
  )
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_msg_dest_pro
  ON message_destinataire (message_id, pro_id) WHERE pro_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_msg_dest_patient
  ON message_destinataire (message_id, patient_id) WHERE patient_id IS NOT NULL;

-- ==========================================
-- = 6) MOS (Analyses & Notifications/Alertes)
-- ==========================================
CREATE TABLE IF NOT EXISTS analyse_resultat (
  id                 BIGSERIAL PRIMARY KEY,
  patient_id         BIGINT NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
  prescripteur_id    BIGINT REFERENCES professionnel(id) ON DELETE SET NULL,
  laboratoire_id     BIGINT REFERENCES structure(id) ON DELETE SET NULL,
  type_analyse_code  TEXT NOT NULL REFERENCES tre_type_analyse(code),
  date_prelevement   DATE,
  date_resultat      DATE NOT NULL,
  fichier_uri        TEXT,
  resume_texte       TEXT
);
CREATE INDEX IF NOT EXISTS ix_analyse_patient ON analyse_resultat(patient_id);
CREATE INDEX IF NOT EXISTS ix_analyse_date ON analyse_resultat(date_resultat);

CREATE TABLE IF NOT EXISTS alerte (
  id             BIGSERIAL PRIMARY KEY,
  type_code      TEXT NOT NULL CHECK (type_code IN ('ANALYSE_RESULTAT')),
  cible_pro_id   BIGINT REFERENCES professionnel(id) ON DELETE CASCADE,
  cible_struct_id BIGINT REFERENCES structure(id) ON DELETE CASCADE,
  payload_json   JSONB NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  lu             BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS ix_alerte_pro ON alerte(cible_pro_id, lu);
CREATE INDEX IF NOT EXISTS ix_alerte_struct ON alerte(cible_struct_id, lu);

-- ======================
-- = 7) VUES de confort =
-- ======================
CREATE OR REPLACE VIEW v_professionnel AS
SELECT p.*,
       tp.libelle AS profession_libelle,
       td.libelle AS diplome_libelle
FROM professionnel p
JOIN tre_profession tp ON tp.code = p.profession_code
JOIN tre_diplome   td ON td.code = p.diplome_code;

CREATE OR REPLACE VIEW v_situation_exercice AS
SELECT se.*,
       p.nom AS pro_nom, p.prenom AS pro_prenom,
       s.nom AS structure_nom,
       tme.libelle AS mode_exercice_libelle
FROM situation_exercice se
JOIN professionnel p ON p.id = se.professionnel_id
JOIN structure s     ON s.id = se.structure_id
JOIN tre_mode_exercice tme ON tme.code = se.mode_exercice_code;

CREATE OR REPLACE VIEW v_rendez_vous AS
SELECT r.*, s.nom AS structure_nom, tr.libelle AS type_rdv_libelle
FROM rendez_vous r
LEFT JOIN structure s ON s.id = r.structure_id
JOIN tre_type_rdv tr ON tr.code = r.type_rdv_code;

CREATE OR REPLACE VIEW v_document AS
SELECT d.*, ttd.libelle AS type_doc_libelle,
       pp.nom AS auteur_pro_nom, pp.prenom AS auteur_pro_prenom,
       ss.nom AS auteur_struct_nom
FROM document d
JOIN tre_type_doc ttd ON ttd.code = d.type_document_code
LEFT JOIN professionnel pp ON pp.id = d.auteur_prof_id
LEFT JOIN structure ss ON ss.id = d.auteur_struct_id;

CREATE OR REPLACE VIEW v_analyse_resultat AS
SELECT a.*, ta.libelle AS type_analyse_libelle,
       p.nom AS patient_nom, p.prenom AS patient_prenom,
       pr.nom AS prescripteur_nom, pr.prenom AS prescripteur_prenom,
       s.nom AS labo_nom
FROM analyse_resultat a
JOIN tre_type_analyse ta ON ta.code = a.type_analyse_code
JOIN patient p ON p.id = a.patient_id
LEFT JOIN professionnel pr ON pr.id = a.prescripteur_id
LEFT JOIN structure s ON s.id = a.laboratoire_id;

-- =======================
-- = 8) Seeds de test    =
-- =======================
INSERT INTO tre_profession(code, libelle) VALUES
  ('MEDE','Médecin'), ('INFI','Infirmier'), ('KINE','Masseur-kinésithérapeute')
ON CONFLICT DO NOTHING;

INSERT INTO tre_diplome(code, libelle) VALUES
  ('D01','Docteur en médecine'),
  ('D02','Diplôme d’État infirmier'),
  ('D03','Diplôme d’État masseur-kinésithérapeute')
ON CONFLICT DO NOTHING;

INSERT INTO tre_mode_exercice(code, libelle) VALUES
  ('LIB','Libéral'), ('SAL','Salarié')
ON CONFLICT DO NOTHING;

INSERT INTO tre_type_identifiant_structure(code, libelle) VALUES
  ('SIRET','SIRET'), ('FINESS','FINESS')
ON CONFLICT DO NOTHING;

INSERT INTO tre_type_entite_juridique(code, libelle) VALUES
  ('CHU','Centre Hospitalier Universitaire'),
  ('CLIN','Clinique privée'),
  ('CAB','Cabinet libéral')
ON CONFLICT DO NOTHING;

INSERT INTO tre_role_cercle(code, libelle) VALUES
  ('MT','Médecin traitant'),
  ('REFINF','Infirmier référent'),
  ('SPEC','Spécialiste')
ON CONFLICT DO NOTHING;

INSERT INTO tre_type_rdv(code, libelle) VALUES
  ('CONS','Consultation'), ('REU','Réunion'), ('EXAM','Examen')
ON CONFLICT DO NOTHING;

INSERT INTO tre_type_doc(code, libelle) VALUES
  ('CR','Compte-rendu'), ('ORD','Ordonnance'), ('IMG','Imagerie')
ON CONFLICT DO NOTHING;

INSERT INTO tre_type_analyse(code, libelle) VALUES
  ('LOINC-718-7','Hémoglobine [Mass/volume]'),
  ('LOINC-2160-0','Créatinine [Mass/volume]')
ON CONFLICT DO NOTHING;

INSERT INTO jdv_profession_autorisee(code) VALUES ('MEDE'), ('INFI')
ON CONFLICT DO NOTHING;

-- Entités/structures
INSERT INTO entite_juridique(siret, raison_sociale, type_code) VALUES
  ('11111111100011','CHU Epitanie','CHU'),
  ('22222222200022','Clinique Pasteur','CLIN')
ON CONFLICT DO NOTHING;

INSERT INTO structure(nom, type_identifiant_code, identifiant, entite_juridique_id)
SELECT 'Hôpital Central Epitanie','FINESS','FNS-0001', ej.id
FROM entite_juridique ej WHERE ej.raison_sociale='CHU Epitanie'
ON CONFLICT DO NOTHING;

INSERT INTO structure(nom, type_identifiant_code, identifiant, entite_juridique_id)
SELECT 'Clinique Pasteur','SIRET','22222222200022', ej.id
FROM entite_juridique ej WHERE ej.raison_sociale='Clinique Pasteur'
ON CONFLICT DO NOTHING;

-- Pros / patients
INSERT INTO professionnel(rpps, nom, prenom, profession_code, diplome_code) VALUES
  ('10101010101','Martin','Jeanne','MEDE','D01'),
  ('20202020202','Dupont','Alice','INFI','D02')
ON CONFLICT DO NOTHING;

INSERT INTO patient(ins, nom, prenom, date_naissance) VALUES
  ('1 84 12 75 123 456 78','Leroy','Maxime','1999-05-12'),
  ('2 91 03 33 987 654 32','Morel','Chloé','2001-10-02')
ON CONFLICT DO NOTHING;

INSERT INTO pathologie(code, libelle) VALUES
  ('I10','Hypertension essentielle (primitive)'),
  ('E11','Diabète sucré de type 2')
ON CONFLICT DO NOTHING;

-- Situations
INSERT INTO situation_exercice(professionnel_id, structure_id, mode_exercice_code, date_debut)
SELECT p.id, s.id, 'SAL', '2023-01-01'
FROM professionnel p, structure s
WHERE p.rpps='10101010101' AND s.nom='Hôpital Central Epitanie'
ON CONFLICT DO NOTHING;

INSERT INTO situation_exercice(professionnel_id, structure_id, mode_exercice_code, date_debut)
SELECT p.id, s.id, 'LIB', '2024-03-15'
FROM professionnel p, structure s
WHERE p.rpps='20202020202' AND s.nom='Clinique Pasteur'
ON CONFLICT DO NOTHING;

-- Cercle de soin
INSERT INTO cercle_de_soin(patient_id, professionnel_id, pathologie_id, role_code, date_debut)
SELECT pa.id, pr.id, pt.id, 'MT', '2024-01-01'
FROM patient pa, professionnel pr, pathologie pt
WHERE pa.nom='Leroy' AND pr.rpps='10101010101' AND pt.code='I10'
ON CONFLICT DO NOTHING;

INSERT INTO cercle_de_soin(patient_id, professionnel_id, pathologie_id, role_code, date_debut)
SELECT pa.id, pr.id, pt.id, 'REFINF', '2024-01-10'
FROM patient pa, professionnel pr, pathologie pt
WHERE pa.nom='Leroy' AND pr.rpps='20202020202' AND pt.code='I10'
ON CONFLICT DO NOTHING;

-- RDV + participants
INSERT INTO rendez_vous(structure_id, type_rdv_code, date_heure_debut, date_heure_fin, lieu, objet)
SELECT s.id, 'CONS', now() + interval '1 day', now() + interval '1 day 30 min', 'Consultation 12', 'Suivi HTA'
FROM structure s WHERE s.nom='Hôpital Central Epitanie'
ON CONFLICT DO NOTHING;

INSERT INTO rdv_patient(rdv_id, patient_id)
SELECT r.id, p.id
FROM rendez_vous r, patient p
WHERE r.objet='Suivi HTA' AND p.nom='Leroy'
ON CONFLICT DO NOTHING;

INSERT INTO rdv_professionnel(rdv_id, professionnel_id)
SELECT r.id, pr.id
FROM rendez_vous r, professionnel pr
WHERE r.objet='Suivi HTA' AND pr.rpps='10101010101'
ON CONFLICT DO NOTHING;

-- Document
INSERT INTO document(patient_id, auteur_prof_id, type_document_code, uri, titre)
SELECT pa.id, pr.id, 'CR', 's3://bucket/documents/CR_001.pdf', 'CR Consultation HTA'
FROM patient pa, professionnel pr
WHERE pa.nom='Leroy' AND pr.rpps='10101010101'
ON CONFLICT DO NOTHING;

-- Analyse + alerte
INSERT INTO analyse_resultat(patient_id, prescripteur_id, laboratoire_id, type_analyse_code, date_prelevement, date_resultat, fichier_uri, resume_texte)
SELECT pa.id, pr.id, s.id, 'LOINC-718-7', '2024-06-01', '2024-06-02', 's3://bucket/lab/RES_0001.pdf', 'Hémoglobine normale'
FROM patient pa, professionnel pr, structure s
WHERE pa.nom='Leroy' AND pr.rpps='10101010101' AND s.nom='Clinique Pasteur'
ON CONFLICT DO NOTHING;

INSERT INTO alerte(type_code, cible_pro_id, payload_json)
SELECT 'ANALYSE_RESULTAT', pr.id, jsonb_build_object('patient','Leroy','analyse','LOINC-718-7')
FROM professionnel pr WHERE pr.rpps='10101010101'
ON CONFLICT DO NOTHING;

-- =======================
-- = 9) Quick checks     =
-- =======================
-- SELECT * FROM v_professionnel;
-- SELECT * FROM v_situation_exercice;
-- SELECT * FROM v_rendez_vous;
-- SELECT * FROM v_document;
-- SELECT * FROM v_analyse_resultat;
