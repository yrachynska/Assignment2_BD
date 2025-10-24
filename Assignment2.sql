USE ecommerce_db;

-- Знайти 30 "найцінніших"(зробили замовлень на 1000 і більше) клієнтів з міста 'Lake Michael', які зареєструвалися у 2024 році.
EXPLAIN ANALYZE
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



SHOW INDEXES FROM customers;

-- Створення індексів для оптимізації
CREATE INDEX idx_customers_city_reg ON customers(city, registration_date);
DROP INDEX idx_customers_city_reg ON customers;

CREATE INDEX idx_products_category ON products(category);
DROP INDEX idx_products_category ON products;


EXPLAIN ANALYZE
WITH filtered_customers AS (
    SELECT /*+ SUBQUERY(MATERIALIZATION) */
        customer_id,
        first_name,
        last_name
    FROM customers USE INDEX (idx_customers_city_reg)
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

