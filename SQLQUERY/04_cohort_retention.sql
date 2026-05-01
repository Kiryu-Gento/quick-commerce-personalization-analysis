-- =====================================================================
-- 04. 코호트 리텐션 매트릭스
-- =====================================================================
-- 목적: 가입(첫 구매) 코호트가 N개월 후 얼마나 활성 상태로 남아있는지 측정
-- 핵심 기법:
--   - 다단계 CTE                            : 코호트 정의 → 활동 → 결합 → 집계
--   - PERIOD_DIFF + DATE_FORMAT              : 코호트 기준 경과 개월수 계산
--   - JOIN을 활용한 분모/분자 결합           : 리텐션율 = 활성수 / 코호트 사이즈
-- 원본 분석: notebook에 없음 (신규 추가)
-- 비즈니스 의미: 휴면율 단일 수치(37.7%)를 가입 시점별 시계열로 입체화
--   → 신규 코호트일수록 빠르게 이탈하는지, 서비스 개선 효과가 있는지 추적 가능
-- DBMS: MySQL 8.0+ (PERIOD_DIFF는 5.7에서도 가능, CTE는 8.0 이상)
-- =====================================================================

WITH valid_orders AS (
    SELECT 회원번호, 주문일시
    FROM sales_data
    WHERE 주문취소여부 IS NULL
),

-- 1) 각 회원의 코호트(=첫 구매월) 정의
customer_cohort AS (
    SELECT
        회원번호,
        DATE_FORMAT(MIN(주문일시), '%Y-%m') AS cohort_month
    FROM valid_orders
    GROUP BY 회원번호
),

-- 2) 회원 × 활동월 (같은 달 여러 번 구매해도 1번만 카운트)
customer_activity AS (
    SELECT DISTINCT
        회원번호,
        DATE_FORMAT(주문일시, '%Y-%m') AS activity_month
    FROM valid_orders
),

-- 3) 코호트 + 활동월 결합 → 경과 개월수 계산
--    PERIOD_DIFF(YYYYMM, YYYYMM)은 두 기간의 개월 차이를 반환
cohort_activity AS (
    SELECT
        c.cohort_month,
        a.activity_month,
        PERIOD_DIFF(
            CAST(REPLACE(a.activity_month, '-', '') AS UNSIGNED),
            CAST(REPLACE(c.cohort_month,   '-', '') AS UNSIGNED)
        ) AS months_since_first,
        c.회원번호
    FROM customer_cohort c
    INNER JOIN customer_activity a
        ON c.회원번호 = a.회원번호
),

-- 4) 코호트 사이즈 (분모)
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT 회원번호) AS cohort_users
    FROM customer_cohort
    GROUP BY cohort_month
),

-- 5) 코호트 × 경과월별 활성 사용자 수 (분자)
retention_counts AS (
    SELECT
        cohort_month,
        months_since_first,
        COUNT(DISTINCT 회원번호) AS active_users
    FROM cohort_activity
    GROUP BY cohort_month, months_since_first
)

-- 최종 결과: 코호트별 월별 리텐션율
SELECT
    r.cohort_month,
    s.cohort_users               AS cohort_size,
    r.months_since_first,
    r.active_users,
    ROUND(r.active_users * 100.0 / s.cohort_users, 1) AS retention_rate_pct
FROM retention_counts r
INNER JOIN cohort_size s
    ON r.cohort_month = s.cohort_month
ORDER BY r.cohort_month, r.months_since_first;


-- =====================================================================
-- [참고] 결과 해석법
-- =====================================================================
-- cohort_month | cohort_size | months_since_first | retention_rate_pct
-- 2021-01      | 1,200       | 0                  | 100.0   ← 1월 가입 1,200명
-- 2021-01      | 1,200       | 1                  | 45.2    ← 그중 1개월 후 45%만 재구매
-- 2021-01      | 1,200       | 2                  | 32.1    ← 2개월 후 32%
-- 2021-02      | 1,350       | 0                  | 100.0   ← 2월 가입 1,350명
-- 2021-02      | 1,350       | 1                  | 48.7    ← 1개월 후 48.7%
-- ...
--
-- 가로(같은 코호트)로 보면 → 시간 흐름에 따른 이탈 추세
-- 세로(같은 경과월)로 보면 → 가입 시기별 리텐션 비교 (서비스 개선 효과 추적)
-- =====================================================================
