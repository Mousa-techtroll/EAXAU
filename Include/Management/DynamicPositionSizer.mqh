//+------------------------------------------------------------------+
//| DynamicPositionSizer.mqh                                         |
//| Dynamic Position Sizing with Kelly Criterion                     |
//| v1.0 - Adaptive risk based on historical performance            |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| Trade Result Structure for Performance Tracking                  |
//+------------------------------------------------------------------+
struct STradeResult
{
   datetime             close_time;         // When trade closed
   ENUM_PATTERN_TYPE    pattern_type;       // Pattern that triggered trade
   ENUM_SIGNAL_TYPE     direction;          // Long or short
   ENUM_REGIME_TYPE     regime;             // Market regime at entry
   double               risk_amount;        // Amount risked
   double               profit;             // Actual P&L
   double               risk_reward;        // Actual R:R achieved
   bool                 is_winner;          // Win or loss
};

//+------------------------------------------------------------------+
//| Pattern Performance Statistics                                   |
//+------------------------------------------------------------------+
struct SPatternStats
{
   ENUM_PATTERN_TYPE    pattern_type;       // Pattern type
   int                  total_trades;       // Total trades with this pattern
   int                  wins;               // Winning trades
   int                  losses;             // Losing trades
   double               win_rate;           // Win rate (0-1)
   double               avg_win;            // Average win amount
   double               avg_loss;           // Average loss amount
   double               profit_factor;      // Gross profit / Gross loss
   double               avg_rr;             // Average R:R achieved
   double               kelly_fraction;     // Optimal Kelly %
   double               recommended_risk;   // Recommended risk %
};

//+------------------------------------------------------------------+
//| Dynamic Position Sizing Configuration                            |
//+------------------------------------------------------------------+
struct SDynamicSizingConfig
{
   // Kelly Criterion settings
   double   kelly_fraction;          // Fraction of Kelly to use (0.25 = quarter Kelly)
   double   min_kelly_trades;        // Min trades before using Kelly (default 20)

   // Risk boundaries
   double   min_risk_pct;            // Minimum risk % (floor)
   double   max_risk_pct;            // Maximum risk % (ceiling)
   double   base_risk_pct;           // Base risk when no history

   // Volatility adjustment
   double   low_vol_risk_mult;       // Risk multiplier in low volatility
   double   high_vol_risk_mult;      // Risk multiplier in high volatility

   // Drawdown protection
   double   drawdown_threshold_1;    // Drawdown % to trigger level 1 reduction
   double   drawdown_threshold_2;    // Drawdown % to trigger level 2 reduction
   double   drawdown_risk_mult_1;    // Risk multiplier at level 1
   double   drawdown_risk_mult_2;    // Risk multiplier at level 2

   // Win streak boost
   int      win_streak_threshold;    // Wins before boost
   double   win_streak_boost;        // Boost multiplier (e.g., 1.2)

   // Recent performance weight
   int      recent_trades_lookback;  // How many recent trades to weight heavily
   double   recent_weight;           // Weight for recent trades (0-1)
};

//+------------------------------------------------------------------+
//| Dynamic Position Sizer Class                                     |
//+------------------------------------------------------------------+
class CDynamicPositionSizer
{
private:
   SDynamicSizingConfig m_config;

   // Trade history for performance tracking
   STradeResult         m_trade_history[];
   int                  m_history_size;
   int                  m_max_history;

   // Pattern-specific statistics
   SPatternStats        m_pattern_stats[];
   int                  m_pattern_count;

   // Overall statistics
   int                  m_total_trades;
   int                  m_total_wins;
   double               m_overall_win_rate;
   double               m_overall_avg_rr;
   double               m_overall_kelly;

   // Current state
   double               m_current_drawdown;
   double               m_peak_balance;
   int                  m_current_win_streak;
   int                  m_current_loss_streak;

