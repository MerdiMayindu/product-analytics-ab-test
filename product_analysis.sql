-- =============================================
-- PRODUCT ANALYTICS: PLAYER ENGAGEMENT, RETENTION & A/B TEST
-- Author: Merdi Mayindu
-- Tool: SQLite (DB Browser)
-- Data: Cookie Cats mobile game (Tactile Entertainment), table = players
--       90,189 players who installed the game during the test period
-- =============================================

-- THE PRODUCT QUESTION
-- In Cookie Cats, players hit a "gate" at certain levels where they must wait
-- or pay to keep playing. The product team tested moving the first gate from
-- level 30 (gate_30, the current version) to level 40 (gate_40).
-- Did the change help or hurt player retention?

-- KEY METRICS
-- Day-1 retention (D1) = % of players who came back and played 1 day after installing
-- Day-7 retention (D7) = % of players who came back and played 7 days after installing
-- Game rounds          = total rounds played in the first 14 days

-- ---------- PHASE 1: DATA CHECKS ----------

-- 1. How many players are there, and are there any duplicates?
-- Finding: 90,189 rows and 90,189 unique player IDs, so there are no duplicate players.
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT userid) AS unique_players
FROM players;

-- 2. Were players split evenly between the two versions?
-- Finding: The split is almost exactly even: 44,700 players (49.6%) got the gate at level 30
-- and 45,489 (50.4%) got it at level 40. That's what a fair A/B test needs.
SELECT version,
  COUNT(*) AS players,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM players), 1) AS pct_of_players
FROM players
GROUP BY version;

-- 3. What format are the retention columns in?
-- Finding: Retention is stored as text ('True' / 'False'), so it can't be averaged.
-- Fix: convert both columns to 1/0 flags in the clean view.
SELECT retention_1, retention_7, COUNT(*) AS players
FROM players
GROUP BY retention_1, retention_7;

-- 4. Are there any extreme outliers in game rounds played?
-- Finding: One player recorded 49,854 rounds in 14 days, over 3,500 rounds a day and
-- 17x more than the next highest player (2,961). This is almost certainly a
-- tracking error or a bot, so it's removed in the clean view.
SELECT userid, version, sum_gamerounds
FROM players
ORDER BY sum_gamerounds DESC
LIMIT 5;

-- 5. How many players installed the game but never played?
-- Finding: 3,994 players (4.4%) installed the game but never played a single round.
-- They're kept, since failing to start playing is a real product problem.
SELECT COUNT(*) AS players_with_zero_rounds,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM players), 1) AS pct_of_players
FROM players
WHERE sum_gamerounds = 0;

-- ---------- PHASE 2: DATA CLEANING ----------

-- 6. Create a clean view of the data for analysis
-- Finding: Removed the 1 extreme outlier (90,188 players remain), converted retention to
-- 1/0 flags, gave the versions readable names and grouped players into 5
-- engagement bands by rounds played.
DROP VIEW IF EXISTS players_clean;
CREATE VIEW players_clean AS
SELECT userid,
  CASE version WHEN 'gate_30' THEN 'Gate at level 30' ELSE 'Gate at level 40' END AS version,
  sum_gamerounds AS game_rounds,
  CASE WHEN retention_1 = 'True' THEN 1 ELSE 0 END AS retained_d1,
  CASE WHEN retention_7 = 'True' THEN 1 ELSE 0 END AS retained_d7,
  CASE
    WHEN sum_gamerounds = 0 THEN '1. Never played'
    WHEN sum_gamerounds < 10 THEN '2. 1-9 rounds'
    WHEN sum_gamerounds < 30 THEN '3. 10-29 rounds'
    WHEN sum_gamerounds < 100 THEN '4. 30-99 rounds'
    ELSE '5. 100+ rounds'
  END AS engagement_band
FROM players
WHERE sum_gamerounds < 10000;

-- ---------- PHASE 3: ENGAGEMENT & RETENTION ----------

-- 7. What are the overall engagement and retention figures?
-- Finding: Players played 51 rounds on average. 44.5% came back the day after installing,
-- but only 18.6% were still playing a week later.
SELECT COUNT(*) AS players,
  ROUND(AVG(game_rounds), 1) AS avg_rounds,
  ROUND(100.0 * AVG(retained_d1), 1) AS d1_retention_pct,
  ROUND(100.0 * AVG(retained_d7), 1) AS d7_retention_pct
FROM players_clean;

-- 8. What is the typical (median) number of rounds played?
-- Finding: The median player played only 16 rounds, far below the 51 average. A small
-- group of very heavy players pulls the average up, so the median gives a truer
-- picture of a typical player.
SELECT game_rounds AS median_rounds
FROM players_clean
ORDER BY game_rounds
LIMIT 1 OFFSET (SELECT COUNT(*) / 2 FROM players_clean);

-- 9. Player funnel: how many players drop off at each stage?
-- Finding: 95.6% of installers played at least once, but more than half dropped off before
-- day 1 (44.5% returned), and only 18.6% were still playing on day 7. The
-- biggest losses happen in the first 24 hours.
SELECT '1. Installed' AS stage, COUNT(*) AS players, 100.0 AS pct_of_installs FROM players_clean
UNION ALL
SELECT '2. Played at least 1 round', SUM(CASE WHEN game_rounds >= 1 THEN 1 ELSE 0 END),
  ROUND(100.0 * SUM(CASE WHEN game_rounds >= 1 THEN 1 ELSE 0 END) / COUNT(*), 1) FROM players_clean
UNION ALL
SELECT '3. Came back on day 1', SUM(retained_d1),
  ROUND(100.0 * SUM(retained_d1) / COUNT(*), 1) FROM players_clean
