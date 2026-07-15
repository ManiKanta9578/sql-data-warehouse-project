-- =================================================================================================
-- SILVER LAYER DATA QUALITY CHECKS
-- Description:
--     Validates the quality, consistency, completeness, uniqueness,
--     standardization, and referential integrity of Silver layer data.
--
-- Expected Result:
--     Most exception queries should return ZERO rows.
--     Summary queries should return standardized and valid values.
-- =================================================================================================


/* =================================================================================================
   1. CRM CUSTOMER INFORMATION
   Table: silver.crm_cust_info

   Quality Checks:
       - Primary key uniqueness
       - Mandatory customer ID validation
       - Leading/trailing whitespace validation
       - Standardized marital status validation
       - Standardized gender validation
       - Duplicate customer key investigation
   ================================================================================================= */


-- -------------------------------------------------------------------------------------------------
-- Check 1.1: Verify customer ID uniqueness
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    cst_id,
    COUNT(*) AS duplicate_count
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 1.2: Verify mandatory customer IDs are not NULL
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_cust_info
WHERE cst_id IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 1.3: Verify customer first names do not contain leading or trailing spaces
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    cst_id,
    cst_firstname
FROM silver.crm_cust_info
WHERE cst_firstname != TRIM(cst_firstname);


-- -------------------------------------------------------------------------------------------------
-- Check 1.4: Verify customer last names do not contain leading or trailing spaces
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    cst_id,
    cst_lastname
FROM silver.crm_cust_info
WHERE cst_lastname != TRIM(cst_lastname);


-- -------------------------------------------------------------------------------------------------
-- Check 1.5: Review standardized marital status values
-- Expected Values: Married, Single, n/a
-- -------------------------------------------------------------------------------------------------

SELECT DISTINCT
    cst_marital_status
FROM silver.crm_cust_info
ORDER BY cst_marital_status;


-- -------------------------------------------------------------------------------------------------
-- Check 1.6: Detect unexpected marital status values
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_cust_info
WHERE cst_marital_status NOT IN ('Married', 'Single', 'n/a')
   OR cst_marital_status IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 1.7: Review standardized gender values
-- Expected Values: Male, Female, n/a
-- -------------------------------------------------------------------------------------------------

SELECT DISTINCT
    cst_gndr
FROM silver.crm_cust_info
ORDER BY cst_gndr;


-- -------------------------------------------------------------------------------------------------
-- Check 1.8: Detect unexpected gender values
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_cust_info
WHERE cst_gndr NOT IN ('Male', 'Female', 'n/a')
   OR cst_gndr IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 1.9: Check for duplicate customer business keys
-- Expected Result: Depends on source business rules
-- -------------------------------------------------------------------------------------------------

SELECT
    cst_key,
    COUNT(*) AS duplicate_count
FROM silver.crm_cust_info
WHERE cst_key IS NOT NULL
GROUP BY cst_key
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 1.10: Review final customer data
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_cust_info;



/* =================================================================================================
   2. CRM PRODUCT INFORMATION
   Table: silver.crm_prd_info

   Quality Checks:
       - Product ID uniqueness
       - Mandatory product ID validation
       - Product cost validation
       - Product line standardization
       - Product date range validation
       - Duplicate product business key investigation
   ================================================================================================= */


-- -------------------------------------------------------------------------------------------------
-- Check 2.1: Verify product ID uniqueness
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    prd_id,
    COUNT(*) AS duplicate_count
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 2.2: Verify mandatory product IDs are not NULL
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_prd_info
WHERE prd_id IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 2.3: Verify product cost is not NULL or negative
-- Expected Result: No rows
--
-- Note:
--     The Silver transformation replaces NULL costs with 0.
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_prd_info
WHERE prd_cost IS NULL
   OR prd_cost < 0;


-- -------------------------------------------------------------------------------------------------
-- Check 2.4: Review standardized product line values
-- Expected Values: Mountain, Road, Other Sales, Touring, n/a
-- -------------------------------------------------------------------------------------------------

SELECT DISTINCT
    prd_line
FROM silver.crm_prd_info
ORDER BY prd_line;


-- -------------------------------------------------------------------------------------------------
-- Check 2.5: Detect unexpected product line values
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_prd_info
WHERE prd_line NOT IN
(
    'Mountain',
    'Road',
    'Other Sales',
    'Touring',
    'n/a'
)
OR prd_line IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 2.6: Validate product date ranges
-- End date must not be earlier than start date
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_prd_info
WHERE prd_end_dt IS NOT NULL
  AND prd_end_dt < prd_start_dt;


