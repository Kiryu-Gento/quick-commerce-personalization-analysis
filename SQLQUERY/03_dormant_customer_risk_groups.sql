-- =====================================================================
-- 03. 휴면고객 위험군 분류
-- =====================================================================
-- 목적: 60일 이상 미구매 휴면고객을 구매빈도 기준 위험군(High/Mid/Low)으로 분할
-- 핵심 기법:
--   - DATEDIFF + WHERE                       : 휴면 정의(60일 미구매)
--   - NTILE(3) OVER (ORDER BY frequency)     : 빈도 기준 3등분
--   - CASE WHEN                              : 위험군 라벨 + 권장 전략 매핑
-- 원본 분석: notebook Section 7
--   → Pandas의 quantile(0.33), quantile(0.66) 수동 binning을 NTILE(3)으로 대체
-- 비즈니스 의미: 위험군별 차등 개입 전략으로 마케팅 ROI 극대화
-- DBMS: MySQL 8.0+
-- =====================================================================

WITH valid_orders AS (
    SELECT 회원번호, 주문일시
    FROM sales_data
    WHERE 주문취소여부 IS NULL
),

customer_rfm AS (
    -- 회원별 Recency, Frequency 계산 (정상회원만)
    SELECT
        v.회원번호,
        m.나이,
        m.구독여부,
        DATEDIFF('2021-10-31', MAX(v.주문일시)) AS recency_days,
        COUNT(*)                                 AS frequency
    FROM valid_orders v
    INNER JOIN member_data m
        ON v.회원번호 = m.회원번호
    WHERE m.회원상태 = '정상회원'
    GROUP BY v.회원번호, m.나이, m.구독여부
),

dormant_customers AS (
    -- 60일 이상 미구매 = 휴면 고객으로 정의 + 위험군 분류
    SELECT
        회원번호,
        나이,
        구독여부,
        recency_days,
        frequency,
        -- 연령 구간 (notebook과 동일한 기준)
        CASE
            WHEN 나이 <= 39 THEN '20-30대'
            WHEN 나이 <= 59 THEN '40-50대'
            ELSE '60대이상'
        END AS age_group,
        -- NTILE(3): frequency 오름차순 → 1=빈도 낮음, 3=빈도 높음
        NTILE(3) OVER (ORDER BY frequency ASC) AS frequency_tier
    FROM customer_rfm
    WHERE recency_days >= 60   -- 휴면 정의
)

SELECT
    회원번호,
    age_group,
    구독여부,
    recency_days,
    frequency,
    -- 빈도 낮음(tier 1) → 복귀 난이도 높음 → High 위험군
    -- 빈도 중간(tier 2) → 잠재 가치 높음 → Mid 위험군
    -- 빈도 높음(tier 3) → 관계 유지 단계  → Low 위험군
    CASE frequency_tier
        WHEN 1 THEN 'High'
        WHEN 2 THEN 'Mid'
        WHEN 3 THEN 'Low'
    END AS risk_group,
    -- 위험군별 권장 개입 전략 (notebook 결론과 일치)
    CASE frequency_tier
        WHEN 1 THEN '1만원 쿠폰 + 무료배송 (푸시+카톡, 오후 8시)'
        WHEN 2 THEN '5천원 쿠폰 (푸시, 오후 8시)'
        WHEN 3 THEN '콘텐츠 중심 관계 유지 (월 1회)'
    END AS suggested_action
FROM dormant_customers
ORDER BY frequency_tier, recency_days DESC;


-- =====================================================================
-- [집계 검증용 보조 쿼리] 위험군별 인원 분포
-- =====================================================================
-- 위 쿼리를 서브쿼리로 감싸 위험군별 카운트로 집계할 때 사용
--
-- SELECT risk_group, COUNT(*) AS customer_count
-- FROM ( ... 위 쿼리 ... ) t
-- GROUP BY risk_group
-- ORDER BY FIELD(risk_group, 'High', 'Mid', 'Low');
