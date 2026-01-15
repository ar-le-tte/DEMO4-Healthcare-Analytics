-- =========================================
-- PART 1: NORMALIZED OLTP SCHEMA (3NF)
-- =========================================

CREATE DATABASE healthcare_analytics;


-- FOR RERUNS
DROP TABLE IF EXISTS billing;
DROP TABLE IF EXISTS encounter_procedures;
DROP TABLE IF EXISTS encounter_diagnoses;
DROP TABLE IF EXISTS encounters;
DROP TABLE IF EXISTS procedures;
DROP TABLE IF EXISTS diagnoses;
DROP TABLE IF EXISTS providers;
DROP TABLE IF EXISTS departments;
DROP TABLE IF EXISTS specialties;
DROP TABLE IF EXISTS patients;

-- =========================================
-- TABLES
-- =========================================

CREATE TABLE patients (
  patient_id INT PRIMARY KEY,
  first_name VARCHAR(100),
  last_name  VARCHAR(100),
  date_of_birth DATE,
  gender CHAR(1),
  mrn VARCHAR(20) UNIQUE
);

CREATE TABLE specialties (
  specialty_id INT PRIMARY KEY,
  specialty_name VARCHAR(100),
  specialty_code VARCHAR(10)
);

CREATE TABLE departments (
  department_id INT PRIMARY KEY,
  department_name VARCHAR(100),
  floor INT,
  capacity INT
);

CREATE TABLE providers (
  provider_id INT PRIMARY KEY,
  first_name VARCHAR(100),
  last_name  VARCHAR(100),
  credential VARCHAR(20),
  specialty_id INT REFERENCES specialties (specialty_id),
  department_id INT REFERENCES departments (department_id)
);

CREATE TABLE encounters (
  encounter_id INT PRIMARY KEY,
  patient_id INT REFERENCES patients (patient_id),
  provider_id INT REFERENCES providers (provider_id),
  encounter_type VARCHAR(50), -- 'Outpatient', 'Inpatient', 'ER'
  encounter_date TIMESTAMP,
  discharge_date TIMESTAMP,
  department_id INT REFERENCES departments (department_id)
);

CREATE INDEX idx_encounter_date ON encounters(encounter_date);

CREATE TABLE diagnoses (
  diagnosis_id INT PRIMARY KEY,
  icd10_code VARCHAR(10),
  icd10_description VARCHAR(200)
);

CREATE TABLE encounter_diagnoses (
  encounter_diagnosis_id INT PRIMARY KEY,
  encounter_id INT REFERENCES encounters (encounter_id),
  diagnosis_id INT REFERENCES diagnoses (diagnosis_id),
  diagnosis_sequence INT
);

CREATE TABLE procedures (
  procedure_id INT PRIMARY KEY,
  cpt_code VARCHAR(10),
  cpt_description VARCHAR(200)
);

CREATE TABLE encounter_procedures (
  encounter_procedure_id INT PRIMARY KEY,
  encounter_id INT REFERENCES encounters (encounter_id),
  procedure_id INT REFERENCES procedures (procedure_id),
  procedure_date DATE
);

CREATE TABLE billing (
  billing_id INT PRIMARY KEY,
  encounter_id INT REFERENCES encounters (encounter_id),
  claim_amount NUMERIC(12,2),
  allowed_amount NUMERIC(12,2),
  claim_date DATE,
  claim_status VARCHAR(50)
);

CREATE INDEX idx_claim_date ON billing(claim_date);

-- =========================================
-- SAMPLE  (RANDOM) DATA: 10000 Records for each table
-- =========================================

-- PATIENTS
INSERT INTO patients
SELECT gs, 'First'||gs, 'Last'||gs, date '1950-01-01' + (random()*20000)::int, CASE WHEN random()<0.5 THEN 'M' ELSE 'F' END, 'MRN'||lpad(gs::text,6,'0')
FROM generate_series(1,10000) gs;

-- SPECIALITIES
INSERT INTO specialties
SELECT gs, 'Specialty '||gs, 'SP'||gs
FROM generate_series(1,10000) gs;

-- DEPARTMENTS
INSERT INTO departments
SELECT gs, 'Department '||gs, (gs % 10)+1, (gs % 100)+10
FROM generate_series(1,10000) gs;

-- PROVIDERS
INSERT INTO providers
SELECT gs, 'ProvFirst'||gs, 'ProvLast'||gs, 'MD', (random()*9999)::int + 1, (random()*9999)::int + 1
FROM generate_series(1,10000) gs;

-- ENCOUNTERS
INSERT INTO encounters
SELECT gs, (random()*9999)::int + 1, (random()*9999)::int + 1, (ARRAY['Outpatient','Inpatient','ER'])[ (random()*2)::int + 1 ],
  timestamp '2023-01-01' + random()*interval '730 days', timestamp '2023-01-01' + random()*interval '730 days' + random()*interval '5 days', (random()*9999)::int + 1
