USE DATABASE my_db;
USE SCHEMA my_schema;

CREATE WAREHOUSE IF NOT EXISTS sync_wh
WITH
WAREHOUSE_SIZE = 'SMALL'
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE sync_wh;

CREATE OR REPLACE TABLE fact_sales (
    transaction_id STRING PRIMARY KEY,
    order_date DATE,
    ship_date DATE,
    product_id INT,
    store_id INT,
    currency_code STRING,
    sales_amount DECIMAL(18,2),
    discount_amount DECIMAL(18,2),
    status STRING
);

CREATE OR REPLACE TABLE fact_exchange_rates (
    exchange_date DATE,
    from_currency STRING,
    to_currency STRING,
    rate DECIMAL(18,6)
);

CREATE OR REPLACE TABLE dim_product (
    product_id INT PRIMARY KEY,
    sku STRING,
    product_name STRING,
    sub_category STRING,
    category STRING,
    base_cost DECIMAL(10,2)
);

CREATE OR REPLACE TABLE dim_geography (
    store_id INT PRIMARY KEY,
    city STRING,
    region STRING,
    country STRING,
    manager_email STRING
);

CREATE OR REPLACE TABLE dim_date (
    date_id DATE PRIMARY KEY,
    year INT,
    quarter INT,
    month_name STRING,
    month_number INT,
    day_of_week STRING,
    week_of_year INT,
    is_weekend BOOLEAN
);

TRUNCATE TABLE dim_date;
TRUNCATE TABLE dim_geography;
TRUNCATE TABLE dim_product;
TRUNCATE TABLE fact_exchange_rates;
TRUNCATE TABLE fact_sales;

INSERT INTO dim_product
SELECT
    product_id,
    sku,
    product_name,
    CASE
        WHEN product_name LIKE '%Laptop%' THEN 'Laptops'
        WHEN product_name LIKE '%Monitor%' THEN 'Monitors'
        WHEN product_name LIKE '%Hub%' THEN 'Accessories'
        ELSE 'Furniture'
    END AS sub_category,
    CASE
        WHEN product_name LIKE '%Laptop%' THEN 'Electronics'
        WHEN product_name LIKE '%Monitor%' THEN 'Electronics'
        WHEN product_name LIKE '%Hub%' THEN 'Electronics'
        ELSE 'Office Supplies'
    END AS category,
    base_cost
FROM (
    SELECT
        100 + SEQ4() AS product_id,
        'SKU-' || UPPER(LEFT(MD5(SEQ4()), 8)) AS sku,
        CASE
            WHEN UNIFORM(1, 4, RANDOM()) = 1 THEN 'Pro Laptop ' || SEQ4()
            WHEN UNIFORM(1, 4, RANDOM()) = 2 THEN 'Ultra Monitor ' || SEQ4()
            WHEN UNIFORM(1, 4, RANDOM()) = 3 THEN 'Wireless Hub ' || SEQ4()
            ELSE 'Office Desk ' || SEQ4()
        END AS product_name,
        UNIFORM(20, 800, RANDOM())::DECIMAL(10,2) AS base_cost
    FROM TABLE(GENERATOR(ROWCOUNT => 1000))
);

INSERT INTO dim_geography
SELECT
    SEQ4() + 1 AS store_id,
    CASE
        WHEN UNIFORM(1, 4, RANDOM()) = 1 THEN 'City_' || SEQ4()
        WHEN UNIFORM(1, 4, RANDOM()) = 2 THEN 'Town_' || SEQ4()
        ELSE 'Metro_' || SEQ4()
    END AS city,
    CASE
        WHEN UNIFORM(1, 4, RANDOM()) = 1 THEN 'North America'
        WHEN UNIFORM(1, 4, RANDOM()) = 2 THEN 'EMEA'
        WHEN UNIFORM(1, 4, RANDOM()) = 3 THEN 'APAC'
        ELSE 'LATAM'
    END AS region,
    CASE
        WHEN region = 'North America' THEN 'USA'
        WHEN region = 'EMEA' THEN 'Germany'
        WHEN region = 'APAC' THEN 'Japan'
        ELSE 'Brazil'
    END AS country,
    LOWER(REPLACE(region, ' ', '_')) || '_lead@company.com' AS manager_email
