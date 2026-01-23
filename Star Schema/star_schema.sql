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

CREATE INDEX IF NOT EXISTS ix_fact_q1
ON fact_encounters (encounter_date_key, specialty_key, encounter_type_key, patient_key);

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
INSERT INTO star.dim_encounter_type (encounter_type_name)
SELECT DISTINCT encounter_type
FROM public.encounters
WHERE encounter_type IS NOT NULL
ON CONFLICT (encounter_type_name) DO NOTHING;

-- Specialty
INSERT INTO star.dim_specialty (specialty_id, specialty_name, specialty_code)
SELECT specialty_id, specialty_name, specialty_code
FROM public.specialties
ON CONFLICT (specialty_id) DO NOTHING;


-- Department
INSERT INTO star.dim_department (department_id, department_name, floor, capacity)
SELECT department_id, department_name, floor, capacity
FROM public.departments
ON CONFLICT (department_id) DO NOTHING;

-- Provider
INSERT INTO star.dim_provider (provider_id, first_name, last_name, provider_name, credential)
SELECT provider_id, first_name, last_name, first_name || ' ' || last_name AS provider_name, credential
FROM public.providers
ON CONFLICT (provider_id) DO NOTHING;


-- Patient
INSERT INTO star.dim_patient (patient_id, mrn, first_name, last_name, date_of_birth, gender, age_years, age_group)
SELECT p.patient_id, p.mrn, p.first_name, p.last_name, p.date_of_birth, p.gender,
  EXTRACT(YEAR FROM age(current_date, p.date_of_birth))::int AS age_years,
  CASE
    WHEN EXTRACT(YEAR FROM age(current_date, p.date_of_birth)) < 18 THEN '0-17'
    WHEN EXTRACT(YEAR FROM age(current_date, p.date_of_birth)) < 35 THEN '18-34'
    WHEN EXTRACT(YEAR FROM age(current_date, p.date_of_birth)) < 50 THEN '35-49'
    WHEN EXTRACT(YEAR FROM age(current_date, p.date_of_birth)) < 65 THEN '50-64'
    ELSE '65+'
  END AS age_group
FROM public.patients p
ON CONFLICT (patient_id) DO NOTHING;


-- Diagnosis
INSERT INTO star.dim_diagnosis (diagnosis_id, icd10_code, icd10_description)
SELECT diagnosis_id, icd10_code, icd10_description
FROM public.diagnoses
ON CONFLICT (diagnosis_id) DO NOTHING;


-- Procedure
INSERT INTO star.dim_procedure (procedure_id, cpt_code, cpt_description)
SELECT procedure_id, cpt_code, cpt_description
FROM public.procedures
ON CONFLICT (procedure_id) DO NOTHING;

-- Dates
WITH bounds AS (SELECT  LEAST((SELECT MIN(encounter_date::date) FROM public.encounters),
      (SELECT MIN(discharge_date::date) FROM public.encounters WHERE discharge_date IS NOT NULL),
      (SELECT MIN(claim_date) FROM public.billing), (SELECT MIN(procedure_date) FROM public.encounter_procedures)) AS min_d,
    GREATEST((SELECT MAX(encounter_date::date) FROM public.encounters), (SELECT MAX(discharge_date::date) FROM public.encounters WHERE discharge_date IS NOT NULL),
      (SELECT MAX(claim_date) FROM public.billing),
      (SELECT MAX(procedure_date) FROM public.encounter_procedures)) AS max_d),
dates AS (
  SELECT generate_series(min_d, max_d, interval '1 day')::date AS d
  FROM bounds)
INSERT INTO star.dim_date (date_key, calendar_date, year, quarter, month_number, month_name,
  day_of_month, day_of_week, week_of_year, is_weekend)
SELECT(to_char(d, 'YYYYMMDD'))::int AS date_key, d AS calendar_date, EXTRACT(YEAR FROM d)::smallint AS year, EXTRACT(QUARTER FROM d)::smallint AS quarter,
  EXTRACT(MONTH FROM d)::smallint AS month_number, to_char(d, 'Mon') AS month_name, EXTRACT(DAY FROM d)::smallint AS day_of_month, EXTRACT(ISODOW FROM d)::smallint AS day_of_week,
  EXTRACT(WEEK FROM d)::smallint AS week_of_year,(EXTRACT(ISODOW FROM d) IN (6,7)) AS is_weekend
