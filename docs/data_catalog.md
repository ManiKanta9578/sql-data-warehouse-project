# Data Catalog

## Overview

This document describes the Gold Layer data warehouse objects used for reporting and analytics.

---

# Table: `gold.dim_customers`

## Purpose
Stores customer master information by combining CRM customer data with ERP demographic and location information.

## Grain
One record per customer.

## Columns

| Column | Data Type | Description |
|:-------|:---------|:------------|
| customer_key | bigint | Surrogate key generated for the customer dimension. Used to join with fact tables. |
| customer_id | int | Business identifier of the customer from the CRM system. |
| customer_number | nvarchar | Customer business key from the source system. |
| first_name | nvarchar | Customer's first name. |
| last_name | nvarchar | Customer's last name. |
| country | nvarchar | Customer's country. |
| marital_status | nvarchar | Customer's marital status. |
| gender | nvarchar | Customer gender. Uses CRM value when available; otherwise ERP value. |
| birthdate | date | Customer's date of birth. |
| create_date | date | Date when the customer record was created. |

---

# Table: `gold.dim_products`

## Purpose
Stores active product master data enriched with category information.

## Grain
One record per active product.

## Columns

| Column | Data Type | Description |
|:-------|:---------|:------------|
| product_key | bigint | Surrogate key generated for the product dimension. |
| product_id | int | Business identifier of the product. |
| product_number | nvarchar | Product business key from the source system. |
| product_name | nvarchar | Name of the product. |
| category_id | nvarchar | Identifier of the product category. |
| category | nvarchar | Product category name. |
| subcategory | nvarchar | Product subcategory name. |
| maintenance | nvarchar | Product maintenance classification. |
| cost | int | Standard cost of the product. |
| product_line | nvarchar | Product line or business line. |
| start_date | date | Date when the product became active. |

---

# Table: `gold.fact_sales`

## Purpose
Stores sales transactions and connects customers and products through surrogate keys.

## Grain
One record per sales order line.

## Columns

| Column | Data Type | Description |
|:-------|:---------|:------------|
| order_number | nvarchar | Unique sales order number. |
| product_key | bigint | Foreign key referencing `gold.dim_products.product_key`. |
| customer_key | bigint | Foreign key referencing `gold.dim_customers.customer_key`. |
| order_date | date | Date when the order was placed. |
| shipping_date | date | Date when the order was shipped. |
| due_date | date | Expected delivery/due date. |
| sales_amount | int | Total sales amount for the order line. |
| quantity | int | Quantity of products sold. |
| price | int | Unit selling price of the product. |

---

# Star Schema

```text
                     +----------------------+
                     |   dim_customers      |
                     +----------------------+
                     | customer_key (PK)    |
                     +----------+-----------+
                                |
                                |
                                |
                     +----------v-----------+
                     |     fact_sales       |
                     +----------------------+
                     | order_number         |
                     | customer_key (FK)    |
                     | product_key (FK)     |
                     | order_date           |
                     | shipping_date        |
                     | due_date             |
                     | sales_amount         |
                     | quantity             |
                     | price                |
                     +----------+-----------+
                                |
                                |
                                |
                     +----------v-----------+
                     |    dim_products      |
                     +----------------------+
                     | product_key (PK)     |
                     +----------------------+
```

# Business Rules

- **customer_key** and **product_key** are surrogate keys generated using `ROW_NUMBER()`.
- **customer_id** and **product_id** are business keys from the source systems.
- Only active products (`prd_end_dt IS NULL`) are included in the product dimension.
- Customer gender is sourced from CRM when available; otherwise ERP is used.
- `fact_sales` references customer and product dimensions using surrogate keys.
- The Gold layer follows a Star Schema optimized for BI reporting and analytics.
