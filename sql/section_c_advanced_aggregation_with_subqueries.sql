-- SokoMart Kenya - Advanced SQL Practical Project
-- SECTION C - Advanced aggregation with subqueries (Q11-Q15)
-- Database: luxdevhq_cohort9_advanced_sql   Schema: sokomart

SET search_path TO sokomart;

SELECT * FROM customers;
SELECT * FROM products;
SELECT * FROM orders;
SELECT * FROM order_items;
SELECT * FROM payments;
SELECT * FROM payment_staging;

-- Q11 - Customer tiers spend summary  (nested derived tables, CASE, scalar subquery) 

SELECT tiered.tier,
       count(*)  AS customer_count,
       min(tiered.total_spent) AS min_spent,
       max(tiered.total_spent) AS max_spent,
       round(AVG(tiered.total_spent), 2) AS avg_spent,
       round(100 * sum(tiered.total_spent) /
             (SELECT sum(i.line_total)
              FROM order_items i
              JOIN orders o ON o.order_id = i.order_id
              WHERE o.order_status = 'completed'), 2) AS revenue_share_pct
FROM (
        SELECT lifetime.customer_id,
               lifetime.total_spent,
               CASE WHEN lifetime.total_spent >= 1000000 THEN 'Platinum'
                    WHEN lifetime.total_spent >=  500000 THEN 'Gold'
                    WHEN lifetime.total_spent >=  100000 THEN 'Silver'
                    ELSE 'Bronze' END AS tier,
               CASE WHEN lifetime.total_spent >= 1000000 THEN 1
                    WHEN lifetime.total_spent >=  500000 THEN 2
                    WHEN lifetime.total_spent >=  100000 THEN 3
                    ELSE 4 END AS tier_order
        FROM (
                SELECT o.customer_id, sum(i.line_total) AS total_spent
                FROM orders o
                JOIN order_items i ON i.order_id = o.order_id
                WHERE o.order_status = 'completed'
                GROUP BY o.customer_id
             ) lifetime
     ) tiered
GROUP BY tiered.tier, tiered.tier_order
ORDER BY tiered.tier_order;

-- Q12 - What did Mombasa buy in October?   (STRING_AGG + EXISTS) --152 rows
		--main query

SELECT c.customer_id,
       c.first_name || ' ' || c.last_name AS full_name,
       count(DISTINCT p.product_id) AS product_count,
       string_agg(DISTINCT p.product_name, '; ' ORDER BY p.product_name) AS products_ordered
FROM customers c
JOIN orders      o ON o.customer_id = c.customer_id
JOIN order_items i ON i.order_id    = o.order_id
JOIN products    p ON p.product_id  = i.product_id
WHERE c.county = 'Mombasa'
  AND o.order_status <> 'cancelled'
  AND o.order_date >= '2026-10-01' AND o.order_date < '2026-11-01'
  AND EXISTS (SELECT 1
              FROM orders o2
              WHERE o2.customer_id  = c.customer_id
                AND o2.order_status <> 'cancelled'
                AND o2.order_date  >= '2026-10-01' AND o2.order_date < '2026-11-01')
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY product_count DESC, c.customer_id;

	--second query - count of qualifying customers above --count is 152 customers
SELECT COUNT(*) AS mombasa_customers
FROM customers c
WHERE c.county = 'Mombasa'
  AND EXISTS (SELECT 1
              FROM orders o
              WHERE o.customer_id  = c.customer_id
                AND o.order_status <> 'cancelled'
                AND o.order_date  >= '2026-10-01' AND o.order_date < '2026-11-01');

SELECT * FROM customers;
SELECT * FROM products;
SELECT * FROM orders;
SELECT * FROM order_items;
SELECT * FROM payments;
SELECT * FROM payment_staging;

-- Q13 - Payment health by method, 2026   (CTE + FILTER) --4 rows

WITH payments_2026 AS (
		SELECT payment_method, payment_status, amount
		FROM payments
		WHERE payment_date >= date_trunc('year', current_date)
			AND payment_date < date_trunc('year', current_date) + INTERVAL '1 year'
	)
	SELECT payment_method, count(*) AS total_payments,
			count(*) FILTER (WHERE payment_status = 'successful') AS successful,
			count(*) FILTER (WHERE payment_status = 'failed') AS failed,
			count(*) FILTER (WHERE payment_status = 'pending') AS pending,
			round(100.0 * count(*) FILTER (WHERE payment_status = 'successful') /
			count(*), 2) AS success_rate_pct,
			coalesce(sum(amount) FILTER (WHERE payment_status = 'failed'), 0) AS failed_amount
		FROM payments_2026
		GROUP BY payment_method
		ORDER BY total_payments DESC;


-- Q14 - Which departments carry the profit?   (CTE + scalar subqueries) --2 rows

WITH category_2025 AS (
    SELECT p.category,
           sum(i.line_total) AS revenue,
           sum(i.line_total - i.quantity * p.cost_price) AS gross_profit
    FROM orders o
    JOIN order_items i ON i.order_id   = o.order_id
    JOIN products p ON p.product_id = i.product_id
    WHERE o.order_status = 'completed'
      AND o.order_date >= date_trunc('year', current_date) - INTERVAL '1 year' 
      			AND o.order_date < date_trunc('year', current_date)
    GROUP BY p.category
)
SELECT category, revenue, gross_profit,
       round(100 * gross_profit / revenue, 2) AS margin_pct,
       round((SELECT avg(gross_profit) FROM category_2025), 2) AS avg_category_gross_profit,
       round(100 * (gross_profit - (SELECT avg(gross_profit) FROM category_2025))
                 / (SELECT avg(gross_profit) FROM category_2025), 2) AS pct_above_avg
FROM category_2025
WHERE gross_profit > (SELECT avg(gross_profit) FROM category_2025)
ORDER BY gross_profit DESC;

-- Q15 - One sales table with subtotals   (GROUPING SETS + GROUPING()) --36 rows

WITH lines_2026 AS (
    SELECT o.shipping_county AS county, p.category, o.order_id, i.line_total
    FROM orders      o
    JOIN order_items i ON i.order_id   = o.order_id
    JOIN products    p ON p.product_id = i.product_id
    WHERE o.order_status = 'completed'
      AND o.order_date >= '2026-01-01' AND o.order_date < '2027-01-01'
      AND o.shipping_county IN ('Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Uasin Gishu')
)
SELECT CASE WHEN grouping(county) = 0 AND grouping(category) = 0 THEN 'county x category'
            WHEN grouping(county) = 0 AND grouping(category) = 1 THEN 'county total'
            WHEN grouping(county) = 1 AND grouping(category) = 0 THEN 'category total'
            ELSE 'grand total' END                       AS grouping_level,
       coalesce(county, 'ALL COUNTIES') AS county,
       coalesce(category, 'ALL CATEGORIES') AS category,
       sum(line_total) AS revenue,
       count(DISTINCT order_id) AS order_count
FROM lines_2026
GROUP BY GROUPING SETS ((county, category), (county), (category), ())
ORDER BY CASE WHEN grouping(county) = 0 AND grouping(category) = 0 THEN 1
              WHEN grouping(county) = 0 AND grouping(category) = 1 THEN 2
              WHEN grouping(county) = 1 AND grouping(category) = 0 THEN 3
              ELSE 4 END,
         county, category;








