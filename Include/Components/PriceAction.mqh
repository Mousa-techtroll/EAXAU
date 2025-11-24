//+------------------------------------------------------------------+
//| PriceAction.mqh                                                   |
//| Component 4: Price Action Pattern Detection                       |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"

//+------------------------------------------------------------------+
//| Price Action Detector Class                                       |
//+------------------------------------------------------------------+
class CPriceAction
{
private:
   // Price action signal data
   SPriceActionData     m_signal;

   // RSI for ranging
   int                  m_handle_rsi;
   int                  m_rsi_period;

   // PERFORMANCE FIX: Cached handles for MA Cross pattern
   int                  m_handle_ma_fast;
   int                  m_handle_ma_slow;
   int                  m_handle_atr_sl;

   // ATR configuration for stop loss
   int                  m_atr_period_sl;
   double               m_atr_multiplier_sl;
   double               m_min_sl_points;
   double               m_scoring_rr_target;

   // Pattern enable/disable flags
   bool                 m_enable_bullish_engulfing;
   bool                 m_enable_bullish_pin_bar;
   bool                 m_enable_bullish_liquidity_sweep;
   bool                 m_enable_bullish_ma_anomaly;
   bool                 m_enable_bearish_engulfing;
   bool                 m_enable_bearish_pin_bar;
   bool                 m_enable_bearish_liquidity_sweep;
   bool                 m_enable_bearish_ma_anomaly;
   bool                 m_enable_support_bounce;

   // Pattern score adjustments
   int                  m_score_bullish_engulfing;
   int                  m_score_bullish_pin_bar;
   int                  m_score_bullish_liquidity_sweep;
   int                  m_score_bullish_ma_anomaly;
   int                  m_score_bearish_engulfing;
   int                  m_score_bearish_pin_bar;
   int                  m_score_bearish_liquidity_sweep;
   int                  m_score_bearish_ma_anomaly;
   int                  m_score_support_bounce;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CPriceAction(int atr_period = 14, double atr_mult = 1.5, double min_sl = 100.0, double scoring_rr_target = 2.0,
                bool enable_bull_eng = true, bool enable_bull_pin = true, bool enable_bull_liq = true, bool enable_bull_ma = true,
                bool enable_bear_eng = true, bool enable_bear_pin = true, bool enable_bear_liq = true, bool enable_bear_ma = true,
                bool enable_support = true,
                int score_bull_eng = 0, int score_bull_pin = 0, int score_bull_liq = 0, int score_bull_ma = 0,
                int score_bear_eng = 0, int score_bear_pin = 0, int score_bear_liq = 0, int score_bear_ma = 0,
                int score_support = 0,
                int rsi_period = 14)
   {
      m_signal.signal = SIGNAL_NONE;
      m_signal.pattern_type = PATTERN_NONE;
      m_atr_period_sl = atr_period;
      m_atr_multiplier_sl = atr_mult;
      m_min_sl_points = min_sl;
      m_scoring_rr_target = scoring_rr_target;
      m_rsi_period = rsi_period;

      // Pattern enable flags
      m_enable_bullish_engulfing = enable_bull_eng;
      m_enable_bullish_pin_bar = enable_bull_pin;
      m_enable_bullish_liquidity_sweep = enable_bull_liq;
      m_enable_bullish_ma_anomaly = enable_bull_ma;
      m_enable_bearish_engulfing = enable_bear_eng;
      m_enable_bearish_pin_bar = enable_bear_pin;
      m_enable_bearish_liquidity_sweep = enable_bear_liq;
      m_enable_bearish_ma_anomaly = enable_bear_ma;
      m_enable_support_bounce = enable_support;

      // Pattern score adjustments
      m_score_bullish_engulfing = score_bull_eng;
      m_score_bullish_pin_bar = score_bull_pin;
      m_score_bullish_liquidity_sweep = score_bull_liq;
      m_score_bullish_ma_anomaly = score_bull_ma;
      m_score_bearish_engulfing = score_bear_eng;
      m_score_bearish_pin_bar = score_bear_pin;
      m_score_bearish_liquidity_sweep = score_bear_liq;
      m_score_bearish_ma_anomaly = score_bear_ma;
      m_score_support_bounce = score_support;
   }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CPriceAction()
   {
      IndicatorRelease(m_handle_rsi);
      IndicatorRelease(m_handle_ma_fast);
      IndicatorRelease(m_handle_ma_slow);
      IndicatorRelease(m_handle_atr_sl);
   }
   
   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init()
   {
      m_handle_rsi = iRSI(_Symbol, PERIOD_H1, m_rsi_period, PRICE_CLOSE);

      if(m_handle_rsi == INVALID_HANDLE)
      {
         LogPrint("ERROR: Failed to create RSI in PriceAction");
         return false;
      }

      // PERFORMANCE FIX: Create cached handles for MA Cross pattern
      m_handle_ma_fast = iMA(_Symbol, PERIOD_H1, 10, 0, MODE_SMA, PRICE_CLOSE);
      m_handle_ma_slow = iMA(_Symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);
      m_handle_atr_sl = iATR(_Symbol, PERIOD_H1, m_atr_period_sl);

      if(m_handle_ma_fast == INVALID_HANDLE || m_handle_ma_slow == INVALID_HANDLE || m_handle_atr_sl == INVALID_HANDLE)
      {
         LogPrint("ERROR: Failed to create MA/ATR handles in PriceAction");
         return false;
      }

      LogPrint("PriceAction initialized successfully");
      return true;
   }
   
