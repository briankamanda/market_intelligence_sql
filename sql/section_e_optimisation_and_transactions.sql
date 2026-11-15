-- SokoMart Kenya - Advanced SQL Practical Project
-- SECTION E - Optimisation and transactions (Q21-Q25)
-- Database: luxdevhq_cohort9_advanced_sql   Schema: sokomart

-- Q21 - Read a query plan
	--query plan
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_id, c.first_name, c.last_name, sum(i.line_total) AS revenue
FROM customers c
JOIN orders o      ON o.customer_id = c.customer_id
JOIN order_items i ON i.order_id = o.order_id
WHERE c.county = 'Kisumu'
  AND o.order_status = 'completed'
  AND o.order_date >= '2026-09-01' AND o.order_date < '2026-10-01'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY revenue DESC;

/*
top_node                        : Sort
join_methods_used               : Hash Join (orders x customers) + Nested Loop (order_items)
scan_on_orders                  : Index Scan using idx_orders_order_date (Filter: order_status = 'completed')
scan_on_customers               : Bitmap Heap Scan via Bitmap Index Scan idx_customers_county
estimated_vs_actual_rows_orders : estimated 2003, actual 2061
planning_ms                     : 0.377
execution_ms                    : 0.991
result_rows                     : 91
*/
	--Q21 query --91 rows
SELECT c.customer_id, c.first_name, c.last_name, SUM(i.line_total) AS revenue
FROM customers c
JOIN orders o      ON o.customer_id = c.customer_id
JOIN order_items i ON i.order_id = o.order_id
WHERE c.county = 'Kisumu'
  AND o.order_status = 'completed'
  AND o.order_date >= '2026-09-01' AND o.order_date < '2026-10-01'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY revenue DESC;

-- Q22 - Prove the indexes help
-- (a) before - first drop the indexes
DROP INDEX IF EXISTS sokomart.idx_customers_county, sokomart.idx_customers_registration_date,
    sokomart.idx_products_category, sokomart.idx_orders_customer_id, sokomart.idx_orders_order_date,
    sokomart.idx_orders_status_date, sokomart.idx_orders_customer_date,
    sokomart.idx_order_items_product_id, sokomart.idx_payments_order_id,
    sokomart.idx_payments_status_method, sokomart.idx_payments_payment_date,
    sokomart.idx_price_history_product_id, sokomart.idx_status_history_order_id;

ANALYZE sokomart.customers, sokomart.products, sokomart.orders, sokomart.order_items, sokomart.payments;

-- Plan 1 BEFORE   --11 rows
EXPLAIN ANALYZE
SELECT order_id, order_date, total_amount FROM orders WHERE customer_id = 408 ORDER BY order_date;

-- Plan 2 BEFORE  --1 row
EXPLAIN ANALYZE
SELECT * FROM payments WHERE order_id = 25000;

-- Plan 3 BEFORE  --358 rows
EXPLAIN ANALYZE
SELECT order_id, quantity, line_total FROM sokomart.order_items WHERE product_id = 71;

-- (b) - After, recreate the indexes such as in the index creation scripts

CREATE INDEX IF NOT EXISTS idx_customers_county            ON sokomart.customers (county);
CREATE INDEX IF NOT EXISTS idx_customers_registration_date ON sokomart.customers (registration_date);
CREATE INDEX IF NOT EXISTS idx_products_category           ON sokomart.products (category);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id          ON sokomart.orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_date           ON sokomart.orders (order_date);
CREATE INDEX IF NOT EXISTS idx_orders_status_date          ON sokomart.orders (order_status, order_date);
CREATE INDEX IF NOT EXISTS idx_orders_customer_date        ON sokomart.orders (customer_id, order_date);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id      ON sokomart.order_items (product_id);
CREATE INDEX IF NOT EXISTS idx_payments_order_id           ON sokomart.payments (order_id);
CREATE INDEX IF NOT EXISTS idx_payments_status_method      ON sokomart.payments (payment_status, payment_method);
CREATE INDEX IF NOT EXISTS idx_payments_payment_date       ON sokomart.payments (payment_date);
CREATE INDEX IF NOT EXISTS idx_price_history_product_id    ON sokomart.product_price_history (product_id);
CREATE INDEX IF NOT EXISTS idx_status_history_order_id     ON sokomart.order_status_history (order_id);

