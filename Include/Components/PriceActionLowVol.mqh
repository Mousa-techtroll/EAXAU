//+------------------------------------------------------------------+
//| PriceActionLowVol.mqh                                             |
//| Low Volatility Pattern Detection for Consolidation Markets       |
//| v2.6 - Relaxed RSI Thresholds (58/42) for Better Detection      |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "2.60"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"

//+------------------------------------------------------------------+
//| Low Volatility Pattern Detector Class                            |
//+------------------------------------------------------------------+
class CPriceActionLowVol
{
private:
   SPriceActionData     m_signal;

   // Bollinger Bands
   int                  m_handle_bb;
   int                  m_bb_period;
   double               m_bb_deviation;

   // RSI
   int                  m_handle_rsi;
   int                  m_rsi_period;

   // ATR
   int                  m_handle_atr;
   int                  m_atr_period;

   // Range detection
   double               m_range_high;
   double               m_range_low;
   int                  m_range_bars_count;
   bool                 m_range_valid;

   // Pattern enable flags
   bool                 m_enable_bb_mean_reversion;
   bool                 m_enable_range_box;
   bool                 m_enable_false_breakout_fade;

   // Risk management
   double               m_scoring_rr_target;
   double               m_min_sl_points;
   double               m_max_atr_lowvol;  // Max ATR for low vol strategies

   // False Breakout Fade tuning parameters
   int                  m_fbf_swing_lookback;    // Swing high/low lookback bars
   double               m_fbf_pullback_pct;      // Min pullback from extreme (e.g., 0.003 = 0.3%)
   double               m_fbf_max_candle_atr;    // Max candle size as ATR multiple
   double               m_fbf_target_pct;        // TP target as % of range (0.5 = middle)
   double               m_fbf_stop_atr;          // SL ATR multiplier beyond breakout
   double               m_fbf_max_sl_points;     // Maximum SL distance in points (caps large stops)
   double               m_fbf_min_rr;            // Minimum R:R ratio to take trade
   bool                 m_fbf_require_trend_align; // Require H4 trend alignment for shorts
   double               m_fbf_min_range_pts;     // Minimum range size in points
   double               m_fbf_rejection_pct;     // Min rejection depth into range (0.10 = 10%)
   double               m_fbf_rsi_long_max;      // Max RSI for longs (oversold filter)
   double               m_fbf_rsi_short_min;     // Min RSI for shorts (overbought filter)
   bool                 m_fbf_require_both_rejection; // Require both price AND pct rejection
   double               m_fbf_max_adx;           // Max ADX for FBF (avoid trending markets)
   double               m_fbf_adx_elevated_thresh; // ADX threshold for elevated R:R
   double               m_fbf_elevated_rr;       // Required R:R when ADX is elevated
   bool                 m_fbf_disable_in_trend;  // Disable FBF when regime is TRENDING

   // H4 trend for FBF filtering (set externally before CheckAllPatterns)
   ENUM_TREND_DIRECTION m_h4_trend;

   // Market regime for FBF filtering (set externally before CheckAllPatterns)
   ENUM_REGIME_TYPE     m_current_regime;