   //+------------------------------------------------------------------+
//| Detect simple MA cross (add BEFORE the Update() method)          |
//+------------------------------------------------------------------+
bool DetectMACross(ENUM_TREND_DIRECTION trend_bias)
{
   LogPrint(">>> DEBUG: DetectMACross() called | Trend Bias: ", EnumToString(trend_bias));

   double ma_fast[], ma_slow[], close[];
   ArraySetAsSeries(ma_fast, true);
   ArraySetAsSeries(ma_slow, true);
   ArraySetAsSeries(close, true);

   // PERFORMANCE FIX: Use cached MA handles (not creating/destroying every call)
   // Get MA data
   if(CopyBuffer(m_handle_ma_fast, 0, 0, 3, ma_fast) <= 0 ||
      CopyBuffer(m_handle_ma_slow, 0, 0, 3, ma_slow) <= 0 ||
      CopyClose(_Symbol, PERIOD_H1, 0, 1, close) <= 0)
   {
      LogPrint("    FAILED: Could not copy MA data");
      return false;
   }

   // Bullish cross
   if(trend_bias == TREND_BULLISH)
   {
      LogPrint("    Checking BULLISH cross | MA[1]: ", ma_fast[1], "/", ma_slow[1], " | MA[0]: ", ma_fast[0], "/", ma_slow[0]);

      // Fast MA crossed above slow MA on the last closed bar
      if(ma_fast[2] <= ma_slow[2] && ma_fast[1] > ma_slow[1])
      {
         LogPrint("    ✓ BULLISH CROSS DETECTED!");

         m_signal.signal = SIGNAL_LONG;
         m_signal.pattern_type = PATTERN_MA_CROSS_ANOMALY;
         m_signal.pattern_name = "Bullish MA Cross";
         m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         // ATR-based stop loss - TIGHTER for MA Cross (2x ATR instead of 3x)
         // MA Cross patterns are prone to slippage, so tighter SL improves R:R
         // PERFORMANCE FIX: Use cached ATR handle
         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(m_handle_atr_sl, 0, 0, 1, atr) > 0)
         {
            // Use 0.67x multiplier for MA Cross (2x ATR if base is 3x)
            double ma_cross_multiplier = m_atr_multiplier_sl * 0.67;
            double stop_buffer = MathMax(atr[0] * ma_cross_multiplier, m_min_sl_points * _Point);
            m_signal.stop_loss = m_signal.entry_price - stop_buffer;  // Use entry price, not slow MA
         }
         else
         {
            m_signal.stop_loss = m_signal.entry_price - m_min_sl_points * _Point;  // Fallback
         }

         m_signal.take_profit = m_signal.entry_price +
                               (m_signal.entry_price - m_signal.stop_loss) * m_scoring_rr_target;
         m_signal.signal_time = TimeCurrent();

         LogPrint("PATTERN DETECTED: Bullish MA Cross | Entry: ", m_signal.entry_price, " | SL: ", m_signal.stop_loss, " (tighter 2x ATR)");

         // No need to release - using cached handles
         return true;
      }
      else
      {
         LogPrint("    No bullish cross (MA[1]: fast ", (ma_fast[1] <= ma_slow[1] ? "below" : "above"), " slow | MA[0]: fast ", (ma_fast[0] > ma_slow[0] ? "above" : "below"), " slow)");
      }
   }

   // Bearish cross
   if(trend_bias == TREND_BEARISH)
   {
      LogPrint("    Checking BEARISH cross | MA[1]: ", ma_fast[1], "/", ma_slow[1], " | MA[0]: ", ma_fast[0], "/", ma_slow[0]);

      // Fast MA crossed below slow MA on the last closed bar
      if(ma_fast[2] >= ma_slow[2] && ma_fast[1] < ma_slow[1])
      {
         LogPrint("    ✓ BEARISH CROSS DETECTED!");

         m_signal.signal = SIGNAL_SHORT;
         m_signal.pattern_type = PATTERN_MA_CROSS_ANOMALY;
         m_signal.pattern_name = "Bearish MA Cross";
         m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         // ATR-based stop loss - TIGHTER for MA Cross (2x ATR instead of 3x)
         // MA Cross patterns are prone to slippage, so tighter SL improves R:R
         // PERFORMANCE FIX: Use cached ATR handle
         double atr_short[];
         ArraySetAsSeries(atr_short, true);
         if(CopyBuffer(m_handle_atr_sl, 0, 0, 1, atr_short) > 0)
         {
            // Use 0.67x multiplier for MA Cross (2x ATR if base is 3x)
            double ma_cross_multiplier = m_atr_multiplier_sl * 0.67;
            double stop_buffer = MathMax(atr_short[0] * ma_cross_multiplier, m_min_sl_points * _Point);
            m_signal.stop_loss = m_signal.entry_price + stop_buffer;  // Use entry price, not slow MA
         }
         else
         {
            m_signal.stop_loss = m_signal.entry_price + m_min_sl_points * _Point;  // Fallback
         }

         m_signal.take_profit = m_signal.entry_price -
                               (m_signal.stop_loss - m_signal.entry_price) * m_scoring_rr_target;
         m_signal.signal_time = TimeCurrent();

         LogPrint("PATTERN DETECTED: Bearish MA Cross | Entry: ", m_signal.entry_price, " | SL: ", m_signal.stop_loss, " (tighter 2x ATR)");

         // No need to release - using cached handles
         return true;
      }
      else
      {
         LogPrint("    No bearish cross (MA[1]: fast ", (ma_fast[1] >= ma_slow[1] ? "above" : "below"), " slow | MA[0]: fast ", (ma_fast[0] < ma_slow[0] ? "below" : "above"), " slow)");
      }
   }

