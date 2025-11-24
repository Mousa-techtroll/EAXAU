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

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CPriceActionLowVol(int bb_period = 20, double bb_dev = 2.0, int rsi_period = 14,
                      int atr_period = 14, double scoring_rr_target = 2.0, double min_sl = 100.0,
                      bool enable_bb_mr = true, bool enable_range = true, bool enable_fade = true,
                      double max_atr = 30.0)
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

      m_range_valid = false;
      m_range_bars_count = 0;

      // Initialize indicators
      m_handle_bb = iBands(_Symbol, PERIOD_H1, m_bb_period, 0, m_bb_deviation, PRICE_CLOSE);
      m_handle_rsi = iRSI(_Symbol, PERIOD_H1, m_rsi_period, PRICE_CLOSE);
      m_handle_atr = iATR(_Symbol, PERIOD_H1, m_atr_period);
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
   //+------------------------------------------------------------------+
   bool DetectFalseBreakoutFade()
   {
      if(!m_enable_false_breakout_fade)
         return false;

      LogPrint(">>> Checking False Breakout Fade pattern...");

      // Check for LOW VOLATILITY (required - breakouts fail in low vol)
      double atr = GetATR();
      if(atr >= m_max_atr_lowvol)
      {
         LogPrint("    ATR too high (", atr, " >= ", m_max_atr_lowvol, ") - breakouts may be valid");
         return false;
      }

      // Get price data
      double close[], high[], low[], open[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(open, true);

      if(CopyClose(_Symbol, PERIOD_H1, 0, 25, close) <= 0 ||
         CopyHigh(_Symbol, PERIOD_H1, 0, 25, high) <= 0 ||
         CopyLow(_Symbol, PERIOD_H1, 0, 25, low) <= 0 ||
         CopyOpen(_Symbol, PERIOD_H1, 0, 25, open) <= 0)
      {
         return false;
      }

      // Find recent swing high/low (from bars 2 to 21)
      double swing_high = high[2];
      double swing_low = low[2];

      for(int i = 3; i <= 21; i++)
      {
         if(high[i] > swing_high) swing_high = high[i];
         if(low[i] < swing_low) swing_low = low[i];
      }

      // The breakout candle is the most recently completed one (index 1)
      double breakout_candle_high = high[1];
      double breakout_candle_low = low[1];
      double breakout_candle_close = close[1];

      LogPrint("    ATR=", atr, " Swing High=", swing_high, " Swing Low=", swing_low);
      LogPrint("    Breakout Candle H/L/C: ", breakout_candle_high, "/", breakout_candle_low, "/", breakout_candle_close);

      // BEARISH FADE: Price broke above swing high but ATR is low
      if(breakout_candle_high > swing_high)
      {
         // Check if it's a false breakout (price pulling back)
         if(breakout_candle_close < breakout_candle_high * 0.997)  // Closed below high (pullback)
         {
            // Additional confirmation: Small breakout candle (not huge momentum)
            double candle_range = breakout_candle_high - breakout_candle_low;
            if(candle_range < atr * 2.0)  // Not an exceptionally large candle
            {
               LogPrint("    ✓ BEARISH FALSE BREAKOUT FADE DETECTED!");
               LogPrint("    Low vol breakout above resistance - likely to fail");

               m_signal.signal = SIGNAL_SHORT;
               m_signal.pattern_type = PATTERN_FALSE_BREAKOUT_FADE;
               m_signal.pattern_name = "False Breakout Fade Short";
               m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

               // Target: Back to middle of recent range
               double range_mid = swing_low + ((swing_high - swing_low) * 0.5);
               m_signal.take_profit = range_mid;

               // v4.4: Stop with minimum SL enforcement
               double atr_sl_fb = breakout_candle_high + (atr * 1.5);
               double min_sl_fb = m_signal.entry_price + m_min_sl_points * _Point;
               m_signal.stop_loss = MathMax(atr_sl_fb, min_sl_fb);  // Use wider SL

               m_signal.signal_time = TimeCurrent();
               return true;
            }
         }
      }

      // BULLISH FADE: Price broke below swing low but ATR is low
      if(breakout_candle_low < swing_low)
      {
         // Check if it's a false breakout (price pulling back)
         if(breakout_candle_close > breakout_candle_low * 1.003)  // Closed above low (pullback)
         {
            // Additional confirmation: Small breakout candle
            double candle_range = breakout_candle_high - breakout_candle_low;
            if(candle_range < atr * 2.0)
            {
               LogPrint("    ✓ BULLISH FALSE BREAKOUT FADE DETECTED!");
               LogPrint("    Low vol breakout below support - likely to fail");

               m_signal.signal = SIGNAL_LONG;
               m_signal.pattern_type = PATTERN_FALSE_BREAKOUT_FADE;
               m_signal.pattern_name = "False Breakout Fade Long";
               m_signal.entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

               // Target: Back to middle of recent range
               double range_mid_l = swing_low + ((swing_high - swing_low) * 0.5);
               m_signal.take_profit = range_mid_l;

               // v4.4: Stop with minimum SL enforcement
               double atr_sl_fbl = breakout_candle_low - (atr * 1.5);
               double min_sl_fbl = m_signal.entry_price - m_min_sl_points * _Point;
               m_signal.stop_loss = MathMin(atr_sl_fbl, min_sl_fbl);  // Use wider SL

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
