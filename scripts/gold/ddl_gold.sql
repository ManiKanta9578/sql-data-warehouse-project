/*============================================================================
    GOLD LAYER - STAR SCHEMA
    ===========================================================================
    Purpose:
        Creates the dimensional model for reporting and analytics.

    Objects:
        1. gold.dim_customers  - Customer Dimension
        2. gold.dim_products   - Product Dimension
        3. gold.fact_sales     - Sales Fact Table (View)

    Notes:
        - Surrogate keys are generated using ROW_NUMBER().
        - Dimension tables contain descriptive business attributes.
        - Fact table stores transactional sales data and references dimensions.
============================================================================*/


/*============================================================================
    View Name : gold.dim_customers
    Purpose   : Customer Dimension

    Description:
        - Combines CRM customer information with ERP customer
          demographic and location data.
        - Generates a surrogate customer key.
        - Standardizes gender values.
        - Provides descriptive customer attributes for analytics.
============================================================================*/
IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
    DROP VIEW gold.dim_customers;
GO

CREATE VIEW gold.dim_customers AS
SELECT
      ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key
    , ci.cst_id AS customer_id
    , ci.cst_key AS customer_number
    , ci.cst_firstname AS first_name
    , ci.cst_lastname AS last_name
    , cl.cntry AS country
    , ci.cst_marital_status AS marital_status
    , CASE
          WHEN ci.cst_gndr <> 'n/a'
              THEN ci.cst_gndr
          ELSE COALESCE(cu.gen, 'n/a')
      END AS gender
    , cu.bdate AS birthdate
    , ci.cst_create_date AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 cu
       ON ci.cst_key = cu.cid
LEFT JOIN silver.erp_loc_a101 cl
       ON ci.cst_key = cl.cid;

GO


/*============================================================================
    View Name : gold.dim_products
    Purpose   : Product Dimension

    Description:
        - Combines product master data with category information.
        - Generates a surrogate product key.
        - Returns only active products
          (products with NULL end date).
        - Provides product hierarchy for reporting.
============================================================================*/
IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO

CREATE VIEW gold.dim_products AS
SELECT
      ROW_NUMBER() OVER (ORDER BY prd.prd_start_dt, prd.prd_key) AS product_key
    , prd.prd_id AS product_id
    , prd.prd_key AS product_number
    , prd.prd_nm AS product_name
    , cat.id AS category_id
    , cat.cat AS category
    , cat.subcat AS subcategory
    , cat.maintenance
    , prd.prd_cost AS cost
    , prd.prd_line AS product_line
    , prd.prd_start_dt AS start_date
FROM silver.crm_prd_info prd
LEFT JOIN silver.erp_px_cat_g1v2 cat
       ON prd.cat_id = cat.id
WHERE prd.prd_end_dt IS NULL;

GO


/*============================================================================
    View Name : gold.fact_sales
    Purpose   : Sales Fact Table

    Description:
        - Stores transactional sales information.
        - Links each transaction to customer and product dimensions.
        - Contains business measures such as:
              • Sales Amount
              • Quantity
              • Unit Price
        - Supports analytical reporting using the star schema.
============================================================================*/
IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;
GO

CREATE VIEW gold.fact_sales AS
SELECT
      sls.sls_ord_num AS order_number
    , prd.product_key AS product_key
    , cus.customer_key AS customer_key
    , sls.sls_order_dt AS order_date
    , sls.sls_ship_dt AS shipping_date
    , sls.sls_due_dt AS due_date
    , sls.sls_sales AS sales_amount
    , sls.sls_quantity AS quantity
    , sls.sls_price AS price
FROM silver.crm_sales_details sls
LEFT JOIN gold.dim_customers cus
       ON sls.sls_cust_id = cus.customer_id
LEFT JOIN gold.dim_products prd
       ON sls.sls_prd_key = prd.product_number;

GO
