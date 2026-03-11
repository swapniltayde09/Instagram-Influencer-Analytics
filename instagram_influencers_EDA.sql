-- Create & load
CREATE DATABASE instagram_influencers;
USE instagram_influencers;

CREATE TABLE top_influencers (
  ranking INT PRIMARY KEY,
  channel_info VARCHAR(100),
  influence_score INT,
  posts_x1000 DECIMAL(10,2),
  followers_1000000 DECIMAL(12,2),
  avg_likes_x100k DECIMAL(10,3),
  eng_rate_pct DECIMAL(5,4),
  new_post_avg_like_x100k DECIMAL(10,3),
  total_likes_billions DECIMAL(12,4),
  country VARCHAR(50)
);

-- Load (local file path)
LOAD DATA LOCAL INFILE 'top_insta_influencers_cleaned_v2.csv'
INTO TABLE top_influencers
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(ranking, channel_info, influence_score, posts_x1000, followers_1000000, 
 avg_likes_x100k, eng_rate_pct, new_post_avg_like_x100k, total_likes_billions, country);

-- Verify
SELECT COUNT(*) as total_rows FROM top_influencers;  -- Expect ~200
SELECT * FROM top_influencers Limit 5;

-- Indexes
CREATE INDEX idx_country ON top_influencers(country);
CREATE INDEX idx_followers ON top_influencers(followers_1000000);

-- =================================
-- Clean update
-- =================================
-- -- Fix "Null" countries
UPDATE top_influencers SET country = NULL WHERE country = 'Null';

-- Fix any #VALUE! (one row)
UPDATE top_influencers SET eng_rate_pct = NULL WHERE eng_rate_pct IS NULL OR eng_rate_pct = '#VALUE!';

-- ============================================
-- Core EDA Queries (Instagram Analyst Style)
-- ============================================
-- Top Performers: Highest avg likes (hundred thousands)
SELECT 
	channel_info, 
	followers_1000000,
    avg_likes_x100k, 
    ROUND(avg_likes_x100k / followers_1000000 * 100, 4) as like_rate_pct
FROM top_influencers 
WHERE avg_likes_x100k > 0
ORDER BY avg_likes_x100k DESC 
LIMIT 10;

-- Country Analysis: Avg engagement by country
SELECT 
	country, 
	COUNT(*) as influencer_count,
    ROUND(AVG(eng_rate_pct * 100), 3) as avg_eng_pct,
    ROUND(AVG(followers_1000000), 1) as avg_followers_m
FROM top_influencers 
WHERE country IS NOT NULL AND country != 'Null'
GROUP BY country 
ORDER BY avg_eng_pct DESC 
LIMIT 10;

-- Scale vs Engagement (Key Insight): Do mega-influencers have lower engagement?
SELECT 
  CASE 
    WHEN followers_1000000 >= 200 THEN 'Mega (>200M)'
    WHEN followers_1000000 >= 50 THEN 'Large (50-200M)'
    ELSE 'Mid (<50M)'
  END as size_tier,
  COUNT(*) as count,
  ROUND(AVG(eng_rate_pct * 100), 3) as avg_eng_pct,
  ROUND(AVG(avg_likes_x100k), 1) as avg_likes_100k
FROM top_influencers 
GROUP BY 1 
ORDER BY avg_eng_pct DESC;

-- Influence Score vs Reality: Does influence_score predict engagement?
SELECT 
  influence_score,
  ROUND(AVG(eng_rate_pct * 100), 3) as avg_eng_pct,
  COUNT(*) as count
FROM top_influencers 
GROUP BY influence_score 
ORDER BY influence_score DESC;

-- =========================================
-- Advanced Insights
-- =========================================
-- Recent momentum: new_post_avg_like vs avg_likes
SELECT 
	channel_info,
    avg_likes_x100k,
    new_post_avg_like_x100k,
    ROUND((new_post_avg_like_x100k - avg_likes_x100k)/avg_likes_x100k * 100, 1) as recent_growth_pct