FROM dates
ON CONFLICT (date_key) DO NOTHING;


-- Fact Table:
WITH diag AS (SELECT encounter_id, COUNT(*)::int AS diagnosis_count
  FROM public.encounter_diagnoses
  GROUP BY encounter_id),
proc AS (
  SELECT encounter_id, COUNT(*)::int AS procedure_count
  FROM public.encounter_procedures
  GROUP BY encounter_id),
bill AS (SELECT encounter_id, COALESCE(SUM(claim_amount), 0)::numeric(12,2)   AS total_claim_amount,
    COALESCE(SUM(allowed_amount), 0)::numeric(12,2) AS total_allowed_amount, (COUNT(*) > 0) AS has_billing
  FROM public.billing
  GROUP BY encounter_id)
INSERT INTO star.fact_encounters (encounter_id, encounter_date_key, discharge_date_key, patient_key, provider_key, specialty_key,
  department_key, encounter_type_key, diagnosis_count, procedure_count, total_claim_amount, total_allowed_amount, length_of_stay_days, has_billing)
SELECT e.encounter_id, (to_char(e.encounter_date::date, 'YYYYMMDD'))::int AS encounter_date_key, CASE WHEN e.discharge_date IS NULL THEN NULL
       ELSE (to_char(e.discharge_date::date, 'YYYYMMDD'))::int
  END AS discharge_date_key, dp.patient_key, dprov.provider_key, dspec.specialty_key, ddept.department_key, det.encounter_type_key,

  COALESCE(dg.diagnosis_count, 0),
  COALESCE(pr.procedure_count, 0),
  COALESCE(bl.total_claim_amount, 0.00),
  COALESCE(bl.total_allowed_amount, 0.00),

  GREATEST(0, COALESCE((e.discharge_date::date - e.encounter_date::date), 0))::int AS length_of_stay_days,
  COALESCE(bl.has_billing, FALSE) AS has_billing
FROM public.encounters e
JOIN star.dim_patient dp ON dp.patient_id = e.patient_id
JOIN star.dim_provider dprov ON dprov.provider_id = e.provider_id
JOIN public.providers p ON p.provider_id = e.provider_id
JOIN star.dim_specialty dspec ON dspec.specialty_id = p.specialty_id
JOIN star.dim_department ddept ON ddept.department_id = e.department_id
JOIN star.dim_encounter_type det ON det.encounter_type_name = e.encounter_type
LEFT JOIN diag dg ON dg.encounter_id = e.encounter_id
LEFT JOIN proc pr ON pr.encounter_id = e.encounter_id
LEFT JOIN bill bl ON bl.encounter_id = e.encounter_id
ON CONFLICT (encounter_id) DO NOTHING;


-- Bridge Tables

-- encounter_diagnoses
INSERT INTO star.bridge_encounter_diagnoses (fact_encounter_key, diagnosis_key, diagnosis_sequence)
SELECT f.fact_encounter_key, dd.diagnosis_key, ed.diagnosis_sequence
FROM public.encounter_diagnoses ed JOIN star.fact_encounters f
  ON f.encounter_id = ed.encounter_id
JOIN star.dim_diagnosis dd ON dd.diagnosis_id = ed.diagnosis_id
ON CONFLICT DO NOTHING;

-- encounter_procedures
INSERT INTO star.bridge_encounter_procedures (fact_encounter_key, procedure_key, procedure_date_key)
SELECT f.fact_encounter_key, dp.procedure_key, (to_char(ep.procedure_date, 'YYYYMMDD'))::int AS procedure_date_key
FROM public.encounter_procedures ep
JOIN star.fact_encounters f ON f.encounter_id = ep.encounter_id
JOIN star.dim_procedure dp ON dp.procedure_id = ep.procedure_id
ON CONFLICT DO NOTHING;

----
SELECT count(*) FROM dim_date;
ANALYZE bridge_encounter_diagnoses;
ANALYZE bridge_encounter_procedures;
ANALYZE fact_encounters;
----

