-- SokoMart Kenya - Advanced SQL Practical Project
-- SECTION A - CTEs and subqueries (Q1-Q5)
-- Database: luxdevhq_cohort9_advanced_sql   Schema: sokomart

SET search_path TO sokomart;

-- Q1 - Big spenders of 2025
		-- main query of Q1 (cte + scalar subquery) --1432 rows

WITH customer_2025_revenue AS (
    SELECT 
        c.customer_id,
        c.first_name || ' ' || c.last_name AS full_name,
        c.county,
        sum(i.line_total) as total_spent_2025
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items i ON o.order_id = i.order_id
    WHERE o.order_status = 'completed'
      AND o.order_date >= '2025-01-01' AND o.order_date < '2026-01-01'
    GROUP BY c.customer_id, c.first_name, c.last_name, c.county
)
SELECT  
    customer_id,
    full_name,
    county,
    total_spent_2025,
    (SELECT avg(total_spent_2025) FROM customer_2025_revenue) AS avg_spent_2025,
    (total_spent_2025 - (SELECT avg(total_spent_2025) FROM customer_2025_revenue)) AS amount_above_avg
FROM customer_2025_revenue
WHERE total_spent_2025 > (SELECT  avg(total_spent_2025) FROM customer_2025_revenue)
ORDER BY total_spent_2025 DESC;

--Q1 - second query of Q1, summary of count + averages and rows returned by first query
		--customers_who_bought_in_2025 are 4358
		--avg_spent_2025 is 118,774.54
		--main_query_rows 1432

WITH customer_2025_revenue AS (
   SELECT  c.customer_id, sum(i.line_total) AS total_spent_2025
   	FROM  customers c
    JOIN  orders o ON c.customer_id = o.customer_id
    JOIN  order_items i ON o.order_id = i.order_id
    WHERE  o.order_status = 'completed'
      AND  o.order_date >= '2025-01-01' AND o.order_date < '2026-01-01'
    GROUP BY  c.customer_id
)
SELECT 
    count(*) AS customers_who_bought_in_2025,
    round(avg(total_spent_2025), 2) AS avg_spent_2025,
    count(*) FILTER (WHERE total_spent_2025 > (SELECT avg(total_spent_2025) FROM customer_2025_revenue)) AS main_query_rows
FROM customer_2025_revenue;

-- Q2 - premium-priced products (correlated subquery)
		--main query --104 rows

SELECT
    product_id,
    product_name,
    category,
    unit_price,
    round((SELECT avg(unit_price) FROM products p2 WHERE p2.category = p1.category), 2) AS category_avg_price,
    unit_price - round((SELECT avg(unit_price) FROM products p2 WHERE p2.category = p1.category),2) AS price_gap
FROM products p1
WHERE product_status = 'active'
  AND unit_price > (SELECT avg(unit_price) FROM products p2 WHERE p2.category = p1.category)
ORDER BY category, price_gap DESC;

--Q2 - second query
		--product count per category --5 rows

SELECT category, COUNT(*) AS premium_product_count
FROM products p
WHERE product_status = 'active'
  AND unit_price > (SELECT AVG(p2.unit_price)
                      FROM products p2
                      WHERE p2.category = p.category)
GROUP BY category
ORDER BY category;

--Q3 - 2026 monthly profit and loss (chained ctes) --10 rows

WITH order_lines_2026 AS (
    SELECT 
        date_trunc('month', o.order_date) AS month,
        i.line_total AS line_revenue,
        (i.quantity * p.cost_price) AS line_cost
    FROM orders o
    JOIN order_items i ON o.order_id = i.order_id
    JOIN products p ON i.product_id = p.product_id
    WHERE o.order_status = 'completed'
      AND o.order_date >= '2026-01-01' AND o.order_date < '2026-11-01'
),
monthly_totals AS (
    SELECT 
        month,
        sum(line_revenue) AS revenue,
        sum(line_cost) AS cost
    FROM order_lines_2026
    GROUP BY month
),
monthly_profit AS (
    SELECT 
        month,
        revenue,
        cost,
        (revenue - cost) AS gross_profit
    FROM monthly_totals
)
SELECT 
    to_char(month, 'yyyy-mm') AS month,
    revenue,
    cost,
    gross_profit,
    round((gross_profit / revenue) * 100, 2) AS margin_pct
FROM monthly_profit
ORDER BY month;

--Q4 - Cross-category shoppers in Nakuru (derived table)
		--main query --346 rows
SELECT 
    c.customer_id,
    c.first_name || ' ' || c.last_name AS full_name,
    c.county,
    sub.category_count,
    sub.total_spent
FROM customers c
JOIN (
    SELECT 
        o.customer_id,
        count(DISTINCT p.category) AS category_count,
        sum(i.line_total) AS total_spent
    FROM orders o
    JOIN order_items i ON o.order_id = i.order_id
    JOIN products p ON i.product_id = p.product_id
    WHERE o.order_status = 'completed'
    GROUP BY o.customer_id
) sub ON c.customer_id = sub.customer_id
WHERE c.county = 'Nakuru'
  AND sub.category_count >= 3
ORDER BY sub.category_count DESC, sub.total_spent DESC;

-- Q4 - second query: counts
			--bought_all_5_categories 196
SELECT 
    count(*) AS qualifying_nakuru_customers,
    count(*) FILTER (WHERE sub.category_count = 5) AS bought_all_5_categories
FROM customers c
JOIN (
    SELECT o.customer_id, count(DISTINCT p.category) AS category_count
    FROM orders o
    JOIN order_items i ON o.order_id = i.order_id
    JOIN products p ON i.product_id = p.product_id
    WHERE o.order_status = 'completed'
    GROUP BY o.customer_id
) sub ON c.customer_id = sub.customer_id
WHERE c.county = 'Nakuru'
  AND sub.category_count >= 3;

-- Q5 - products nobody has ordered (not exists) --18 rows

SELECT 
    product_id,
    product_name,
    category,
    product_status,
    stock_quantity,
    created_at
FROM products p
WHERE NOT EXISTS (
    SELECT 1 
    FROM order_items i 
    WHERE i.product_id = p.product_id
)
ORDER BY category, product_name;