-- -------------------------------------------------------------------------------------------------
-- Check 2.7: Verify product start date is available
-- Expected Result: Depends on source business rules
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_prd_info
WHERE prd_start_dt IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 2.8: Check for duplicate product business keys and start dates
-- Expected Result: No rows if each product version is unique
-- -------------------------------------------------------------------------------------------------

SELECT
    prd_key,
    prd_start_dt,
    COUNT(*) AS duplicate_count
FROM silver.crm_prd_info
GROUP BY
    prd_key,
    prd_start_dt
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 2.9: Validate product version date continuity
--
-- Expected Result: No rows
--
-- Each product version's end date should be exactly one day before
-- the next version's start date.
-- -------------------------------------------------------------------------------------------------

WITH product_versions AS
(
    SELECT
        prd_id,
        prd_key,
        prd_start_dt,
        prd_end_dt,
        LEAD(prd_start_dt) OVER
        (
            PARTITION BY prd_key
            ORDER BY prd_start_dt
        ) AS next_start_dt
    FROM silver.crm_prd_info
)
SELECT *
FROM product_versions
WHERE next_start_dt IS NOT NULL
  AND prd_end_dt != DATEADD(DAY, -1, next_start_dt);


-- -------------------------------------------------------------------------------------------------
-- Check 2.10: Review final product data
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_prd_info;



/* =================================================================================================
   3. CRM SALES DETAILS
   Table: silver.crm_sales_details

   Quality Checks:
       - Product referential integrity
       - Customer referential integrity
       - Date validity
       - Date sequence validation
       - Sales amount validation
       - Quantity validation
       - Price validation
   ================================================================================================= */


-- -------------------------------------------------------------------------------------------------
-- Check 3.1: Identify sales records with product keys not found in Silver product data
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    s.*
FROM silver.crm_sales_details AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.crm_prd_info AS p
    WHERE p.prd_key = s.sls_prd_key
);


-- -------------------------------------------------------------------------------------------------
-- Check 3.2: Identify sales records with customer IDs not found in Silver customer data
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    s.*
FROM silver.crm_sales_details AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.crm_cust_info AS c
    WHERE c.cst_id = s.sls_cust_id
);


-- -------------------------------------------------------------------------------------------------
-- Check 3.3: Verify mandatory sales keys are not NULL
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_sales_details
WHERE sls_ord_num IS NULL
   OR sls_prd_key IS NULL
   OR sls_cust_id IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 3.4: Validate sales date range
-- Expected Result: No rows
--
-- Adjust the minimum date based on actual business requirements.
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_sales_details
WHERE sls_order_dt < '1900-01-01'
   OR sls_order_dt > GETDATE()
   OR sls_ship_dt < '1900-01-01'
   OR sls_ship_dt > GETDATE()
   OR sls_due_dt < '1900-01-01'
   OR sls_due_dt > GETDATE();


-- -------------------------------------------------------------------------------------------------
-- Check 3.5: Validate chronological order of sales dates
--
-- Business Rule:
--     Order Date <= Ship Date
--     Order Date <= Due Date
--
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_sales_details
WHERE (sls_order_dt IS NOT NULL
       AND sls_ship_dt IS NOT NULL
       AND sls_order_dt > sls_ship_dt)
   OR (sls_order_dt IS NOT NULL
       AND sls_due_dt IS NOT NULL
       AND sls_order_dt > sls_due_dt);


-- -------------------------------------------------------------------------------------------------
-- Check 3.6: Validate sales amount
--
-- Business Rule:
--     Sales = Quantity × ABS(Price)
--
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    sls_ord_num,
    sls_sales,
    sls_quantity,
    sls_price,
    sls_quantity * ABS(sls_price) AS expected_sales
FROM silver.crm_sales_details
WHERE sls_sales IS NULL
   OR sls_sales <= 0
   OR sls_sales != sls_quantity * ABS(sls_price);


-- -------------------------------------------------------------------------------------------------
-- Check 3.7: Validate sales quantity
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_sales_details
WHERE sls_quantity IS NULL
   OR sls_quantity <= 0;


-- -------------------------------------------------------------------------------------------------
-- Check 3.8: Validate product price
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_sales_details
WHERE sls_price IS NULL
   OR sls_price <= 0;


-- -------------------------------------------------------------------------------------------------
-- Check 3.9: Check for possible duplicate sales records
--
-- Expected Result:
--     Review based on the actual business key of the sales table.
-- -------------------------------------------------------------------------------------------------

SELECT
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    COUNT(*) AS duplicate_count
FROM silver.crm_sales_details
GROUP BY
    sls_ord_num,
    sls_prd_key,
    sls_cust_id
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 3.10: Review final sales data
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.crm_sales_details;



