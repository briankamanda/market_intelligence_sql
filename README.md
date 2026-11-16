# SokoMart Kenya: Advanced SQL Practical Project

LuxDevHQ Data Engineering / Data Analytics, Cohort 9

- Author: Brian Mugo
- Database: PostgreSQL, database `luxdevhq_cohort9_advanced_sql`, schema `sokomart`
- Client: DBeaver

SokoMart Kenya is an online shop selling electronics, groceries, fashion, home appliances and beauty products across Kenya. In this project I work as its data analyst and answer 25 business requests in SQL, after 10 warm-up drills. Each answer has a query, its result and a screenshot. The company, the people and every record are synthetic.

## What the project covers

| Section | Questions | Skills |
|---|---|---|
| Practice drills | D1–D10 | Subqueries, CTEs, functions and stored procedures (unmarked warm-ups) |
| A. CTEs and subqueries | Q1–Q5 | CTEs, scalar, correlated and derived-table subqueries, `NOT EXISTS` |
| B. Window functions | Q6–Q10 | `DENSE_RANK`, `ROW_NUMBER`, `LAG`, running totals with explicit frames |
| C. Advanced aggregation | Q11–Q15 | Nested derived tables, `STRING_AGG`, `FILTER`, `GROUPING SETS` |
| D. Views, functions, procedures and triggers | Q16–Q20 | Views, materialised views, functions, stored procedures, triggers, atomic order placement |
| E. Optimisation and transactions | Q21–Q25 | `EXPLAIN ANALYZE`, indexes, transactions and savepoints, de-duplication, gaps and islands |

## Repository structure

```
.
├── README.md
├── sql/
│   ├── 00_practice_drills.sql
│   ├── section_a_ctes_subqueries.sql
│   ├── section_b_window_functions.sql
│   ├── section_c_advanced_aggregation_with_subqueries.sql
│   ├── section_d_views_functions_stored_procedures_triggers.sql
│   └── section_e_optimisation_and_transactions.sql
└── screenshots/
```

Screenshot names start with the question number, so `q19c_error.png` belongs to Question 19, part (c).

## Tables used

| Table | Purpose |
|---|---|
| `customers` | Who buys, the county they live in, their status |
| `products` | The catalogue: category, price, cost price, stock, status |
| `orders` | One row per order: date, status, shipping county, delivery fee, total |
| `order_items` | The lines on each order: quantity, price on the day, discount, line total |
| `payments` | One payment per order: method, amount, status, transaction reference |
| `product_price_history` | Written by the price-change procedure (Q18) |
| `order_status_history` | Written by the order-status trigger (Q19) |
| `audit_logs` | Audit trail with old and new values as JSONB (Q18–Q20 and Q23) |
| `payment_staging` | Raw settlement files, including re-sent duplicates (Q24) |

## Business rules

These come from the project brief and apply to every query.

Revenue and profit:

- Revenue is `SUM(order_items.line_total)` for orders with `order_status = 'completed'`. Delivery fees, pending, cancelled and returned orders are not revenue.
- `payments.amount` is used only for payment analysis (Q13 and Q24), never as revenue.
- Cost is `SUM(order_items.quantity * products.cost_price)` for the same order lines.
- Gross profit is revenue minus cost. Margin % is 100 × gross profit ÷ revenue.

Dates and places:

- Months are calendar months of `orders.order_date`, using `DATE_TRUNC('month', order_date)`, shown as `YYYY-MM`.
- Date ranges are half-open, for example `order_date >= '2025-01-01' AND order_date < '2026-01-01'`. `BETWEEN` with an end date such as `'2025-12-31'` would drop everything after midnight on 31 December, because `order_date` is a timestamp.
- A customer's county is `customers.county`, where they live. It only becomes `orders.shipping_county` when a question says shipping county.
- Full name is `first_name || ' ' || last_name`.

Output:

- Column names and their order follow the "Expected output" of each question, and results are ordered as asked.
- Percentages are rounded to 2 decimal places, and money is never cast to `FLOAT`.

Rules built into the procedures and triggers:

- An order can only move from `pending` to `completed`, from `pending` to `cancelled`, or from `completed` to `returned`. Anything else raises an exception (Q19).
- When an order is completed its payment becomes `successful`. When it is cancelled, an unpaid payment becomes `failed` (Q19).
- Every status change is logged in `order_status_history` and `audit_logs`, whether it comes from the procedure or a plain `UPDATE`. An update that leaves the status unchanged logs nothing (Q19).
- A new product price must be above zero and not below the product's `cost_price`. Every change is recorded in `product_price_history` and `audit_logs` (Q18).
- Placing an order is all or nothing. The customer must exist and be `active`, the product and quantity lists must be the same length, and stock is taken with a conditional `UPDATE` that acts as a lock. If any product has too little stock, the whole order is undone (Q20).
- The delivery fee (Q20) depends on the items total:
  - KES 5,000 or more: free
  - below KES 5,000, Nairobi: KES 200
  - below KES 5,000, Kiambu, Kajiado or Machakos: KES 250
  - below KES 5,000, anywhere else: KES 350
- Two `payment_staging` rows are the same payment when `payment_id`, `order_id`, `payment_date`, `payment_method`, `amount`, `payment_status` and `transaction_reference` all match. The first-loaded copy (earliest `loaded_at`, then lowest `staging_id`) is kept (Q24).
- Anti-joins use `NOT EXISTS` and never `NOT IN`, because `NOT IN` returns nothing at all if the subquery yields a `NULL` (Q5).

## Running the SQL

Before running anything, the database `luxdevhq_cohort9_advanced_sql` must already exist, with the `sokomart` schema and the nine tables listed above, loaded with the project data. The repository holds the queries only and does not create or load these tables.

1. Make `sokomart` the default schema, so that tables can be written without the schema name. Run this once, as a user who can alter the database, then open a new connection:

   ```sql
   ALTER DATABASE luxdevhq_cohort9_advanced_sql SET search_path TO sokomart, public;
   ```

   Alternatively, run `SET search_path TO sokomart;` at the start of each session.
2. Run the files in this order: `00_practice_drills.sql`, then Sections A, B, C, D and E.
3. Run Section D before Section E. Q20 depends on the materialised view from Q16 and the trigger from Q19.
4. Sections D and E change data. Restore the original data before running them a second time.
5. Keep DBeaver in auto-commit mode. For the `BEGIN ... COMMIT` blocks in Q23 and Q24, run the block as a script (Alt+X) so that every statement uses the same session.
6. Some statements are meant to fail, because the question asks to show the error: Q17.4, Q18.2, Q19c, Q20.2, Q23c and Q24d. Their screenshots show the error message.

## Question index

The "Rows" column is the number of rows each query returns, as shown in its screenshot. These are not timings.

