-- ============================================================
-- 3.2: Building the Star Schema:
-- Added metadata comments on tables to keep directions of entry
-- ============================================================
CREATE SCHEMA IF NOT EXISTS star;
-- 1) DIMENSIONS

-- dim_date
CREATE TABLE IF NOT EXISTS dim_date (
  date_key        INT PRIMARY KEY,                
  calendar_date   DATE NOT NULL,
  year            SMALLINT NOT NULL,
  quarter         SMALLINT NOT NULL CHECK (quarter BETWEEN 1 AND 4),
  month_number    SMALLINT NOT NULL CHECK (month_number BETWEEN 1 AND 12),
  month_name      VARCHAR(15) NOT NULL,
  day_of_month    SMALLINT NOT NULL CHECK (day_of_month BETWEEN 1 AND 31),
  day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
  week_of_year    SMALLINT NOT NULL CHECK (week_of_year BETWEEN 1 AND 53),
  is_weekend      BOOLEAN NOT NULL);

COMMENT ON TABLE dim_date IS 'Date dimension (one row per calendar date).';
COMMENT ON COLUMN dim_date.date_key IS 'Surrogate date key in YYYYMMDD format.';


-- dim_patient
CREATE TABLE IF NOT EXISTS dim_patient (
  patient_key     BIGSERIAL PRIMARY KEY,
  patient_id      INT NOT NULL UNIQUE,             
  mrn             VARCHAR(20) NOT NULL UNIQUE,
  first_name      VARCHAR(100) NOT NULL,
  last_name       VARCHAR(100) NOT NULL,
  date_of_birth   DATE NOT NULL,
  gender          CHAR(1) NOT NULL,
  age_years       SMALLINT NOT NULL,
  age_group       VARCHAR(20) NOT NULL);

-- dim_specialty
CREATE TABLE IF NOT EXISTS dim_specialty (
  specialty_key   BIGSERIAL PRIMARY KEY,
  specialty_id    INT NOT NULL UNIQUE,            
  specialty_name  VARCHAR(100) NOT NULL,
  specialty_code  VARCHAR(10) NOT NULL);

-- dim_department
CREATE TABLE IF NOT EXISTS dim_department (
  department_key  BIGSERIAL PRIMARY KEY,
  department_id   INT NOT NULL UNIQUE,             
  department_name VARCHAR(100) NOT NULL,
  floor           SMALLINT NOT NULL,
  capacity        INT NOT NULL);

-- dim_provider
CREATE TABLE IF NOT EXISTS dim_provider (
  provider_key    BIGSERIAL PRIMARY KEY,
  provider_id     INT NOT NULL UNIQUE,             
  first_name      VARCHAR(100) NOT NULL,
  last_name       VARCHAR(100) NOT NULL,
  provider_name   VARCHAR(201) NOT NULL,           
  credential      VARCHAR(20) NOT NULL);

-- dim_encounter_type
CREATE TABLE IF NOT EXISTS dim_encounter_type (
  encounter_type_key  BIGSERIAL PRIMARY KEY,
  encounter_type_name VARCHAR(50) NOT NULL UNIQUE);

COMMENT ON TABLE dim_encounter_type IS 'Encounter type dimension (Outpatient/Inpatient/ER).';

-- dim_diagnosis
CREATE TABLE IF NOT EXISTS dim_diagnosis (
  diagnosis_key      BIGSERIAL PRIMARY KEY,
  diagnosis_id       INT NOT NULL UNIQUE,          
  icd10_code         VARCHAR(10) NOT NULL,  --(ICD-10)
  icd10_description  VARCHAR(200) NOT NULL);

-- dim_procedure
CREATE TABLE IF NOT EXISTS dim_procedure (
  procedure_key      BIGSERIAL PRIMARY KEY,
  procedure_id       INT NOT NULL UNIQUE,          
  cpt_code           VARCHAR(10) NOT NULL,
  cpt_description    VARCHAR(200) NOT NULL);

-- 2) FACT TABLE
CREATE TABLE IF NOT EXISTS fact_encounters (
  fact_encounter_key   BIGSERIAL PRIMARY KEY,
  encounter_id          INT NOT NULL UNIQUE,
  -- Dimension foreign keys
  encounter_date_key    INT NOT NULL REFERENCES dim_date(date_key),
  discharge_date_key    INT NULL REFERENCES dim_date(date_key),

  patient_key           BIGINT NOT NULL REFERENCES dim_patient(patient_key),
  provider_key          BIGINT NOT NULL REFERENCES dim_provider(provider_key),
  specialty_key         BIGINT NOT NULL REFERENCES dim_specialty(specialty_key),
  department_key        BIGINT NOT NULL REFERENCES dim_department(department_key),
  encounter_type_key    BIGINT NOT NULL REFERENCES dim_encounter_type(encounter_type_key),
  -- Pre-aggregated measures
  diagnosis_count       INT NOT NULL DEFAULT 0,
  procedure_count       INT NOT NULL DEFAULT 0,
  total_claim_amount    NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  total_allowed_amount  NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  length_of_stay_days   INT NOT NULL DEFAULT 0,

  has_billing           BOOLEAN NOT NULL DEFAULT FALSE);