   // ADX indicator handle for FBF trend strength filter
   int                  m_handle_adx;

public:
   //+------------------------------------------------------------------+
   //| Set H4 trend for FBF filtering (call before CheckAllPatterns)    |
   //+------------------------------------------------------------------+
   void SetH4Trend(ENUM_TREND_DIRECTION trend) { m_h4_trend = trend; }
   //+------------------------------------------------------------------+
   //| Set market regime for FBF filtering (call before CheckAllPatterns)|
   //+------------------------------------------------------------------+
   void SetRegime(ENUM_REGIME_TYPE regime) { m_current_regime = regime; }
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CPriceActionLowVol(int bb_period = 20, double bb_dev = 2.0, int rsi_period = 14,
                      int atr_period = 14, double scoring_rr_target = 2.0, double min_sl = 100.0,
                      bool enable_bb_mr = true, bool enable_range = true, bool enable_fade = true,
                      double max_atr = 30.0,
                      int fbf_swing_lookback = 20, double fbf_pullback_pct = 0.003,
                      double fbf_max_candle_atr = 2.0, double fbf_target_pct = 0.5,
                      double fbf_stop_atr = 1.5, double fbf_max_sl_points = 400.0, double fbf_min_rr = 1.2,
                      bool fbf_require_trend_align = true,
                      double fbf_min_range_pts = 300.0, double fbf_rejection_pct = 0.10,
                      double fbf_rsi_long_max = 50.0, double fbf_rsi_short_min = 55.0,
                      bool fbf_require_both_rejection = false,
                      double fbf_max_adx = 30.0,
                      double fbf_adx_elevated_thresh = 20.0, double fbf_elevated_rr = 1.5,
                      bool fbf_disable_in_trend = true)
   {
      m_signal.signal = SIGNAL_NONE;
      m_signal.pattern_type = PATTERN_NONE;

      m_bb_period = bb_period;
      m_bb_deviation = bb_dev;
      m_rsi_period = rsi_period;
      m_atr_period = atr_period;
      m_scoring_rr_target = scoring_rr_target;
      m_min_sl_points = min_sl;
      m_max_atr_lowvol = max_atr;

      m_enable_bb_mean_reversion = enable_bb_mr;
      m_enable_range_box = enable_range;
      m_enable_false_breakout_fade = enable_fade;

      // False Breakout Fade tuning
      m_fbf_swing_lookback = fbf_swing_lookback;
      m_fbf_pullback_pct = fbf_pullback_pct;
      m_fbf_max_candle_atr = fbf_max_candle_atr;
      m_fbf_target_pct = fbf_target_pct;
      m_fbf_stop_atr = fbf_stop_atr;
      m_fbf_max_sl_points = fbf_max_sl_points;
      m_fbf_min_rr = fbf_min_rr;
      m_fbf_require_trend_align = fbf_require_trend_align;
      m_fbf_min_range_pts = fbf_min_range_pts;
      m_fbf_rejection_pct = fbf_rejection_pct;
      m_fbf_rsi_long_max = fbf_rsi_long_max;
      m_fbf_rsi_short_min = fbf_rsi_short_min;
      m_fbf_require_both_rejection = fbf_require_both_rejection;
      m_fbf_max_adx = fbf_max_adx;
      m_fbf_adx_elevated_thresh = fbf_adx_elevated_thresh;
      m_fbf_elevated_rr = fbf_elevated_rr;
      m_fbf_disable_in_trend = fbf_disable_in_trend;

      m_range_valid = false;
      m_range_bars_count = 0;
      m_h4_trend = TREND_NEUTRAL;  // Default neutral until set externally
      m_current_regime = REGIME_UNKNOWN;  // Default until set externally

      // Initialize indicators
      m_handle_bb = iBands(_Symbol, PERIOD_H1, m_bb_period, 0, m_bb_deviation, PRICE_CLOSE);
      m_handle_rsi = iRSI(_Symbol, PERIOD_H1, m_rsi_period, PRICE_CLOSE);
      m_handle_atr = iATR(_Symbol, PERIOD_H1, m_atr_period);
      m_handle_adx = iADX(_Symbol, PERIOD_H1, 14);  // ADX for FBF trend strength filter
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CPriceActionLowVol()
   {
      if(m_handle_bb != INVALID_HANDLE) IndicatorRelease(m_handle_bb);
      if(m_handle_rsi != INVALID_HANDLE) IndicatorRelease(m_handle_rsi);
      if(m_handle_atr != INVALID_HANDLE) IndicatorRelease(m_handle_atr);
   }

   //+------------------------------------------------------------------+
   //| Get current ATR value                                            |
   //+------------------------------------------------------------------+
   double GetATR()
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(m_handle_atr, 0, 0, 1, atr_buffer) <= 0)
         return 0.0;