   // ATR handles for volatility
   int                  m_handle_atr_h1;
   double               m_atr_average;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CDynamicPositionSizer()
   {
      m_max_history = 200;  // Keep last 200 trades
      m_history_size = 0;
      m_pattern_count = 0;
      m_total_trades = 0;
      m_total_wins = 0;
      m_overall_win_rate = 0.5;  // Default assumption
      m_overall_avg_rr = 1.5;    // Default assumption
      m_overall_kelly = 0;
      m_current_drawdown = 0;
      m_peak_balance = 0;
      m_current_win_streak = 0;
      m_current_loss_streak = 0;
      m_atr_average = 0;

      ArrayResize(m_trade_history, m_max_history);
      ArrayResize(m_pattern_stats, 10);  // 10 pattern types

      // Initialize default configuration
      m_config.kelly_fraction = 0.25;          // Quarter Kelly (conservative)
      m_config.min_kelly_trades = 20;
      m_config.min_risk_pct = 0.5;
      m_config.max_risk_pct = 3.0;
      m_config.base_risk_pct = 1.0;
      m_config.low_vol_risk_mult = 1.2;
      m_config.high_vol_risk_mult = 0.7;
      m_config.drawdown_threshold_1 = 5.0;
      m_config.drawdown_threshold_2 = 10.0;
      m_config.drawdown_risk_mult_1 = 0.75;
      m_config.drawdown_risk_mult_2 = 0.5;
      m_config.win_streak_threshold = 3;
      m_config.win_streak_boost = 1.15;
      m_config.recent_trades_lookback = 10;
      m_config.recent_weight = 0.6;

      // Initialize pattern stats
      InitializePatternStats();
   }

   //+------------------------------------------------------------------+
   //| Configure with custom parameters                                  |
   //+------------------------------------------------------------------+
   void Configure(double kelly_frac, int min_trades, double min_risk, double max_risk,
                  double base_risk, double low_vol_mult, double high_vol_mult,
                  double dd_thresh1, double dd_thresh2, double dd_mult1, double dd_mult2,
                  int win_streak_thresh, double win_streak_mult,
                  int recent_lookback, double recent_wt)
   {
      m_config.kelly_fraction = MathMax(0.1, MathMin(0.5, kelly_frac));
      m_config.min_kelly_trades = MathMax(10, min_trades);
      m_config.min_risk_pct = MathMax(0.25, min_risk);
      m_config.max_risk_pct = MathMin(5.0, max_risk);
      m_config.base_risk_pct = base_risk;
      m_config.low_vol_risk_mult = low_vol_mult;
      m_config.high_vol_risk_mult = high_vol_mult;
      m_config.drawdown_threshold_1 = dd_thresh1;
      m_config.drawdown_threshold_2 = dd_thresh2;
      m_config.drawdown_risk_mult_1 = dd_mult1;
      m_config.drawdown_risk_mult_2 = dd_mult2;
      m_config.win_streak_threshold = win_streak_thresh;
      m_config.win_streak_boost = win_streak_mult;
      m_config.recent_trades_lookback = recent_lookback;
      m_config.recent_weight = recent_wt;
   }

