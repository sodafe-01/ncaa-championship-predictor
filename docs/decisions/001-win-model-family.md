# 001 — Win model family: logistic regression

- **Decision:** the simulations and explanations use the walk-forward LOGISTIC_REG family (`m_game_win_lr_s<season>`); the 2018-19 forecast uses the rating-only logistic model (`m_game_win_rt_all`) because the projection has ratings but no style numbers.
- **Evidence (core tournaments, walk-forward, pre-tournament features only):** tournament log loss 0.504 / 0.553 / 0.514 (average 0.524) for logistic regression vs 0.523 / 0.559 / 0.529 (average 0.537) for boosted trees, March 2015-2017. The rating-only model scored 0.506 / 0.559 / 0.514, close to the full model.
- **Rule:** `m_game_win.is_chosen_model` picks the full-feature family with the lower average core log loss, so a rebuild re-applies the rule rather than a hard-coded name. Boosted trees did better on the March 2018 extension (0.562 vs 0.582); the choice uses only the core seasons.
