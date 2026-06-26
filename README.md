# Healthcare-Revenue-Cycle-Denials-Analytics
Healthcare analytics project using SQL and Tableau to clean raw hospital claim logs, find duplicate billing errors, and map out where a hospital is losing revenue to insurance denials.

## Quick Links
* **Interactive Dashboard:** [View Live Healthcare Revenue Integrity Scorecard on Tableau Public](https://public.tableau.com/views/HealthcareRevenueIntegrityScorecard/Dashboard1?:language=en-US&publish=yes&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)
* **SQL Data Cleaning Script:** [View Healthcare_Revenue.sql](./Healthcare_Revenue.sql)

## Data Source
Original Dataset: https://www.kaggle.com/datasets/abuthahir1998/synthetic-healthcare-claims-dataset?resource=download&select=claim_data.csv

## The Challenge
In hospital administration, revenue cycle management ensures that clinical services rendered are accurately documented, billed, and reimbursed without financial leakages. This project bridges the gap between clinical documentation and financial data by staging raw transactional claim logs, auditing billing anomalies, and delivering an interactive revenue integrity scorecard. This data process helps hospital administrators isolate root causes of revenue leakage, improve clinical coding accuracy, and optimize overall cash flow performance.

## Tools Used
* **SQL (MySQL):** Window Functions (`ROW_NUMBER()`), Common Table Expressions (CTEs), Data Type Casting (`STR_TO_DATE`), String Cleansing (`TRIM`), Conditional Logic (`CASE WHEN`), Data Integrity Auditing, Views
* **Tableau:** Data Visualization, Interactive Scorecards, Filter Actions, Drill-down Logic, Trend Lines
* **Excel:** Initial Data Viewing

---

## The Process

### 1. Base Inspection & Environment Setup
* **Visual Audit:** Scanned the raw dataset in Excel to map column relationships and verify general data structure. 
* **Staging Environment:** Created a structured `claims_staging` table with explicit, native database types (`DECIMAL`, `DATE`, `VARCHAR`) to protect original file integrity.
* **Data Transformation during Ingest:** Populated the staging environment by cleaning text-based rows on the fly, applying `STR_TO_DATE` and `TRIM` to fix messy formatting into query-safe data types.

```sql
INSERT INTO claims_staging (...)
SELECT 
    `Claim ID`, `Provider ID`, `Patient ID`, 
    STR_TO_DATE(TRIM(`Date of Service`), '%m/%d/%Y'), 
    `Billed Amount`, `Procedure Code` -- 
FROM claim_data_raw;
```

### 2. Duplicate Claim Auditing (Step 1)
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

### 3. Data Cleansing & Text Standardization (Steps 2 & 3)
* **Whitespace Scrubbing:** Temporarily adjusted the database parameters via `SQL_SAFE_UPDATES` to safely run a multi-column `TRIM` statement, removing hidden spaces from structural text rows (`insurance_type`, `claim_status`, etc.).
* **Blank & Null Field Matrix:** Programmed conditional `SUM(CASE WHEN...)` matrices to scan clinical coding attributes and patient identification values for empty spaces, zeros, or hidden null strings.

```sql
SELECT 
    SUM(CASE WHEN patient_id IS NULL OR patient_id = '' OR patient_id = 0 THEN 1 ELSE 0 END) AS null_patient_ids,
    SUM(CASE WHEN diagnosis_code IS NULL OR diagnosis_code = '' THEN 1 ELSE 0 END) AS null_diagnosis_codes
FROM claims_staging;
```

### 4. Financial Integrity Verification & Volume Audits (Steps 3 & 4)
* **Accounting Logic Rules:** Ran mathematical exception checks to isolate data anomalies where insurance networks paid more than allowed contract values, or where allowed parameters exceeded the original baseline hospital bills.
* **Clinical Drivers Breakdown:** Aggregated system transaction counts by procedure codes to isolate and highlight primary clinical workload drivers.

```sql
-- Checking for internal financial integrity violations
SELECT COUNT(*) AS billing_logic_error
FROM claims_staging
WHERE paid_amount > allowed_amount 
   OR allowed_amount > billed_amount;
```

### 5. Final Metric Engineering & Tableau Production View (Step 5)
* **Calculated Feature Layout:** Structured an optimized database `VIEW` to serve clean data straight to Tableau without altering base staging tables. Embedded complex business math formulas to calculate insurance contract margins and tracking parameters.
* **Division Error Handling:** Deployed the `NULLIF` parameter to protect reporting metrics from mathematical division-by-zero calculation breaks.

```sql
CREATE OR REPLACE VIEW v_healthcare_revenue_integrity AS
SELECT 
    claim_id,
    (billed_amount - allowed_amount) AS contractual_adjustment,
    (allowed_amount - paid_amount) AS revenue_leakage,
    CASE WHEN reason_code = 'Duplicate Claim' THEN 1 ELSE 0 END AS duplicate_denial,
    ROUND((paid_amount / NULLIF(allowed_amount, 0)) * 100, 2) AS revenue_realization_rate
FROM claims_staging;
```

---

## Key Insights & Recommendations
* **Denial Root Causes:** Isolating insurance claim denials by reason codes revealed that specific departments had repetitive coding errors, showing exactly where staff need targeted documentation training.
* **Payer Inefficiencies:** Segmenting financial performance by insurance type identified which private payers held the highest volume of unresolved claims, giving hospital networks data leverage for contract renegotiations.
* **A/R Bottlenecks:** Tracking cash flow timelines by A/R status highlighted process delays post-patient discharge, helping administration identify exactly where billings stall.
