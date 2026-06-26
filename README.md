# Healthcare-Revenue-Cycle-Denials-Analytics
Healthcare analytics project using SQL and Tableau to clean raw hospital claim logs, find duplicate billing errors, and map out where a hospital is losing revenue to insurance denials.

## 🔍 My Step-by-Step SQL Process

Here is exactly how I cleaned and prepped the raw billing data before connecting it to Tableau.

### Step 1: Setting up a Staging Table
Instead of messing with the raw raw data, I created a fresh staging table to do my cleaning work. This is where I fixed the column data types—making sure things like dates were stored as actual `DATE` types and dollar amounts were saved as `DECIMAL` numbers so the math wouldn't break later.

```sql
CREATE TABLE claims_staging (
    claim_id VARCHAR(50) PRIMARY KEY,
    billed_amount DECIMAL(10,2),  
    date_of_service DATE,  
    allowed_amount DECIMAL(10,2),
    paid_amount DECIMAL(10,2)
);
```

### Step 2: Catching Duplicate Claims
In hospital billing, system lag often causes the same claim to get submitted twice. To find these, I used a CTE and a window function (`ROW_NUMBER()`). I grouped the data by patient, doctor, date, and procedure code to flag any identical rows that shouldn't be there.

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

### Step 3: Double-Checking the Math
Next, I checked for data entry typos and weird accounting errors. I wrote a query to find any weird cases where the insurance company somehow paid *more* than what was contractually allowed, or where the allowed amount was higher than what the hospital originally billed.

```sql
SELECT COUNT(*) AS billing_logic_error
FROM claims_staging
WHERE paid_amount > allowed_amount 
   OR allowed_amount > billed_amount;
```

### Step 4: Building the Final Database View
Once the data was completely cleaned up, I wrapped everything into a database `VIEW` for Tableau. Inside this view, I wrote the math to calculate the hospital's financial losses (revenue leakage) and the percentage of money they actually collected. I used `NULLIF` to prevent division-by-zero math errors.

```sql
CREATE OR REPLACE VIEW v_healthcare_revenue_integrity AS
SELECT 
    claim_id,
    billed_amount,
    allowed_amount,
    paid_amount,
    (billed_amount - allowed_amount) AS contractual_adjustment,
    (allowed_amount - paid_amount) AS revenue_leakage,
    ROUND((paid_amount / NULLIF(allowed_amount, 0)) * 100, 2) AS revenue_realization_rate
FROM claims_staging;
```
