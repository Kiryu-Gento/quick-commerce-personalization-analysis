-- =====================================================================
-- 02. RFM 세그멘테이션
-- =====================================================================
-- 목적: 고객을 R/F/M 점수(1~5점)로 정량 평가하고 표준 세그먼트 분류
-- 핵심 기법:
--   - NTILE(5) OVER (ORDER BY ...)  : 데이터를 5등분하여 점수 부여
--   - 다단계 CTE 체이닝               : 단계별 가독성 확보
--   - CASE WHEN                      : 점수 조합으로 세그먼트 정의
-- 원본 분석: notebook Section 6 (RFM 평균값만 비교)
--   → SQL 버전은 5점 만점 스코어링 + 표준 세그먼트(Champion/Loyal/...)까지 확장
-- 비즈니스 의미: 세그먼트별 차별화된 마케팅 전략 수립의 기반
-- DBMS: MySQL 8.0+
-- =====================================================================

WITH valid_orders AS (
    SELECT 회원번호, 주문일시, 구매금액
    FROM sales_data
    WHERE 주문취소여부 IS NULL
),

rfm_base AS (
    -- 회원별 RFM 원시 값 계산 (정상회원만 대상)
    -- 분석 기준일: 2021-10-31
    SELECT
        v.회원번호,
        DATEDIFF('2021-10-31', MAX(v.주문일시)) AS recency_days,
        COUNT(*)                                 AS frequency,
        SUM(v.구매금액)                          AS monetary
    FROM valid_orders v
    INNER JOIN member_data m
        ON v.회원번호 = m.회원번호
    WHERE m.회원상태 = '정상회원'
    GROUP BY v.회원번호
),

rfm_scored AS (
    -- NTILE(5)로 각 지표를 5등분하여 1~5점 부여
    -- Recency : 최근 구매일수록 5점 (recency_days 작을수록 5점)
    -- Frequency: 많이 살수록 5점
    -- Monetary : 많이 쓸수록 5점
    SELECT
        회원번호,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS R_score,
        NTILE(5) OVER (ORDER BY frequency DESC)    AS F_score,
        NTILE(5) OVER (ORDER BY monetary DESC)     AS M_score
    FROM rfm_base
)

SELECT
    회원번호,
    recency_days,
    frequency,
    monetary,
    R_score,
    F_score,
    M_score,
    CONCAT(R_score, F_score, M_score) AS rfm_code,
    -- 표준 RFM 세그먼트 분류
    CASE
        WHEN R_score = 5 AND F_score >= 4 AND M_score >= 4 THEN 'Champion'
        WHEN R_score >= 4 AND F_score >= 3                 THEN 'Loyal'
        WHEN R_score = 5 AND F_score <= 2                  THEN 'New Customer'
        WHEN R_score = 3 AND F_score >= 3                  THEN 'Potential Loyalist'
        WHEN R_score <= 2 AND F_score >= 4                 THEN 'At Risk'
        WHEN R_score = 1 AND F_score = 1                   THEN 'Lost'
        WHEN R_score <= 2 AND F_score <= 2                 THEN 'Hibernating'
        ELSE 'Others'
    END AS customer_segment,
    -- 세그먼트별 권장 액션 (마케팅 전략 매핑)
    CASE
        WHEN R_score = 5 AND F_score >= 4 AND M_score >= 4 THEN '리워드/VIP 프로그램'
        WHEN R_score >= 4 AND F_score >= 3                 THEN '교차판매/구독 제안'
        WHEN R_score = 5 AND F_score <= 2                  THEN '온보딩 강화'
        WHEN R_score <= 2 AND F_score >= 4                 THEN '복귀 캠페인 (고가치)'
        WHEN R_score = 1 AND F_score = 1                   THEN '저비용 리텐션 또는 제외'
        ELSE '일반 마케팅'
    END AS recommended_action
FROM rfm_scored
ORDER BY R_score DESC, F_score DESC, M_score DESC;