-- indexes
CREATE INDEX IF NOT EXISTS ix_fact_encounters_enc_date
ON fact_encounters(encounter_date_key);

CREATE INDEX IF NOT EXISTS ix_fact_encounters_specialty_date
ON fact_encounters(specialty_key, encounter_date_key);

CREATE INDEX IF NOT EXISTS ix_fact_encounters_patient_date
ON fact_encounters(patient_key, encounter_date_key);


-- 3) BRIDGE TABLES:

-- bridge_encounter_diagnoses
CREATE TABLE IF NOT EXISTS bridge_encounter_diagnoses (
  bridge_encounter_diagnosis_key BIGSERIAL PRIMARY KEY,
  fact_encounter_key             BIGINT NOT NULL REFERENCES fact_encounters(fact_encounter_key) ON DELETE CASCADE,
  diagnosis_key                  BIGINT NOT NULL REFERENCES dim_diagnosis(diagnosis_key),
  diagnosis_sequence             INT NOT NULL,

  CONSTRAINT ux_bridge_enc_diag UNIQUE (fact_encounter_key, diagnosis_key));

CREATE INDEX IF NOT EXISTS ix_bridge_enc_diag_diag
ON bridge_encounter_diagnoses(diagnosis_key);

CREATE INDEX IF NOT EXISTS ix_bridge_enc_diag_fact
ON bridge_encounter_diagnoses(fact_encounter_key);

-- bridge_encounter_procedures
CREATE TABLE IF NOT EXISTS bridge_encounter_procedures (
  bridge_encounter_procedure_key BIGSERIAL PRIMARY KEY,
  fact_encounter_key             BIGINT NOT NULL REFERENCES fact_encounters(fact_encounter_key) ON DELETE CASCADE,
  procedure_key                  BIGINT NOT NULL REFERENCES dim_procedure(procedure_key),
  procedure_date_key             INT NULL REFERENCES dim_date(date_key),

  CONSTRAINT ux_bridge_enc_proc UNIQUE (fact_encounter_key, procedure_key));

CREATE INDEX IF NOT EXISTS ix_bridge_enc_proc_proc
ON bridge_encounter_procedures(procedure_key);

CREATE INDEX IF NOT EXISTS ix_bridge_enc_proc_fact
ON bridge_encounter_procedures(fact_encounter_key);

-- Let us Populate the Tables

--For Repopulation
TRUNCATE TABLE
  bridge_encounter_procedures,
  bridge_encounter_diagnoses,
  fact_encounters,
  dim_procedure,
  dim_diagnosis,
  dim_encounter_type,
  dim_provider,
  dim_department,
  dim_specialty,
  dim_patient,
  dim_date
RESTART IDENTITY CASCADE;

-- Encounter Types
INSERT INTO dim_encounter_type (encounter_type_name)
VALUES ('Outpatient'), ('Inpatient'), ('ER')
ON CONFLICT (encounter_type_name) DO NOTHING;

-- Specialty
INSERT INTO dim_specialty (specialty_id, specialty_name, specialty_code)
SELECT gs AS specialty_id, 'Specialty ' || gs AS specialty_name, 'SP' || lpad(gs::text, 3, '0') AS specialty_code
FROM generate_series(1, 25) gs;

-- Department
INSERT INTO dim_department (department_id, department_name, floor, capacity)
SELECT gs AS department_id, 'Department ' || gs AS department_name,  (1 + (random()*5)::int)::smallint AS floor,
  (10 + (random()*60)::int) AS capacity
FROM generate_series(1, 30) gs;

-- Provider
INSERT INTO dim_provider (provider_id, first_name, last_name, provider_name, credential)
SELECT gs AS provider_id, 'ProvFirst' || gs, 'ProvLast' || gs, 'ProvFirst' || gs || ' ' || 'ProvLast' || gs, (ARRAY['MD','RN','DO','PA'])[1 + (random()*3)::int]
FROM generate_series(1, 500) gs;

-- Patient
INSERT INTO dim_patient (patient_id, mrn, first_name, last_name, date_of_birth, gender, age_years, age_group)
SELECT gs AS patient_id, 'MRN' || lpad(gs::text, 6, '0') AS mrn, 'PatFirst' || gs, 'PatLast' || gs,
  (DATE '1950-01-01' + (random()*25000)::int) AS date_of_birth, (CASE WHEN random() < 0.5 THEN 'M' ELSE 'F' END)::char(1) AS gender,
  EXTRACT(YEAR FROM age(current_date, (DATE '1950-01-01' + (random()*25000)::int)))::int AS age_years, 'unknown'::varchar(20) AS age_group
