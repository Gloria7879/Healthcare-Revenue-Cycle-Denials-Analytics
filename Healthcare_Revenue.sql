
-- Project: Healthcare Revenue Cycle Management
-- Objective: Clean,validate, and standardize raw claim transactions for Tableau.

-- Stages:
-- 1)Remove duplicates 
-- 2) Standardize the data 
-- 3) Null values or blank values 
-- 4) Remove any columns
-- 5) Create Production View for Tableau

USE healthcare_analytics;

-- Base inspection of raw data source
SELECT *
FROM claim_data_raw;

-- Create staging table with defined data types
CREATE TABLE claims_staging (
    claim_id VARCHAR(50) PRIMARY KEY,
    provider_id VARCHAR(50),      
    patient_id VARCHAR(50),       
    date_of_service DATE,  
    billed_amount DECIMAL(10,2),  
    procedure_code VARCHAR(20),   
    diagnosis_code VARCHAR(20),
    allowed_amount DECIMAL(10,2),
    paid_amount DECIMAL(10,2),
    insurance_type VARCHAR(50),
    claim_status VARCHAR(50),
    reason_code VARCHAR(255),
    follow_up_required VARCHAR(10),
    ar_status VARCHAR(50),
    outcome VARCHAR(50)
);

-- Populate staging table with raw data
INSERT INTO claims_staging (
    `claim_id`, `provider_id`, `patient_id`, `date_of_service`, `billed_amount`, 
    `procedure_code`, `diagnosis_code`, `allowed_amount`, `paid_amount`, 
    `insurance_type`, `claim_status`, `reason_code`, `follow_up_required`, `ar_status`, `outcome`
)
SELECT 
    `Claim ID`, `Provider ID`, `Patient ID`, 
    STR_TO_DATE(TRIM(`Date of Service`), '%m/%d/%Y'), 
    `Billed Amount`, `Procedure Code`, `Diagnosis Code`, `Allowed Amount`, `Paid Amount`, 
    `Insurance Type`, `Claim Status`, `Reason Code`, `Follow-up Required`, `AR Status`, `Outcome`
FROM claim_data_raw;

-- STEP 1: REMOVE DUPLICATES (AUDITING ENCOUNTERS & TRANSACTION CODES)

-- Check for duplicate transactions
WITH duplicate_cte AS (
    SELECT *,
           ROW_NUMBER() OVER(
               PARTITION BY claim_id, provider_id, patient_id, date_of_service, procedure_code 
               ORDER BY claim_id
           ) as row_num
    FROM claims_staging
)
SELECT * 
FROM duplicate_cte
WHERE row_num > 1; 

-- Inspect unique values in reason code column
SELECT 
DISTINCT reason_code
FROM claims_staging;

-- Isolate records flagged with 'Duplicate Claim'
SELECT * 
FROM claims_staging
WHERE reason_code = 'Duplicate Claim';

-- Audit full patient histories flagged with a 'Duplicate Claim' reason code
WITH duplicate_cte_reason_code AS (
    SELECT DISTINCT patient_id, date_of_service, procedure_code
    FROM claims_staging
    WHERE reason_code = 'Duplicate Claim'
)

SELECT c.*
FROM claims_staging c
JOIN duplicate_cte_reason_code d 
    ON c.patient_id = d.patient_id 
    AND c.date_of_service = d.date_of_service
    AND c.procedure_code = d.procedure_code
ORDER BY c.patient_id, c.date_of_service;

-- Check for multi-row patient encounter volumes 
SELECT patient_id, COUNT(*) as appearance_count
FROM claims_staging
GROUP BY patient_id
HAVING appearance_count > 1
ORDER BY appearance_count DESC;

-- Analyze duplicate claim totals by insurance type
SELECT 
    insurance_type, 
    claim_status, 
    outcome, 
    COUNT(*) as total_claims,
    AVG(billed_amount) as avg_billed_amt
FROM claims_staging
WHERE reason_code = 'Duplicate Claim'
GROUP BY insurance_type, claim_status, outcome
ORDER BY total_claims DESC;

-- STEP 2: STANDARDIZE DATA

-- Verify string-to-date changes
SELECT
date_of_service
FROM claims_staging;

-- Verify final table data and structure
SELECT *
FROM claims_staging;

DESCRIBE claims_staging;

-- STEP 3: NULL VALUES OR BLANK VALUES

-- Audit text columns for hidden formatting or space issues
SELECT DISTINCT 
reason_code
FROM claims_staging;

SELECT DISTINCT follow_up_required 
FROM claims_staging;

SELECT DISTINCT insurance_type 
FROM claims_staging;

SELECT DISTINCT claim_status
 FROM claims_staging;
 