UNION ALL
SELECT '4. Came back on day 7', SUM(retained_d7),
  ROUND(100.0 * SUM(retained_d7) / COUNT(*), 1) FROM players_clean;

-- 10. How does engagement relate to retention?
-- Finding: Engagement and retention move together. A third of players (33.5%) played
-- fewer than 10 rounds, and only 1.8% of them were still playing on day 7.
-- Players with 100+ rounds kept playing at 71.1%.
SELECT engagement_band,
  COUNT(*) AS players,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM players_clean), 1) AS pct_of_players,
  ROUND(100.0 * AVG(retained_d1), 1) AS d1_retention_pct,
  ROUND(100.0 * AVG(retained_d7), 1) AS d7_retention_pct
FROM players_clean
GROUP BY engagement_band
ORDER BY engagement_band;

-- 11. Of players who came back on day 1, how many were still playing on day 7?
-- Finding: Players who came back on day 1 were 4.5x more likely to still be playing on
-- day 7 (32.8% vs 7.2%). Getting players back the next day is the key to keeping them.
SELECT CASE WHEN retained_d1 = 1 THEN 'Came back on day 1' ELSE 'Did not come back on day 1' END AS day_1,
  COUNT(*) AS players,
  ROUND(100.0 * AVG(retained_d7), 1) AS d7_retention_pct
FROM players_clean
GROUP BY day_1;

-- ---------- PHASE 4: A/B TEST - GATE AT LEVEL 30 vs LEVEL 40 ----------

-- 12. How did retention compare between the two versions?
-- Finding: Keeping the gate at level 30 gave better retention on both measures:
-- D1 44.82% vs 44.23%, and D7 19.02% vs 18.20%.
SELECT version,
  COUNT(*) AS players,
  ROUND(100.0 * AVG(retained_d1), 2) AS d1_retention_pct,
  ROUND(100.0 * AVG(retained_d7), 2) AS d7_retention_pct
FROM players_clean
GROUP BY version;

-- 13. How big is the difference, in percentage points and in players?
-- Finding: The gate at level 30 was 0.59 points better on D1 and 0.82 points better on D7.
-- Applied to the 45,489 players in the level 40 group, that's around 372 fewer
-- players still playing after a week. A two-proportion z-test shows the D7
-- difference is statistically significant (p = 0.002), so it's very unlikely
-- to be chance. The D1 difference is not significant (p = 0.07).
SELECT
  ROUND(100.0 * (AVG(CASE WHEN version = 'Gate at level 30' THEN retained_d1 END)
               - AVG(CASE WHEN version = 'Gate at level 40' THEN retained_d1 END)), 2) AS d1_difference_pts,
  ROUND(100.0 * (AVG(CASE WHEN version = 'Gate at level 30' THEN retained_d7 END)
               - AVG(CASE WHEN version = 'Gate at level 40' THEN retained_d7 END)), 2) AS d7_difference_pts,
  ROUND((AVG(CASE WHEN version = 'Gate at level 30' THEN retained_d7 END)
       - AVG(CASE WHEN version = 'Gate at level 40' THEN retained_d7 END))
       * SUM(CASE WHEN version = 'Gate at level 40' THEN 1 ELSE 0 END), 0) AS fewer_d7_players_with_gate_40
FROM players_clean;

-- 14. Did the version affect how much people played?
-- Finding: Both versions averaged 51.3 rounds and the same share of players reached 30
-- and 40 rounds, so moving the gate didn't change how much people played in
-- the first two weeks, only whether they kept coming back.
SELECT version,
  ROUND(AVG(game_rounds), 1) AS avg_rounds,
  ROUND(100.0 * AVG(CASE WHEN game_rounds >= 30 THEN 1 ELSE 0 END), 1) AS pct_reached_30_rounds,
  ROUND(100.0 * AVG(CASE WHEN game_rounds >= 40 THEN 1 ELSE 0 END), 1) AS pct_reached_40_rounds
FROM players_clean
GROUP BY version;

-- 15. Where is the difference coming from? D7 retention by version and engagement
-- Finding: The gap is biggest among players who played 10-99 rounds (e.g. 27.8% vs 25.7%
-- for 30-99 rounds), the players most likely to reach the gate. For very light
-- and very heavy players, the version made almost no difference.
SELECT engagement_band,
  ROUND(100.0 * AVG(CASE WHEN version = 'Gate at level 30' THEN retained_d7 END), 1) AS gate_30_d7_pct,
  ROUND(100.0 * AVG(CASE WHEN version = 'Gate at level 40' THEN retained_d7 END), 1) AS gate_40_d7_pct
FROM players_clean
GROUP BY engagement_band
ORDER BY engagement_band;

-- ---------- SUMMARY & RECOMMENDATIONS ----------
-- 1. Keep the gate at level 30. Moving it to level 40 significantly lowered 7-day
--    retention (19.0% vs 18.2%), worth around 370 fewer active players per 45,000
--    installs. A likely reason: the earlier gate gives players a natural break,
--    which keeps the game from feeling repetitive and brings them back later.
-- 2. Focus on the first 24 hours. Over half of players never return after day 1,
--    and those who do are 4.5x more likely to stick around. Onboarding, early
--    rewards and day-1 push notifications should be the top priority.
-- 3. Get light players to 10+ rounds. A third of players stop before 10 rounds and
--    almost none of them return. Easier early levels or a starter reward could
--    move them into the higher-retention bands.
-- 4. Re-engage players who skip day 1 with a reminder or free lives, since 7% of
--    them still come back by day 7.
-- 5. Report median as well as average engagement. A small group of heavy players
--    makes the average (51 rounds) far higher than the typical player (16).