/* =================================================================================================
   4. ERP CUSTOMER INFORMATION
   Table: silver.erp_cust_az12

   Quality Checks:
       - Customer ID consistency with CRM
       - Future birth date validation
       - Unrealistic birth date investigation
       - Gender standardization
       - Duplicate customer ID validation
   ================================================================================================= */


-- -------------------------------------------------------------------------------------------------
-- Check 4.1: Verify ERP customer IDs exist in CRM customer data
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    e.*
FROM silver.erp_cust_az12 AS e
WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.crm_cust_info AS c
    WHERE c.cst_key = e.cid
);


-- -------------------------------------------------------------------------------------------------
-- Check 4.2: Check for duplicate ERP customer IDs
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    cid,
    COUNT(*) AS duplicate_count
FROM silver.erp_cust_az12
GROUP BY cid
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 4.3: Verify birth dates are not in the future
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_cust_az12
WHERE bdate > GETDATE();


-- -------------------------------------------------------------------------------------------------
-- Check 4.4: Identify potentially unrealistic birth dates
--
-- Expected Result:
--     Review manually.
--
-- Note:
--     This is a business-quality check rather than a strict technical error.
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_cust_az12
WHERE bdate < '1924-01-01';


-- -------------------------------------------------------------------------------------------------
-- Check 4.5: Review standardized gender values
-- Expected Values: Male, Female, n/a
-- -------------------------------------------------------------------------------------------------

SELECT DISTINCT
    gen
FROM silver.erp_cust_az12
ORDER BY gen;


-- -------------------------------------------------------------------------------------------------
-- Check 4.6: Detect unexpected gender values
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_cust_az12
WHERE gen NOT IN ('Male', 'Female', 'n/a')
   OR gen IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 4.7: Review final ERP customer data
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_cust_az12;



/* =================================================================================================
   5. ERP CUSTOMER LOCATION
   Table: silver.erp_loc_a101

   Quality Checks:
       - Customer ID consistency with CRM
       - Duplicate customer IDs
       - Country standardization
       - Missing country values
       - Customer ID format validation
   ================================================================================================= */


-- -------------------------------------------------------------------------------------------------
-- Check 5.1: Verify location customer IDs exist in CRM customer data
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    l.*
FROM silver.erp_loc_a101 AS l
WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.crm_cust_info AS c
    WHERE c.cst_key = l.cid
);


-- -------------------------------------------------------------------------------------------------
-- Check 5.2: Check for duplicate location customer IDs
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    cid,
    COUNT(*) AS duplicate_count
FROM silver.erp_loc_a101
GROUP BY cid
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 5.3: Verify customer IDs no longer contain hyphens
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_loc_a101
WHERE cid LIKE '%-%';


-- -------------------------------------------------------------------------------------------------
-- Check 5.4: Review standardized country values
-- -------------------------------------------------------------------------------------------------

SELECT DISTINCT
    cntry
FROM silver.erp_loc_a101
ORDER BY cntry;


-- -------------------------------------------------------------------------------------------------
-- Check 5.5: Detect NULL or blank country values
--
-- Expected Result: No rows
-- Missing values should have been standardized to 'n/a'.
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_loc_a101
WHERE cntry IS NULL
   OR TRIM(cntry) = '';


-- -------------------------------------------------------------------------------------------------
-- Check 5.6: Detect unstandardized country codes
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_loc_a101
WHERE cntry IN ('USA', 'US', 'DE');


-- -------------------------------------------------------------------------------------------------
-- Check 5.7: Review final ERP location data
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_loc_a101;



/* =================================================================================================
   6. ERP PRODUCT CATEGORY INFORMATION
   Table: silver.erp_px_cat_g1v2

   Quality Checks:
       - Category ID uniqueness
       - Mandatory category ID validation
       - Product category referential integrity
       - Missing category attributes
   ================================================================================================= */


-- -------------------------------------------------------------------------------------------------
-- Check 6.1: Verify category ID uniqueness
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT
    id,
    COUNT(*) AS duplicate_count
FROM silver.erp_px_cat_g1v2
GROUP BY id
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------------------------------------------
-- Check 6.2: Verify category IDs are not NULL
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_px_cat_g1v2
WHERE id IS NULL;


-- -------------------------------------------------------------------------------------------------
-- Check 6.3: Verify CRM product category IDs exist in ERP category data
-- Expected Result: No rows
-- -------------------------------------------------------------------------------------------------

SELECT DISTINCT
    p.cat_id