SELECT DISTINCT ar_status 
FROM claims_staging;

SELECT DISTINCT outcome 
FROM claims_staging;

SELECT 
    SUM(CASE WHEN patient_id IS NULL OR patient_id = '' OR patient_id = 0 THEN 1 ELSE 0 END) AS null_patient_ids,
    SUM(CASE WHEN provider_id IS NULL OR provider_id = '' OR provider_id = 0 THEN 1 ELSE 0 END) AS null_provider_ids,
    SUM(CASE WHEN procedure_code IS NULL OR procedure_code = '' OR procedure_code = 0 THEN 1 ELSE 0 END) AS null_procedure_codes,
    SUM(CASE WHEN diagnosis_code IS NULL OR diagnosis_code = '' THEN 1 ELSE 0 END) AS null_diagnosis_codes
FROM claims_staging;

SET SQL_SAFE_UPDATES = 0;

UPDATE claims_staging
SET 
    insurance_type = TRIM(insurance_type),
    claim_status = TRIM(claim_status),
    ar_status = TRIM(ar_status),
    outcome = TRIM(outcome);
    
SET SQL_SAFE_UPDATES = 1;
    
-- Inspect financial ranges to check for anomalies or negative billing balances
SELECT 
    MIN(billed_amount) AS min_billed, 
    MAX(billed_amount) AS max_billed,
    MIN(paid_amount) AS min_paid, 
    MAX(paid_amount) AS max_paid
FROM claims_staging;

-- AUDIT: Check for financial integrity violations
SELECT COUNT(*) AS billing_logic_error
FROM claims_staging
WHERE paid_amount > allowed_amount 
   OR allowed_amount > billed_amount;


-- Scan text columns for missing or blank data fields
SELECT 
    COUNT(*) as total_rows,
    SUM(CASE WHEN insurance_type IS NULL OR insurance_type = '' THEN 1 ELSE 0 END) as null_insurance,
    SUM(CASE WHEN claim_status IS NULL OR claim_status = '' THEN 1 ELSE 0 END) as null_status,
    SUM(CASE WHEN ar_status IS NULL OR ar_status = '' THEN 1 ELSE 0 END) as null_ar,
    SUM(CASE WHEN outcome IS NULL OR outcome = '' THEN 1 ELSE 0 END) as null_outcome
FROM claims_staging;

-- Scan identification fields and clinical codes for missing or blank entries
SELECT 
    SUM(CASE WHEN patient_id IS NULL OR patient_id = '' OR patient_id = 0 THEN 1 ELSE 0 END) AS null_patient_ids,
    SUM(CASE WHEN provider_id IS NULL OR provider_id = '' OR provider_id = 0 THEN 1 ELSE 0 END) AS null_provider_ids,
    SUM(CASE WHEN procedure_code IS NULL OR procedure_code = '' OR procedure_code = 0 THEN 1 ELSE 0 END) AS null_procedure_codes,
    SUM(CASE WHEN diagnosis_code IS NULL OR diagnosis_code = '' THEN 1 ELSE 0 END) AS null_diagnosis_codes
FROM claims_staging;

-- STEP 4: REMOVE ANY COLUMNS

-- Examine primary procedure volumes to find key medical drivers
SELECT procedure_code, COUNT(*) as volume
FROM claims_staging
GROUP BY procedure_code
ORDER BY volume DESC;

SELECT * 
FROM claims_staging;

-- STEP 5: CREATE PRODUCTION VIEW FOR TABLEAU 

CREATE OR REPLACE VIEW v_healthcare_revenue_integrity AS
SELECT 
    claim_id,
    provider_id,
    patient_id,
    date_of_service,
    billed_amount,
    allowed_amount,
    paid_amount,
    insurance_type,
    claim_status,
    procedure_code,
    diagnosis_code,
    reason_code,
    follow_up_required,
    ar_status,
    outcome,
    
    -- Contractual Adjustment: The standard pre-negotiated discount given to the insurer
    (billed_amount - allowed_amount) AS contractual_adjustment,
    
    -- Revenue Leakage: The gap between the approved contract rate and actual cash received
    (allowed_amount - paid_amount) AS revenue_leakage,
    
    -- Denials tracking: Isolates administrative billing submission errors for provider billing audits
    CASE WHEN reason_code = 'Duplicate Claim' THEN 1 ELSE 0 END AS duplicate_denial,
    
    -- Collection Scorecard: Revenue Realization Rate metric based on what we are contractually allowed to collect
    ROUND((paid_amount / NULLIF(allowed_amount, 0)) * 100, 2) AS revenue_realization_rate
FROM claims_staging;

-- Production View for Tableau
SELECT * FROM v_healthcare_revenue_integrity;