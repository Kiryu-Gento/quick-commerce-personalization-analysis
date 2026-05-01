-- =====================================================================
-- 01. 월별 인기상품 빈도지수 (Top 3)
-- =====================================================================
-- 목적: 월별로 가장 인기 있었던 상품 대분류 Top 3 추출
-- 핵심 기법:
--   - AVG() OVER (PARTITION BY 카테고리)  : 카테고리별 월평균 계산
--   - ROW_NUMBER() OVER (PARTITION BY 월) : 월별 순위 매기기
-- 원본 분석: notebook Section 5 (Pandas groupby + sort + head)
-- 비즈니스 의미: 시즌별 메인 배너/푸시 알림에 노출할 상품 선정 기준
-- DBMS: MySQL 8.0+ (윈도우 함수 필요)
-- =====================================================================

WITH valid_orders AS (
    -- 취소되지 않은 주문 + 상품 정보 결합
    SELECT
        s.회원번호,
        s.제품번호,
        s.주문일시,
        MONTH(s.주문일시) AS order_month,
        p.물품대분류 AS category
    FROM sales_data s
    INNER JOIN product_data p
        ON s.제품번호 = p.제품번호
    WHERE s.주문취소여부 IS NULL
),

monthly_category_counts AS (
    -- 월 × 카테고리별 주문 건수
    SELECT
        order_month,
        category,
        COUNT(*) AS order_count
    FROM valid_orders
    GROUP BY order_month, category
),

frequency_index AS (
    -- 빈도지수 = 해당 월 주문건수 / 카테고리 월평균
    -- 1.0 = 평소 수준, 1.5 = 평소의 1.5배, 0.5 = 평소의 절반
    SELECT
        order_month,
        category,
        order_count,
        ROUND(
            AVG(order_count) OVER (PARTITION BY category),
            1
        ) AS monthly_avg,
        ROUND(
            order_count / AVG(order_count) OVER (PARTITION BY category),
            3
        ) AS frequency_index
    FROM monthly_category_counts
),

ranked AS (
    -- 월별 빈도지수 기준 순위
    SELECT
        order_month,
        category,
        order_count,
        monthly_avg,
        frequency_index,
        ROW_NUMBER() OVER (
            PARTITION BY order_month
            ORDER BY frequency_index DESC
        ) AS rank_in_month
    FROM frequency_index
)

SELECT
    order_month,
    rank_in_month,
    category,
    order_count,
    monthly_avg,
    frequency_index
FROM ranked
WHERE rank_in_month <= 3
ORDER BY order_month, rank_in_month;
