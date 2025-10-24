# Assignment2_BD
Знайти 30 "найцінніших"(зробили замовлень на 1000 і більше) клієнтів з міста 'Lake Michael', які зареєструвалися у 2024 році.

---
## 1️⃣ Non-optimized query (AI-generated)
```sql
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    
    -- ПОГАНА ПРАКТИКА №1: Корельований підзапит у SELECT
    -- Цей підзапит виконується для КОЖНОГО рядка, який проходить фільтри WHERE.
    -- Він окремо обчислює загальну суму витрат для кожного клієнта.
    (
        SELECT SUM(oi.quantity * oi.price_per_item)
        FROM orders o
        JOIN order_items oi ON o.order_id = oi.order_id
        WHERE o.customer_id = c.customer_id
    ) AS total_spent
FROM
    customers c
WHERE
    -- Фільтр №1: на таблиці 'customers'. Це нормально, але...
    c.city = 'Lake Michael'
    AND c.registration_date >= '2024-01-01' 
    AND c.registration_date <= '2024-12-31'

    -- ПОГАНА ПРАКТИКА №2: Корельований підзапит 'EXISTS'
    -- Це головний "вбивця" продуктивності. Для кожного клієнта з 'Lake Michael',
    -- що зареєструвався у 2024, він запускає важкий пошук.
    AND EXISTS (
        SELECT 1
        FROM orders o
        JOIN order_items oi ON o.order_id = oi.order_id
        JOIN products p ON oi.product_id = p.product_id
        WHERE
            o.customer_id = c.customer_id
            AND p.category = 'Electronics'
        GROUP BY
            o.order_id
        -- ПОГАНА ПРАКТИКА №3: Використання HAVING для простої перевірки
        HAVING
            SUM(oi.quantity * oi.price_per_item) >= 1000
    )
ORDER BY
    total_spent DESC
LIMIT 30;
```
<img width="303" height="495" alt="Знімок екрана 2025-10-23 о 12 01 34" src="https://github.com/user-attachments/assets/95a2cda2-fc6d-4b96-9b15-898d2ca87689" />

## 2️⃣ Optimized (my version)
```sql
CREATE INDEX idx_customers_city_reg ON customers(city, registration_date);

CREATE INDEX idx_products_category ON products(category);

WITH filtered_customers AS (
    SELECT
        customer_id,
        first_name,
        last_name
    FROM customers
    WHERE city = 'Lake Michael'
        AND registration_date BETWEEN '2024-01-01' AND '2024-12-31' -- CTE для фільтрації клієнтів за містом та роком
),
customer_total_spend AS (
    SELECT
        o.customer_id,
        SUM(oi.quantity * oi.price_per_item) AS total_spent
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.customer_id IN (SELECT customer_id FROM filtered_customers)
    GROUP BY o.customer_id  -- CTE для розрахунку витрат клієнта 
),
eligible_electronics_customers AS (
    SELECT o.customer_id
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.customer_id IN (SELECT customer_id FROM filtered_customers)
        AND p.category = 'Electronics'
    GROUP BY o.order_id, o.customer_id
    HAVING SUM(oi.price_per_item * oi.quantity) >= 1000 -- СTE для фільтрації за категорією покупки та загальною витраценою сумою
)
SELECT
    fc.customer_id,
    fc.first_name,
    fc.last_name,
    cts.total_spent
FROM filtered_customers fc
JOIN eligible_electronics_customers eec ON fc.customer_id = eec.customer_id
JOIN customer_total_spend cts ON fc.customer_id = cts.customer_id
ORDER BY cts.total_spent DESC
LIMIT 30;
```
<img width="300" height="490" alt="Знімок екрана 2025-10-23 о 12 05 42" src="https://github.com/user-attachments/assets/f4128648-c595-4759-ba2e-38b2d1dfdf71" />

---
## EXPLAIN
1. Non-optimized
<img width="1230" height="128" alt="Знімок екрана 2025-10-23 о 12 10 19" src="https://github.com/user-attachments/assets/6254f5c6-ff3b-4588-bbe2-3ea497f32649" />

2. Optimized
<img width="1214" height="203" alt="Знімок екрана 2025-10-24 о 11 17 09" src="https://github.com/user-attachments/assets/b95ea59a-ba3f-4d9e-bf8d-49098ea3da44" />


---
## EXPLAIN ANALYZE
**1. Non-optimized**