ANALYZE sokomart.customers, sokomart.products, sokomart.orders, sokomart.order_items, sokomart.payments;

-- Plan 1 AFTER --9 rows
EXPLAIN ANALYZE
SELECT order_id, order_date, total_amount FROM sokomart.orders WHERE customer_id = 408 ORDER BY order_date;

-- Plan 2 AFTER --1 row
EXPLAIN ANALYZE
SELECT * FROM sokomart.payments WHERE order_id = 25000;

-- Plan 3 AFTER --358 rows
EXPLAIN ANALYZE
SELECT order_id, quantity, line_total FROM sokomart.order_items WHERE product_id = 71;

--Partial Index
CREATE INDEX idx_orders_pending_date ON sokomart.orders (order_date) WHERE order_status = 'pending';
ANALYZE sokomart.orders;

EXPLAIN ANALYZE --203 rows
SELECT order_id, order_date, total_amount
FROM sokomart.orders
WHERE order_status = 'pending' AND order_date < '2026-10-25';

-- Size comparison
-- Q22c sizes
SELECT pg_relation_size('sokomart.idx_orders_pending_date') AS partial_index_size,
       pg_relation_size('sokomart.idx_orders_order_date')   AS full_index_size;

-- Q23 - Transactions you can see
--23(a) before transaction
SELECT ROUND(AVG(unit_price), 2) AS avg_beauty_price FROM products WHERE category = 'Beauty';

--23(a) inside transaction

BEGIN;
UPDATE sokomart.products SET unit_price = ROUND(unit_price * 0.90, 2) WHERE category = 'Beauty';

SELECT ROUND(AVG(unit_price), 2) AS avg_beauty_price_inside_txn FROM sokomart.products WHERE category = 'Beauty';
ROLLBACK;

--23(a) after rollback
SELECT ROUND(AVG(unit_price), 2) AS avg_beauty_price_after_rollback FROM sokomart.products WHERE category = 'Beauty';

-- Q23(b) savepoint
--BEFORE the savepoint
SELECT product_id, stock_quantity FROM sokomart.products WHERE product_id IN (59, 166) ORDER BY product_id;

BEGIN;
UPDATE sokomart.products SET stock_quantity = stock_quantity + 40 WHERE product_id = 59;

INSERT INTO sokomart.audit_logs (table_name, record_id, action, old_data, new_data)
SELECT 'products', product_id, 'UPDATE',
       jsonb_build_object('stock_quantity', stock_quantity - 40),
       jsonb_build_object('stock_quantity', stock_quantity)
FROM sokomart.products WHERE product_id = 59;

SAVEPOINT after_restock;

UPDATE sokomart.products SET stock_quantity = 0 WHERE product_id = 166;

--inside the mistake

SELECT product_id, stock_quantity FROM sokomart.products WHERE product_id IN (59, 166) ORDER BY product_id;

ROLLBACK TO SAVEPOINT after_restock;
COMMIT;

--23b after rollback to savepoint and commit

SELECT product_id, stock_quantity FROM products WHERE product_id IN (59, 166) ORDER BY product_id;

--audit row kept
SELECT table_name, record_id, action, old_data, new_data
FROM sokomart.audit_logs WHERE table_name = 'products' AND record_id = 59 ORDER BY audit_id DESC LIMIT 1;

-- Q23(c) audit row kept
SELECT product_id, stock_quantity FROM products WHERE product_id = 166;

BEGIN;
UPDATE products SET stock_quantity = stock_quantity + 1 WHERE product_id = 166;
UPDATE products SET stock_quantity = -5 WHERE product_id = 166;
SELECT 1;
COMMIT;  --aborted due to the error

--Q23c after
SELECT product_id, stock_quantity FROM products WHERE product_id = 166; --remain unchanged


-- Q24(a) -  Clean up the duplicate payments
WITH dup_groups AS (
    SELECT payment_id, order_id, payment_date, payment_method, amount, payment_status,
           transaction_reference, COUNT(*) AS copies
    FROM payment_staging
    GROUP BY payment_id, order_id, payment_date, payment_method, amount, payment_status, transaction_reference
    HAVING COUNT(*) > 1
)
SELECT COUNT(*)        AS duplicated_payments,
       SUM(copies - 1) AS extra_rows_to_delete,
       MAX(copies)     AS max_copies
FROM dup_groups;

