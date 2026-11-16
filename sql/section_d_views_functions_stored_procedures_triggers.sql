-- SokoMart Kenya - Advanced SQL Practical Project
-- SECTION D - Views, functions, stored procedures, triggers (Q16-Q20)
-- Database: luxdevhq_cohort9_advanced_sql   Schema: sokomart

SET search_path TO sokomart;

-- Q16 (a) - v_customer_purchase_summary  (VIEW over CTEs + LEFT JOIN) --5000 rows in the view

CREATE OR REPLACE VIEW v_customer_purchase_summary AS
WITH completed_orders AS (
    SELECT o.customer_id, o.order_id, o.order_date,
           sum(i.line_total) AS order_revenue
    FROM orders o
    JOIN order_items i ON i.order_id = o.order_id
    WHERE o.order_status = 'completed'
    GROUP BY o.customer_id, o.order_id, o.order_date
),
customer_totals AS (
    SELECT customer_id,
           count(*) AS completed_orders,
           sum(order_revenue)    AS lifetime_spent,
           min(order_date)::date AS first_order_date,
           max(order_date)::date AS last_order_date
    FROM completed_orders
    GROUP BY customer_id
)
SELECT c.customer_id,
       c.first_name || ' ' || c.last_name AS full_name,
       c.county,
       c.registration_date,
       coalesce(t.completed_orders, 0) AS completed_orders,
       coalesce(t.lifetime_spent, 0)  AS lifetime_spent,
       round(t.lifetime_spent / nullif(t.completed_orders, 0), 2) AS avg_order_value,
       t.first_order_date,
       t.last_order_date,
       (date '2026-10-31' - t.last_order_date) AS days_since_last_order
FROM customers c
LEFT JOIN customer_totals t ON t.customer_id = c.customer_id;

-- 16(a) top 10 customers living in kiambu --10 rows

SELECT customer_id, full_name, county, registration_date, completed_orders, lifetime_spent,
       avg_order_value, first_order_date, last_order_date, days_since_last_order
FROM v_customer_purchase_summary
WHERE county = 'Kiambu'
ORDER BY lifetime_spent DESC
LIMIT 10;

-- 16(a) view size

SELECT COUNT(*) AS rows_in_view,
       COUNT(*) FILTER (WHERE completed_orders = 0) AS customers_with_zero_completed_orders
FROM v_customer_purchase_summary;

-- Q16 (b) - mv_monthly_category_sales  (MATERIALIZED VIEW)

DROP MATERIALIZED VIEW IF EXISTS mv_monthly_category_sales;

CREATE MATERIALIZED VIEW sokomart.mv_monthly_category_sales AS
SELECT DATE_TRUNC('month', o.order_date)::date AS sales_month,
       p.category,
       count(DISTINCT o.order_id) AS orders,
       sum(i.quantity) AS units_sold,
       sum(i.line_total) AS revenue,
       sum(i.line_total - i.quantity * p.cost_price) AS gross_profit
FROM orders  o
JOIN order_items i ON i.order_id   = o.order_id
JOIN products p ON p.product_id = i.product_id
WHERE o.order_status = 'completed'
GROUP BY DATE_TRUNC('month', o.order_date)::date, p.category
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS ux_mv_monthly_category_sales
    ON mv_monthly_category_sales (sales_month, category);

-- Q16b december 2025 ordered by revenue

SELECT to_char(sales_month, 'YYYY-MM') AS sales_month, category, 
		orders, units_sold, revenue, gross_profit
FROM mv_monthly_category_sales
WHERE sales_month = date '2025-12-01'
ORDER BY revenue DESC;

-- Q17 - fn_customer_spend  (PL/pgSQL function)

CREATE OR REPLACE FUNCTION sokomart.fn_customer_spend(
    p_customer_id INTEGER,
    p_start_date  DATE,
    p_end_date    DATE)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_spend NUMERIC;
BEGIN
    IF p_end_date < p_start_date THEN
        RAISE EXCEPTION 'End date (%) cannot be before start date (%)', p_end_date, p_start_date;
    END IF;

    SELECT COALESCE(SUM(i.line_total), 0)
    INTO   v_spend
    FROM   orders o
    JOIN   order_items i ON i.order_id = o.order_id
    WHERE  o.customer_id  = p_customer_id
      AND  o.order_status = 'completed'
      AND  o.order_date  >= p_start_date
      AND  o.order_date  <  p_end_date + 1;

    RETURN v_spend;
END;
$$;
-- Q17.1 five calls, for customer 4000 and -1
SELECT fn_customer_spend(4000, DATE '2025-01-01', DATE '2025-12-31') AS spend_2025,
       fn_customer_spend(4000, DATE '2026-01-01', DATE '2026-10-31') AS spend_jan_oct_2026,
       fn_customer_spend(4000, DATE '2025-01-01', DATE '2026-10-31') AS spend_all_time,
       fn_customer_spend(4000, DATE '2025-12-01', DATE '2025-12-31') AS spend_dec_2025,
       fn_customer_spend(-1,   DATE '2025-01-01', DATE '2026-10-31') AS spend_customer_minus_1;

--the function agrees with the view
-- Q17.2 function vs view
SELECT v.customer_id,
       v.lifetime_spent,
       fn_customer_spend(v.customer_id, DATE '2025-01-01', DATE '2026-10-31') AS fn_value,
       v.lifetime_spent = fn_customer_spend(v.customer_id, DATE '2025-01-01', DATE '2026-10-31') AS matches
FROM v_customer_purchase_summary v
WHERE v.customer_id = 4000;

--function used inside a query: top 5 Nairobi-resident customers by Dec 2025 spend
-- Q17.3 top 5 Nairobi
SELECT c.customer_id,
       c.first_name || ' ' || c.last_name AS full_name,
       fn_customer_spend(c.customer_id, DATE '2025-12-01', DATE '2025-12-31') AS december_2025_spend
FROM customers c
WHERE c.county = 'Nairobi'
ORDER BY december_2025_spend DESC, c.customer_id
LIMIT 5;

-- EXPECTED ERROR: end date before start date
--Q17.4 error
SELECT fn_customer_spend(4000, DATE '2026-02-01', DATE '2026-01-01');

-- Q18 - sp_update_product_price  (procedure, FOR UPDATE, 3 tables)

CREATE OR REPLACE PROCEDURE sp_update_product_price(
    p_product_id integer,
    p_new_price  numeric,
    p_reason  varchar)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_price numeric;
    v_cost numeric;
BEGIN
    SELECT unit_price, cost_price
    INTO   v_old_price, v_cost
    FROM   products
    WHERE  product_id = p_product_id
    FOR UPDATE;
IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % does not exist', p_product_id;
    END IF;
    IF p_new_price IS NULL OR p_new_price <= 0 THEN
        RAISE EXCEPTION 'New price must be greater than 0 (got %)', p_new_price;
    END IF;
    IF p_new_price < v_cost THEN
        RAISE EXCEPTION 'New price % is below the cost price % of product %',
                        p_new_price, v_cost, p_product_id;
    END IF;
UPDATE products
    SET    unit_price = p_new_price
    WHERE  product_id = p_product_id;
INSERT INTO product_price_history (product_id, old_price, new_price, change_reason)
    VALUES (p_product_id, v_old_price, p_new_price, p_reason);
INSERT INTO audit_logs (table_name, record_id, action, old_data, new_data)
    VALUES ('products', p_product_id, 'UPDATE',
            jsonb_build_object('unit_price', v_old_price),
            jsonb_build_object('unit_price', p_new_price));
END;
$$;

-- Q18.1 before call

SELECT product_id, product_name, unit_price, cost_price FROM products WHERE product_id = 71;

-- Q18.1 call

CALL sp_update_product_price(71, 1099.00, 'Supplier price increase - Nov 2026');

SELECT product_id, product_name, unit_price, cost_price FROM products WHERE product_id = 71;

--Q18.1 history row

SELECT price_history_id, product_id, old_price, new_price, change_reason
FROM product_price_history
WHERE product_id = 71
ORDER BY price_history_id;

-- Q18.1 audit row

SELECT table_name, record_id, action, old_data, new_data
FROM audit_logs
WHERE table_name = 'products' AND record_id = 71
ORDER BY audit_id DESC
LIMIT 1;

-- 2. Rejected call (EXPECTED ERROR) and proof that nothing extra was written

-- Q18.2 history rows before

SELECT COUNT(*) AS history_rows_before FROM product_price_history WHERE product_id = 71;

--  Q18.2 rejected call (EXPECTED ERROR)

CALL sp_update_product_price(71, 500.00, 'Test - below cost');

-- Q18.2 history rows after

SELECT COUNT(*) AS history_rows_after FROM product_price_history WHERE product_id = 71;

-- Q18.2 price still 1099

SELECT product_id, unit_price FROM products WHERE product_id = 71;

-- Q19 (a) - trigger function + trg_orders_status_audit

CREATE OR REPLACE FUNCTION fn_orders_status_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_status_history (order_id, old_status, new_status)
        VALUES (NEW.order_id, NULL, NEW.order_status);

        INSERT INTO audit_logs (table_name, record_id, action, old_data, new_data)
        VALUES ('orders', NEW.order_id, 'INSERT', NULL,
                jsonb_build_object('order_status', NEW.order_status));

    ELSIF TG_OP = 'UPDATE' AND NEW.order_status IS DISTINCT FROM OLD.order_status THEN
        INSERT INTO order_status_history (order_id, old_status, new_status)
        VALUES (NEW.order_id, OLD.order_status, NEW.order_status);

        INSERT INTO audit_logs (table_name, record_id, action, old_data, new_data)
        VALUES ('orders', NEW.order_id, 'UPDATE',
                jsonb_build_object('order_status', OLD.order_status),
                jsonb_build_object('order_status', NEW.order_status));
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_status_audit ON orders;
CREATE TRIGGER trg_orders_status_audit
    AFTER INSERT OR UPDATE OF order_status ON orders
    FOR EACH ROW
    EXECUTE FUNCTION fn_orders_status_audit();

-- Q19 (b) - sp_update_order_status  (business rules)

CREATE OR REPLACE PROCEDURE sp_update_order_status(
    p_order_id   INTEGER,
    p_new_status VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_status VARCHAR;
BEGIN
    SELECT order_status
    INTO   v_old_status
    FROM   orders
    WHERE  order_id = p_order_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % does not exist', p_order_id;
    END IF;

    IF NOT ((v_old_status = 'pending'   AND p_new_status IN ('completed', 'cancelled'))
         OR (v_old_status = 'completed' AND p_new_status = 'returned')) THEN
        RAISE EXCEPTION 'Order %: changing status from % to % is not allowed',
                        p_order_id, v_old_status, p_new_status;
    END IF;
    UPDATE orders SET order_status = p_new_status WHERE order_id = p_order_id;
    IF p_new_status = 'completed' THEN
        UPDATE payments
        SET    payment_status = 'successful'
        WHERE  order_id = p_order_id AND payment_status <> 'successful';
    ELSIF p_new_status = 'cancelled' THEN
        UPDATE payments
        SET    payment_status = 'failed'
        WHERE  order_id = p_order_id AND payment_status = 'pending';
    END IF;
END;
$$;

-- Q19 (c) - proof on order 48882 (pending)
	--before
SELECT o.order_id, o.order_status, p.payment_status
FROM orders o JOIN payments p ON p.order_id = o.order_id
WHERE o.order_id = 48882;

-- Q19c call complete

CALL sp_update_order_status(48882, 'completed');

-- Q19 (c)	--after
SELECT o.order_id, o.order_status, p.payment_status
FROM orders o JOIN payments p ON p.order_id = o.order_id
WHERE o.order_id = 48882;

--  Q19 (c) audit after complete
SELECT table_name, record_id, action, old_data, new_data
FROM audit_logs WHERE table_name = 'orders' AND record_id = 48882 ORDER BY audit_id;

-- Q19 (c) plain update to returned, trigger still logs even without procedure
UPDATE orders SET order_status = 'returned' WHERE order_id = 48882;

-- Q19 (c) history after plain update --2 rows
SELECT order_id, old_status, new_status
FROM order_status_history WHERE order_id = 48882 ORDER BY status_history_id;

-- Q19 (c) no change update

UPDATE orders SET shipping_county = shipping_county WHERE order_id = 48882;

-- Q19 (c) history count still 2

SELECT COUNT(*) AS history_rows FROM order_status_history WHERE order_id = 48882;

-- Q19 (c) error
CALL sp_update_order_status(49961, 'completed');

-- Q20 - sp_place_order  (atomic procedure)

CREATE OR REPLACE PROCEDURE sp_place_order(
    p_customer_id     INTEGER,
    p_product_ids     INTEGER[],
    p_quantities      INTEGER[],
    p_payment_method  VARCHAR,
    INOUT p_order_id  INTEGER DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_county      VARCHAR;
    v_status      VARCHAR;
    v_n           INTEGER;
    i             INTEGER;
    v_price       NUMERIC;
    v_available   INTEGER;
    v_items_total NUMERIC := 0;
    v_fee         NUMERIC;
    v_prefix      VARCHAR;
BEGIN
    -- 1. validation
    SELECT county, customer_status INTO v_county, v_status
    FROM   customers WHERE customer_id = p_customer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % does not exist', p_customer_id;
    END IF;
    IF v_status <> 'active' THEN
        RAISE EXCEPTION 'Customer % is % and cannot place orders', p_customer_id, v_status;
    END IF;

    v_n := COALESCE(array_length(p_product_ids, 1), 0);
    IF v_n = 0 THEN
        RAISE EXCEPTION 'An order needs at least one product';
    END IF;
    IF v_n <> COALESCE(array_length(p_quantities, 1), 0) THEN
        RAISE EXCEPTION 'Product list has % items but quantity list has %',
                        v_n, COALESCE(array_length(p_quantities, 1), 0);
    END IF;
    IF p_payment_method NOT IN ('M-Pesa', 'card', 'bank transfer', 'cash on delivery') THEN
        RAISE EXCEPTION 'Unknown payment method %', p_payment_method;
    END IF;

    -- 2. order header
    INSERT INTO orders (customer_id, order_date, order_status, shipping_county, delivery_fee, total_amount)
    VALUES (p_customer_id, CURRENT_TIMESTAMP, 'pending', v_county, 0, 0)
    RETURNING order_id INTO p_order_id;

    -- 3. lines: the conditional UPDATE is the stock lock
    FOR i IN 1 .. v_n LOOP
        UPDATE products
        SET    stock_quantity = stock_quantity - p_quantities[i]
        WHERE  product_id = p_product_ids[i]
          AND  stock_quantity >= p_quantities[i]
          AND  product_status = 'active'
        RETURNING unit_price INTO v_price;

        IF NOT FOUND THEN
            SELECT stock_quantity INTO v_available
            FROM   products WHERE product_id = p_product_ids[i];
            RAISE EXCEPTION 'Cannot order product %: requested %, available % (product must also be active)',
                            p_product_ids[i], p_quantities[i], COALESCE(v_available, 0);
        END IF;

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_percentage, line_total)
        VALUES (p_order_id, p_product_ids[i], p_quantities[i], v_price, 0,
                ROUND(p_quantities[i] * v_price, 2));

        v_items_total := v_items_total + ROUND(p_quantities[i] * v_price, 2);
    END LOOP;

    -- 4. delivery fee and total
    v_fee := CASE WHEN v_items_total >= 5000 THEN 0
                  WHEN v_county = 'Nairobi' THEN 200
                  WHEN v_county IN ('Kiambu', 'Kajiado', 'Machakos') THEN 250
                  ELSE 350 END;

    UPDATE orders
    SET    delivery_fee = v_fee,
           total_amount = v_items_total + v_fee
    WHERE  order_id = p_order_id;

    -- 5. pending payment for the full amount
    v_prefix := CASE p_payment_method WHEN 'M-Pesa' THEN 'MPX'
                                      WHEN 'card'   THEN 'CRD'
                                      ELSE 'BNK' END;
    INSERT INTO payments (order_id, payment_date, payment_method, amount, payment_status, transaction_reference)
    VALUES (p_order_id, CURRENT_TIMESTAMP, p_payment_method, v_items_total + v_fee, 'pending',
            CASE WHEN p_payment_method = 'cash on delivery' THEN NULL
                 ELSE v_prefix || TO_CHAR(CURRENT_DATE, 'YYMM') || LPAD(p_order_id::TEXT, 8, '0') END);
END;
$$;

-- Q20.1 products before
SELECT product_id, product_name, unit_price, stock_quantity
FROM products WHERE product_id IN (6, 73, 82) ORDER BY product_id;

-- Q20.1 call
CALL sp_place_order(177, ARRAY[6,73,82], ARRAY[1,2,3], 'M-Pesa', NULL);

-- Q20.1 order with items total
SELECT o.order_id, o.customer_id, o.order_status, o.shipping_county, o.delivery_fee, o.total_amount,
       (SELECT SUM(i.line_total) FROM order_items i WHERE i.order_id = o.order_id) AS items_total
FROM orders o
WHERE o.order_id = (SELECT MAX(order_id) FROM orders);

-- Q20.1 lines
SELECT order_id, product_id, quantity, unit_price, line_total
FROM order_items
WHERE order_id = (SELECT MAX(order_id) FROM orders)
ORDER BY product_id;

-- Q20.1 payment
SELECT order_id, payment_method, amount, payment_status,
       (transaction_reference IS NOT NULL) AS has_reference
FROM payments
WHERE order_id = (SELECT MAX(order_id) FROM orders);

-- Q20.1 stock after
SELECT product_id, product_name, unit_price, stock_quantity
FROM products WHERE product_id IN (6, 73, 82) ORDER BY product_id;

-- Q20.1 trigger history
SELECT order_id, old_status, new_status
FROM order_status_history
WHERE order_id = (SELECT MAX(order_id) FROM orders);

-- Q20.2 failure path

	--Q20.2 before
SELECT (SELECT count(*) FROM orders WHERE customer_id = 408) AS orders_of_408,
		(SELECT stock_quantity FROM products WHERE product_id = 6) AS stock_p6,
		(SELECT stock_quantity FROM products WHERE product_id = 59) AS stock_p59;

	--Q20.2 call   --error cannot order product 59, requested 2, available 1
CALL sp_place_order(408, ARRAY[6, 59], ARRAY[1, 2], 'card', NULL);

	--Q20.2 after --unchanged
SELECT (SELECT count(*) FROM orders WHERE customer_id = 408) AS orders_of_408,
		(SELECT stock_quantity FROM products WHERE product_id = 6) AS stock_p6,
		(SELECT stock_quantity FROM products WHERE product_id = 59) AS stock_p59;
   
   -- Q20.3 complete the new order, refresh the materialised view (MV), show november 2026
CALL sp_update_order_status(50001, 'completed');

	--Q20.3 refresh
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_category_sales;
	--Q20.3 november sales
SELECT to_char(sales_month, 'YYYY-MM') AS sales_month, category, orders, units_sold, revenue, gross_profit
FROM mv_monthly_category_sales
WHERE sales_month = date '2026-11-01'
ORDER BY category;