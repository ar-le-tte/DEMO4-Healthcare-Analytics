-- ============================================================
-- 3.2: Building the Star Schema:
-- Added metadata comments on tables to keep directions of entry
-- ============================================================

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

-- Let us Populate the Tables with Data from the old OLTP tables:

--Encounter Types
INSERT INTO dim_encounter_type (encounter_type_name)
VALUES ('Outpatient'), ('Inpatient'), ('ER');

--Dates
WITH bounds AS (SELECT LEAST((SELECT MIN(encounter_date::date) FROM public.encounters),
      (SELECT MIN(discharge_date::date) FROM public.encounters WHERE discharge_date IS NOT NULL),
      (SELECT MIN(claim_date) FROM public.billing), (SELECT MIN(procedure_date) FROM public.encounter_procedures)) AS min_d,
    GREATEST((SELECT MAX(encounter_date::date) FROM public.encounters),
      (SELECT MAX(discharge_date::date) FROM public.encounters WHERE discharge_date IS NOT NULL),(SELECT MAX(claim_date) FROM public.billing),
      (SELECT MAX(procedure_date) FROM public.encounter_procedures)) AS max_d),
dates AS (SELECT generate_series(min_d, max_d, interval '1 day')::date AS d
  FROM bounds)
INSERT INTO star.dim_date (date_key, calendar_date, year, quarter, month_number, month_name,
  day_of_month, day_of_week, week_of_year, is_weekend)
SELECT
  (to_char(d, 'YYYYMMDD'))::int AS date_key, d AS calendar_date, EXTRACT(YEAR FROM d)::smallint AS year,
  EXTRACT(QUARTER FROM d)::smallint AS quarter, EXTRACT(MONTH FROM d)::smallint AS month_number,
  to_char(d, 'Mon') AS month_name, EXTRACT(DAY FROM d)::smallint AS day_of_month,
  EXTRACT(ISODOW FROM d)::smallint AS day_of_week, EXTRACT(WEEK FROM d)::smallint AS week_of_year,
  (EXTRACT(ISODOW FROM d) IN (6,7)) AS is_weekend
FROM dates
ON CONFLICT (date_key) DO NOTHING;