-- Q24(b) --list of first 10 rows to be deleted
WITH ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY payment_id, order_id, payment_date, payment_method,
                                           amount, payment_status, transaction_reference
                              ORDER BY loaded_at, staging_id) AS copy_no
    FROM payment_staging s
)
SELECT staging_id, payment_id, transaction_reference, amount, source_file, loaded_at, copy_no
FROM ranked
WHERE copy_no > 1
ORDER BY staging_id
LIMIT 10;

-- Q24(c) --Delete inside a transaction, verify, then COMMIT

--before
SELECT COUNT(*) AS staging_rows_before, COUNT(DISTINCT payment_id) AS distinct_payments_before
FROM payment_staging;

--deleting inside the transaction
BEGIN;
WITH ranked AS (
    SELECT staging_id,
           ROW_NUMBER() OVER (PARTITION BY payment_id, order_id, payment_date, payment_method,
                                           amount, payment_status, transaction_reference
                              ORDER BY loaded_at, staging_id) AS copy_no
    FROM sokomart.payment_staging
)
DELETE FROM payment_staging s
USING ranked r
WHERE s.staging_id = r.staging_id
  AND r.copy_no > 1;

--24d after
SELECT COUNT(*)                  AS staging_rows_after,
       COUNT(DISTINCT payment_id) AS distinct_payments_after,
       SUM(amount)               AS staged_amount_after,
       (SELECT SUM(p.amount)
        FROM payments p
        WHERE p.payment_id IN (SELECT payment_id FROM payment_staging)) AS same_payments_in_payments_table
FROM payment_staging;

COMMIT;

--Prevent it happening again
-- Q24(d) index
CREATE UNIQUE INDEX ux_payment_staging_payment_id ON payment_staging (payment_id);

--reinserting
INSERT INTO payment_staging
       (payment_id, order_id, payment_date, payment_method, amount, payment_status,
        transaction_reference, source_file)
SELECT payment_id, order_id, payment_date, payment_method, amount, payment_status,
       transaction_reference, 'resent_file.csv'
FROM payment_staging
ORDER BY staging_id
LIMIT 1; --returns an error


-- Three months in a row
-- Q25(a) top 10
WITH customer_months AS (
    SELECT DISTINCT o.customer_id,
           DATE_TRUNC('month', o.order_date)::DATE AS month_start,
           EXTRACT(YEAR FROM o.order_date)::INT * 12 + EXTRACT(MONTH FROM o.order_date)::INT AS month_no
    FROM sokomart.orders o
    WHERE o.order_status = 'completed'
),
numbered AS (
    SELECT customer_id, month_start, month_no,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY month_no) AS rn
    FROM customer_months
),
islands AS (
    SELECT customer_id, month_start, month_no - rn AS island_id
    FROM numbered
),
streaks AS (
    SELECT customer_id, island_id,
           MIN(month_start) AS streak_start,
           MAX(month_start) AS streak_end,
           COUNT(*)         AS streak_length
    FROM islands
    GROUP BY customer_id, island_id
    HAVING COUNT(*) >= 3
),
best AS (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY customer_id
                              ORDER BY streak_length DESC, streak_start) AS rk
    FROM streaks s
)
SELECT b.customer_id,
       c.first_name || ' ' || c.last_name AS full_name,
       c.county,
       TO_CHAR(b.streak_start, 'YYYY-MM') AS streak_start_month,
       TO_CHAR(b.streak_end,   'YYYY-MM') AS streak_end_month,
       b.streak_length
FROM best b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.rk = 1
ORDER BY b.streak_length DESC, b.customer_id
LIMIT 10;

--Q25 second query: qualifying customers and the longest streak
-- Q25(b) summary
WITH customer_months AS (
    SELECT DISTINCT o.customer_id,
           EXTRACT(YEAR FROM o.order_date)::INT * 12 + EXTRACT(MONTH FROM o.order_date)::INT AS month_no
    FROM sokomart.orders o
    WHERE o.order_status = 'completed'
),
numbered AS (
    SELECT customer_id, month_no,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY month_no) AS rn
    FROM customer_months
),
streaks AS (
    SELECT customer_id, month_no - rn AS island_id, COUNT(*) AS streak_length
    FROM numbered
    GROUP BY customer_id, month_no - rn
    HAVING COUNT(*) >= 3
)
SELECT COUNT(DISTINCT customer_id) AS customers_with_3plus_streak,
       MAX(streak_length)          AS longest_streak
FROM streaks;