   //+------------------------------------------------------------------+
   //| Initialize indicator handles                                      |
   //+------------------------------------------------------------------+
   bool Init()
   {
      m_handle_atr_h1 = iATR(_Symbol, PERIOD_H1, 14);

      if(m_handle_atr_h1 == INVALID_HANDLE)
      {
         LogPrint("ERROR: DynamicPositionSizer failed to create ATR indicator");
         return false;
      }

      // Initialize peak balance
      m_peak_balance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Load trade history from account history
      LoadHistoricalTrades();

      LogPrint("DynamicPositionSizer initialized successfully");
      LogPrint("  Kelly Fraction: ", m_config.kelly_fraction * 100, "%");
      LogPrint("  Risk Range: ", m_config.min_risk_pct, "% - ", m_config.max_risk_pct, "%");
      LogPrint("  Drawdown Thresholds: ", m_config.drawdown_threshold_1, "% / ", m_config.drawdown_threshold_2, "%");
      LogPrint("  Historical Trades Loaded: ", m_total_trades);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CDynamicPositionSizer()
   {
      if(m_handle_atr_h1 != INVALID_HANDLE)
         IndicatorRelease(m_handle_atr_h1);
   }

   //+------------------------------------------------------------------+
   //| Calculate dynamic risk percentage                                 |
   //+------------------------------------------------------------------+
   double CalculateDynamicRisk(double base_risk, ENUM_PATTERN_TYPE pattern,
                               ENUM_SETUP_QUALITY quality, ENUM_REGIME_TYPE regime)
   {
      LogPrint("=== DYNAMIC POSITION SIZING ===");
      LogPrint("  Base Risk: ", DoubleToString(base_risk, 2), "%");
      LogPrint("  Pattern: ", EnumToString(pattern));
      LogPrint("  Quality: ", EnumToString(quality));
      LogPrint("  Regime: ", EnumToString(regime));

      double final_risk = base_risk;

      // Step 1: Apply Kelly Criterion if we have enough history
      double kelly_risk = CalculateKellyRisk(pattern);
      if(kelly_risk > 0 && m_total_trades >= m_config.min_kelly_trades)
      {
         // Blend Kelly with base risk (weighted average)
         double kelly_weight = MathMin(1.0, (double)m_total_trades / 50.0);  // Full weight at 50 trades
         final_risk = (kelly_risk * kelly_weight) + (base_risk * (1.0 - kelly_weight));
         LogPrint("  Kelly Risk: ", DoubleToString(kelly_risk, 2), "% (weight: ", DoubleToString(kelly_weight * 100, 0), "%)");
      }
      else
      {
         LogPrint("  Kelly: Insufficient history (", m_total_trades, "/", m_config.min_kelly_trades, " trades)");
      }

      // Step 2: Apply pattern-specific adjustment
      double pattern_mult = GetPatternMultiplier(pattern);
      final_risk *= pattern_mult;
      LogPrint("  Pattern Multiplier: ", DoubleToString(pattern_mult, 2), "x");

      // Step 3: Apply volatility adjustment
      double vol_mult = GetVolatilityMultiplier();
      final_risk *= vol_mult;
      LogPrint("  Volatility Multiplier: ", DoubleToString(vol_mult, 2), "x");

      // Step 4: Apply regime adjustment
      double regime_mult = GetRegimeMultiplier(regime);
      final_risk *= regime_mult;
      LogPrint("  Regime Multiplier: ", DoubleToString(regime_mult, 2), "x");

      // Step 5: Apply drawdown protection
      UpdateDrawdown();
      double dd_mult = GetDrawdownMultiplier();
      final_risk *= dd_mult;
      if(dd_mult < 1.0)
         LogPrint("  Drawdown Protection: ", DoubleToString(dd_mult, 2), "x (DD: ", DoubleToString(m_current_drawdown, 1), "%)");

      // Step 6: Apply win streak boost (only if no drawdown reduction)
      if(dd_mult >= 1.0 && m_current_win_streak >= m_config.win_streak_threshold)
      {
         final_risk *= m_config.win_streak_boost;
         LogPrint("  Win Streak Boost: ", DoubleToString(m_config.win_streak_boost, 2), "x (", m_current_win_streak, " wins)");
      }

      // Step 7: Apply quality tier adjustment
      double quality_mult = GetQualityMultiplier(quality);
      final_risk *= quality_mult;
      LogPrint("  Quality Multiplier: ", DoubleToString(quality_mult, 2), "x");

      // Step 8: Enforce boundaries
      final_risk = MathMax(m_config.min_risk_pct, MathMin(m_config.max_risk_pct, final_risk));

      LogPrint("  FINAL DYNAMIC RISK: ", DoubleToString(final_risk, 2), "%");
      LogPrint("================================");

      return final_risk;
   }

   //+------------------------------------------------------------------+
   //| Record trade result for performance tracking                     |
   //+------------------------------------------------------------------+
   void RecordTradeResult(ENUM_PATTERN_TYPE pattern, ENUM_SIGNAL_TYPE direction,
                          ENUM_REGIME_TYPE regime, double risk_amount,
                          double profit, double risk_reward, bool is_winner)
   {
      // Add to history (circular buffer)
      int idx = m_history_size % m_max_history;

      m_trade_history[idx].close_time = TimeCurrent();
      m_trade_history[idx].pattern_type = pattern;
      m_trade_history[idx].direction = direction;
      m_trade_history[idx].regime = regime;
      m_trade_history[idx].risk_amount = risk_amount;
      m_trade_history[idx].profit = profit;
      m_trade_history[idx].risk_reward = risk_reward;
      m_trade_history[idx].is_winner = is_winner;

      m_history_size++;
      m_total_trades++;

      if(is_winner)
      {
         m_total_wins++;
         m_current_win_streak++;
         m_current_loss_streak = 0;
      }
      else
      {
         m_current_loss_streak++;
         m_current_win_streak = 0;
      }

      // Update overall statistics
      UpdateOverallStats();

      // Update pattern-specific statistics
      UpdatePatternStats(pattern, profit, risk_amount, risk_reward, is_winner);

      LogPrint("Trade Result Recorded: ", EnumToString(pattern),
               " | ", is_winner ? "WIN" : "LOSS",
               " | P&L: $", DoubleToString(profit, 2),
               " | R:R: ", DoubleToString(risk_reward, 2));
      LogPrint("  Overall Stats: ", m_total_wins, "/", m_total_trades,
               " (", DoubleToString(m_overall_win_rate * 100, 1), "% WR)",
               " | Kelly: ", DoubleToString(m_overall_kelly * 100, 2), "%");
   }

   //+------------------------------------------------------------------+
   //| Get pattern-specific statistics                                   |
   //+------------------------------------------------------------------+
   SPatternStats GetPatternStats(ENUM_PATTERN_TYPE pattern)
   {
      for(int i = 0; i < m_pattern_count; i++)
      {
         if(m_pattern_stats[i].pattern_type == pattern)
            return m_pattern_stats[i];
      }

      // Return empty stats if not found
      SPatternStats empty;
      empty.pattern_type = pattern;
      empty.total_trades = 0;
      empty.wins = 0;
      empty.losses = 0;
      empty.win_rate = 0.5;
      empty.avg_win = 0;
      empty.avg_loss = 0;
      empty.profit_factor = 1.0;
      empty.avg_rr = 1.5;
      empty.kelly_fraction = 0;
      empty.recommended_risk = m_config.base_risk_pct;
      return empty;
   }

   //+------------------------------------------------------------------+
   //| Get overall statistics                                            |
   //+------------------------------------------------------------------+
   double GetOverallWinRate() { return m_overall_win_rate; }
   double GetOverallKelly() { return m_overall_kelly; }
   int GetTotalTrades() { return m_total_trades; }
   double GetCurrentDrawdown() { return m_current_drawdown; }
   int GetWinStreak() { return m_current_win_streak; }
   int GetLossStreak() { return m_current_loss_streak; }

   //+------------------------------------------------------------------+
   //| Get configuration                                                 |
   //+------------------------------------------------------------------+
   SDynamicSizingConfig GetConfig() { return m_config; }

private:
   //+------------------------------------------------------------------+
   //| Initialize pattern statistics array                               |
   //+------------------------------------------------------------------+
   void InitializePatternStats()
   {
      // Initialize stats for each pattern type
      ENUM_PATTERN_TYPE patterns[] = {
         PATTERN_ENGULFING, PATTERN_PIN_BAR, PATTERN_MA_CROSS_ANOMALY,
         PATTERN_LIQUIDITY_SWEEP, PATTERN_SR_BOUNCE, PATTERN_BB_MEAN_REVERSION,
         PATTERN_RANGE_BOX, PATTERN_FALSE_BREAKOUT_FADE, PATTERN_BREAKOUT_RETEST
      };

      m_pattern_count = ArraySize(patterns);
      ArrayResize(m_pattern_stats, m_pattern_count);

      for(int i = 0; i < m_pattern_count; i++)
      {
         m_pattern_stats[i].pattern_type = patterns[i];
         m_pattern_stats[i].total_trades = 0;
         m_pattern_stats[i].wins = 0;
         m_pattern_stats[i].losses = 0;
         m_pattern_stats[i].win_rate = 0.5;
         m_pattern_stats[i].avg_win = 0;
         m_pattern_stats[i].avg_loss = 0;
         m_pattern_stats[i].profit_factor = 1.0;
         m_pattern_stats[i].avg_rr = 1.5;
         m_pattern_stats[i].kelly_fraction = 0;
         m_pattern_stats[i].recommended_risk = m_config.base_risk_pct;
      }
   }

   //+------------------------------------------------------------------+
   //| Load historical trades from account history                       |
   //+------------------------------------------------------------------+
   void LoadHistoricalTrades()
   {
      // Load last 30 days of history
      datetime from_date = TimeCurrent() - 30 * 24 * 60 * 60;
      HistorySelect(from_date, TimeCurrent());

      int deals = HistoryDealsTotal();
      double total_wins_amount = 0;
      double total_losses_amount = 0;

      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);

         // Only count exit deals
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;

         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
         profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         if(profit > 0)
         {
            m_total_wins++;
            total_wins_amount += profit;
         }
         else if(profit < 0)
         {
            total_losses_amount += MathAbs(profit);
         }

         m_total_trades++;
      }

