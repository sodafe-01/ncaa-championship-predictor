-- The core backtests (seasons 2014-2016, the March 2015-2017 tournaments) are all present
SELECT season
FROM UNNEST([2014, 2015, 2016]) AS season
WHERE season NOT IN (SELECT season FROM {{ ref('mart_backtest') }})
