-- SokoMart Kenya - Advanced SQL Practical Project
-- SECTION B - Window functions (Q6-Q10)
-- Database: luxdevhq_cohort9_advanced_sql   Schema: sokomart

SET search_path TO sokomart;

-- Q6 - county leaderboards (dense_rank) --42 rows
WITH spending AS (
    SELECT c.customer_id,
           c.first_name || ' ' || c.last_name AS full_name,
           c.county,
           sum(i.line_total)  AS total_spent
    FROM customers   c
    JOIN orders      o ON o.customer_id = c.customer_id
    JOIN order_items i ON i.order_id    = o.order_id
    WHERE o.order_status = 'completed'
    GROUP BY c.customer_id, c.first_name, c.last_name, c.county
),
ranked_customers AS (
    SELECT county,
           DENSE_RANK() OVER (PARTITION BY county ORDER BY total_spent DESC) AS county_rank,
           customer_id,
           full_name,
           total_spent
    FROM spending
)
SELECT county, county_rank, customer_id, full_name, total_spent
FROM ranked_customers
WHERE county_rank <= 3
ORDER BY county, county_rank, customer_id;

--Q7 - Best sellers per category, 2025 (ROW_NUMBER) --15 rows

WITH product_sales AS (
    SELECT p.category,
           p.product_id,
           p.product_name,
           sum(i.line_total) AS revenue,
           sum(i.quantity)   AS units_sold
    FROM orders      o
    JOIN order_items i ON i.order_id   = o.order_id
    JOIN products    p ON p.product_id = i.product_id
    WHERE o.order_status = 'completed'
      AND o.order_date >= '2025-01-01' AND o.order_date < '2026-01-01'
    GROUP BY p.category, p.product_id, p.product_name
),
numbered AS (
    SELECT category, product_id, product_name, revenue, units_sold,
           row_number() OVER (PARTITION BY category
                              ORDER BY revenue DESC, product_id) AS rank_in_category
    FROM product_sales
)
SELECT category, rank_in_category, product_id, product_name, revenue, units_sold
FROM numbered
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

--Q8 - Month-over-month growth (LAG + NULLIF) --22 rows

WITH monthly_revenue AS (
    SELECT 
        date_trunc('month', o.order_date) AS month_val, 
        sum(i.line_total) AS revenue
    FROM orders o
    JOIN order_items i on o.order_id = i.order_id
    WHERE o.order_status = 'completed'
    GROUP BY date_trunc('month', o.order_date)
),
lagged_revenue AS (
    SELECT 
        to_char(month_val, 'yyyy-mm') AS month,
        revenue,
        lag(revenue) OVER (ORDER BY month_val) AS prev_month_revenue
    FROM monthly_revenue
)
SELECT 
    month,
    revenue,
    prev_month_revenue,
    round(((revenue - prev_month_revenue) / nullif(prev_month_revenue, 0)) * 100, 2) AS growth_pct
FROM lagged_revenue
ORDER BY month;

--Q9 - Is each order bigger than the last? (LAG per customer) --393 rows

WITH nyeri_orders AS (
    SELECT o.customer_id, o.order_id, o.order_date, o.total_amount
    FROM orders    o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE c.county = 'Nyeri'
      AND o.order_status = 'completed'
      AND o.order_date >= '2026-01-01' AND o.order_date < '2027-01-01'
),
lag_orders AS (
    SELECT customer_id, order_id, order_date, total_amount,
           lag(total_amount) OVER (PARTITION BY customer_id
                                   ORDER BY order_date, order_id) AS previous_order_amount
    FROM nyeri_orders
)
SELECT customer_id,
       order_id,
       order_date,
       total_amount,
       previous_order_amount,
       total_amount - previous_order_amount AS change_amount,
       CASE WHEN previous_order_amount IS NULL          THEN 'first order'
            WHEN total_amount > previous_order_amount   THEN 'up'
            WHEN total_amount < previous_order_amount   THEN 'down'
            ELSE 'same' END                              AS direction
FROM lag_orders
ORDER BY customer_id, order_date, order_id;

-- Q9 second query, summary counts

WITH nyeri_orders AS (
    SELECT o.customer_id, o.order_id, o.order_date, o.total_amount
    FROM orders    o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE c.county = 'Nyeri'
      AND o.order_status = 'completed'
      AND o.order_date >= '2026-01-01' AND o.order_date < '2027-01-01'
),
lag_orders AS (
    SELECT customer_id, order_id, total_amount,
           lag(total_amount) OVER (PARTITION BY customer_id
                                   ORDER BY order_date, order_id) AS previous_order_amount
    FROM nyeri_orders
)
SELECT count(*)  AS total_rows,
       count(DISTINCT customer_id) AS distinct_customers,
       count(*) FILTER (WHERE previous_order_amount IS NULL) AS first_orders,
       count(*) FILTER (WHERE total_amount > previous_order_amount) AS bigger_than_previous,
       count(*) FILTER (WHERE total_amount < previous_order_amount)  AS smaller_than_previous
FROM lag_orders;

-- Q10 - Year-to-date revenue  (sum over partitionwith explicit frame) --22 rows
WITH monthly_totals AS (
    SELECT date_trunc('month', o.order_date) AS month,
           EXTRACT(YEAR FROM o.order_date)::int AS year,
           sum(i.line_total) AS monthly_revenue
    FROM orders      o
    JOIN order_items i ON i.order_id = o.order_id
    WHERE o.order_status = 'completed'
    GROUP BY date_trunc('month', o.order_date), EXTRACT(YEAR FROM o.order_date)
)
SELECT year,
   to_char(month, 'YYYY-MM') AS month,
   monthly_revenue,
   sum(monthly_revenue) OVER (
       			PARTITION BY year
                ORDER BY month
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue_ytd,
       sum(monthly_revenue) OVER (
       			ORDER BY month
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue_all_time
FROM monthly_totals
ORDER BY MONTH;