      return atr_buffer[0];
   }
   //+------------------------------------------------------------------+
   //| GETTER: Allow Main EA to check RSI                               |
   //+------------------------------------------------------------------+
   double GetRSI()
   {
      double rsi_buffer[];
      ArraySetAsSeries(rsi_buffer, true);

      // Use the class's internal RSI handle
      if (CopyBuffer(m_handle_rsi, 0, 0, 1, rsi_buffer) > 0)
         return rsi_buffer[0];

      return 50.0; // Default neutral if error
   }
   //+------------------------------------------------------------------+
   //| GETTER: Get ADX value for FBF trend strength filter              |
   //+------------------------------------------------------------------+
   double GetADX()
   {
      double adx_buffer[];
      ArraySetAsSeries(adx_buffer, true);

      // ADX buffer 0 is the main ADX line
      if (CopyBuffer(m_handle_adx, 0, 0, 1, adx_buffer) > 0)
         return adx_buffer[0];

      return 50.0; // Default high (trending) if error - conservative
   }
   //+------------------------------------------------------------------+
   //| Get Bollinger Band middle (20-period SMA)                        |
   //| PERFORMANCE FIX: Reuses existing BB handle instead of creating new MA|
   //+------------------------------------------------------------------+
   double GetBBMiddle()
   {
      double bb_middle[];
      ArraySetAsSeries(bb_middle, true);

      // Bollinger Bands buffer 0 is the middle line (SMA)
      if(CopyBuffer(m_handle_bb, 0, 0, 1, bb_middle) <= 0)
         return 0.0;

      return bb_middle[0];
   }

   //+------------------------------------------------------------------+
   //| STRATEGY 1: Bollinger Band Mean Reversion                        |
   //| Trade bounces off BB extremes back to mean                       |
   //+------------------------------------------------------------------+
   bool DetectBBMeanReversion()
   {
      if(!m_enable_bb_mean_reversion)
         return false;

      LogPrint(">>> Checking BB Mean Reversion pattern...");

      // Get price data
      double close[], high[], low[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      if(CopyClose(_Symbol, PERIOD_H1, 0, 3, close) <= 0 ||
         CopyHigh(_Symbol, PERIOD_H1, 0, 3, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, 3, low) <= 0)
      {
         LogPrint("    ERROR: Could not copy price data");
         return false;
      }

      // Get Bollinger Bands
      double bb_upper[], bb_middle[], bb_lower[];
      ArraySetAsSeries(bb_upper, true);
      ArraySetAsSeries(bb_middle, true);
      ArraySetAsSeries(bb_lower, true);

      if(CopyBuffer(m_handle_bb, 0, 0, 3, bb_middle) <= 0 ||
         CopyBuffer(m_handle_bb, 1, 0, 3, bb_upper) <= 0 ||
         CopyBuffer(m_handle_bb, 2, 0, 3, bb_lower) <= 0)
      {
         LogPrint("    ERROR: Could not copy BB buffers");
         return false;
      }

      // Get RSI
      double rsi_buffer[];
      ArraySetAsSeries(rsi_buffer, true);

      if(CopyBuffer(m_handle_rsi, 0, 0, 3, rsi_buffer) <= 0)
      {
         LogPrint("    ERROR: Could not copy RSI buffer");
         return false;
      }

      double current_close = close[1];  // Last completed bar
      double current_rsi = rsi_buffer[1];
      double bb_mid = bb_middle[1];
      double bb_up = bb_upper[1];
      double bb_low = bb_lower[1];

      // Check for LOW VOLATILITY (required for mean reversion)
      double atr = GetATR();
      if(atr > m_max_atr_lowvol)
      {
         LogPrint("    ATR too high (", atr, " > ", m_max_atr_lowvol, ") - not low volatility environment");
         return false;
      }

      LogPrint("    ATR=", atr, " BB_Mid=", bb_mid, " BB_Up=", bb_up, " BB_Low=", bb_low);
      LogPrint("    Close=", current_close, " RSI=", current_rsi);

      // BULLISH: Price touched/near lower BB and RSI oversold
      // v2.6: Relaxed RSI from < 35 to < 42 for better detection in low vol
      if(current_close <= bb_low * 1.002 && current_rsi < 42)  // Within 0.2% of lower BB
      {
         // Confirmation: Price closing back inside (mean reversion starting)
         if(close[1] > low[2])  // Current close higher than previous low
         {
            LogPrint("    ✓ BULLISH BB MEAN REVERSION DETECTED!");
            LogPrint("    Price at lower BB, RSI oversold, bouncing up");

            m_signal.signal = SIGNAL_LONG;
            m_signal.pattern_type = PATTERN_BB_MEAN_REVERSION;
            m_signal.pattern_name = "BB Mean Reversion Long";
            m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            m_signal.take_profit = bb_mid;  // Target: middle BB

            // v4.4: Stop uses ATR with minimum SL enforcement
            double atr_sl_distance = atr * 1.5;
            double min_sl_distance = m_min_sl_points * _Point;
            double sl_distance = MathMax(atr_sl_distance, min_sl_distance);
            m_signal.stop_loss = m_signal.entry_price - sl_distance;

            LogPrint("BB Mean Reversion Long SL: ATR=", atr_sl_distance, " Min=", min_sl_distance, " Used=", sl_distance);

            m_signal.signal_time = TimeCurrent();
            return true;
         }
      }

      // BEARISH: Price touched/near upper BB and RSI overbought
      // v2.6: Relaxed RSI from > 65 to > 58 for better detection in low vol
      if(current_close >= bb_up * 0.998 && current_rsi > 58)  // Within 0.2% of upper BB
      {
         // Confirmation: Price closing back inside
         if(close[1] < high[2])  // Current close lower than previous high
         {
            LogPrint("    ✓ BEARISH BB MEAN REVERSION DETECTED!");
            LogPrint("    Price at upper BB, RSI overbought, bouncing down");

            m_signal.signal = SIGNAL_SHORT;
            m_signal.pattern_type = PATTERN_BB_MEAN_REVERSION;
            m_signal.pattern_name = "BB Mean Reversion Short";
            m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            m_signal.take_profit = bb_mid;  // Target: middle BB

            // v4.4: Stop uses ATR with minimum SL enforcement
            double atr_sl_dist = atr * 1.5;
            double min_sl_dist = m_min_sl_points * _Point;
            double sl_dist = MathMax(atr_sl_dist, min_sl_dist);
            m_signal.stop_loss = m_signal.entry_price + sl_dist;

            LogPrint("BB Mean Reversion Short SL: ATR=", atr_sl_dist, " Min=", min_sl_dist, " Used=", sl_dist);

            m_signal.signal_time = TimeCurrent();
            return true;
         }
      }

      LogPrint("    BB Mean Reversion conditions not met");
      return false;
   }

   //+------------------------------------------------------------------+
   //| STRATEGY 2: Range Box Trading                                    |
   //| Identify consolidation ranges, buy low, sell high                |
   //+------------------------------------------------------------------+
   bool DetectRangeBox()
   {
      if(!m_enable_range_box)
         return false;

      LogPrint(">>> Checking Range Box pattern...");

      // First, detect/update range
      UpdateRange();

      if(!m_range_valid)
      {
         LogPrint("    No valid range detected");
         return false;
      }

      // Get price data
      double close[], high[], low[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      if(CopyClose(_Symbol, PERIOD_H1, 0, 3, close) <= 0 ||
         CopyHigh(_Symbol, PERIOD_H1, 0, 3, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, 3, low) <= 0)
      {
         return false;
      }

      // Check for LOW VOLATILITY
      double atr = GetATR();
      if(atr > m_max_atr_lowvol)
      {
         LogPrint("    ATR too high (", atr, " > ", m_max_atr_lowvol, ") - not suitable for range trading");
         return false;
      }

      double current_close = close[1];
      double range_height = m_range_high - m_range_low;
      double range_25_pct = m_range_low + (range_height * 0.25);
      double range_75_pct = m_range_low + (range_height * 0.75);

      LogPrint("    Range: ", m_range_low, " - ", m_range_high, " (", m_range_bars_count, " bars)");
      LogPrint("    Current close: ", current_close, " ATR: ", atr);

      // BULLISH: Price in lower 25% of range
      if(current_close <= range_25_pct)
      {
         // Confirmation: Bullish candle
         if(close[1] > close[2])
         {
            LogPrint("    ✓ BULLISH RANGE BOX TRADE DETECTED!");
            LogPrint("    Price at bottom of range, buying support");

            m_signal.signal = SIGNAL_LONG;
            m_signal.pattern_type = PATTERN_RANGE_BOX;
            m_signal.pattern_name = "Range Box Long";
            m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            // Target: 80% to top of range
            m_signal.take_profit = m_range_low + (range_height * 0.80);

            // v4.4: Stop with minimum SL enforcement
            double range_sl = m_range_low - (range_height * 0.20);
            double min_sl_rb = m_signal.entry_price - m_min_sl_points * _Point;
            m_signal.stop_loss = MathMin(range_sl, min_sl_rb);  // Use wider SL

            m_signal.signal_time = TimeCurrent();
            return true;
         }
      }

      // BEARISH: Price in upper 75% of range
      if(current_close >= range_75_pct)
      {
         // Confirmation: Bearish candle
         if(close[1] < close[2])
         {
            LogPrint("    ✓ BEARISH RANGE BOX TRADE DETECTED!");
            LogPrint("    Price at top of range, selling resistance");

            m_signal.signal = SIGNAL_SHORT;
            m_signal.pattern_type = PATTERN_RANGE_BOX;
            m_signal.pattern_name = "Range Box Short";
            m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            // Target: 80% to bottom of range
            m_signal.take_profit = m_range_high - (range_height * 0.80);

            // v4.4: Stop with minimum SL enforcement
            double range_sl_s = m_range_high + (range_height * 0.20);
            double min_sl_rb_s = m_signal.entry_price + m_min_sl_points * _Point;
            m_signal.stop_loss = MathMax(range_sl_s, min_sl_rb_s);  // Use wider SL

            m_signal.signal_time = TimeCurrent();
            return true;
         }
      }

      LogPrint("    Range Box conditions not met (not at extremes)");
      return false;
   }

   //+------------------------------------------------------------------+
   //| STRATEGY 3: False Breakout Fade                                  |
   //| Fade breakouts in low volatility (likely to fail)                |
   //| ALL parameters are configurable via inputs - NO hardcoded values |
   //+------------------------------------------------------------------+
   bool DetectFalseBreakoutFade()
   {
      if(!m_enable_false_breakout_fade)
         return false;

      LogPrint(">>> Checking False Breakout Fade pattern...");

      // REGIME FILTER: Disable FBF in trending market regime
      if(m_fbf_disable_in_trend && m_current_regime == REGIME_TRENDING)
      {
         LogPrint("    REGIME is TRENDING - FBF disabled in trending markets");
         return false;
      }

      // Check for LOW VOLATILITY (required - breakouts fail in low vol)
      double atr = GetATR();
      if(atr >= m_max_atr_lowvol)
      {
         LogPrint("    ATR too high (", atr, " >= ", m_max_atr_lowvol, ") - breakouts may be valid");
         return false;
      }

      // ADX TREND STRENGTH FILTER (FBF only) - tiered system
      // ADX > max = reject, ADX > elevated = require higher R:R
      double adx = 0;
      double effective_min_rr = m_fbf_min_rr;  // Default R:R requirement

      if(m_fbf_max_adx > 0)
      {
         adx = GetADX();
         if(adx > m_fbf_max_adx)
         {
            LogPrint("    ADX too high (", DoubleToString(adx, 1), " > ", m_fbf_max_adx, ") - market trending, skip FBF");
            return false;
         }
         // Tiered R:R: if ADX is elevated (but below max), require higher R:R
         if(adx > m_fbf_adx_elevated_thresh)
         {
            effective_min_rr = m_fbf_elevated_rr;
            LogPrint("    ADX=", DoubleToString(adx, 1), " (elevated, >", m_fbf_adx_elevated_thresh, ") - requiring R:R >= ", effective_min_rr);
         }
         else
         {
            LogPrint("    ADX=", DoubleToString(adx, 1), " (low) - using standard R:R >= ", effective_min_rr);
         }
      }

      // Calculate required bars for lookback
      int bars_needed = m_fbf_swing_lookback + 5;

      // Get price data
      double close[], high[], low[], open[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(open, true);

      if(CopyClose(_Symbol, PERIOD_H1, 0, bars_needed, close) <= 0 ||
         CopyHigh(_Symbol, PERIOD_H1, 0, bars_needed, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, bars_needed, low) <= 0 ||
         CopyOpen(_Symbol, PERIOD_H1, 0, bars_needed, open) <= 0)
      {
         return false;
      }

      // Get RSI for confirmation
      double rsi = GetRSI();

      // Find recent swing high/low using configurable lookback (from bars 3 to m_fbf_swing_lookback+2)
      double swing_high = high[3];
      double swing_low = low[3];

      for(int i = 4; i <= m_fbf_swing_lookback + 2; i++)
      {
         if(high[i] > swing_high) swing_high = high[i];
         if(low[i] < swing_low) swing_low = low[i];
      }

      double range_size = swing_high - swing_low;

      // Minimum range size filter (configurable)
      if(range_size < m_fbf_min_range_pts * _Point)
      {
         LogPrint("    Range too small (", range_size/_Point, " pts < ", m_fbf_min_range_pts, " pts) - skipping");
         return false;
      }

      LogPrint("    ATR=", atr, " Swing High=", swing_high, " Swing Low=", swing_low, " Range=", range_size/_Point, " pts");
      LogPrint("    RSI=", DoubleToString(rsi, 1), " H4 Trend: ", EnumToString(m_h4_trend));
      LogPrint("    FBF Params: Lookback=", m_fbf_swing_lookback, " Pullback=", m_fbf_pullback_pct,
               " MaxCandleATR=", m_fbf_max_candle_atr, " TargetPct=", m_fbf_target_pct, " StopATR=", m_fbf_stop_atr,
               " MinRR=", m_fbf_min_rr, " TrendAlign=", m_fbf_require_trend_align);
      LogPrint("    MinRangePts=", m_fbf_min_range_pts, " RejectionPct=", m_fbf_rejection_pct,
               " RSILongMax=", m_fbf_rsi_long_max, " RSIShortMin=", m_fbf_rsi_short_min,
               " RequireBoth=", m_fbf_require_both_rejection);

      // Check last 2 bars for breakout+rejection pattern
      double recent_high = MathMax(high[1], high[2]);
      double recent_low = MathMin(low[1], low[2]);
      double current_close = close[1];  // Last completed bar's close

      LogPrint("    Recent 2-bar H/L: ", recent_high, "/", recent_low, " | Close[1]=", current_close);

      // ============ BEARISH FADE (Breakout above swing high) ============
      if(recent_high > swing_high)
      {
         // H4 TREND FILTER FOR SHORTS
         if(m_fbf_require_trend_align && m_h4_trend == TREND_BULLISH)
         {
            LogPrint("    SHORT BLOCKED: H4 trend is BULLISH - Gold bullish bias protection");
         }
         else
         {
            // Check rejection using configurable depth into range
            double min_rejection_level = swing_high - (range_size * m_fbf_rejection_pct);
            bool price_rejected = (current_close < min_rejection_level);

            // Percentage-based pullback from the extreme
            double pullback_threshold = recent_high * (1.0 - m_fbf_pullback_pct);
            bool pct_rejected = (current_close < pullback_threshold);

            LogPrint("    SHORT Check: Price rejected (", m_fbf_rejection_pct*100, "%% into range)? ", price_rejected, " | Pct rejected? ", pct_rejected);

            // Use configurable AND/OR logic
            bool rejection_confirmed = m_fbf_require_both_rejection ? (price_rejected && pct_rejected) : (price_rejected || pct_rejected);

            if(rejection_confirmed)
            {
               // Candle size filter
               double breakout_candle_range = high[1] - low[1];
               if(breakout_candle_range < atr * m_fbf_max_candle_atr)
               {
                  // RSI confirmation for shorts (configurable threshold)
                  if(rsi < m_fbf_rsi_short_min)
                  {
                     LogPrint("    SHORT SKIPPED: RSI not overbought (", DoubleToString(rsi,1), " < ", m_fbf_rsi_short_min, ")");
                  }
                  else
                  {
                     double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                     double atr_sl_fb = recent_high + (atr * m_fbf_stop_atr);
                     double min_sl_fb = entry_price + m_min_sl_points * _Point;
                     double max_sl_fb = entry_price + m_fbf_max_sl_points * _Point;  // Cap SL distance
                     double stop_loss = MathMax(atr_sl_fb, min_sl_fb);
                     stop_loss = MathMin(stop_loss, max_sl_fb);  // Apply cap
                     double take_profit = swing_low + (range_size * (1.0 - m_fbf_target_pct));

                     double risk = stop_loss - entry_price;
                     double reward = entry_price - take_profit;
                     double rr_ratio = (risk > 0) ? (reward / risk) : 0;

                     LogPrint("    SHORT R:R Check: Entry=", entry_price, " SL=", stop_loss, " TP=", take_profit);
                     LogPrint("    Risk=", risk, " Reward=", reward, " R:R=", rr_ratio, " Required=", effective_min_rr);

                     if(rr_ratio < effective_min_rr)
                     {
                        LogPrint("    SHORT REJECTED: R:R ", rr_ratio, " < minimum ", effective_min_rr);
                     }
                     else
                     {
                        LogPrint("    ✓ BEARISH FALSE BREAKOUT FADE DETECTED!");
                        m_signal.signal = SIGNAL_SHORT;
                        m_signal.pattern_type = PATTERN_FALSE_BREAKOUT_FADE;
                        m_signal.pattern_name = "False Breakout Fade Short";
                        m_signal.entry_price = entry_price;
                        m_signal.take_profit = take_profit;
                        m_signal.stop_loss = stop_loss;
                        m_signal.signal_time = TimeCurrent();
                        return true;
                     }
                  }
               }
            }
         }
      }

      // ============ BULLISH FADE (Breakout below swing low) ============
      if(recent_low < swing_low)
      {
         // Check rejection using configurable depth into range
         double min_rejection_level = swing_low + (range_size * m_fbf_rejection_pct);
         bool price_rejected = (current_close > min_rejection_level);

         // Percentage-based pullback from the extreme
         double pullback_threshold_l = recent_low * (1.0 + m_fbf_pullback_pct);
         bool pct_rejected = (current_close > pullback_threshold_l);

         LogPrint("    LONG Check: Price rejected (", m_fbf_rejection_pct*100, "%% into range)? ", price_rejected, " | Pct rejected? ", pct_rejected);

         // Use configurable AND/OR logic
         bool rejection_confirmed = m_fbf_require_both_rejection ? (price_rejected && pct_rejected) : (price_rejected || pct_rejected);

         if(rejection_confirmed)
         {
            // Candle size filter
            double breakout_candle_range = high[1] - low[1];
            if(breakout_candle_range < atr * m_fbf_max_candle_atr)
            {
               // RSI confirmation for longs (configurable threshold)
               if(rsi > m_fbf_rsi_long_max)
               {
                  LogPrint("    LONG SKIPPED: RSI too high (", DoubleToString(rsi,1), " > ", m_fbf_rsi_long_max, ")");
                  return false;
               }

               double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double atr_sl_fbl = recent_low - (atr * m_fbf_stop_atr);
               double min_sl_fbl = entry_price - m_min_sl_points * _Point;
               double max_sl_fbl = entry_price - m_fbf_max_sl_points * _Point;  // Cap SL distance
               double stop_loss = MathMin(atr_sl_fbl, min_sl_fbl);
               stop_loss = MathMax(stop_loss, max_sl_fbl);  // Apply cap (for longs, max = higher price)
               double take_profit = swing_high - (range_size * (1.0 - m_fbf_target_pct));

               double risk = entry_price - stop_loss;
               double reward = take_profit - entry_price;
               double rr_ratio = (risk > 0) ? (reward / risk) : 0;

               LogPrint("    LONG R:R Check: Entry=", entry_price, " SL=", stop_loss, " TP=", take_profit);
               LogPrint("    Risk=", risk, " Reward=", reward, " R:R=", rr_ratio, " Required=", effective_min_rr);

               if(rr_ratio < effective_min_rr)
               {
                  LogPrint("    LONG REJECTED: R:R ", rr_ratio, " < minimum ", effective_min_rr);
                  return false;
               }

               LogPrint("    ✓ BULLISH FALSE BREAKOUT FADE DETECTED! (RSI: ", DoubleToString(rsi,1), ")");
               m_signal.signal = SIGNAL_LONG;
               m_signal.pattern_type = PATTERN_FALSE_BREAKOUT_FADE;
               m_signal.pattern_name = "False Breakout Fade Long";
               m_signal.entry_price = entry_price;
               m_signal.take_profit = take_profit;
               m_signal.stop_loss = stop_loss;
               m_signal.signal_time = TimeCurrent();
               return true;
            }
         }
      }

      LogPrint("    False Breakout Fade conditions not met");
      return false;
   }

   //+------------------------------------------------------------------+
   //| Update range detection                                           |
   //+------------------------------------------------------------------+
   void UpdateRange()
   {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      int lookback = 50;  // Look back 50 bars

      if(CopyHigh(_Symbol, PERIOD_H1, 0, lookback, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, lookback, low) <= 0)
      {
         m_range_valid = false;
         return;
      }

      // Simple range detection: Find highest high and lowest low in recent bars
      // FIX: Start at index 1 to avoid lookahead bias from the current (forming) bar
      double recent_high = high[1];
      double recent_low = low[1];

      for(int i = 2; i < 30; i++)  // Check last 30 bars (index 1 to 29)
      {
         if(high[i] > recent_high) recent_high = high[i];
         if(low[i] < recent_low) recent_low = low[i];
      }

      double range_size = recent_high - recent_low;

      // Validate range
      // FIX: Adjusted for Gold - Min: 200 points ($2), Max: 5000 points ($50)
      // Previous values (50-300) were too small and effectively disabled range trading on Gold
      if(range_size >= 200 * _Point && range_size <= 5000 * _Point)
      {
         // Check if price has been consolidating (touching both sides)
         int top_touches = 0;
         int bottom_touches = 0;

         for(int i = 1; i < 30; i++) // Check from index 1
         {
            if(high[i] >= recent_high * 0.995) top_touches++;  // Within 0.5% of high
            if(low[i] <= recent_low * 1.005) bottom_touches++;  // Within 0.5% of low
         }

         // Valid range if touched both sides at least twice
         if(top_touches >= 2 && bottom_touches >= 2)
         {
            m_range_high = recent_high;
            m_range_low = recent_low;
            m_range_bars_count = 30;
            m_range_valid = true;
            return;
         }
      }

      m_range_valid = false;
   }

   //+------------------------------------------------------------------+
   //| Get signal data                                                   |
   //+------------------------------------------------------------------+
   SPriceActionData GetSignal() { return m_signal; }

   //+------------------------------------------------------------------+
   //| Check all low volatility patterns                                |
   //+------------------------------------------------------------------+
   bool CheckAllPatterns()
   {
      // Priority order (most reliable first)
      if(DetectBBMeanReversion()) return true;
      if(DetectRangeBox()) return true;
      if(DetectFalseBreakoutFade()) return true;

      return false;
   }
};