| Q | Topic | Technique | Rows / result | SQL file | Screenshots |
|---|---|---|---|---|---|
| Q1 | Big spenders of 2025 | CTE + scalar subquery | 1,432 | [section_a_ctes_subqueries.sql](sql/section_a_ctes_subqueries.sql) | [q01_big_spenders_2025](screenshots/q01_big_spenders_2025.png) |
| Q2 | Premium-priced products | Correlated subquery | 104 | [section_a_ctes_subqueries.sql](sql/section_a_ctes_subqueries.sql) | [q02_premium_priced_products](screenshots/q02_premium_priced_products.png) |
| Q3 | 2026 monthly profit and loss | Three chained CTEs | 10 | [section_a_ctes_subqueries.sql](sql/section_a_ctes_subqueries.sql) | [q03_monthly_profit_and_loss](screenshots/q03_monthly_profit_and_loss.png) |
| Q4 | Cross-category shoppers in Nakuru | Derived table, COUNT(DISTINCT) | 346 | [section_a_ctes_subqueries.sql](sql/section_a_ctes_subqueries.sql) | [q04_nakuru_cross_category_shoppers](screenshots/q04_nakuru_cross_category_shoppers.png) |
| Q5 | Products nobody has ordered | NOT EXISTS anti-join | 18 | [section_a_ctes_subqueries.sql](sql/section_a_ctes_subqueries.sql) | [q05_products_without_orders](screenshots/q05_products_without_orders.png) |
| Q6 | County leaderboards | DENSE_RANK() OVER (PARTITION BY ...) | 42 | [section_b_window_functions.sql](sql/section_b_window_functions.sql) | [q06_county_leaderboards](screenshots/q06_county_leaderboards.png) |
| Q7 | Best sellers per category, 2025 | ROW_NUMBER() top-N per group | 15 | [section_b_window_functions.sql](sql/section_b_window_functions.sql) | [q07_categories_best_sellers](screenshots/q07_categories_best_sellers.png) |
| Q8 | Month-over-month growth | LAG() + NULLIF | 22 | [section_b_window_functions.sql](sql/section_b_window_functions.sql) | [q08_mom_growth](screenshots/q08_mom_growth.png) |
| Q9 | Is each order bigger than the last? | LAG() per customer | 393 | [section_b_window_functions.sql](sql/section_b_window_functions.sql) | [q09_customer_lag_order](screenshots/q09_customer_lag_order.png) |
| Q10 | Year-to-date revenue | SUM() OVER with an explicit frame | 22 | [section_b_window_functions.sql](sql/section_b_window_functions.sql) | [q10_ytd_revenue](screenshots/q10_ytd_revenue.png) |
| Q11 | Customer tiers | Nested derived tables, CASE, scalar subquery | 4 | [section_c_advanced_aggregation_with_subqueries.sql](sql/section_c_advanced_aggregation_with_subqueries.sql) | [q11_customer_tiers_spend_summary](screenshots/q11_customer_tiers_spend_summary.png) |
| Q12 | What did Mombasa buy in October? | STRING_AGG(DISTINCT ...), EXISTS | 152 | [section_c_advanced_aggregation_with_subqueries.sql](sql/section_c_advanced_aggregation_with_subqueries.sql) | [q12_october_ordered_products_mombasa](screenshots/q12_october_ordered_products_mombasa.png) |
| Q13 | Payment health by method, 2026 | FILTER clause + CTE | 4 | [section_c_advanced_aggregation_with_subqueries.sql](sql/section_c_advanced_aggregation_with_subqueries.sql) | [q13_2026_payment_health_by_method](screenshots/q13_2026_payment_health_by_method.png) |
| Q14 | Which categories carry the profit? | CTE + scalar subqueries | 2 | [section_c_advanced_aggregation_with_subqueries.sql](sql/section_c_advanced_aggregation_with_subqueries.sql) | [q14_categories_best_performers](screenshots/q14_categories_best_performers.png) |
| Q15 | One sales table with subtotals | GROUPING SETS + GROUPING() | 36 | [section_c_advanced_aggregation_with_subqueries.sql](sql/section_c_advanced_aggregation_with_subqueries.sql) | [q15_sales_table_with_subtotals](screenshots/q15_sales_table_with_subtotals.png) |
| Q16 | Customer summary view and monthly category materialised view | View over CTEs, materialised view, unique index | 5,000 (view) | [section_d_views_functions_stored_procedures_triggers.sql](sql/section_d_views_functions_stored_procedures_triggers.sql) | [q16a_v_customer_purchase_summary](screenshots/q16a_v_customer_purchase_summary.png)<br>[q16a_view_size](screenshots/q16a_view_size.png)<br>[q16b_dec_2025_categorical_revenue](screenshots/q16b_dec_2025_categorical_revenue.png) |
| Q17 | Function: customer spend for a date range | PL/pgSQL function, validation, RAISE EXCEPTION | n/a | [section_d_views_functions_stored_procedures_triggers.sql](sql/section_d_views_functions_stored_procedures_triggers.sql) | [q17.1_five_numbers](screenshots/q17.1_five_numbers.png)<br>[q17.2_function_vs_view](screenshots/q17.2_function_vs_view.png)<br>[q17.3_top_5_Nairobi](screenshots/q17.3_top_5_Nairobi.png)<br>[q17.4_error](screenshots/q17.4_error.png) |
| Q18 | Procedure: change a price and keep its history | FOR UPDATE, validation, three tables | n/a | [section_d_views_functions_stored_procedures_triggers.sql](sql/section_d_views_functions_stored_procedures_triggers.sql) | [q18.1_audit_row](screenshots/q18.1_audit_row.png)<br>[q18.1_before_call](screenshots/q18.1_before_call.png)<br>[q18.1_call_new_price](screenshots/q18.1_call_new_price.png)<br>[q18.1_history_row](screenshots/q18.1_history_row.png)<br>[q18.2_history_rows_after](screenshots/q18.2_history_rows_after.png)<br>[q18.2_history_rows_before](screenshots/q18.2_history_rows_before.png)<br>[q18.2_price_still_same](screenshots/q18.2_price_still_same.png)<br>[q18.2_rejected_call_error](screenshots/q18.2_rejected_call_error.png) |
| Q19 | Trigger and procedure: status changes are always logged | Trigger function, TG_OP, IS DISTINCT FROM | n/a | [section_d_views_functions_stored_procedures_triggers.sql](sql/section_d_views_functions_stored_procedures_triggers.sql) | [q19a_trigger_function](screenshots/q19a_trigger_function.png)<br>[q19b_sp_update_order_status](screenshots/q19b_sp_update_order_status.png)<br>[q19c_after_call_successful](screenshots/q19c_after_call_successful.png)<br>[q19c_audit_after_complete](screenshots/q19c_audit_after_complete.png)<br>[q19c_before_call_pending](screenshots/q19c_before_call_pending.png)<br>[q19c_error](screenshots/q19c_error.png)<br>[q19c_history_after_plain_update](screenshots/q19c_history_after_plain_update.png)<br>[q19c_history_count_same_after_no_change_update](screenshots/q19c_history_count_same_after_no_change_update.png) |
| Q20 | Procedure: place an order atomically | Arrays, INOUT, conditional UPDATE as a stock lock | n/a | [section_d_views_functions_stored_procedures_triggers.sql](sql/section_d_views_functions_stored_procedures_triggers.sql) | [q20.1_call](screenshots/q20.1_call.png)<br>[q20.1_lines](screenshots/q20.1_lines.png)<br>[q20.1_order_with_items_total](screenshots/q20.1_order_with_items_total.png)<br>[q20.1_payment](screenshots/q20.1_payment.png)<br>[q20.1_products_before](screenshots/q20.1_products_before.png)<br>[q20.1_stock_after](screenshots/q20.1_stock_after.png)<br>[q20.1_trigger_history](screenshots/q20.1_trigger_history.png)<br>[q20.2_after_call_unchanged](screenshots/q20.2_after_call_unchanged.png)<br>[q20.2_before_call](screenshots/q20.2_before_call.png)<br>[q20.2_call_error](screenshots/q20.2_call_error.png)<br>[q20.3_november_sales_mv](screenshots/q20.3_november_sales_mv.png) |
| Q21 | Read a query plan | EXPLAIN (ANALYZE, BUFFERS) | 91 | [section_e_optimisation_and_transactions.sql](sql/section_e_optimisation_and_transactions.sql) | [q21_query](screenshots/q21_query.png)<br>[q21_query_plan](screenshots/q21_query_plan.png) |
| Q22 | Prove the indexes help | Before/after plans, partial index | Plan 1: 11, Plan 3: 358, partial index query: 203 | [section_e_optimisation_and_transactions.sql](sql/section_e_optimisation_and_transactions.sql) | [q22a_plan_1_before_indexing](screenshots/q22a_plan_1_before_indexing.png)<br>[q22a_plan_3_before_indexing](screenshots/q22a_plan_3_before_indexing.png)<br>[q22b_partial_view](screenshots/q22b_partial_view.png)<br>[q22b_plan_1_after_indexing](screenshots/q22b_plan_1_after_indexing.png)<br>[q22b_plan_3_after_indexing](screenshots/q22b_plan_3_after_indexing.png)<br>[q22c_size_comparison](screenshots/q22c_size_comparison.png) |
| Q23 | Transactions you can see | BEGIN, ROLLBACK, SAVEPOINT, aborted transactions | n/a | [section_e_optimisation_and_transactions.sql](sql/section_e_optimisation_and_transactions.sql) | [q23a_after_rollback](screenshots/q23a_after_rollback.png)<br>[q23a_before_transaction](screenshots/q23a_before_transaction.png)<br>[q23a_inside_transaction](screenshots/q23a_inside_transaction.png)<br>[q23b_after_rollback_and_commit](screenshots/q23b_after_rollback_and_commit.png)<br>[q23b_before_savepoint](screenshots/q23b_before_savepoint.png)<br>[q23b_inside_mistake](screenshots/q23b_inside_mistake.png)<br>[q23c_after](screenshots/q23c_after.png)<br>[q23c_error_message](screenshots/q23c_error_message.png)<br>[q23c_remain_unchanged_after_commit](screenshots/q23c_remain_unchanged_after_commit.png) |
| Q24 | Clean up the duplicate payments | ROW_NUMBER() de-duplication, unique index | 200 payments had duplicates; 240 surplus rows deleted | [section_e_optimisation_and_transactions.sql](sql/section_e_optimisation_and_transactions.sql) | [q24a_duplicated_payment](screenshots/q24a_duplicated_payment.png)<br>[q24b_first_ten_rows](screenshots/q24b_first_ten_rows.png)<br>[q24c_before_deleting](screenshots/q24c_before_deleting.png)<br>[q24c_rowchecks_before_deleting](screenshots/q24c_rowchecks_before_deleting.png)<br>[q24d_after](screenshots/q24d_after.png)<br>[q24d_reinserting_value_error](screenshots/q24d_reinserting_value_error.png) |
| Q25 | Three months in a row | Gaps and islands | 1,459 customers, longest streak 22 months | [section_e_optimisation_and_transactions.sql](sql/section_e_optimisation_and_transactions.sql) | [q25a_top_10](screenshots/q25a_top_10.png)<br>[q25b_longest_streak_customers](screenshots/q25b_longest_streak_customers.png) |