'-> Limit: 30 row(s)  (actual time=400..400 rows=30 loops=1)\n    -> Sort: total_spent DESC, limit input to 30 row(s) per chunk  (actual time=400..400 rows=30 loops=1)\n        -> Stream results  (cost=101515 rows=11033) (actual time=5.02..400 rows=38 loops=1)\n            -> Filter: ((c.city = \'Lake Michael\') and (c.registration_date >= DATE\'2024-01-01\') and (c.registration_date <= DATE\'2024-12-31\') and exists(select #3))  (cost=101515 rows=11033) (actual time=4.93..399 rows=38 loops=1)\n                -> Table scan on c  (cost=101515 rows=993134) (actual time=0.157..349 rows=1e+6 loops=1)\n                -> Select #3 (subquery in condition; dependent)\n                    -> Limit: 1 row(s)  (actual time=0.0347..0.0347 rows=0.222 loops=171)\n                        -> Filter: (`sum((oi.quantity * oi.price_per_item))` >= 1000)  (actual time=0.0345..0.0345 rows=0.222 loops=171)\n                            -> Table scan on <temporary>  (actual time=0.0343..0.0343 rows=0.62 loops=171)\n                                -> Aggregate using temporary table  (actual time=0.0341..0.0341 rows=0.749 loops=171)\n                                    -> Nested loop inner join  (cost=9.8 rows=0.608) (actual time=0.0227..0.033 rows=0.889 loops=171)\n                                        -> Nested loop inner join  (cost=7.67 rows=6.08) (actual time=0.0116..0.0247 rows=4.8 loops=171)\n                                            -> Covering index lookup on o using idx_orders_customer_id (customer_id=c.customer_id)  (cost=1.27 rows=2.72) (actual time=0.00386..0.00431 rows=2.47 loops=171)\n                                            -> Index lookup on oi using idx_order_items_order_id (order_id=o.order_id)  (cost=2.21 rows=2.23) (actual time=0.00746..0.00801 rows=1.95 loops=422)\n                                        -> Filter: (p.category = \'Electronics\')  (cost=0.252 rows=0.1) (actual time=0.00159..0.00161 rows=0.185 loops=821)\n                                            -> Single-row index lookup on p using PRIMARY (product_id=oi.product_id)  (cost=0.252 rows=1) (actual time=0.00139..0.00142 rows=1 loops=821)\n'

**2. Optimized**