FROM silver.crm_prd_info AS p
WHERE p.cat_id IS NOT NULL
  AND NOT EXISTS
(
    SELECT 1
    FROM silver.erp_px_cat_g1v2 AS c
    WHERE c.id = p.cat_id
);


-- -------------------------------------------------------------------------------------------------
-- Check 6.4: Detect missing category or subcategory values
-- Expected Result: Review based on business requirements
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_px_cat_g1v2
WHERE cat IS NULL
   OR TRIM(cat) = ''
   OR subcat IS NULL
   OR TRIM(subcat) = '';


-- -------------------------------------------------------------------------------------------------
-- Check 6.5: Review final product category data
-- -------------------------------------------------------------------------------------------------

SELECT *
FROM silver.erp_px_cat_g1v2;



/* =================================================================================================
   7. SILVER LAYER ROW COUNT SUMMARY

   Purpose:
       Provides a quick overview of the number of records loaded into each Silver table.
   ================================================================================================= */

SELECT
    'silver.crm_cust_info' AS table_name,
    COUNT(*) AS row_count
FROM silver.crm_cust_info

UNION ALL

SELECT
    'silver.crm_prd_info',
    COUNT(*)
FROM silver.crm_prd_info

UNION ALL

SELECT
    'silver.crm_sales_details',
    COUNT(*)
FROM silver.crm_sales_details

UNION ALL

SELECT
    'silver.erp_cust_az12',
    COUNT(*)
FROM silver.erp_cust_az12

UNION ALL

SELECT
    'silver.erp_loc_a101',
    COUNT(*)
FROM silver.erp_loc_a101

UNION ALL

SELECT
    'silver.erp_px_cat_g1v2',
    COUNT(*)
FROM silver.erp_px_cat_g1v2;



/* =================================================================================================
   8. SILVER LAYER HIGH-LEVEL DATA QUALITY SUMMARY

   Purpose:
       Returns the number of detected issues for important quality rules.

   Expected Result:
       issue_count = 0 for all critical checks.
   ================================================================================================= */

SELECT
    'Duplicate Customer IDs' AS quality_check,
    COUNT(*) AS issue_count
FROM
(
    SELECT cst_id
    FROM silver.crm_cust_info
    GROUP BY cst_id
    HAVING COUNT(*) > 1
) AS issues

UNION ALL

SELECT
    'Duplicate Product IDs',
    COUNT(*)
FROM
(
    SELECT prd_id
    FROM silver.crm_prd_info
    GROUP BY prd_id
    HAVING COUNT(*) > 1
) AS issues

UNION ALL

SELECT
    'Orphan Sales Product Keys',
    COUNT(*)
FROM silver.crm_sales_details AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.crm_prd_info AS p
    WHERE p.prd_key = s.sls_prd_key
)

UNION ALL

SELECT
    'Orphan Sales Customer IDs',
    COUNT(*)
FROM silver.crm_sales_details AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM silver.crm_cust_info AS c
    WHERE c.cst_id = s.sls_cust_id
)

UNION ALL

SELECT
    'Invalid Sales Amounts',
    COUNT(*)
FROM silver.crm_sales_details
WHERE sls_sales IS NULL
   OR sls_sales <= 0
   OR sls_sales != sls_quantity * ABS(sls_price)

UNION ALL

SELECT
    'Invalid Sales Quantities',
    COUNT(*)
FROM silver.crm_sales_details
WHERE sls_quantity IS NULL
   OR sls_quantity <= 0

UNION ALL

SELECT
    'Invalid Sales Prices',
    COUNT(*)
FROM silver.crm_sales_details
WHERE sls_price IS NULL
   OR sls_price <= 0

UNION ALL

SELECT
    'Future Birth Dates',
    COUNT(*)
FROM silver.erp_cust_az12
WHERE bdate > GETDATE()

UNION ALL

SELECT
    'Invalid CRM Gender Values',
    COUNT(*)
FROM silver.crm_cust_info
WHERE cst_gndr NOT IN ('Male', 'Female', 'n/a')
   OR cst_gndr IS NULL

UNION ALL

SELECT
    'Invalid CRM Marital Status Values',
    COUNT(*)
FROM silver.crm_cust_info
WHERE cst_marital_status NOT IN ('Married', 'Single', 'n/a')
   OR cst_marital_status IS NULL

UNION ALL

SELECT
    'Missing Product Categories',
    COUNT(*)
FROM silver.crm_prd_info AS p
WHERE p.cat_id IS NOT NULL
  AND NOT EXISTS
(
    SELECT 1
    FROM silver.erp_px_cat_g1v2 AS c
    WHERE c.id = p.cat_id
);