FROM top_influencers 
ORDER BY recent_growth_pct DESC 
LIMIT 10;

-- Total content value: posts × avg_likes
SELECT 
	country,
    SUM(posts_x1000 * avg_likes_x100k) as total_content_value_100k
FROM top_influencers 
GROUP BY country 
ORDER BY total_content_value_100k DESC;

-- Recent Momentum Leaders: Influencers gaining traction (new posts outperform historical avg)
SELECT 
	channel_info, 
    ROUND((new_post_avg_like_x100k / NULLIF(avg_likes_x100k,0) - 1)*100, 1) as momentum_pct
FROM top_influencers 
WHERE avg_likes_x100k > 0 
ORDER BY momentum_pct DESC 
LIMIT 10;

-- Efficiency Score (Likes per Post per Million Followers)
SELECT 
	channel_info, 
    ROUND(avg_likes_x100k / (posts_x1000 * followers_1000000 / 1000), 4) as eff_score
FROM top_influencers 
WHERE posts_x1000 > 0 AND followers_1000000 > 0
ORDER BY eff_score DESC 
LIMIT 10;

-- Engagement Velocity (60-day vs Historical)
SELECT 
	channel_info,
    eng_rate_pct * 100 as recent_eng_pct,
	(SELECT AVG(eng_rate_pct)*100 FROM top_influencers) as platform_avg,
    CASE 
		WHEN eng_rate_pct > (SELECT AVG(eng_rate_pct) FROM top_influencers) THEN 'Growing' 
        ELSE 'Declining' 
        END as trend
FROM top_influencers 
ORDER BY recent_eng_pct DESC 
LIMIT 10;

-- Market Share by Country (Total Likes Dominance)
SELECT 
	country,
	SUM(total_likes_billions) as country_total_likes_b,
	ROUND(SUM(total_likes_billions) / (SELECT SUM(total_likes_billions) FROM top_influencers) * 100, 1) as global_share_pct
FROM top_influencers 
WHERE country IS NOT NULL 
GROUP BY country 
ORDER BY country_total_likes_b DESC 
LIMIT 5;

-- Content Saturation Risk
SELECT 
	channel_info,
	posts_x1000 / followers_1000000 * 1000 as posts_per_m_follower,
    eng_rate_pct * 100 as eng_pct
FROM top_influencers 
ORDER BY posts_per_m_follower DESC 
LIMIT 10;

-- Undervalued Gems (High Eng, Low Followers)			
WITH ranked_influencers AS (
  SELECT channel_info,
         followers_1000000,
         eng_rate_pct * 100 as eng_pct,
         NTILE(4) OVER (ORDER BY eng_rate_pct DESC) as eng_quartile
  FROM top_influencers 
  WHERE followers_1000000 < 50
)
SELECT channel_info, followers_1000000, eng_pct, eng_quartile
FROM ranked_influencers 
WHERE eng_quartile = 1  -- Top quartile engagement
ORDER BY eng_pct DESC;

-- Influence Score Accuracy									xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-- Correlation: does influence_score predict reality?
SELECT 
  ROUND(
    (AVG(influence_score * eng_rate_pct) - AVG(influence_score) * AVG(eng_rate_pct)) /
    (STDDEV(influence_score) * STDDEV(eng_rate_pct)), 4
  ) as influence_eng_corr,
  ROUND(
    (AVG(influence_score * avg_likes_x100k) - AVG(influence_score) * AVG(avg_likes_x100k)) /
    (STDDEV(influence_score) * STDDEV(avg_likes_x100k)), 4
  ) as influence_likes_corr
FROM top_influencers 
WHERE influence_score IS NOT NULL 
  AND eng_rate_pct IS NOT NULL 
  AND avg_likes_x100k IS NOT NULL;
  
  -- Confirm: High score = low engagement?
SELECT 
  AVG(CASE WHEN influence_score >= 90 THEN eng_rate_pct END) * 100 as high_score_eng,
  AVG(CASE WHEN influence_score < 80 THEN eng_rate_pct END) * 100 as low_score_eng,
  COUNT(*) as total