   LogPrint("    MA Cross NOT detected (wrong trend bias or no cross)");
   // No need to release - using cached handles
   return false;
}

//+------------------------------------------------------------------+
//| Update - detect patterns using SCORE-BASED SYSTEM                |
//+------------------------------------------------------------------+
void Update(ENUM_TREND_DIRECTION trend_bias, ENUM_REGIME_TYPE regime)
{
   // Reset signal
   m_signal.signal = SIGNAL_NONE;
   m_signal.pattern_type = PATTERN_NONE;
   m_signal.pattern_name = "";

   // SCORE-BASED SYSTEM: Evaluate ALL patterns and select the best one
   SPriceActionData candidates[5];
   double scores[5];

   // Initialize all scores to 0
   for(int i = 0; i < 5; i++) {
      scores[i] = 0;
      candidates[i].signal = SIGNAL_NONE;
   }

   SPriceActionData saved_signal = m_signal; // Save state

   // -----------------------------------------------------------------------
   // DETECT PATTERNS (Both Bullish and Bearish)
   // -----------------------------------------------------------------------

   // Pattern 0: MA Cross
   if(m_enable_bullish_ma_anomaly && DetectMACross(TREND_BULLISH)) {
      candidates[0] = m_signal;
      scores[0] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[0] += m_score_bullish_ma_anomaly;
   } 
   else if(m_enable_bearish_ma_anomaly && DetectMACross(TREND_BEARISH)) {
      candidates[0] = m_signal;
      scores[0] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[0] += m_score_bearish_ma_anomaly;
   }
   m_signal = saved_signal;

   // Pattern 1: Liquidity Sweep
   if(m_enable_bullish_liquidity_sweep && DetectLiquiditySweep(TREND_BULLISH)) {
      candidates[1] = m_signal;
      scores[1] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[1] += m_score_bullish_liquidity_sweep;
   }
   else if(m_enable_bearish_liquidity_sweep && DetectLiquiditySweep(TREND_BEARISH)) {
      candidates[1] = m_signal;
      scores[1] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[1] += m_score_bearish_liquidity_sweep;
   }
   m_signal = saved_signal;

   // Pattern 2: Engulfing
   if(m_enable_bullish_engulfing && DetectEngulfing(TREND_BULLISH)) {
      candidates[2] = m_signal;
      scores[2] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[2] += m_score_bullish_engulfing;
   }
   else if(m_enable_bearish_engulfing && DetectEngulfing(TREND_BEARISH)) {
      candidates[2] = m_signal;
      scores[2] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[2] += m_score_bearish_engulfing;
   }
   m_signal = saved_signal;

   // Pattern 3: Pin Bar
   if(m_enable_bullish_pin_bar && DetectPinBar(TREND_BULLISH)) {
      candidates[3] = m_signal;
      scores[3] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[3] += m_score_bullish_pin_bar;
   }
   else if(m_enable_bearish_pin_bar && DetectPinBar(TREND_BEARISH)) {
      candidates[3] = m_signal;
      scores[3] = CalculatePatternScore(m_signal, regime, trend_bias);
      scores[3] += m_score_bearish_pin_bar;
   }
   m_signal = saved_signal;

   // Pattern 4: S/R Bounce
   if(m_enable_support_bounce && (regime != REGIME_TRENDING))
   {
      if(DetectSRBounce()) {
         candidates[4] = m_signal;
         scores[4] = CalculatePatternScore(m_signal, regime, trend_bias);
         scores[4] += m_score_support_bounce;
      }
   }

   // Find highest scoring pattern
   int best_index = -1;
   double best_score = -9999; 
   int detected_count = 0;

   // REMOVED THE UNUSED ARRAY 'pattern_names' HERE

   for(int i = 0; i < 5; i++)
   {
      if(candidates[i].signal != SIGNAL_NONE)
      {
         detected_count++;
         
         // Use the ACTUAL pattern name stored in the candidate
         LogPrint("  [", i, "] DETECTED: ", candidates[i].pattern_name, 
               " | Score: ", DoubleToString(scores[i], 1), 
               " | Trend Bias: ", EnumToString(trend_bias));

         if(scores[i] > best_score)
         {
            best_score = scores[i];
            best_index = i;
         }
      }
   }

   // Set the best pattern as the signal
   if(best_index >= 0)
   {
      m_signal = candidates[best_index];
      m_signal.signal_time = TimeCurrent();
      LogPrint(">>> WINNER: ", m_signal.pattern_name, " (Score: ", DoubleToString(best_score, 1), ")");
   }
   else
   {
      m_signal.signal = SIGNAL_NONE;
   }
}
   
   //+------------------------------------------------------------------+
   //| Get signal                                                        |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE GetSignal() const { return m_signal.signal; }
   string GetPatternName() const { return m_signal.pattern_name; }
   double GetEntryPrice() const { return m_signal.entry_price; }
   double GetStopLoss() const { return m_signal.stop_loss; }
   double GetTakeProfit() const { return m_signal.take_profit; }
   ENUM_PATTERN_TYPE GetPatternType() const { return m_signal.pattern_type; }

