//+------------------------------------------------------------------+
//| TrendDetector.mqh                                                 |
//| Component 1: Multi-Timeframe Trend Detection                      |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| Trend Detector Class                                              |
//+------------------------------------------------------------------+
class CTrendDetector
{
private:
   // Parameters
   int                  m_ma_fast_period;
   int                  m_ma_slow_period;
   int                  m_swing_lookback;
   
   // Indicator handles
   int                  m_handle_ma_fast_d1, m_handle_ma_slow_d1;
   int                  m_handle_ma_fast_h4, m_handle_ma_slow_h4;
   int                  m_handle_ma_fast_h1, m_handle_ma_slow_h1;
   int                  m_handle_atr_d1, m_handle_atr_h4, m_handle_atr_h1;
   
   // Trend data
   STrendData           m_trend_d1;
   STrendData           m_trend_h4;
   STrendData           m_trend_h1;
   
   bool                 m_all_aligned;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CTrendDetector(int fast_period = 20, int slow_period = 50, int swing_lookback = 20)
   {
      m_ma_fast_period = fast_period;
      m_ma_slow_period = slow_period;
      m_swing_lookback = swing_lookback;
      
      m_all_aligned = false;
   }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CTrendDetector()
   {
      IndicatorRelease(m_handle_ma_fast_d1);
      IndicatorRelease(m_handle_ma_slow_d1);
      IndicatorRelease(m_handle_ma_fast_h4);
      IndicatorRelease(m_handle_ma_slow_h4);
      IndicatorRelease(m_handle_ma_fast_h1);
      IndicatorRelease(m_handle_ma_slow_h1);
      IndicatorRelease(m_handle_atr_d1);
      IndicatorRelease(m_handle_atr_h4);
      IndicatorRelease(m_handle_atr_h1);
   }
   