'-> Limit: 30 row(s)  (actual time=23..23 rows=30 loops=1)\n    -> Sort: cts.total_spent DESC, limit input to 30 row(s) per chunk  (actual time=23..23 rows=30 loops=1)\n        -> Stream results  (cost=97.9 rows=0) (actual time=22.6..22.9 rows=42 loops=1)\n            -> Nested loop inner join  (cost=97.9 rows=0) (actual time=22.6..22.9 rows=42 loops=1)\n                -> Nested loop inner join  (cost=75.4 rows=0) (actual time=14.3..14.6 rows=42 loops=1)\n                    -> Table scan on eec  (cost=2.5..2.5 rows=0) (actual time=14.3..14.3 rows=42 loops=1)\n                        -> Materialize CTE eligible_electronics_customers  (cost=0..0 rows=0) (actual time=14.3..14.3 rows=42 loops=1)\n                            -> Filter: (`sum((oi.price_per_item * oi.quantity))` >= 1000)  (actual time=14.2..14.2 rows=42 loops=1)\n                                -> Table scan on <temporary>  (actual time=14.2..14.2 rows=128 loops=1)\n                                    -> Aggregate using temporary table  (actual time=14.2..14.2 rows=128 loops=1)\n                                        -> Nested loop inner join  (cost=1714 rows=179) (actual time=0.42..13.9 rows=152 loops=1)\n                                            -> Nested loop inner join  (cost=1350 rows=1039) (actual time=0.151..11.1 rows=821 loops=1)\n                                                -> Nested loop inner join  (cost=256 rows=466) (actual time=0.093..2.01 rows=422 loops=1)\n                                                    -> Filter: ((customers.city = \'Lake Michael\') and (customers.registration_date between \'2024-01-01\' and \'2024-12-31\'))  (cost=38.5 rows=171) (actual time=0.0715..0.394 rows=171 loops=1)\n                                                        -> Covering index range scan on customers using idx_customers_city_reg over (city = \'Lake Michael\' AND \'2024-01-01\' <= registration_date <= \'2024-12-31\')  (cost=38.5 rows=171) (actual time=0.064..0.234 rows=171 loops=1)\n                                                    -> Covering index lookup on o using idx_orders_customer_id (customer_id=customers.customer_id)  (cost=1 rows=2.72) (actual time=0.00781..0.00904 rows=2.47 loops=171)\n                                                -> Index lookup on oi using idx_order_items_order_id (order_id=o.order_id)  (cost=2.13 rows=2.23) (actual time=0.0196..0.0211 rows=1.95 loops=422)\n                                            -> Filter: (p.category = \'Electronics\')  (cost=0.25 rows=0.172) (actual time=0.00324..0.00326 rows=0.185 loops=821)\n                                                -> Single-row index lookup on p using PRIMARY (product_id=oi.product_id)  (cost=0.25 rows=1) (actual time=0.00292..0.00297 rows=1 loops=821)\n                    -> Filter: ((customers.city = \'Lake Michael\') and (customers.registration_date between \'2024-01-01\' and \'2024-12-31\'))  (cost=0.41 rows=0.05) (actual time=0.00652..0.00668 rows=1 loops=42)\n                        -> Single-row index lookup on customers using PRIMARY (customer_id=eec.customer_id)  (cost=0.41 rows=1) (actual time=0.00573..0.00578 rows=1 loops=42)\n                -> Index lookup on cts using <auto_key0> (customer_id=eec.customer_id)  (cost=0.261..2.64 rows=10.1) (actual time=0.198..0.198 rows=1 loops=42)\n                    -> Materialize CTE customer_total_spend  (cost=0..0 rows=0) (actual time=8.28..8.28 rows=151 loops=1)\n                        -> Table scan on <temporary>  (actual time=8.15..8.17 rows=151 loops=1)\n                            -> Aggregate using temporary table  (actual time=8.14..8.14 rows=151 loops=1)\n                                -> Nested loop inner join  (cost=1350 rows=1039) (actual time=0.0744..7.6 rows=821 loops=1)\n                                    -> Nested loop inner join  (cost=256 rows=466) (actual time=0.0506..1.45 rows=422 loops=1)\n                                        -> Filter: ((customers.city = \'Lake Michael\') and (customers.registration_date between \'2024-01-01\' and \'2024-12-31\'))  (cost=38.5 rows=171) (actual time=0.039..0.265 rows=171 loops=1)\n                                            -> Covering index range scan on customers using idx_customers_city_reg over (city = \'Lake Michael\' AND \'2024-01-01\' <= registration_date <= \'2024-12-31\')  (cost=38.5 rows=171) (actual time=0.0337..0.155 rows=171 loops=1)\n                                        -> Covering index lookup on o using idx_orders_customer_id (customer_id=customers.customer_id)  (cost=1 rows=2.72) (actual time=0.00593..0.00665 rows=2.47 loops=171)\n                                    -> Index lookup on oi using idx_order_items_order_id (order_id=o.order_id)  (cost=2.13 rows=2.23) (actual time=0.0134..0.0143 rows=1.95 loops=422)\n'

---
## USE INDEX and /*+ SUBQUERY(MATERIALIZATION) */
```sql
WITH filtered_customers AS (
    SELECT /*+ SUBQUERY(MATERIALIZATION) */
        customer_id,
        first_name,
        last_name
    FROM customers USE INDEX (idx_customers_city_reg)
    WHERE city = 'Lake Michael'
        AND registration_date BETWEEN '2024-01-01' AND '2024-12-31' -- CTE для фільтрації клієнтів за містом та роком
),
```
**EXPLAIN**

<img width="1219" height="226" alt="Знімок екрана 2025-10-24 о 11 22 20" src="https://github.com/user-attachments/assets/6b94d0b4-0c18-4d5c-832d-1daea26928e9" />



**EXPLAIN ANALYZE**