      // Calculate initial statistics
      if(m_total_trades > 0)
      {
         m_overall_win_rate = (double)m_total_wins / m_total_trades;

         double avg_win = (m_total_wins > 0) ? total_wins_amount / m_total_wins : 0;
         double avg_loss = (m_total_trades - m_total_wins > 0) ?
                           total_losses_amount / (m_total_trades - m_total_wins) : 1;

         m_overall_avg_rr = (avg_loss > 0) ? avg_win / avg_loss : 1.5;

         // Calculate Kelly
         CalculateOverallKelly();
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Kelly Criterion optimal risk                            |
   //+------------------------------------------------------------------+
   double CalculateKellyRisk(ENUM_PATTERN_TYPE pattern)
   {
      // First try pattern-specific Kelly
      SPatternStats stats = GetPatternStats(pattern);

      if(stats.total_trades >= 10 && stats.kelly_fraction > 0)
      {
         // Use pattern-specific Kelly with configured fraction
         return stats.kelly_fraction * m_config.kelly_fraction * 100.0;
      }

      // Fall back to overall Kelly
      if(m_overall_kelly > 0)
      {
         return m_overall_kelly * m_config.kelly_fraction * 100.0;
      }

      return 0;  // No Kelly available
   }

   //+------------------------------------------------------------------+
   //| Calculate overall Kelly percentage                                |
   //+------------------------------------------------------------------+
   void CalculateOverallKelly()
   {
      if(m_total_trades < 5)
      {
         m_overall_kelly = 0;
         return;
      }

      // Kelly Formula: K = W - (1-W)/R
      // Where W = win rate, R = avg win / avg loss ratio
      double W = m_overall_win_rate;
      double R = m_overall_avg_rr;

      if(R <= 0)
      {
         m_overall_kelly = 0;
         return;
      }

      double kelly = W - ((1.0 - W) / R);

      // Kelly can be negative (meaning don't trade this setup)
      // We cap it at reasonable bounds
      m_overall_kelly = MathMax(0, MathMin(0.25, kelly));  // Max 25% of bankroll
   }

   //+------------------------------------------------------------------+
   //| Update overall statistics                                         |
   //+------------------------------------------------------------------+
   void UpdateOverallStats()
   {
      if(m_total_trades == 0)
         return;

      // Calculate win rate with recent trades weighted more heavily
      int recent_count = MathMin(m_config.recent_trades_lookback, m_history_size);
      int recent_wins = 0;
      double recent_rr_sum = 0;

      int start_idx = (m_history_size > m_max_history) ?
                      (m_history_size % m_max_history) : 0;

      for(int i = 0; i < recent_count; i++)
      {
         int idx = (start_idx + m_history_size - 1 - i) % m_max_history;
         if(idx < 0) idx += m_max_history;

         if(m_trade_history[idx].is_winner)
            recent_wins++;
         recent_rr_sum += m_trade_history[idx].risk_reward;
      }

      double recent_win_rate = (recent_count > 0) ? (double)recent_wins / recent_count : 0.5;
      double overall_win_rate = (double)m_total_wins / m_total_trades;

      // Weighted average of recent and overall
      m_overall_win_rate = (recent_win_rate * m_config.recent_weight) +
                           (overall_win_rate * (1.0 - m_config.recent_weight));

      // Update average R:R
      if(recent_count > 0)
      {
         double recent_avg_rr = recent_rr_sum / recent_count;
         m_overall_avg_rr = (recent_avg_rr * m_config.recent_weight) +
                            (m_overall_avg_rr * (1.0 - m_config.recent_weight));
      }

      // Recalculate Kelly
      CalculateOverallKelly();
   }

   //+------------------------------------------------------------------+
   //| Update pattern-specific statistics                                |
   //+------------------------------------------------------------------+
   void UpdatePatternStats(ENUM_PATTERN_TYPE pattern, double profit,
                           double risk_amount, double rr, bool is_winner)
   {
      // Find pattern in array
      int idx = -1;
      for(int i = 0; i < m_pattern_count; i++)
      {
         if(m_pattern_stats[i].pattern_type == pattern)
         {
            idx = i;
            break;
         }
      }

      if(idx < 0)
         return;

      // Update counts
      m_pattern_stats[idx].total_trades++;
      if(is_winner)
         m_pattern_stats[idx].wins++;
      else
         m_pattern_stats[idx].losses++;

      // Update win rate
      m_pattern_stats[idx].win_rate = (double)m_pattern_stats[idx].wins /
                                       m_pattern_stats[idx].total_trades;

      // Update average R:R (exponential moving average)
      double alpha = 0.2;  // Smoothing factor
      m_pattern_stats[idx].avg_rr = (m_pattern_stats[idx].avg_rr * (1 - alpha)) + (rr * alpha);

      // Update average win/loss
      if(is_winner && profit > 0)
      {
         if(m_pattern_stats[idx].avg_win == 0)
            m_pattern_stats[idx].avg_win = profit;
         else
            m_pattern_stats[idx].avg_win = (m_pattern_stats[idx].avg_win * (1 - alpha)) + (profit * alpha);
      }
      else if(!is_winner && profit < 0)
      {
         if(m_pattern_stats[idx].avg_loss == 0)
            m_pattern_stats[idx].avg_loss = MathAbs(profit);
         else
            m_pattern_stats[idx].avg_loss = (m_pattern_stats[idx].avg_loss * (1 - alpha)) + (MathAbs(profit) * alpha);
      }

      // Calculate profit factor
      if(m_pattern_stats[idx].avg_loss > 0)
      {
         double gross_profit = m_pattern_stats[idx].avg_win * m_pattern_stats[idx].wins;
         double gross_loss = m_pattern_stats[idx].avg_loss * m_pattern_stats[idx].losses;
         m_pattern_stats[idx].profit_factor = (gross_loss > 0) ? gross_profit / gross_loss : 1.0;
      }

      // Calculate pattern Kelly
      if(m_pattern_stats[idx].total_trades >= 10)
      {
         double W = m_pattern_stats[idx].win_rate;
         double R = (m_pattern_stats[idx].avg_loss > 0) ?
                    m_pattern_stats[idx].avg_win / m_pattern_stats[idx].avg_loss : 1.5;

         double kelly = W - ((1.0 - W) / R);
         m_pattern_stats[idx].kelly_fraction = MathMax(0, MathMin(0.25, kelly));

         // Calculate recommended risk
         m_pattern_stats[idx].recommended_risk = m_pattern_stats[idx].kelly_fraction *
                                                  m_config.kelly_fraction * 100.0;
         m_pattern_stats[idx].recommended_risk = MathMax(m_config.min_risk_pct,
                                                  MathMin(m_config.max_risk_pct,
                                                  m_pattern_stats[idx].recommended_risk));
      }
   }

   //+------------------------------------------------------------------+
   //| Get pattern-specific multiplier based on historical performance   |
   //+------------------------------------------------------------------+
   double GetPatternMultiplier(ENUM_PATTERN_TYPE pattern)
   {
      SPatternStats stats = GetPatternStats(pattern);

      if(stats.total_trades < 5)
         return 1.0;  // Not enough data

      // Base multiplier on profit factor
      double mult = 1.0;

      if(stats.profit_factor > 2.0)
         mult = 1.2;  // Very profitable pattern
      else if(stats.profit_factor > 1.5)
         mult = 1.1;  // Profitable pattern
      else if(stats.profit_factor < 0.8)
         mult = 0.7;  // Underperforming pattern
      else if(stats.profit_factor < 1.0)
         mult = 0.85; // Slightly unprofitable

      return mult;
   }

   //+------------------------------------------------------------------+
   //| Get volatility-based multiplier                                   |
   //+------------------------------------------------------------------+
   double GetVolatilityMultiplier()
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(m_handle_atr_h1, 0, 0, 50, atr_buffer) <= 0)
         return 1.0;

      // Calculate average ATR
      double sum = 0;
      for(int i = 0; i < 50; i++)
         sum += atr_buffer[i];
      m_atr_average = sum / 50.0;

      double current_atr = atr_buffer[0];
      double atr_ratio = (m_atr_average > 0) ? current_atr / m_atr_average : 1.0;

      // Low volatility: Increase risk slightly (better risk/reward)
      if(atr_ratio < 0.7)
         return m_config.low_vol_risk_mult;

      // High volatility: Decrease risk (larger stops needed)
      if(atr_ratio > 1.3)
         return m_config.high_vol_risk_mult;

      // Normal volatility: Interpolate
      if(atr_ratio < 1.0)
      {
         // Between 0.7 and 1.0
         double t = (atr_ratio - 0.7) / 0.3;
         return m_config.low_vol_risk_mult + t * (1.0 - m_config.low_vol_risk_mult);
      }
      else
      {
         // Between 1.0 and 1.3
         double t = (atr_ratio - 1.0) / 0.3;
         return 1.0 + t * (m_config.high_vol_risk_mult - 1.0);
      }
   }

   //+------------------------------------------------------------------+
   //| Get regime-based multiplier                                       |
   //+------------------------------------------------------------------+
   double GetRegimeMultiplier(ENUM_REGIME_TYPE regime)
   {
      switch(regime)
      {
         case REGIME_TRENDING:
            return 1.1;   // Trending is favorable

         case REGIME_RANGING:
            return 0.95;  // Slightly reduce in ranges

         case REGIME_VOLATILE:
            return 0.8;   // Reduce in high volatility

         case REGIME_CHOPPY:
            return 0.7;   // Significantly reduce in chop

         case REGIME_UNKNOWN:
         default:
            return 0.9;   // Conservative when uncertain
      }
   }

   //+------------------------------------------------------------------+
   //| Update drawdown calculation                                       |
   //+------------------------------------------------------------------+
   void UpdateDrawdown()
   {
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Update peak balance
      if(current_balance > m_peak_balance)
         m_peak_balance = current_balance;

      // Calculate drawdown from peak
      if(m_peak_balance > 0)
         m_current_drawdown = ((m_peak_balance - current_equity) / m_peak_balance) * 100.0;
      else
         m_current_drawdown = 0;
   }

   //+------------------------------------------------------------------+
   //| Get drawdown protection multiplier                                |
   //+------------------------------------------------------------------+
   double GetDrawdownMultiplier()
   {
      if(m_current_drawdown >= m_config.drawdown_threshold_2)
         return m_config.drawdown_risk_mult_2;

      if(m_current_drawdown >= m_config.drawdown_threshold_1)
         return m_config.drawdown_risk_mult_1;

      return 1.0;
   }

   //+------------------------------------------------------------------+
   //| Get quality tier multiplier                                       |
   //+------------------------------------------------------------------+
   double GetQualityMultiplier(ENUM_SETUP_QUALITY quality)
   {
      switch(quality)
      {
         case SETUP_A_PLUS:
            return 1.15;  // Best setups get boost

         case SETUP_A:
            return 1.05;  // Good setups

         case SETUP_B_PLUS:
            return 1.0;   // Standard

         case SETUP_B:
            return 0.9;   // Marginal setups reduced

         default:
            return 0.8;
      }
   }
};