FROM top_influencers;

-- Score Decile Analysis: Engagement by score deciles
WITH score_deciles AS (
  SELECT *,
         NTILE(10) OVER (ORDER BY influence_score) as score_decile
  FROM top_influencers 
  WHERE influence_score IS NOT NULL
)
SELECT 
  score_decile,
  COUNT(*) as influencers,
  ROUND(AVG(eng_rate_pct * 100), 3) as avg_eng_pct,
  ROUND(AVG(followers_1000000), 1) as avg_followers_m
FROM score_deciles 
GROUP BY score_decile 
ORDER BY score_decile;

-- Create corrected score
ALTER TABLE top_influencers ADD COLUMN corrected_score DECIMAL(5,2);
UPDATE top_influencers 
SET corrected_score = influence_score * 0.3 + (eng_rate_pct * 10000) * 0.7;

-- Top 10 by corrected_score
SELECT 
	channel_info, 
    influence_score, 
    corrected_score, 
    eng_rate_pct*100 as eng_pct
FROM top_influencers 
ORDER BY corrected_score DESC LIMIT 10;
-- ======================================================================

-- Lifetime Value per Influencer
SELECT 
	channel_info,
	total_likes_billions / followers_1000000 as lifetime_likes_per_follower,
	total_likes_billions * 0.01 as est_brand_value_m  -- $0.01/like
FROM top_influencers 
ORDER BY lifetime_likes_per_follower DESC 
LIMIT 10;

-- Momentum Leaders
SELECT 
  channel_info,
  followers_1000000,
  avg_likes_x100k as historical_avg_100k,
  new_post_avg_like_x100k as recent_avg_100k,
  ROUND((new_post_avg_like_x100k / NULLIF(avg_likes_x100k, 0) - 1) * 100, 1) as momentum_pct
FROM top_influencers 
WHERE avg_likes_x100k > 0 
ORDER BY momentum_pct DESC 
LIMIT 10;

-- Create summary table for Tableau/Power BI
CREATE TABLE influencer_insights AS
SELECT 
  t.*,
  ROUND((t.new_post_avg_like_x100k / NULLIF(t.avg_likes_x100k, 0) - 1) * 100, 1) as momentum_pct,
  CASE 
    WHEN (t.new_post_avg_like_x100k / NULLIF(t.avg_likes_x100k, 0) - 1) * 100 > 50 THEN 'Hot'
    WHEN (t.new_post_avg_like_x100k / NULLIF(t.avg_likes_x100k, 0) - 1) * 100 > 0 THEN 'Rising' 
    ELSE 'Stable'
  END as momentum_tier,
  t.corrected_score
FROM top_influencers t
WHERE t.avg_likes_x100k > 0;

-- Infulencers Insight
-- Drop if exists, recreate clean
DROP TABLE IF EXISTS influencer_insights;

CREATE TABLE influencer_insights AS
SELECT 
  ranking, channel_info, influence_score, posts_x1000, followers_1000000,
  avg_likes_x100k, eng_rate_pct, new_post_avg_like_x100k, total_likes_billions, country,
  corrected_score,  -- Already exists
  ROUND((new_post_avg_like_x100k / NULLIF(avg_likes_x100k, 0) - 1) * 100, 1) as momentum_pct,
  CASE 
    WHEN (new_post_avg_like_x100k / NULLIF(avg_likes_x100k, 0) - 1) * 100 > 50 THEN 'Hot'
    WHEN (new_post_avg_like_x100k / NULLIF(avg_likes_x100k, 0) - 1) * 100 > 0 THEN 'Rising' 
    ELSE 'Stable'
  END as momentum_tier
FROM top_influencers 
WHERE avg_likes_x100k > 0;

-- Verify 
SELECT momentum_tier, COUNT(*), ROUND(AVG(corrected_score),1) as avg_corrected 
FROM influencer_insights 
GROUP BY momentum_tier;