   //+------------------------------------------------------------------+
   //| Initialize indicators                                             |
   //+------------------------------------------------------------------+
   bool Init()
   {
      // v4.3: Changed to EMA for faster trend response
      // This helps detect bearish trends earlier for timely shorts
      m_handle_ma_fast_d1 = iMA(_Symbol, PERIOD_D1, m_ma_fast_period, 0, MODE_EMA, PRICE_CLOSE);
      m_handle_ma_slow_d1 = iMA(_Symbol, PERIOD_D1, m_ma_slow_period, 0, MODE_EMA, PRICE_CLOSE);

      m_handle_ma_fast_h4 = iMA(_Symbol, PERIOD_H4, m_ma_fast_period, 0, MODE_EMA, PRICE_CLOSE);
      m_handle_ma_slow_h4 = iMA(_Symbol, PERIOD_H4, m_ma_slow_period, 0, MODE_EMA, PRICE_CLOSE);

      m_handle_ma_fast_h1 = iMA(_Symbol, PERIOD_H1, m_ma_fast_period, 0, MODE_EMA, PRICE_CLOSE);
      m_handle_ma_slow_h1 = iMA(_Symbol, PERIOD_H1, m_ma_slow_period, 0, MODE_EMA, PRICE_CLOSE);

      // FIXED: Create ATR handles for trend strength calculation (performance optimization)
      m_handle_atr_d1 = iATR(_Symbol, PERIOD_D1, 14);
      m_handle_atr_h4 = iATR(_Symbol, PERIOD_H4, 14);
      m_handle_atr_h1 = iATR(_Symbol, PERIOD_H1, 14);

      // Validate handles
      if(m_handle_ma_fast_d1 == INVALID_HANDLE || m_handle_ma_slow_d1 == INVALID_HANDLE ||
         m_handle_ma_fast_h4 == INVALID_HANDLE || m_handle_ma_slow_h4 == INVALID_HANDLE ||
         m_handle_ma_fast_h1 == INVALID_HANDLE || m_handle_ma_slow_h1 == INVALID_HANDLE ||
         m_handle_atr_d1 == INVALID_HANDLE || m_handle_atr_h4 == INVALID_HANDLE || m_handle_atr_h1 == INVALID_HANDLE)
      {
         LogPrint("ERROR: Failed to create indicators in TrendDetector");
         return false;
      }

      LogPrint("TrendDetector initialized with EMA (Fast: ", m_ma_fast_period, ", Slow: ", m_ma_slow_period, ")");
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update all timeframes                                            |
   //+------------------------------------------------------------------+
   void Update()
   {
      UpdateTimeframe(PERIOD_D1, m_trend_d1, m_handle_ma_fast_d1, m_handle_ma_slow_d1);
      UpdateTimeframe(PERIOD_H4, m_trend_h4, m_handle_ma_fast_h4, m_handle_ma_slow_h4);
      UpdateTimeframe(PERIOD_H1, m_trend_h1, m_handle_ma_fast_h1, m_handle_ma_slow_h1);
      
      CheckAlignment();
   }
   
   //+------------------------------------------------------------------+
   //| Get trend data                                                    |
   //+------------------------------------------------------------------+
   ENUM_TREND_DIRECTION GetDailyTrend() const { return m_trend_d1.direction; }
   ENUM_TREND_DIRECTION GetH4Trend() const { return m_trend_h4.direction; }
   ENUM_TREND_DIRECTION GetH1Trend() const { return m_trend_h1.direction; }
   bool IsAligned() const { return m_all_aligned; }
   
   double GetTrendStrength(ENUM_TIMEFRAMES tf)
   {
      if(tf == PERIOD_D1) return m_trend_d1.strength;
      if(tf == PERIOD_H4) return m_trend_h4.strength;
      if(tf == PERIOD_H1) return m_trend_h1.strength;
      return 0.0;
   }

private:
  //+------------------------------------------------------------------+
//| Update single timeframe - RELAXED VERSION                        |
//+------------------------------------------------------------------+
bool UpdateTimeframe(ENUM_TIMEFRAMES tf, STrendData &trend_data,
                     int handle_fast, int handle_slow)
{
   double ma_fast[], ma_slow[], close[];
   ArraySetAsSeries(ma_fast, true);
   ArraySetAsSeries(ma_slow, true);
   ArraySetAsSeries(close, true);
   
   // Copy data
   if(CopyBuffer(handle_fast, 0, 0, 3, ma_fast) <= 0 ||
      CopyBuffer(handle_slow, 0, 0, 3, ma_slow) <= 0 ||
      CopyClose(_Symbol, tf, 0, 3, close) <= 0)
   {
      return false;
   }
   
   // Store MA values
   trend_data.ma_fast = ma_fast[0];
   trend_data.ma_slow = ma_slow[0];
   
   // Analyze MA position
   bool fast_above_slow = ma_fast[0] > ma_slow[0];
   bool price_above_fast = close[0] > ma_fast[0];
   bool price_below_fast = close[0] < ma_fast[0];
   bool price_above_slow = close[0] > ma_slow[0];
   bool price_below_slow = close[0] < ma_slow[0];

   // Detect swing structure (optional - not required)
   trend_data.making_hh = DetectHigherHighs(tf);
   trend_data.making_ll = DetectLowerLows(tf);

   // v4.3: IMPROVED TREND DETECTION - More responsive to trend changes
   // Key insight: Don't wait for full MA crossover, detect early when price breaks fast MA

   // BULLISH: Price above both MAs OR price above fast AND making higher highs
   if(price_above_fast && price_above_slow)
   {
      trend_data.direction = TREND_BULLISH;
      LogPrint(tf, " BULLISH: Price=", close[0], " > MA_Fast=", ma_fast[0], " & > MA_Slow=", ma_slow[0]);
   }
   // BEARISH: Price below both MAs OR price below fast AND making lower lows
   else if(price_below_fast && price_below_slow)
   {
      trend_data.direction = TREND_BEARISH;
      LogPrint(tf, " BEARISH: Price=", close[0], " < MA_Fast=", ma_fast[0], " & < MA_Slow=", ma_slow[0]);
   }
   // EARLY BEARISH: Price broke below fast MA (early warning even if slow MA still above)
   else if(price_below_fast && fast_above_slow && trend_data.making_ll)
   {
      trend_data.direction = TREND_BEARISH;
      LogPrint(tf, " EARLY BEARISH: Price=", close[0], " broke below Fast MA=", ma_fast[0], " + making lower lows");
   }
   // EARLY BULLISH: Price broke above fast MA (early warning even if slow MA still below)
   else if(price_above_fast && !fast_above_slow && trend_data.making_hh)
   {
      trend_data.direction = TREND_BULLISH;
      LogPrint(tf, " EARLY BULLISH: Price=", close[0], " broke above Fast MA=", ma_fast[0], " + making higher highs");
   }
   else
   {
      trend_data.direction = TREND_NEUTRAL;
      LogPrint(tf, " NEUTRAL: MAs mixed or price between MAs");
   }
   
   // Calculate trend strength
   trend_data.strength = CalculateTrendStrength(tf, trend_data);
   trend_data.last_update = TimeCurrent();
   
   return true;
}
   
   //+------------------------------------------------------------------+
   //| Detect higher highs                                              |
   //+------------------------------------------------------------------+
   bool DetectHigherHighs(ENUM_TIMEFRAMES tf)
   {
      double high[];
      ArraySetAsSeries(high, true);
      
      int bars_needed = m_swing_lookback + 5;
      if(CopyHigh(_Symbol, tf, 0, bars_needed, high) <= 0)
         return false;
      
      double swing_highs[3];
      int swing_count = 0;
      
      // Find last 3 swing highs
      for(int i = 2; i < m_swing_lookback + 3 && swing_count < 3; i++)
      {
         if(high[i] > high[i-1] && high[i] > high[i-2] &&
            high[i] > high[i+1] && high[i] > high[i+2])
         {
            swing_highs[swing_count] = high[i];
            swing_count++;
         }
      }
      
      if(swing_count < 3) return false;
      
      // Check if ascending
      return (swing_highs[0] > swing_highs[1] && swing_highs[1] > swing_highs[2]);
   }
   
   //+------------------------------------------------------------------+
   //| Detect lower lows                                                |
   //+------------------------------------------------------------------+
   bool DetectLowerLows(ENUM_TIMEFRAMES tf)
   {
      double low[];
      ArraySetAsSeries(low, true);
      
      int bars_needed = m_swing_lookback + 5;
      if(CopyLow(_Symbol, tf, 0, bars_needed, low) <= 0)
         return false;
      
      double swing_lows[3];
      int swing_count = 0;
      
      // Find last 3 swing lows
      for(int i = 2; i < m_swing_lookback + 3 && swing_count < 3; i++)
      {
         if(low[i] < low[i-1] && low[i] < low[i-2] &&
            low[i] < low[i+1] && low[i] < low[i+2])
         {
            swing_lows[swing_count] = low[i];
            swing_count++;
         }
      }
      
      if(swing_count < 3) return false;
      
      // Check if descending
      return (swing_lows[0] < swing_lows[1] && swing_lows[1] < swing_lows[2]);
   }
   
   //+------------------------------------------------------------------+
   //| Calculate trend strength                                         |
   //+------------------------------------------------------------------+
   double CalculateTrendStrength(ENUM_TIMEFRAMES tf, const STrendData &trend)
   {
      double strength = 0.0;

      // Factor 1: MA separation (40%)
      double ma_separation = MathAbs(trend.ma_fast - trend.ma_slow);

      // FIXED: Use cached ATR handle instead of creating new one every tick
      int atr_handle = INVALID_HANDLE;
      if(tf == PERIOD_D1) atr_handle = m_handle_atr_d1;
      else if(tf == PERIOD_H4) atr_handle = m_handle_atr_h4;
      else if(tf == PERIOD_H1) atr_handle = m_handle_atr_h1;

      double atr[];
      ArraySetAsSeries(atr, true);

      if(atr_handle != INVALID_HANDLE && CopyBuffer(atr_handle, 0, 0, 1, atr) > 0)
      {
         if(atr[0] > 0)
            strength += MathMin((ma_separation / atr[0]) * 0.4, 0.4);
      }
      
      // Factor 2: Swing structure (30%)
      if(trend.making_hh || trend.making_ll)
         strength += 0.3;
      
      // Factor 3: Clear direction (30%)
      if(trend.direction != TREND_NEUTRAL)
         strength += 0.3;
      
      return MathMin(strength, 1.0);
   }
   
   //+------------------------------------------------------------------+
   //| Check multi-timeframe alignment                                  |
   //+------------------------------------------------------------------+
   void CheckAlignment()
   {
      m_all_aligned = (m_trend_d1.direction == m_trend_h4.direction &&
                       m_trend_h4.direction == m_trend_h1.direction &&
                       m_trend_d1.direction != TREND_NEUTRAL);
   }
};