'-> Limit: 30 row(s)  (actual time=25.7..25.7 rows=30 loops=1)\n    -> Sort: cts.total_spent DESC, limit input to 30 row(s) per chunk  (actual time=25.7..25.7 rows=30 loops=1)\n        -> Stream results  (cost=178 rows=0) (actual time=24.3..25.6 rows=42 loops=1)\n            -> Nested loop inner join  (cost=178 rows=0) (actual time=24.2..25.6 rows=42 loops=1)\n                -> Inner hash join (customers.customer_id = eec.customer_id)  (cost=178 rows=0) (actual time=17..18.2 rows=42 loops=1)\n                    -> Index range scan on customers using idx_customers_city_reg over (city = \'Lake Michael\' AND \'2024-01-01\' <= registration_date <= \'2024-12-31\'), with index condition: ((customers.city = \'Lake Michael\') and (customers.registration_date between \'2024-01-01\' and \'2024-12-31\'))  (cost=87.6 rows=171) (actual time=0.243..1.43 rows=171 loops=1)\n                    -> Hash\n                        -> Table scan on eec  (cost=2.5..2.5 rows=0) (actual time=16.6..16.6 rows=42 loops=1)\n                            -> Materialize CTE eligible_electronics_customers  (cost=0..0 rows=0) (actual time=16.6..16.6 rows=42 loops=1)\n                                -> Filter: (`sum((oi.price_per_item * oi.quantity))` >= 1000)  (actual time=16.6..16.6 rows=42 loops=1)\n                                    -> Table scan on <temporary>  (actual time=16.6..16.6 rows=128 loops=1)\n                                        -> Aggregate using temporary table  (actual time=16.6..16.6 rows=128 loops=1)\n                                            -> Nested loop inner join  (cost=752 rows=179) (actual time=0.93..16.2 rows=152 loops=1)\n                                                -> Nested loop inner join  (cost=388 rows=1039) (actual time=0.626..12.6 rows=821 loops=1)\n                                                    -> Nested loop inner join  (cost=278 rows=466) (actual time=0.577..2.35 rows=422 loops=1)\n                                                        -> Table scan on <subquery4>  (cost=55.6..60.2 rows=171) (actual time=0.55..0.597 rows=171 loops=1)\n                                                            -> Materialize with deduplication  (cost=55.6..55.6 rows=171) (actual time=0.548..0.548 rows=171 loops=1)\n                                                                -> Filter: ((customers.city = \'Lake Michael\') and (customers.registration_date between \'2024-01-01\' and \'2024-12-31\'))  (cost=38.5 rows=171) (actual time=0.088..0.456 rows=171 loops=1)\n                                                                    -> Covering index range scan on customers using idx_customers_city_reg over (city = \'Lake Michael\' AND \'2024-01-01\' <= registration_date <= \'2024-12-31\')  (cost=38.5 rows=171) (actual time=0.0806..0.272 rows=171 loops=1)\n                                                        -> Covering index lookup on o using idx_orders_customer_id (customer_id=`<subquery4>`.customer_id)  (cost=172 rows=2.72) (actual time=0.0085..0.00982 rows=2.47 loops=171)\n                                                    -> Index lookup on oi using idx_order_items_order_id (order_id=o.order_id)  (cost=2.21 rows=2.23) (actual time=0.0221..0.0239 rows=1.95 loops=422)\n                                                -> Filter: (p.category = \'Electronics\')  (cost=42.8 rows=0.172) (actual time=0.00398..0.00401 rows=0.185 loops=821)\n                                                    -> Single-row index lookup on p using PRIMARY (product_id=oi.product_id)  (cost=42.8 rows=1) (actual time=0.00361..0.00367 rows=1 loops=821)\n                -> Index lookup on cts using <auto_key0> (customer_id=eec.customer_id)  (cost=1.25..2.5 rows=2) (actual time=0.173..0.174 rows=1 loops=42)\n                    -> Materialize CTE customer_total_spend  (cost=0..0 rows=0) (actual time=7.24..7.24 rows=151 loops=1)\n                        -> Table scan on <temporary>  (actual time=7.13..7.14 rows=151 loops=1)\n                            -> Aggregate using temporary table  (actual time=7.13..7.13 rows=151 loops=1)\n                                -> Nested loop inner join  (cost=388 rows=1039) (actual time=0.275..6.62 rows=821 loops=1)\n                                    -> Nested loop inner join  (cost=278 rows=466) (actual time=0.249..1.24 rows=422 loops=1)\n                                        -> Table scan on <subquery7>  (cost=55.6..60.2 rows=171) (actual time=0.233..0.257 rows=171 loops=1)\n                                            -> Materialize with deduplication  (cost=55.6..55.6 rows=171) (actual time=0.232..0.232 rows=171 loops=1)\n                                                -> Filter: ((customers.city = \'Lake Michael\') and (customers.registration_date between \'2024-01-01\' and \'2024-12-31\'))  (cost=38.5 rows=171) (actual time=0.0355..0.172 rows=171 loops=1)\n                                                    -> Covering index range scan on customers using idx_customers_city_reg over (city = \'Lake Michael\' AND \'2024-01-01\' <= registration_date <= \'2024-12-31\')  (cost=38.5 rows=171) (actual time=0.0315..0.102 rows=171 loops=1)\n                                        -> Covering index lookup on o using idx_orders_customer_id (customer_id=`<subquery7>`.customer_id)  (cost=172 rows=2.72) (actual time=0.0048..0.00553 rows=2.47 loops=171)\n                                    -> Index lookup on oi using idx_order_items_order_id (order_id=o.order_id)  (cost=2.21 rows=2.23) (actual time=0.0117..0.0125 rows=1.95 loops=422)\n'