FROM generate_series(1, 5000) gs;
UPDATE dim_patient
SET age_group = CASE
  WHEN age_years < 18 THEN '0-17'
  WHEN age_years < 35 THEN '18-34'
  WHEN age_years < 50 THEN '35-49'
  WHEN age_years < 65 THEN '50-64'
  ELSE '65+'
END;

-- Diagnosis
INSERT INTO dim_diagnosis (diagnosis_id, icd10_code, icd10_description)
SELECT gs AS diagnosis_id, 'D' || lpad(gs::text, 4, '0') AS icd10_code, 'Diagnosis ' || gs AS icd10_description
FROM generate_series(1, 500) gs;

-- Procedure
INSERT INTO dim_procedure (procedure_id, cpt_code, cpt_description)
SELECT gs AS procedure_id, 'P' || lpad(gs::text, 4, '0') AS cpt_code, 'Procedure ' || gs AS cpt_description
FROM generate_series(1, 300) gs;

-- Dates
WITH dates AS ( SELECT generate_series(DATE '2023-01-01', DATE '2024-12-31', interval '1 day')::date AS d)
INSERT INTO dim_date ( date_key, calendar_date, year, quarter, month_number, month_name, day_of_month, day_of_week, week_of_year, is_weekend)
SELECT (to_char(d, 'YYYYMMDD'))::int, d, EXTRACT(YEAR FROM d)::smallint, EXTRACT(QUARTER FROM d)::smallint, EXTRACT(MONTH FROM d)::smallint,
  to_char(d, 'Mon'), EXTRACT(DAY FROM d)::smallint, EXTRACT(ISODOW FROM d)::smallint, EXTRACT(WEEK FROM d)::smallint, (EXTRACT(ISODOW FROM d) IN (6,7))
FROM dates
ON CONFLICT (date_key) DO NOTHING;

-- Fact Table:
WITH et AS ( SELECT encounter_type_key, encounter_type_name FROM dim_encounter_type),
rand_rows AS ( SELECT gs AS encounter_id, (SELECT patient_key FROM dim_patient ORDER BY random() LIMIT 1) AS patient_key,
    (SELECT provider_key FROM dim_provider ORDER BY random() LIMIT 1) AS provider_key,
    (SELECT specialty_key FROM dim_specialty ORDER BY random() LIMIT 1) AS specialty_key,
    (SELECT department_key FROM dim_department ORDER BY random() LIMIT 1) AS department_key,
    (SELECT encounter_type_key FROM et ORDER BY random() LIMIT 1) AS encounter_type_key,
    (SELECT date_key FROM dim_date ORDER BY random() LIMIT 1) AS encounter_date_key
  FROM generate_series(1, 10000) gs),
with_discharge AS ( SELECT r.*,  CASE
      WHEN (SELECT encounter_type_name FROM et WHERE et.encounter_type_key = r.encounter_type_key) = 'Outpatient'
        THEN r.encounter_date_key
      WHEN (SELECT encounter_type_name FROM et WHERE et.encounter_type_key = r.encounter_type_key) = 'ER'
        THEN r.encounter_date_key
      ELSE r.encounter_date_key
    END AS discharge_date_key
  FROM rand_rows r
)
INSERT INTO fact_encounters ( encounter_id, encounter_date_key, discharge_date_key, patient_key, provider_key, specialty_key, department_key,
  encounter_type_key, diagnosis_count, procedure_count, total_claim_amount, total_allowed_amount, length_of_stay_days, has_billing)
SELECT encounter_id, encounter_date_key, discharge_date_key, patient_key, provider_key, specialty_key, department_key, encounter_type_key,
  (1 + (random()*3)::int) AS diagnosis_count, (1 + (random()*2)::int) AS procedure_count, round((50 + random()*15000)::numeric, 2) AS total_claim_amount,
  round((40 + random()*12000)::numeric, 2) AS total_allowed_amount, (random()*10)::int AS length_of_stay_days, (random() < 0.7) AS has_billing
FROM with_discharge;

-- Bridge Tables

-- encounter_diagnoses
INSERT INTO bridge_encounter_diagnoses (fact_encounter_key, diagnosis_key, diagnosis_sequence)
SELECT f.fact_encounter_key, (SELECT diagnosis_key FROM dim_diagnosis ORDER BY random() LIMIT 1) AS diagnosis_key,
  gs AS diagnosis_sequence
FROM fact_encounters f
JOIN LATERAL generate_series(1, GREATEST(f.diagnosis_count,1)) gs ON TRUE
ON CONFLICT DO NOTHING;

-- encounter_procedures
INSERT INTO bridge_encounter_procedures (fact_encounter_key, procedure_key, procedure_date_key)
SELECT f.fact_encounter_key, (SELECT procedure_key FROM dim_procedure ORDER BY random() LIMIT 1) AS procedure_key, f.encounter_date_key
FROM fact_encounters f
JOIN LATERAL generate_series(1, GREATEST(f.procedure_count,1)) gs ON TRUE
ON CONFLICT DO NOTHING;

SELECT count(*) FROM fact_encounters;

-- Query Test Runs:





