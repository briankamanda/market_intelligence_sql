-- SokoMart Kenya - Advanced SQL Practical Project
-- Database: luxdevhq_cohort9_advanced_sql   Schema: sokomart

-- ## Practice drills 

SELECT * FROM customers;
SELECT * FROM orders;
SELECT * FROM products;
SELECT * FROM order_items;
SELECT * FROM payments;

SELECT * FROM payment_staging;

--D1: products above overall average unit price

--all products above avg unit price
--show 10 most expensive, and count

--10 most espensive   --10
SELECT product_id, product_name, category, unit_price, 
	(SELECT round(avg(unit_price), 2) FROM products) AS overall_avg_price
FROM products
WHERE unit_price > (SELECT avg(unit_price) FROM products)
ORDER BY unit_price DESC
LIMIT 10;

--count --65
SELECT count(product_id) AS product_above_avg
FROM products
WHERE unit_price > (SELECT avg(unit_price) FROM products);

-- D2: mombasa customers with orders in december 2025 and the count
--mombasa customers with at least one order in dec --204 rows

SELECT 
	customer_id, first_name, last_name, email
FROM customers
WHERE county = 'Mombasa'
	AND customer_id IN (SELECT customer_id FROM orders WHERE order_date >= '2025-12-01' AND order_date < '2026-01-01');

--count 					--204 dec orders
SELECT count(*) AS mombasa_customers_dec_orders
FROM customers
WHERE county = 'Mombasa'
	AND customer_id IN (SELECT customer_id
						FROM orders
						WHERE order_date >= '2025-12-01'
						AND order_date < '2026-01-01');

-- D3: kisumu customers with failed payments --155 rows
						
SELECT count(*) AS kisumu_customers_with_failed_payments 
FROM customers c
WHERE c.county = 'Kisumu'
		AND EXISTS (SELECT *
					FROM orders o
              		JOIN payments p ON p.order_id = o.order_id
              		WHERE o.customer_id = c.customer_id
                	AND p.payment_status = 'failed');



-- D4: order status breakdown using a subquery in from

--count orders for each order_status
--avg number of lines (rows) per order
--avg number of units per order


SELECT dt.order_status,
		count(*) AS orders,
		round(avg(dt.line_count), 2) AS avg_lines_per_order,
		round(avg(dt.unit_count), 2) AS avg_units_per_orders
FROM (SELECT o.order_id, o.order_status, 
		count(i.order_item_id) AS line_count, 
		sum(i.quantity) AS unit_count
		FROM orders o 
		JOIN order_items i ON o.order_id = i.order_id 
		GROUP BY o.order_id, o.order_status) AS dt
GROUP BY dt.order_status 
ORDER BY dt.order_status;

SELECT 
	order_status, orders, avg_lines_per_order, avg_units_per_order
	FROM (
		SELECT 
			o.order_status,
			COUNT(oi.order_id) AS orders,
			ROUND(AVG(oi.line_total), 2)  AS avg_lines_per_order,
			ROUND(AVG(oi.quantity),2) AS avg_units_per_order
		FROM order_items oi
		JOIN orders o USING(order_id)
		GROUP BY o.order_status
	);


-- D5: top 5 shipping counties by completed 2026 orders

WITH shipping_counties AS(
	SELECT
		o.shipping_county, COUNT(*) AS completed_orders
	FROM orders o
	WHERE order_date >= '2026-01-01' AND order_date <'2027-01-01'
		AND order_status = 'completed'
	GROUP BY o.shipping_county
	ORDER BY completed_orders DESC
	LIMIT 5
) SELECT shipping_county,completed_orders
FROM shipping_counties;

--D6: monthly order performance against the 2025 average

with monthly_counts as (
    select 
        date_trunc('month', order_date) as month, 
        count(order_id) as completed_orders
    from orders
    where order_status = 'completed'
      and order_date >= '2025-01-01' and order_date < '2026-01-01'
    group by date_trunc('month', order_date)
),
average_calc as (
    select avg(completed_orders) as avg_per_month 
    from monthly_counts
)
select 
    m.month, 
    m.completed_orders, 
    round(a.avg_per_month, 2) as avg_per_month,
    case 
        when m.completed_orders > a.avg_per_month then 'above average'
        else 'at/below average'
    end as vs_average
from monthly_counts m
cross join average_calc a
order by m.month;

-- d7: custom order count function
create or replace function fn_order_count(p_customer_id integer) 
returns integer 
language plpgsql as $$
declare
    v_count integer;
begin
    select count(order_id) into v_count
    from orders
    where customer_id = p_customer_id;
    
    return v_count;
end;
$$;

-- function calls
select fn_order_count(177); --7
select fn_order_count(-1); --0

-- d8: update customer status with exception handling
CREATE OR REPLACE PROCEDURE sp_set_customer_status(p_customer_id INTEGER, p_status VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_status NOT IN ('active', 'inactive', 'suspended') THEN
        RAISE EXCEPTION 'Invalid status "%": must be active, inactive or suspended', p_status;
    END IF;
    UPDATE customers SET customer_status = p_status WHERE customer_id = p_customer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % does not exist', p_customer_id;
    END IF;
END;
$$;

-- test rollback
SELECT customer_id, customer_status AS status_before FROM customers WHERE customer_id = 177; --active before transaction begins
BEGIN;
CALL sp_set_customer_status(177, 'suspended');
SELECT customer_id, customer_status AS status_inside_txn FROM customers WHERE customer_id = 177; --suspended in the transaction
ROLLBACK;
SELECT customer_id, customer_status AS status_after_rollback FROM customers WHERE customer_id = 177; --active after rollback

-- test exception, test fails
call sp_set_customer_status(177, 'vip'); --error message


-- D9: Beauty products below the average Beauty stock (CTE + scalar subquery on the CTE) --21 rows

WITH beauty AS (
    SELECT product_id, product_name, stock_quantity
    FROM sokomart.products
    WHERE category = 'Beauty'
)
SELECT b.product_id, b.product_name, b.stock_quantity,
       (SELECT ROUND(AVG(stock_quantity), 2) FROM beauty) AS beauty_avg_stock
FROM beauty b
WHERE b.stock_quantity < (SELECT AVG(stock_quantity) FROM beauty)
ORDER BY b.stock_quantity, b.product_id;

-- D10: procedure without parameters

create or replace procedure sp_county_summary(
    in p_county varchar, 
    out p_customers integer, 
    out p_revenue numeric
)
language plpgsql as $$
begin
    select count(distinct c.customer_id) into p_customers
    from customers c
    where c.county = p_county;

    select coalesce(sum(i.line_total), 0) into p_revenue
    from orders o
    join order_items i on o.order_id = i.order_id
    join customers c on o.customer_id = c.customer_id
    where c.county = p_county
      and o.order_status = 'completed';
end;
$$;

-- call the procedure
call sp_county_summary('Nakuru', null, null);