## Business insights

These come from the results of the queries above. The question number after each figure shows where to check it.

### Revenue growth

Revenue for January to October 2026 is KES 457.0 million, against KES 378.4 million for the same months of 2025, an increase of 20.8% (Q10). Full-year 2025 revenue was KES 517.6 million. I would use the 2025 monthly pattern as the starting point for 2026 stock and staffing plans, and keep checking the month-over-month growth in Q8 for any slowdown.

### Seasonality

December 2025 was the strongest month at KES 72.8 million, followed by November 2025 at KES 66.4 million. The weakest months were February 2025 (KES 28.7 million), March 2025 (KES 32.0 million) and June 2025 (KES 33.3 million) (Q8). Stock and delivery capacity need to be ready before November, and the quiet months are a good time for loyalty and win-back campaigns.

### Category profitability

In 2025 only Electronics and Fashion earned more gross profit than the average category (Q14). Electronics made KES 43.6 million on KES 325.7 million of revenue, a margin of 13.4%. Fashion made KES 24.4 million on KES 54.8 million, a margin of 44.5%. Across 2026 the monthly margin stayed between 17.97% and 19.65% (Q3). Electronics brings the volume but at a thin margin, so offering Fashion items alongside electronics orders could add more profit than pushing electronics volume alone.

### Customer tiers and inactive customers