private:
   //+------------------------------------------------------------------+
   //| Calculate pattern score based on regime and conditions           |
   //+------------------------------------------------------------------+
   double CalculatePatternScore(SPriceActionData &pattern, ENUM_REGIME_TYPE regime, ENUM_TREND_DIRECTION trend_bias)
   {
      double base_score = 50.0; // Start with base score
      string pattern_name = pattern.pattern_name;

      // REGIME-BASED SCORING (Option 4 logic baked in)

      // === TRENDING REGIME === (Favor directional breakouts)
      if(regime == REGIME_TRENDING)
      {
         if(pattern_name == "Bullish Liquidity Sweep" || pattern_name == "Bearish Liquidity Sweep")
            base_score += 30.0; // Best for trending markets
         else if(pattern_name == "Bullish Pin Bar" || pattern_name == "Bearish Pin Bar")
            base_score += 25.0; // Great for trend continuations
         else if(pattern_name == "Bullish MA Cross" || pattern_name == "Bearish MA Cross")
            base_score += 15.0; // Decent in trending markets
         else if(pattern_name == "Bullish Engulfing" || pattern_name == "Bearish Engulfing")
            base_score += 10.0; // OK but not ideal
         else if(pattern_name == "Support Bounce" || pattern_name == "Resistance Bounce")
            base_score -= 20.0; // Poor in trending markets (counter-trend)
      }

      // === RANGING REGIME === (Favor mean reversion)
      else if(regime == REGIME_RANGING)
      {
         if(pattern_name == "Support Bounce" || pattern_name == "Resistance Bounce")
            base_score += 35.0; // Perfect for ranging markets
         else if(pattern_name == "Bullish Engulfing" || pattern_name == "Bearish Engulfing")
            base_score += 25.0; // Excellent reversal signals
         else if(pattern_name == "Bullish Pin Bar" || pattern_name == "Bearish Pin Bar")
            base_score += 15.0; // Good rejection candles
         else if(pattern_name == "Bullish MA Cross" || pattern_name == "Bearish MA Cross")
            base_score -= 10.0; // Whipsaw risk in ranging
         else if(pattern_name == "Bullish Liquidity Sweep" || pattern_name == "Bearish Liquidity Sweep")
            base_score += 5.0; // Can work at range extremes
      }

      // === CHOPPY REGIME === (Be very selective)
      else if(regime == REGIME_CHOPPY)
      {
         base_score -= 20.0; // Reduce all signals in choppy markets

         if(pattern_name == "Bullish Liquidity Sweep" || pattern_name == "Bearish Liquidity Sweep")
            base_score += 20.0; // Only strong breakouts work
         else if(pattern_name == "Support Bounce" || pattern_name == "Resistance Bounce")
            base_score += 10.0; // Extreme S/R only
      }

      // === VOLATILE REGIME === (Favor strong patterns with clear structure)
      else if(regime == REGIME_VOLATILE)
      {
         if(pattern_name == "Bullish Pin Bar" || pattern_name == "Bearish Pin Bar")
            base_score += 30.0; // Pin bars excel in volatile markets
         else if(pattern_name == "Bullish Engulfing" || pattern_name == "Bearish Engulfing")
            base_score += 25.0; // Strong reversals
         else if(pattern_name == "Bullish Liquidity Sweep" || pattern_name == "Bearish Liquidity Sweep")
            base_score += 20.0; // Good for momentum
         else if(pattern_name == "Bullish MA Cross" || pattern_name == "Bearish MA Cross")
            base_score -= 5.0; // Can lag in fast markets
      }

      // TREND ALIGNMENT BONUS (critical for success)
      bool signal_aligned_with_trend = false;

      if(trend_bias == TREND_BULLISH && pattern.signal == SIGNAL_LONG)
         signal_aligned_with_trend = true;
      else if(trend_bias == TREND_BEARISH && pattern.signal == SIGNAL_SHORT)
         signal_aligned_with_trend = true;

      if(signal_aligned_with_trend)
         base_score += 20.0; // Big bonus for trend alignment
      else
         base_score -= 5.0; // Penalty for counter-trend

      // RISK/REWARD QUALITY BONUS
      double rr_ratio = 0;
      double sl_distance = MathAbs(pattern.entry_price - pattern.stop_loss);

      if(sl_distance > 0)
      {
         double tp_distance = MathAbs(pattern.take_profit - pattern.entry_price);
         rr_ratio = tp_distance / sl_distance;

         if(rr_ratio >= 2.5)
            base_score += 15.0; // Excellent R:R
         else if(rr_ratio >= 2.0)
            base_score += 10.0; // Good R:R
         else if(rr_ratio >= 1.5)
            base_score += 5.0;  // Acceptable R:R
         else
            base_score -= 10.0; // Poor R:R
      }

      // Ensure score doesn't go below 0
      if(base_score < 0)
         base_score = 0;

      return base_score;
   }

   //+------------------------------------------------------------------+
   //| Detect liquidity sweep pattern                                   |
   //+------------------------------------------------------------------+
   bool DetectLiquiditySweep(ENUM_TREND_DIRECTION trend_bias)
   {
      LogPrint(">>> DEBUG: DetectLiquiditySweep() called | Trend Bias: ", EnumToString(trend_bias));

      double high[], low[], close[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);

      if(CopyHigh(_Symbol, PERIOD_H1, 0, 25, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, 25, low) <= 0 ||
         CopyClose(_Symbol, PERIOD_H1, 0, 5, close) <= 0)
      {
         LogPrint("    FAILED: Could not copy price data");
         return false;
      }

      // FIX v2.0: Calculate swing from OLDER bars, check sweep in RECENT bars
      // For BULLISH sweep
      if(trend_bias == TREND_BULLISH)
      {
         // Find swing low from OLDER bars (bars 4-20, excluding recent 3 bars)
         double swing_low = low[4];
         for(int i = 5; i < 21; i++)
            swing_low = MathMin(swing_low, low[i]);

         LogPrint("    Checking BULLISH sweep | Swing Low (bars 4-20): ", swing_low);

         // Check RECENT 3 bars (1-3) for sweep
         bool sweep_found = false;
         for(int i = 1; i <= 3; i++)
         {
            // Did price sweep below older swing low?
            if(low[i] < swing_low)
            {
               LogPrint("    Bar[", i, "] swept below swing low (", low[i], " < ", swing_low, ")");

               // Did it close back above?
               if(close[i] > swing_low)
               {
                  LogPrint("    Bar[", i, "] closed back above (", close[i], " > ", swing_low, ")");

                  // Confirm with the last closed M15 candle to avoid lookahead bias
                  double m15_close[];
                  ArraySetAsSeries(m15_close, true);
                  if(CopyClose(_Symbol, PERIOD_M15, 0, 2, m15_close) > 1)
                  {
                     // Check last closed M15 bar
                     if(m15_close[1] > swing_low)
                     {
                        LogPrint("    ✓ BULLISH LIQUIDITY SWEEP CONFIRMED! M15 price closed above swing low");

                        // BULLISH SWEEP CONFIRMED
                        m_signal.signal = SIGNAL_LONG;
                        m_signal.pattern_type = PATTERN_LIQUIDITY_SWEEP;
                        m_signal.pattern_name = "Bullish Liquidity Sweep";
                        m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

                        // v4.4: Enforce minimum SL distance
                        // FIX: Increased buffer from 10 to 50 points ($0.50) for Gold
                        double pattern_sl_bull = low[i] - 50 * _Point;
                        double min_sl_bull = m_signal.entry_price - m_min_sl_points * _Point;
                        m_signal.stop_loss = MathMin(pattern_sl_bull, min_sl_bull);  // Use wider SL

                        m_signal.take_profit = m_signal.entry_price +
                                              (m_signal.entry_price - m_signal.stop_loss) * m_scoring_rr_target;
                        m_signal.signal_time = TimeCurrent();

                        LogPrint("Bullish Liquidity Sweep SL: Pattern=", pattern_sl_bull, " Min=", min_sl_bull, " Used=", m_signal.stop_loss);
                        return true;
                     }
                     else
                     {
                        LogPrint("    M15 closed below swing low (", m15_close[1], " <= ", swing_low, ") - no confirmation");
                     }
                  }
               }
               else
               {
                  LogPrint("    Bar[", i, "] did NOT close above swing low (", close[i], " <= ", swing_low, ")");
               }
               sweep_found = true;
            }
         }

         if(!sweep_found)
            LogPrint("    No swing low sweep detected in recent 3 bars");
      }
      
      // For BEARISH sweep
      if(trend_bias == TREND_BEARISH)
      {
         // Find swing high from OLDER bars (bars 4-20, excluding recent 3 bars)
         double swing_high = high[4];
         for(int i = 5; i < 21; i++)
            swing_high = MathMax(swing_high, high[i]);

         LogPrint("    Checking BEARISH sweep | Swing High (bars 4-20): ", swing_high);

         // Check RECENT 3 bars (1-3) for sweep
         bool sweep_found = false;
         for(int i = 1; i <= 3; i++)
         {
            if(high[i] > swing_high)
            {
               LogPrint("    Bar[", i, "] swept above swing high (", high[i], " > ", swing_high, ")");

               if(close[i] < swing_high)
               {
                  LogPrint("    Bar[", i, "] closed back below (", close[i], " < ", swing_high, ")");

                  // Confirm with the last closed M15 candle to avoid lookahead bias
                  double m15_close[];
                  ArraySetAsSeries(m15_close, true);
                  if(CopyClose(_Symbol, PERIOD_M15, 0, 2, m15_close) > 1)
                  {
                     // Check last closed M15 bar
                     if(m15_close[1] < swing_high)
                     {
                        LogPrint("    ✓ BEARISH LIQUIDITY SWEEP CONFIRMED! M15 price closed below swing high");

                        // BEARISH SWEEP CONFIRMED
                        m_signal.signal = SIGNAL_SHORT;
                        m_signal.pattern_type = PATTERN_LIQUIDITY_SWEEP;
                        m_signal.pattern_name = "Bearish Liquidity Sweep";
                        m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

                        // v4.4: Enforce minimum SL distance
                        // FIX: Increased buffer from 10 to 50 points ($0.50) for Gold
                        double pattern_sl_bear = high[i] + 50 * _Point;
                        double min_sl_bear = m_signal.entry_price + m_min_sl_points * _Point;
                        m_signal.stop_loss = MathMax(pattern_sl_bear, min_sl_bear);  // Use wider SL

                        m_signal.take_profit = m_signal.entry_price -
                                              (m_signal.stop_loss - m_signal.entry_price) * m_scoring_rr_target;
                        m_signal.signal_time = TimeCurrent();

                        LogPrint("Bearish Liquidity Sweep SL: Pattern=", pattern_sl_bear, " Min=", min_sl_bear, " Used=", m_signal.stop_loss);
                        return true;
                     }
                     else
                     {
                        LogPrint("    M15 closed above swing high (", m15_close[1], " >= ", swing_high, ") - no confirmation");
                     }
                  }
               }
               else
               {
                  LogPrint("    Bar[", i, "] did NOT close below swing high (", close[i], " >= ", swing_high, ")");
               }
               sweep_found = true;
            }
         }

         if(!sweep_found)
            LogPrint("    No swing high sweep detected in recent 3 bars");
      }

      LogPrint("    Liquidity Sweep NOT detected");
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Detect engulfing pattern                                         |
   //+------------------------------------------------------------------+
   bool DetectEngulfing(ENUM_TREND_DIRECTION trend_bias)
   {
      LogPrint(">>> DEBUG: DetectEngulfing() called | Trend Bias: ", EnumToString(trend_bias));

      double open[], high[], low[], close[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);

      if(CopyOpen(_Symbol, PERIOD_H1, 0, 4, open) <= 0 ||
         CopyHigh(_Symbol, PERIOD_H1, 0, 4, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, 4, low) <= 0 ||
         CopyClose(_Symbol, PERIOD_H1, 0, 4, close) <= 0)
      {
         LogPrint("    FAILED: Could not copy price data");
         return false;
      }

      // FIX v2.0: Check COMPLETED candles (bar[2] and bar[1]) instead of bar[1] and forming bar[0]
      // Bullish engulfing
      if(trend_bias == TREND_BULLISH)
      {
         bool prev_bearish = (close[2] < open[2]);
         bool curr_bullish = (close[1] > open[1]);

         LogPrint("    Checking BULLISH engulfing | Prev bearish (bar[2]): ", prev_bearish, " | Curr bullish (bar[1]): ", curr_bullish);

         if(prev_bearish && curr_bullish)
         {
            double prev_body = MathAbs(close[2] - open[2]);
            double curr_body = MathAbs(close[1] - open[1]);

            LogPrint("    Body sizes - Prev: ", prev_body, " | Curr: ", curr_body, " | Curr >= 80% Prev: ", (curr_body >= prev_body * 0.8));

            // Check engulfing - FIX: Tightened from 50% to 80% to reduce false signals
            if(open[1] <= close[2] && close[1] >= open[2] && curr_body >= prev_body * 0.8)
            {
               LogPrint("    ✓ BULLISH ENGULFING DETECTED!");

               m_signal.signal = SIGNAL_LONG;
               m_signal.pattern_type = PATTERN_ENGULFING;
               m_signal.pattern_name = "Bullish Engulfing";
               m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

               // v4.4: Enforce minimum SL distance
               // FIX: Increased buffer from 10 to 50 points ($0.50) for Gold
               double pattern_sl_eng = low[1] - 50 * _Point;
               double min_sl_eng = m_signal.entry_price - m_min_sl_points * _Point;
               m_signal.stop_loss = MathMin(pattern_sl_eng, min_sl_eng);  // Use wider SL

               m_signal.take_profit = m_signal.entry_price +
                                     (m_signal.entry_price - m_signal.stop_loss) * m_scoring_rr_target;
               m_signal.signal_time = TimeCurrent();

               LogPrint("Bullish Engulfing SL: Pattern=", pattern_sl_eng, " Min=", min_sl_eng, " Used=", m_signal.stop_loss);
               return true;
            }
            else
            {
               LogPrint("    Engulfing conditions not met (open[1]=", open[1], " close[2]=", close[2], " close[1]=", close[1], " open[2]=", open[2], ")");
            }
         }
      }

      // Bearish engulfing
      if(trend_bias == TREND_BEARISH)
      {
         bool prev_bullish = (close[2] > open[2]);
         bool curr_bearish = (close[1] < open[1]);

         LogPrint("    Checking BEARISH engulfing | Prev bullish (bar[2]): ", prev_bullish, " | Curr bearish (bar[1]): ", curr_bearish);

         if(prev_bullish && curr_bearish)
         {
            double prev_body = MathAbs(close[2] - open[2]);
            double curr_body = MathAbs(close[1] - open[1]);

            LogPrint("    Body sizes - Prev: ", prev_body, " | Curr: ", curr_body, " | Curr >= 80% Prev: ", (curr_body >= prev_body * 0.8));

            // Check engulfing - FIX: Tightened from 50% to 80% to reduce false signals
            if(open[1] >= close[2] && close[1] <= open[2] && curr_body >= prev_body * 0.8)
            {
               LogPrint("    ✓ BEARISH ENGULFING DETECTED!");

               m_signal.signal = SIGNAL_SHORT;
               m_signal.pattern_type = PATTERN_ENGULFING;
               m_signal.pattern_name = "Bearish Engulfing";
               m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

               // v4.4: Enforce minimum SL distance
               // FIX: Increased buffer from 10 to 50 points ($0.50) for Gold
               double pattern_sl_eng_b = high[1] + 50 * _Point;
               double min_sl_eng_b = m_signal.entry_price + m_min_sl_points * _Point;
               m_signal.stop_loss = MathMax(pattern_sl_eng_b, min_sl_eng_b);  // Use wider SL

               m_signal.take_profit = m_signal.entry_price -
                                     (m_signal.stop_loss - m_signal.entry_price) * m_scoring_rr_target;
               m_signal.signal_time = TimeCurrent();

               LogPrint("Bearish Engulfing SL: Pattern=", pattern_sl_eng_b, " Min=", min_sl_eng_b, " Used=", m_signal.stop_loss);
               return true;
            }
            else
            {
               LogPrint("    Engulfing conditions not met (open[1]=", open[1], " close[2]=", close[2], " close[1]=", close[1], " open[2]=", open[2], ")");
            }
         }
      }

      LogPrint("    Engulfing pattern NOT detected");
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Detect pin bar                                                   |
   //+------------------------------------------------------------------+
   bool DetectPinBar(ENUM_TREND_DIRECTION trend_bias)
   {
      LogPrint(">>> DEBUG: DetectPinBar() called | Trend Bias: ", EnumToString(trend_bias));

      double open[], high[], low[], close[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);

      if(CopyOpen(_Symbol, PERIOD_H1, 0, 3, open) <= 0 ||
         CopyHigh(_Symbol, PERIOD_H1, 0, 3, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, 3, low) <= 0 ||
         CopyClose(_Symbol, PERIOD_H1, 0, 3, close) <= 0)
      {
         LogPrint("    FAILED: Could not copy H1 price data");
         return false;
      }

      // FIX v2.0: Check COMPLETED candle (bar[1]) instead of forming candle (bar[0])
      double body_size = MathAbs(close[1] - open[1]);
      double upper_wick = high[1] - MathMax(close[1], open[1]);
      double lower_wick = MathMin(close[1], open[1]) - low[1];

      LogPrint("    Candle measurements (bar[1]) | Body: ", body_size, " | Upper Wick: ", upper_wick,
            " | Lower Wick: ", lower_wick);

      // Bullish pin bar
      if(trend_bias == TREND_BULLISH)
      {
         LogPrint("    Checking BULLISH Pin Bar | Lower wick > body*1.5: ", (lower_wick > body_size * 1.5),
               " (", lower_wick, " > ", body_size * 1.5, ") | Upper wick < body*0.8: ", (upper_wick < body_size * 0.8),
               " (", upper_wick, " < ", body_size * 0.8, ")");

         // FIX: Allow upper wick to be up to 80% of body size (was "< body_size")
         // Gold often has a small wick on top even in good pin bars
         if(lower_wick > body_size * 1.5 && upper_wick < body_size * 0.8)
         {
            LogPrint("    ✓ BULLISH PIN BAR DETECTED!");

            m_signal.signal = SIGNAL_LONG;
            m_signal.pattern_type = PATTERN_PIN_BAR;
            m_signal.pattern_name = "Bullish Pin Bar";
            m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            // v4.4: Enforce minimum SL distance
            // FIX: Increased buffer from 10 to 50 points ($0.50) for Gold
            double pattern_sl_pin = low[1] - 50 * _Point;
            double min_sl_pin = m_signal.entry_price - m_min_sl_points * _Point;
            m_signal.stop_loss = MathMin(pattern_sl_pin, min_sl_pin);  // Use wider SL

            m_signal.take_profit = m_signal.entry_price +
                                  (m_signal.entry_price - m_signal.stop_loss) * m_scoring_rr_target;
            m_signal.signal_time = TimeCurrent();

            LogPrint("Bullish Pin Bar SL: Pattern=", pattern_sl_pin, " Min=", min_sl_pin, " Used=", m_signal.stop_loss);
            LogPrint("    Setup | Entry: ", m_signal.entry_price, " | SL: ", m_signal.stop_loss,
                  " | TP: ", m_signal.take_profit);
            return true;
         }
         else
         {
            LogPrint("    Bullish pin bar conditions NOT met");
         }
      }

      // Bearish pin bar
      if(trend_bias == TREND_BEARISH)
      {
         LogPrint("    Checking BEARISH Pin Bar | Upper wick > body*1.5: ", (upper_wick > body_size * 1.5),
               " (", upper_wick, " > ", body_size * 1.5, ") | Lower wick < body*0.8: ", (lower_wick < body_size * 0.8),
               " (", lower_wick, " < ", body_size * 0.8, ")");

         // FIX: Allow lower wick to be up to 80% of body size (was "< body_size")
         // Gold often has a small wick on bottom even in good pin bars
         if(upper_wick > body_size * 1.5 && lower_wick < body_size * 0.8)
         {
            LogPrint("    ✓ BEARISH PIN BAR DETECTED!");

            m_signal.signal = SIGNAL_SHORT;
            m_signal.pattern_type = PATTERN_PIN_BAR;
            m_signal.pattern_name = "Bearish Pin Bar";
            m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            // v4.4: Enforce minimum SL distance
            // FIX: Increased buffer from 10 to 50 points ($0.50) for Gold
            double pattern_sl_pin_b = high[1] + 50 * _Point;
            double min_sl_pin_b = m_signal.entry_price + m_min_sl_points * _Point;
            m_signal.stop_loss = MathMax(pattern_sl_pin_b, min_sl_pin_b);  // Use wider SL

            m_signal.take_profit = m_signal.entry_price -
                                  (m_signal.stop_loss - m_signal.entry_price) * m_scoring_rr_target;
            m_signal.signal_time = TimeCurrent();

            LogPrint("Bearish Pin Bar SL: Pattern=", pattern_sl_pin_b, " Min=", min_sl_pin_b, " Used=", m_signal.stop_loss);
            LogPrint("    Setup | Entry: ", m_signal.entry_price, " | SL: ", m_signal.stop_loss,
                  " | TP: ", m_signal.take_profit);
            return true;
         }
         else
         {
            LogPrint("    Bearish pin bar conditions NOT met");
         }
      }

      LogPrint("    Pin Bar pattern NOT detected");
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Detect S/R bounce (ranging markets)                              |
   //+------------------------------------------------------------------+
   bool DetectSRBounce()
   {
      LogPrint(">>> DEBUG: DetectSRBounce() called");

      double close[], high[], low[], rsi[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(rsi, true);

      // Copy enough data for lookback and signal bar
      if(CopyClose(_Symbol, PERIOD_H1, 0, 31, close) <= 0 ||
         CopyHigh(_Symbol, PERIOD_H1, 0, 31, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, 31, low) <= 0 ||
         CopyBuffer(m_handle_rsi, 0, 0, 2, rsi) <= 0)
      {
         LogPrint("    FAILED: Could not copy H1 price data or RSI");
         return false;
      }

      // Find support/resistance from closed bars (index 2 to 30)
      double resistance = high[2];
      double support = low[2];
      for(int i = 3; i < 31; i++)
      {
         resistance = MathMax(resistance, high[i]);
         support = MathMin(support, low[i]);
      }
      
      // Signal candle is the last closed bar (index 1)
      double signal_close = close[1];
      double signal_rsi = rsi[1];

      LogPrint("    S/R Levels (bars 2-30) | Support: ", support, " | Resistance: ", resistance);
      LogPrint("    Signal Candle (bar 1)  | Close: ", signal_close, " | RSI: ", signal_rsi);

      // Calculate distances
      double dist_from_support = MathAbs(signal_close - support) / support;
      double dist_from_resistance = MathAbs(signal_close - resistance) / resistance;

      LogPrint("    Distance from Support: ", dist_from_support * 100, "% | Distance from Resistance: ",
            dist_from_resistance * 100, "%");

      // Check if at support (long)
      LogPrint("    Checking SUPPORT BOUNCE | At support (<0.5%): ", (dist_from_support < 0.005),
            " | RSI oversold (<35): ", (signal_rsi < 35));

      if(dist_from_support < 0.005 && signal_rsi < 35)
      {
         LogPrint("    ✓ SUPPORT BOUNCE DETECTED!");

         m_signal.signal = SIGNAL_LONG;
         m_signal.pattern_type = PATTERN_SR_BOUNCE;
         m_signal.pattern_name = "Support Bounce";
         m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         m_signal.stop_loss = support - (resistance - support) * 0.1;
         m_signal.take_profit = m_signal.entry_price +
                               (m_signal.entry_price - m_signal.stop_loss) * m_scoring_rr_target;
         m_signal.signal_time = TimeCurrent();

         LogPrint("    Setup | Entry: ", m_signal.entry_price, " | SL: ", m_signal.stop_loss,
               " | TP: ", m_signal.take_profit);
         return true;
      }

      // Check if at resistance (short)
      LogPrint("    Checking RESISTANCE BOUNCE | At resistance (<0.5%): ", (dist_from_resistance < 0.005),
            " | RSI overbought (>60): ", (signal_rsi > 60));

      if(dist_from_resistance < 0.005 && signal_rsi > 60)
      {
         LogPrint("    ✓ RESISTANCE BOUNCE DETECTED!");

         m_signal.signal = SIGNAL_SHORT;
         m_signal.pattern_type = PATTERN_SR_BOUNCE;
         m_signal.pattern_name = "Resistance Bounce";
         m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         m_signal.stop_loss = resistance + (resistance - support) * 0.1;
         m_signal.take_profit = m_signal.entry_price -
                               (m_signal.stop_loss - m_signal.entry_price) * m_scoring_rr_target;
         m_signal.signal_time = TimeCurrent();

         LogPrint("    Setup | Entry: ", m_signal.entry_price, " | SL: ", m_signal.stop_loss,
               " | TP: ", m_signal.take_profit);
         return true;
      }

      LogPrint("    S/R Bounce NOT detected (not close enough to S/R or RSI not extreme)");
      return false;
   }
};