FROM generate_series(1,10000) gs;

-- Make discharge_date AFTER encounter_date
UPDATE encounters
SET discharge_date =
  CASE
    WHEN encounter_type = 'Outpatient' THEN encounter_date + (random() * interval '6 hours')
    WHEN encounter_type = 'ER'        THEN encounter_date + (random() * interval '12 hours')
    ELSE                                   encounter_date + (random() * interval '10 days')
  end;

-- DIAGNOSES
INSERT INTO diagnoses
SELECT gs, 'D'||lpad(gs::text,5,'0'), 'Diagnosis '||gs
FROM generate_series(1,10000) gs;

-- ENCOUNTER_DIAGNOSES
INSERT INTO encounter_diagnoses
SELECT gs, (random()*9999)::int + 1, (random()*9999)::int + 1, (random()*3)::int + 1
FROM generate_series(1,10000) gs;

-- PROCEDURES
INSERT INTO procedures
SELECT gs, 'P'||lpad(gs::text,5,'0'), 'Procedure '||gs
FROM generate_series(1,10000) gs;


-- ENCOUNTER_PROCEDURES
INSERT INTO encounter_procedures
SELECT gs, (random()*9999)::int + 1, (random()*9999)::int + 1, date '2023-01-01' + (random()*730)::int
FROM generate_series(1,10000) gs;

-- BILLING
INSERT INTO billing
SELECT gs, (random()*9999)::int + 1, round((50+random()*10000)::numeric,2), round((20+random()*8000)::numeric,2),
  date '2023-01-01' + (random()*730)::int, (ARRAY['Paid','Denied','Pending'])[ (random()*2)::int + 1 ]
FROM generate_series(1,10000) gs;


--======================================================
-- TEST RUNS & ANALYSIS
--======================================================
-- Question 1
EXPLAIN (ANALYZE)
SELECT date_trunc('month', e.encounter_date)::date AS month_start, s.specialty_name,
  e.encounter_type, COUNT(*) AS total_encounters, COUNT(DISTINCT e.patient_id) AS unique_patients
FROM encounters e
JOIN providers p   ON p.provider_id = e.provider_id
JOIN specialties s ON s.specialty_id = p.specialty_id
GROUP BY date_trunc('month', e.encounter_date)::date, s.specialty_name, e.encounter_type
ORDER BY month_start, s.specialty_name, e.encounter_type;

-- Question 2
EXPLAIN (ANALYZE)
SELECT d.icd10_code, p.cpt_code, COUNT(DISTINCT ed.encounter_id) AS encounter_count
FROM encounter_diagnoses ed
JOIN diagnoses d ON d.diagnosis_id = ed.diagnosis_id
JOIN encounter_procedures ep ON ep.encounter_id = ed.encounter_id
JOIN procedures p ON p.procedure_id = ep.procedure_id
GROUP BY d.icd10_code, p.cpt_code
ORDER BY encounter_count DESC
LIMIT 20;

-- Question 3:
EXPLAIN (ANALYZE)
SELECT s.specialty_name, COUNT(DISTINCT e1.encounter_id) AS inpatient_discharges,
  COUNT(DISTINCT CASE WHEN e2.encounter_id IS NOT NULL THEN e1.encounter_id END) AS readmitted_in_30d,
  ROUND(COUNT(DISTINCT CASE WHEN e2.encounter_id IS NOT NULL THEN e1.encounter_id END)::numeric / NULLIF(COUNT(DISTINCT e1.encounter_id), 0), 4)
    AS readmission_rate
FROM encounters e1
JOIN providers p1 ON p1.provider_id = e1.provider_id
JOIN specialties s ON s.specialty_id = p1.specialty_id
LEFT JOIN encounters e2 ON e2.patient_id = e1.patient_id
 AND e2.encounter_date > e1.discharge_date
 AND e2.encounter_date <= e1.discharge_date + INTERVAL '30 days'
WHERE e1.encounter_type = 'Inpatient'
GROUP BY s.specialty_name
ORDER BY readmission_rate DESC;

--Question 4:
EXPLAIN (ANALYZE)
SELECT date_trunc('month', b.claim_date)::date AS month_start, s.specialty_name, SUM(b.allowed_amount) AS total_allowed_amount
FROM billing b
JOIN encounters e ON e.encounter_id = b.encounter_id
JOIN providers p ON p.provider_id = e.provider_id
JOIN specialties s ON s.specialty_id = p.specialty_id
GROUP BY date_trunc('month', b.claim_date)::date, s.specialty_name
ORDER BY month_start, total_allowed_amount DESC;