Silver customers are the largest group: 2,362 customers who produce 54.46% of revenue. The 111 Platinum customers produce 17.59%, and the 1,823 Bronze customers only 8.64% (Q11). Separately, 425 of the 5,000 customers have never completed an order (Q16a). Moving Silver customers towards Gold is the biggest opportunity, and the 425 who never bought would be a target for a first-purchase offer.

### Payments

The payments team suspected that one channel fails more than the others. In 2026 the success rate is close to the same on every channel: 90.08% for bank transfer, 89.51% for card, 89.33% for M-Pesa and 89.09% for cash on delivery (Q13). M-Pesa has the largest failed value, KES 30.2 million, because it carries 14,726 of the 23,817 payments. The suspicion is not supported by the data, so retry prompts and reminders should cover all channels instead of one.

### Regional sales

For the five counties in Q15, 2026 revenue is KES 315.8 million, and Nairobi accounts for KES 180.4 million of it (57.1%). Mombasa follows with KES 49.5 million, then Nakuru (KES 36.5 million), Kisumu (KES 26.2 million) and Uasin Gishu (KES 23.2 million). Electronics makes up about 62% of the five-county total. Growth outside Nairobi is where the room is, particularly in Kisumu and Uasin Gishu.

### Repeat buying

1,459 customers bought in at least three consecutive months, and the longest run is 22 months, which is every month in the data (Q25). These are the customers a subscription offer would suit.

### Unsold stock and duplicate payments

18 products have never appeared on an order and hold 1,771 units between them: 5 in Beauty, 5 in Fashion, 4 in Groceries, 3 in Electronics and 1 in Home Appliances (Q5). They are candidates for clearance or removal from the catalogue. In the payment staging table, 2,640 rows contained 200 payments that were sent more than once, 240 surplus rows in all, with up to 3 copies of the same payment (Q24). After cleaning, 2,400 rows remain, one per payment, and the unique index on `payment_id` stops the same file from loading twice.

## Notes

- The data is synthetic, so the findings show how I analysed it and are not real-world conclusions.
- Execution times in Q21 and Q22 differ from one machine to another, so compare the scan types rather than the milliseconds.
- Cost and margin use the current `products.cost_price`, as the brief defines.