-- Let us calculate a pre-aggregated table to simple calculations and minimize joins
CREATE TABLE fact_diag_proc_pairs AS
SELECT
  bd.diagnosis_key,
  bp.procedure_key,
  COUNT(DISTINCT bd.fact_encounter_key) AS encounter_count
FROM bridge_encounter_diagnoses bd
JOIN bridge_encounter_procedures bp
  ON bp.fact_encounter_key = bd.fact_encounter_key
GROUP BY bd.diagnosis_key, bp.procedure_key;

CREATE INDEX ON fact_diag_proc_pairs (encounter_count DESC);
CREATE INDEX ON fact_diag_proc_pairs (diagnosis_key, procedure_key);

ANALYZE fact_diag_proc_pairs;


-- Query Test Runs:

--Qn1. Monthly Encounters by Specialty
EXPLAIN (ANALYZE)
SELECT d.year, d.month_number, d.month_name, s.specialty_name, et.encounter_type_name,
  COUNT(*) AS total_encounters,
  COUNT(DISTINCT f.patient_key) AS unique_patients
FROM fact_encounters f
JOIN dim_date d ON d.date_key = f.encounter_date_key
JOIN dim_specialty s ON s.specialty_key = f.specialty_key
JOIN dim_encounter_type et ON et.encounter_type_key = f.encounter_type_key
GROUP BY
  d.year, d.month_number, d.month_name, s.specialty_name, et.encounter_type_name
ORDER BY
  d.year, d.month_number, s.specialty_name, et.encounter_type_name;

--Qn2. Monthly Encounters by Specialty

EXPLAIN (ANALYZE)
SELECT d.icd10_code, p.cpt_code, fp.encounter_count
FROM fact_diag_proc_pairs fp
JOIN dim_diagnosis d ON d.diagnosis_key = fp.diagnosis_key
JOIN dim_procedure p ON p.procedure_key = fp.procedure_key
ORDER BY fp.encounter_count DESC
LIMIT 20;

--Qn3. Day Readmission Rate by Specialty

EXPLAIN (ANALYZE, BUFFERS)
WITH inpatient AS (SELECT f.encounter_id, f.patient_key, f.specialty_key, f.discharge_date_key, dc.date_key AS cutoff_date_key
  FROM star.fact_encounters f
  JOIN star.dim_encounter_type et ON et.encounter_type_key = f.encounter_type_key
  JOIN star.dim_date dd ON dd.date_key = f.discharge_date_key
  JOIN star.dim_date dc ON dc.calendar_date = dd.calendar_date + INTERVAL '30 days'
  WHERE et.encounter_type_name = 'Inpatient'
    AND f.discharge_date_key IS NOT NULL),
next_within_30 AS (SELECT i.encounter_id, i.specialty_key, (nxt.fact_encounter_key IS NOT NULL) AS is_readmitted
  FROM inpatient i
  LEFT JOIN LATERAL (
    SELECT f2.fact_encounter_key
    FROM star.fact_encounters f2
    WHERE f2.patient_key = i.patient_key
      AND f2.encounter_date_key > i.discharge_date_key
      AND f2.encounter_date_key <= i.cutoff_date_key
    ORDER BY f2.encounter_date_key
    LIMIT 1) nxt ON TRUE)
SELECT s.specialty_name, COUNT(*) FILTER (WHERE is_readmitted) AS readmissions, COUNT(*) AS inpatient_discharges,
  ROUND(COUNT(*) FILTER (WHERE is_readmitted)::numeric / NULLIF(COUNT(*),0), 4) AS readmission_rate
FROM next_within_30 r
JOIN star.dim_specialty s ON s.specialty_key = r.specialty_key
GROUP BY s.specialty_name
ORDER BY readmission_rate DESC;

--Qn4. Revenue by Specialty & Month
EXPLAIN (ANALYZE)
SELECT d.year, d.month_number, d.month_name, s.specialty_name, SUM(f.total_allowed_amount) AS total_allowed_amount
FROM star.fact_encounters f
JOIN star.dim_date d ON d.date_key = f.encounter_date_key
JOIN star.dim_specialty s ON s.specialty_key = f.specialty_key
WHERE f.has_billing = TRUE
GROUP BY d.year, d.month_number, d.month_name, s.specialty_name
ORDER BY d.year, d.month_number, total_allowed_amount DESC;








