# Healthcare-Revenue-Cycle-Denials-Analytics
Healthcare analytics project using SQL and Tableau to clean raw hospital claim logs, find duplicate billing errors, and map out where a hospital is losing revenue to insurance denials.

## Quick Links
* **Interactive Dashboard:** [View Live Healthcare Revenue Integrity Scorecard on Tableau Public](https://public.tableau.com/views/HealthcareRevenueIntegrityScorecard/Dashboard1?:language=en-US&publish=yes&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)
* **SQL Data Cleaning Script:** [View Healthcare_Revenue.sql](./Healthcare_Revenue.sql)

  ## Dashboard Preview
![Healthcare Revenue Integrity Scorecard] (./Healthcare_Revenue_Dashboard.png)

## Data Source
Original Dataset: https://www.kaggle.com/datasets/abuthahir1998/synthetic-healthcare-claims-dataset?resource=download&select=claim_data.csv

## The Challenge
In hospital administration, revenue cycle management ensures that clinical services rendered are accurately documented, billed, and reimbursed without financial leakages. This project bridges the gap between clinical documentation and financial data by staging raw transactional claim logs, auditing billing anomalies, and delivering an interactive revenue integrity scorecard. This data process helps hospital administrators isolate root causes of revenue leakage, improve clinical coding accuracy, and optimize overall cash flow performance.

## Tools Used
* **SQL (MySQL):** Window Functions (`ROW_NUMBER()`), Common Table Expressions (CTEs), Data Type Casting (`STR_TO_DATE`), String Cleansing (`TRIM`), Conditional Logic (`CASE WHEN`), Data Integrity Auditing, Views
* **Tableau:** Data Visualization, Interactive Scorecards, Filter Actions, Drill-down Logic
* **Excel:** Initial Data Viewing

---

## Data Process

### Step 1: Base Inspection & Environment Setup
* **Visual Audit:** Scanned the raw dataset in Excel to map column relationships and verify general data structure. 
* **Staging Environment:** Created a structured `claims_staging` table with explicit, native database types (`DECIMAL`, `DATE`, `VARCHAR`) to protect original file integrity.
* **Data Transformation during Ingest:** Populated the staging environment by cleaning text-based rows on the fly, applying `STR_TO_DATE` and `TRIM` to fix messy formatting into query-safe data types.

```sql
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
```

### Step 2: Duplicate Claim Auditing
* **Encounter Volume Partitioning:** Built a Common Table Expression (CTE) utilizing `ROW_NUMBER()` to group transactions by matching patient attributes and transaction dates to pinpoint duplicate billing submission lag.
* **Deep History Audits:** Isolated rows explicitly flagged with a 'Duplicate Claim' reason code and joined them back against patient history records to audit repeating billing errors.
* **Aggregation by Payer:** Evaluated duplicate billing trends across different insurance networks using `COUNT` and `AVG` functions to isolate systemic billing problems.

```sql
WITH duplicate_cte AS (
    SELECT *,
           ROW_NUMBER() OVER(
               PARTITION BY claim_id, provider_id, patient_id, date_of_service, procedure_code 
               ORDER BY claim_id
           ) as row_num
    FROM claims_staging
)
SELECT * FROM duplicate_cte WHERE row_num > 1; 
```

### Step 3: Data Cleansing & Text Standardization
* **Text Space Trimming:** Temporarily adjusted the database parameters via `SQL_SAFE_UPDATES` to safely run a multi-column `TRIM` statement, removing hidden spaces from structural text rows (`insurance_type`, `claim_status`, etc.).
* **Blank & Null Field Tracking:** Programmed conditional `SUM(CASE WHEN...)` checks to scan clinical coding attributes and patient identification values for empty spaces, zeros, or hidden null strings.

```sql
SELECT 
    SUM(CASE WHEN patient_id IS NULL OR patient_id = '' OR patient_id = 0 THEN 1 ELSE 0 END) AS null_patient_ids,
    SUM(CASE WHEN provider_id IS NULL OR provider_id = '' OR provider_id = 0 THEN 1 ELSE 0 END) AS null_provider_ids,
    SUM(CASE WHEN procedure_code IS NULL OR procedure_code = '' OR procedure_code = 0 THEN 1 ELSE 0 END) AS null_procedure_codes,
    SUM(CASE WHEN diagnosis_code IS NULL OR diagnosis_code = '' THEN 1 ELSE 0 END) AS null_diagnosis_codes
FROM claims_staging;
```

### Step 4: Financial Integrity Verification & Volume Audits
* **Accounting Logic Rules:** Ran mathematical exception checks to isolate data anomalies where insurance networks paid more than allowed contract values, or where allowed parameters exceeded the original baseline hospital bills.
* **Clinical Drivers Breakdown:** Aggregated system transaction counts by procedure codes to isolate and highlight primary clinical workload drivers.

```sql
-- Checking for internal financial integrity violations
SELECT COUNT(*) AS billing_logic_error
FROM claims_staging
WHERE paid_amount > allowed_amount 
   OR allowed_amount > billed_amount;
```

### Step 5: Final Metric Engineering & BI Dashboard Production
* **Calculated Feature Layout:** Structured an optimized database `VIEW` to serve clean data straight to Tableau without altering base staging tables. Embedded complex business math formulas to calculate insurance contract margins and tracking parameters.
* **Division Error Handling:** Deployed the `NULLIF` parameter to protect reporting metrics from mathematical division-by-zero calculation breaks.

```sql
CREATE OR REPLACE VIEW v_healthcare_revenue_integrity AS
SELECT 
    claim_id, provider_id, patient_id, date_of_service, billed_amount, allowed_amount, paid_amount,
    insurance_type, claim_status, procedure_code, diagnosis_code, reason_code, follow_up_required, ar_status, outcome,
    (billed_amount - allowed_amount) AS contractual_adjustment,
    (allowed_amount - paid_amount) AS revenue_leakage,
    CASE WHEN reason_code = 'Duplicate Claim' THEN 1 ELSE 0 END AS duplicate_denial,
    ROUND((paid_amount / NULLIF(allowed_amount, 0)) * 100, 2) AS revenue_realization_rate
FROM claims_staging;
```

---

## Dashboard Key Performance Indicators (KPIs)
* **Total Billed Amount:** $297,000  
* **Total Collected Amount:** $220,754  
* **Revenue Realization Rate:** 89.9%  

---

## Dashboard Analysis & Business Utility

* **Accounts Receivable Queue Partitioning**
  * **Dashboard Function:** Breaks down the $297K outstanding balance into clear administrative statuses, color-coding each bucket by whether a manual intervention flag is active.
  * **Business Utility:** Gives operations managers a centralized view to filter down work volumes and divide stuck balances (ranging from $23K to $27K per category) among billing teams.

* **Denial Root Cause Tracing**
  * **Dashboard Function:** Maps uncollected revenue leakage directly against front-end submission errors, pointing out specific drivers like "Authorization Not Obtained" ($3,529) and "Incorrect Billing Info" ($3,391).
  * **Business Utility:** Identifies exactly which front-end check processes need adjustment to stop preventable billing leaks before claims are submitted.

* **Revenue Stream Mix**
  * **Dashboard Function:** Tracks the percentage breakdown of total collected funds across Commercial (26.5%), Medicaid (26.5%), Self-Pay (25.0%), and Medicare (22.0%).
  * **Business Utility:** Monitors overall financial risk exposure, highlighting that self-pay patients represent a substantial quarter of all successful collections.