FROM TABLE(GENERATOR(ROWCOUNT => 1000));

INSERT INTO dim_date (
    date_id,
    year,
    quarter,
    month_name,
    month_number,
    day_of_week,
    week_of_year,
    is_weekend
)
SELECT
    date_id,
    YEAR(date_id),
    QUARTER(date_id),
    MONTHNAME(date_id),
    MONTH(date_id),
    DAYNAME(date_id),
    WEEKOFYEAR(date_id),
    CASE WHEN DAYNAME(date_id) IN ('Sat', 'Sun') THEN TRUE ELSE FALSE END
FROM (
    SELECT DATEADD(day, SEQ4(), '2024-01-01') AS date_id
    FROM TABLE(GENERATOR(ROWCOUNT => 10000))
);

INSERT INTO fact_exchange_rates
SELECT
    d.date_id AS exchange_date,
    c.from_curr AS from_currency,
    'USD' AS to_currency,
    CASE
        WHEN c.from_curr = 'EUR' THEN 1.05 + (UNIFORM(-20, 20, RANDOM()) / 1000.0)
        WHEN c.from_curr = 'GBP' THEN 1.25 + (UNIFORM(-20, 20, RANDOM()) / 1000.0)
        WHEN c.from_curr = 'JPY' THEN 0.0065 + (UNIFORM(-5, 5, RANDOM()) / 100000.0)
        ELSE 1.0
    END AS rate
FROM dim_date d
CROSS JOIN (
    SELECT 'EUR' AS from_curr
    UNION ALL SELECT 'GBP'
    UNION ALL SELECT 'JPY'
) c;

INSERT INTO fact_exchange_rates
SELECT date_id, 'USD', 'USD', 1.0
FROM dim_date;

INSERT INTO fact_sales
SELECT
    'TXN-' || LPAD(SEQ4()::STRING, 10, '0') AS transaction_id,
    order_date,
    DATEADD(day, UNIFORM(1, 10, RANDOM()), order_date) AS ship_date,
    UNIFORM(100, 1099, RANDOM()) AS product_id,
    UNIFORM(1, 100, RANDOM()) AS store_id,
    CASE
        WHEN UNIFORM(1, 100, RANDOM()) <= 50 THEN 'USD'
        WHEN UNIFORM(1, 100, RANDOM()) <= 75 THEN 'EUR'
        WHEN UNIFORM(1, 100, RANDOM()) <= 90 THEN 'GBP'
        ELSE 'JPY'
    END AS currency_code,
    UNIFORM(100, 1000, RANDOM())::DECIMAL(18,2) AS sales_amount,
    CASE
        WHEN UNIFORM(1, 10, RANDOM()) > 7 THEN (UNIFORM(100, 1000, RANDOM()) * 0.20)::DECIMAL(18,2)
        ELSE 0.00
    END AS discount_amount,
    CASE
        WHEN UNIFORM(1, 20, RANDOM()) = 1 THEN 'Returned'
        WHEN UNIFORM(1, 25, RANDOM()) = 1 THEN 'Cancelled'
        ELSE 'Completed'
    END AS status
FROM (
    SELECT DATEADD(day, -UNIFORM(1, 365, RANDOM()), CURRENT_DATE()) AS order_date
    FROM TABLE(GENERATOR(ROWCOUNT => 100000))
);

SELECT status, COUNT(*)
FROM fact_sales
GROUP BY status;

SELECT currency_code, COUNT(*)
FROM fact_sales
GROUP BY currency_code;

SELECT
    MIN(order_date),
    MAX(order_date),
    MIN(ship_date),
    MAX(ship_date)
FROM fact_sales;

SELECT COUNT(*) AS unmatched_products
FROM fact_sales f
LEFT JOIN dim_product p
    ON f.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS unmatched_stores
FROM fact_sales f
LEFT JOIN dim_geography g
    ON f.store_id = g.store_id
WHERE g.store_id IS NULL;

select * from fact_sales;
select * from dim_date;
select * from dim_geography;
select * from dim_product;
select * from fact_exchange_rates;2