
-- =================================================================================================
-- Procedure Name : silver.load_silver
-- Description    : Loads and transforms data from the Bronze layer into the Silver layer.
--                  Performs data cleansing, standardization, deduplication, and validation.
--
-- Execution      : EXEC silver.load_silver;
-- =================================================================================================

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    SET NOCOUNT ON;

    -- =============================================================================================
    -- Execution Tracking Variables
    -- =============================================================================================

    DECLARE @batch_start_time DATETIME2 = SYSDATETIME();
    DECLARE @batch_end_time   DATETIME2;
    DECLARE @table_start_time DATETIME2;
    DECLARE @table_end_time   DATETIME2;
    DECLARE @rows_inserted    INT;

    BEGIN TRY

        PRINT '================================================================================';
        PRINT 'Starting Silver Layer Load';
        PRINT 'Start Time: ' + CONVERT(VARCHAR(19), @batch_start_time, 120);
        PRINT '================================================================================';


        /* =========================================================================================
           1. LOAD CRM CUSTOMER INFORMATION
           Source      : bronze.crm_cust_info
           Target      : silver.crm_cust_info
           Description :
               - Removes records with NULL customer IDs
               - Deduplicates customers and keeps the latest record
               - Trims customer names
               - Standardizes marital status
               - Standardizes gender values
           ========================================================================================= */

        SET @table_start_time = SYSDATETIME();

        PRINT '';
        PRINT '--------------------------------------------------------------------------------';
        PRINT 'Loading silver.crm_cust_info...';

        TRUNCATE TABLE silver.crm_cust_info;

        INSERT INTO silver.crm_cust_info
        (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        SELECT
            cst_id,
            cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname) AS cst_lastname,
            CASE
                WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
                WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
                ELSE 'n/a'
            END AS cst_marital_status,
            CASE
                WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
                WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
                ELSE 'n/a'
            END AS cst_gndr,
            cst_create_date
        FROM
        (
            SELECT
                *,
                ROW_NUMBER() OVER
                (
                    PARTITION BY cst_id
                    ORDER BY cst_create_date DESC
                ) AS flag
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
        ) AS t
        WHERE t.flag = 1;

        SET @rows_inserted = @@ROWCOUNT;
        SET @table_end_time = SYSDATETIME();

        PRINT 'Completed silver.crm_cust_info';
        PRINT 'Rows Inserted : ' + CAST(@rows_inserted AS VARCHAR(20));
        PRINT 'Duration      : '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, @table_end_time) AS VARCHAR(20))
            + ' ms';


        /* =========================================================================================
           2. LOAD CRM PRODUCT INFORMATION
           Source      : bronze.crm_prd_info
           Target      : silver.crm_prd_info
           Description :
               - Extracts category ID from the product key
               - Cleans the product key
               - Replaces NULL product costs with zero
               - Standardizes product line values
               - Calculates product end date using the next product start date
           ========================================================================================= */

        SET @table_start_time = SYSDATETIME();

        PRINT '';
        PRINT '--------------------------------------------------------------------------------';
        PRINT 'Loading silver.crm_prd_info...';

        TRUNCATE TABLE silver.crm_prd_info;

        INSERT INTO silver.crm_prd_info
        (
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        SELECT
            prd_id,

            -- Extract category ID from the first five characters of the product key
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,

            -- Remove the category prefix from the original product key
            SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,

            prd_nm,

            -- Replace missing product costs with zero
            ISNULL(prd_cost, 0) AS prd_cost,

            -- Standardize product line codes into descriptive values
            CASE
                WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
                WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
                WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
                WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
                ELSE 'n/a'
            END AS prd_line,

            CAST(prd_start_dt AS DATE) AS prd_start_dt,

            -- Set the end date to one day before the next product start date
            CAST
            (
                LEAD(prd_start_dt) OVER
                (
                    PARTITION BY prd_key
                    ORDER BY prd_start_dt
                ) - 1
                AS DATE
            ) AS prd_end_dt

        FROM bronze.crm_prd_info;

        SET @rows_inserted = @@ROWCOUNT;
        SET @table_end_time = SYSDATETIME();

        PRINT 'Completed silver.crm_prd_info';
        PRINT 'Rows Inserted : ' + CAST(@rows_inserted AS VARCHAR(20));
        PRINT 'Duration      : '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, @table_end_time) AS VARCHAR(20))
            + ' ms';


        /* =========================================================================================
           3. LOAD CRM SALES DETAILS
           Source      : bronze.crm_sales_details
           Target      : silver.crm_sales_details
           Description :
               - Validates and converts integer-based date values
               - Recalculates invalid or missing sales amounts
               - Corrects invalid or missing product prices
               - Prevents division-by-zero errors
           ========================================================================================= */

        SET @table_start_time = SYSDATETIME();

        PRINT '';
        PRINT '--------------------------------------------------------------------------------';
        PRINT 'Loading silver.crm_sales_details...';

        TRUNCATE TABLE silver.crm_sales_details;

        INSERT INTO silver.crm_sales_details
        (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,

            -- Convert valid YYYYMMDD values to DATE; invalid values become NULL
            CASE
                WHEN sls_order_dt = 0
                     OR LEN(sls_order_dt) != 8
                    THEN NULL
                ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
            END AS sls_order_dt,

            CASE
                WHEN sls_ship_dt = 0
                     OR LEN(sls_ship_dt) != 8
                    THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
            END AS sls_ship_dt,

            CASE
                WHEN sls_due_dt = 0
                     OR LEN(sls_due_dt) != 8
                    THEN NULL
                ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
            END AS sls_due_dt,

            -- Recalculate sales when the existing value is missing, invalid,
            -- or inconsistent with quantity × price
            CASE
                WHEN sls_sales IS NULL
                     OR sls_sales <= 0
                     OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales,

            sls_quantity,

            -- Derive price from sales and quantity when price is missing or invalid
            CASE
                WHEN sls_price IS NULL
                     OR sls_price <= 0
                    THEN sls_sales / NULLIF(sls_quantity, 0)
                ELSE sls_price
            END AS sls_price

        FROM bronze.crm_sales_details;

        SET @rows_inserted = @@ROWCOUNT;
        SET @table_end_time = SYSDATETIME();

        PRINT 'Completed silver.crm_sales_details';
        PRINT 'Rows Inserted : ' + CAST(@rows_inserted AS VARCHAR(20));
        PRINT 'Duration      : '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, @table_end_time) AS VARCHAR(20))
            + ' ms';


        /* =========================================================================================
           4. LOAD ERP CUSTOMER INFORMATION
           Source      : bronze.erp_cust_az12
           Target      : silver.erp_cust_az12
           Description :
               - Removes the "NAS" prefix from customer IDs
               - Replaces future birth dates with NULL
               - Standardizes gender values
           ========================================================================================= */

        SET @table_start_time = SYSDATETIME();

        PRINT '';
        PRINT '--------------------------------------------------------------------------------';
        PRINT 'Loading silver.erp_cust_az12...';

        TRUNCATE TABLE silver.erp_cust_az12;

        INSERT INTO silver.erp_cust_az12
        (
            cid,
            bdate,
            gen
        )
        SELECT
            -- Remove the NAS prefix to align the customer ID with CRM data
            CASE
                WHEN cid LIKE 'NAS%'
                    THEN SUBSTRING(cid, 4, LEN(cid))
                ELSE cid
            END AS cid,

            -- Future birth dates are considered invalid
            CASE
                WHEN bdate > GETDATE()
                    THEN NULL
                ELSE bdate
            END AS bdate,

            -- Standardize gender values
            CASE
                WHEN gen IS NULL OR gen = '' THEN 'n/a'
                WHEN gen = 'M' THEN 'Male'
                WHEN gen = 'F' THEN 'Female'
                ELSE gen
            END AS gen

        FROM bronze.erp_cust_az12;

        SET @rows_inserted = @@ROWCOUNT;
        SET @table_end_time = SYSDATETIME();

        PRINT 'Completed silver.erp_cust_az12';
        PRINT 'Rows Inserted : ' + CAST(@rows_inserted AS VARCHAR(20));
        PRINT 'Duration      : '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, @table_end_time) AS VARCHAR(20))
            + ' ms';


        /* =========================================================================================
           5. LOAD ERP CUSTOMER LOCATION
           Source      : bronze.erp_loc_a101
           Target      : silver.erp_loc_a101
           Description :
               - Removes hyphens from customer IDs
               - Standardizes country names and country codes
               - Replaces missing country values with "n/a"
           ========================================================================================= */

        SET @table_start_time = SYSDATETIME();

        PRINT '';
        PRINT '--------------------------------------------------------------------------------';
        PRINT 'Loading silver.erp_loc_a101...';

        TRUNCATE TABLE silver.erp_loc_a101;

        INSERT INTO silver.erp_loc_a101
        (
            cid,
            cntry
        )
        SELECT
            -- Remove hyphens to align customer IDs with other source systems
            REPLACE(cid, '-', '') AS cid,

            -- Standardize country values
            CASE
                WHEN TRIM(cntry) IN ('USA', 'US') THEN 'United States'
                WHEN TRIM(cntry) IS NULL OR TRIM(cntry) = '' THEN 'n/a'
                WHEN TRIM(cntry) = 'DE' THEN 'Germany'
                ELSE TRIM(cntry)
            END AS cntry

        FROM bronze.erp_loc_a101;

        SET @rows_inserted = @@ROWCOUNT;
        SET @table_end_time = SYSDATETIME();

        PRINT 'Completed silver.erp_loc_a101';
        PRINT 'Rows Inserted : ' + CAST(@rows_inserted AS VARCHAR(20));
        PRINT 'Duration      : '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, @table_end_time) AS VARCHAR(20))
            + ' ms';


        /* =========================================================================================
           6. LOAD ERP PRODUCT CATEGORY INFORMATION
           Source      : bronze.erp_px_cat_g1v2
           Target      : silver.erp_px_cat_g1v2
           Description :
               - Loads product category and subcategory reference data
               - No additional transformation is required
           ========================================================================================= */

        SET @table_start_time = SYSDATETIME();

        PRINT '';
        PRINT '--------------------------------------------------------------------------------';
        PRINT 'Loading silver.erp_px_cat_g1v2...';

        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        INSERT INTO silver.erp_px_cat_g1v2
        (
            id,
            cat,
            subcat,
            maintenance
        )
        SELECT
            id,
            cat,
            subcat,
            maintenance
        FROM bronze.erp_px_cat_g1v2;

        SET @rows_inserted = @@ROWCOUNT;
        SET @table_end_time = SYSDATETIME();

        PRINT 'Completed silver.erp_px_cat_g1v2';
        PRINT 'Rows Inserted : ' + CAST(@rows_inserted AS VARCHAR(20));
        PRINT 'Duration      : '
            + CAST(DATEDIFF(MILLISECOND, @table_start_time, @table_end_time) AS VARCHAR(20))
            + ' ms';


        /* =========================================================================================
           SILVER LAYER LOAD COMPLETED SUCCESSFULLY
           ========================================================================================= */

        SET @batch_end_time = SYSDATETIME();

        PRINT '';
        PRINT '================================================================================';
        PRINT 'Silver Layer Load Completed Successfully';
        PRINT 'Start Time     : ' + CONVERT(VARCHAR(19), @batch_start_time, 120);
        PRINT 'End Time       : ' + CONVERT(VARCHAR(19), @batch_end_time, 120);
        PRINT 'Total Duration : '
            + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS VARCHAR(20))
            + ' seconds';
        PRINT '================================================================================';

    END TRY

    BEGIN CATCH

        -- =========================================================================================
        -- Capture Error Information
        -- =========================================================================================

        SET @batch_end_time = SYSDATETIME();

        DECLARE @error_number    INT            = ERROR_NUMBER();
        DECLARE @error_severity  INT            = ERROR_SEVERITY();
        DECLARE @error_state     INT            = ERROR_STATE();
        DECLARE @error_procedure NVARCHAR(128)  = ERROR_PROCEDURE();
        DECLARE @error_line      INT            = ERROR_LINE();
        DECLARE @error_message   NVARCHAR(4000) = ERROR_MESSAGE();

        PRINT '';
        PRINT '================================================================================';
        PRINT 'ERROR: Silver Layer Load Failed';
        PRINT '================================================================================';
        PRINT 'Start Time      : ' + CONVERT(VARCHAR(19), @batch_start_time, 120);
        PRINT 'Failure Time    : ' + CONVERT(VARCHAR(19), @batch_end_time, 120);
        PRINT 'Duration Before Failure: '
            + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS VARCHAR(20))
            + ' seconds';
        PRINT '--------------------------------------------------------------------------------';
        PRINT 'Error Number    : ' + CAST(@error_number AS VARCHAR(20));
        PRINT 'Error Severity  : ' + CAST(@error_severity AS VARCHAR(20));
        PRINT 'Error State     : ' + CAST(@error_state AS VARCHAR(20));
        PRINT 'Error Procedure : ' + ISNULL(@error_procedure, 'N/A');
        PRINT 'Error Line      : ' + CAST(@error_line AS VARCHAR(20));
        PRINT 'Error Message   : ' + @error_message;
        PRINT '================================================================================';

        -- Re-throw the original error to the calling application or SQL Agent job
        THROW;

    END CATCH;

END;
GO


-- =================================================================================================
-- Execute Procedure
-- =================================================================================================

-- EXEC silver.load_silver;
