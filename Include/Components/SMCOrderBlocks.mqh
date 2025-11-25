//+------------------------------------------------------------------+
//| SMCOrderBlocks.mqh                                               |
//| Smart Money Concepts - Order Block Detection                     |
//| v1.0 - Institutional level analysis for Gold trading            |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| SMC Zone Type Enumeration                                        |
//+------------------------------------------------------------------+
enum ENUM_SMC_ZONE_TYPE
{
   SMC_ZONE_NONE,
   SMC_ZONE_BULLISH_OB,        // Bullish Order Block (demand zone)
   SMC_ZONE_BEARISH_OB,        // Bearish Order Block (supply zone)
   SMC_ZONE_BULLISH_FVG,       // Bullish Fair Value Gap
   SMC_ZONE_BEARISH_FVG,       // Bearish Fair Value Gap
   SMC_ZONE_BULLISH_BREAKER,   // Bullish Breaker Block
   SMC_ZONE_BEARISH_BREAKER    // Bearish Breaker Block
};

//+------------------------------------------------------------------+
//| Break of Structure Type                                          |
//+------------------------------------------------------------------+
enum ENUM_BOS_TYPE
{
   BOS_NONE,
   BOS_BULLISH,                // Break of structure to upside
   BOS_BEARISH,                // Break of structure to downside
   CHOCH_BULLISH,              // Change of character bullish
   CHOCH_BEARISH               // Change of character bearish
};

//+------------------------------------------------------------------+
//| SMC Zone Structure                                               |
//+------------------------------------------------------------------+
struct SSMCZone
{
   ENUM_SMC_ZONE_TYPE   type;           // Zone type
   double               top;            // Zone top price
   double               bottom;         // Zone bottom price
   datetime             formed_time;    // When zone formed
   int                  formed_bar;     // Bar index when formed
   bool                 is_valid;       // Zone still valid (not mitigated)
   int                  touch_count;    // Times price touched zone
   double               strength;       // Zone strength (0-100)
   ENUM_TIMEFRAMES      timeframe;      // Timeframe zone was detected on
};

//+------------------------------------------------------------------+
//| Liquidity Pool Structure                                         |
//+------------------------------------------------------------------+
struct SLiquidityPool
{
   double               price;          // Liquidity level price
   bool                 is_high;        // true = equal highs, false = equal lows
   int                  touch_count;    // Number of touches
   datetime             first_touch;    // First touch time
   datetime             last_touch;     // Last touch time
   bool                 is_swept;       // Has been swept
   double               strength;       // Pool strength
};

//+------------------------------------------------------------------+
//| SMC Analysis Result Structure                                    |
//+------------------------------------------------------------------+
struct SSMCAnalysis
{
   // Order Blocks
   bool                 in_bullish_ob;       // Price in bullish OB
   bool                 in_bearish_ob;       // Price in bearish OB
   SSMCZone             nearest_bullish_ob;  // Nearest bullish OB below
   SSMCZone             nearest_bearish_ob;  // Nearest bearish OB above

   // Fair Value Gaps
   bool                 in_bullish_fvg;      // Price in bullish FVG
   bool                 in_bearish_fvg;      // Price in bearish FVG
   SSMCZone             nearest_bullish_fvg; // Nearest bullish FVG
   SSMCZone             nearest_bearish_fvg; // Nearest bearish FVG

   // Break of Structure
   ENUM_BOS_TYPE        recent_bos;          // Most recent BOS
   datetime             bos_time;            // When BOS occurred
   double               bos_level;           // BOS level

   // Liquidity
   SLiquidityPool       nearest_buy_liquidity;   // Equal lows below
   SLiquidityPool       nearest_sell_liquidity;  // Equal highs above
   bool                 liquidity_swept;         // Recent sweep detected

   // Overall SMC Bias
   int                  smc_score;           // -100 to +100 (bearish to bullish)
   bool                 supports_long;       // SMC supports long entry
   bool                 supports_short;      // SMC supports short entry
};

//+------------------------------------------------------------------+
//| SMC Configuration                                                |
//+------------------------------------------------------------------+
struct SSMCConfig
{
   int      ob_lookback;              // Bars to look back for OBs
   double   ob_min_body_pct;          // Min body % of candle for OB
   double   ob_impulse_atr_mult;      // Min impulse size (ATR multiple)
   int      fvg_min_gap_points;       // Min gap size in points
   int      bos_swing_lookback;       // Swing detection lookback
   double   liquidity_equal_tolerance;// Tolerance for equal highs/lows (points)
   int      liquidity_min_touches;    // Min touches for valid liquidity pool
   int      zone_max_age_bars;        // Max age before zone expires
   bool     use_htf_confluence;       // Require HTF confirmation
};

//+------------------------------------------------------------------+
//| SMC Order Blocks Class                                           |
//+------------------------------------------------------------------+
class CSMCOrderBlocks
{
private:
   SSMCConfig           m_config;

   // Zone arrays
   SSMCZone             m_bullish_obs[];
   SSMCZone             m_bearish_obs[];
   SSMCZone             m_bullish_fvgs[];
   SSMCZone             m_bearish_fvgs[];
   SLiquidityPool       m_liquidity_pools[];

   // Zone counts
   int                  m_bullish_ob_count;
   int                  m_bearish_ob_count;
   int                  m_bullish_fvg_count;
   int                  m_bearish_fvg_count;
   int                  m_liquidity_count;

   // Indicator handles
   int                  m_handle_atr;

   // Cached swing points
   double               m_swing_highs[];
   double               m_swing_lows[];
   int                  m_swing_high_bars[];
   int                  m_swing_low_bars[];
   int                  m_swing_count;

   // Last BOS tracking
   ENUM_BOS_TYPE        m_last_bos;
   datetime             m_last_bos_time;
   double               m_last_bos_level;
   double               m_last_swing_high;
   double               m_last_swing_low;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSMCOrderBlocks()
   {
      // Default configuration
      m_config.ob_lookback = 50;
      m_config.ob_min_body_pct = 0.5;
      m_config.ob_impulse_atr_mult = 1.5;
      m_config.fvg_min_gap_points = 50;
      m_config.bos_swing_lookback = 20;
      m_config.liquidity_equal_tolerance = 30;
      m_config.liquidity_min_touches = 2;
      m_config.zone_max_age_bars = 200;
      m_config.use_htf_confluence = true;

      // Initialize counts
      m_bullish_ob_count = 0;
      m_bearish_ob_count = 0;
      m_bullish_fvg_count = 0;
      m_bearish_fvg_count = 0;
      m_liquidity_count = 0;
      m_swing_count = 0;

      m_last_bos = BOS_NONE;
      m_last_bos_time = 0;
      m_last_bos_level = 0;
      m_last_swing_high = 0;
      m_last_swing_low = 0;

      // Resize arrays
      ArrayResize(m_bullish_obs, 20);
      ArrayResize(m_bearish_obs, 20);
      ArrayResize(m_bullish_fvgs, 20);
      ArrayResize(m_bearish_fvgs, 20);
      ArrayResize(m_liquidity_pools, 20);
      ArrayResize(m_swing_highs, 50);
      ArrayResize(m_swing_lows, 50);
      ArrayResize(m_swing_high_bars, 50);
      ArrayResize(m_swing_low_bars, 50);
   }

   //+------------------------------------------------------------------+
   //| Configure with custom parameters                                  |
   //+------------------------------------------------------------------+
   void Configure(int ob_lookback, double ob_body_pct, double ob_impulse_mult,
                  int fvg_min_points, int bos_lookback, double liq_tolerance,
                  int liq_min_touches, int zone_max_age, bool use_htf)
   {
      m_config.ob_lookback = ob_lookback;
      m_config.ob_min_body_pct = ob_body_pct;
      m_config.ob_impulse_atr_mult = ob_impulse_mult;
      m_config.fvg_min_gap_points = fvg_min_points;
      m_config.bos_swing_lookback = bos_lookback;
      m_config.liquidity_equal_tolerance = liq_tolerance;
      m_config.liquidity_min_touches = liq_min_touches;
      m_config.zone_max_age_bars = zone_max_age;
      m_config.use_htf_confluence = use_htf;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init()
   {
      m_handle_atr = iATR(_Symbol, PERIOD_H1, 14);

      if(m_handle_atr == INVALID_HANDLE)
      {
         LogPrint("ERROR: SMCOrderBlocks failed to create ATR indicator");
         return false;
      }

      // Initial scan for zones
      ScanForOrderBlocks();
      ScanForFairValueGaps();
      ScanForLiquidityPools();
      DetectSwingPoints();

      LogPrint("SMCOrderBlocks initialized successfully");
      LogPrint("  OB Lookback: ", m_config.ob_lookback, " bars");
      LogPrint("  FVG Min Gap: ", m_config.fvg_min_gap_points, " points");
      LogPrint("  Initial Bullish OBs: ", m_bullish_ob_count);
      LogPrint("  Initial Bearish OBs: ", m_bearish_ob_count);
      LogPrint("  Initial FVGs: ", m_bullish_fvg_count + m_bearish_fvg_count);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CSMCOrderBlocks()
   {
      if(m_handle_atr != INVALID_HANDLE)
         IndicatorRelease(m_handle_atr);
   }

   //+------------------------------------------------------------------+
   //| Update on new bar                                                 |
   //+------------------------------------------------------------------+
   void Update()
   {
      // Scan for new zones
      ScanForOrderBlocks();
      ScanForFairValueGaps();
      DetectBreakOfStructure();
      UpdateLiquidityPools();

      // Invalidate mitigated zones
      InvalidateMitigatedZones();

      // Remove expired zones
      RemoveExpiredZones();
   }

   //+------------------------------------------------------------------+
   //| Get full SMC analysis for current price                          |
   //+------------------------------------------------------------------+
   SSMCAnalysis GetAnalysis()
   {
      SSMCAnalysis result;

      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Initialize
      result.in_bullish_ob = false;
      result.in_bearish_ob = false;
      result.in_bullish_fvg = false;
      result.in_bearish_fvg = false;
      result.recent_bos = m_last_bos;
      result.bos_time = m_last_bos_time;
      result.bos_level = m_last_bos_level;
      result.liquidity_swept = false;
      result.smc_score = 0;
      result.supports_long = false;
      result.supports_short = false;

      // Check if price is in any bullish OB
      for(int i = 0; i < m_bullish_ob_count; i++)
      {
         if(m_bullish_obs[i].is_valid &&
            current_price >= m_bullish_obs[i].bottom &&
            current_price <= m_bullish_obs[i].top)
         {
            result.in_bullish_ob = true;
            result.nearest_bullish_ob = m_bullish_obs[i];
            break;
         }
      }

      // Check if price is in any bearish OB
      for(int i = 0; i < m_bearish_ob_count; i++)
      {
         if(m_bearish_obs[i].is_valid &&
            current_price >= m_bearish_obs[i].bottom &&
            current_price <= m_bearish_obs[i].top)
         {
            result.in_bearish_ob = true;
            result.nearest_bearish_ob = m_bearish_obs[i];
            break;
         }
      }

      // Find nearest OBs if not currently in one
      if(!result.in_bullish_ob)
         result.nearest_bullish_ob = FindNearestZoneBelow(current_price, true);
      if(!result.in_bearish_ob)
         result.nearest_bearish_ob = FindNearestZoneAbove(current_price, true);

      // Check FVGs
      for(int i = 0; i < m_bullish_fvg_count; i++)
      {
         if(m_bullish_fvgs[i].is_valid &&
            current_price >= m_bullish_fvgs[i].bottom &&
            current_price <= m_bullish_fvgs[i].top)
         {
            result.in_bullish_fvg = true;
            result.nearest_bullish_fvg = m_bullish_fvgs[i];
            break;
         }
      }

      for(int i = 0; i < m_bearish_fvg_count; i++)
      {
         if(m_bearish_fvgs[i].is_valid &&
            current_price >= m_bearish_fvgs[i].bottom &&
            current_price <= m_bearish_fvgs[i].top)
         {
            result.in_bearish_fvg = true;
            result.nearest_bearish_fvg = m_bearish_fvgs[i];
            break;
         }
      }

      // Find nearest liquidity pools
      result.nearest_buy_liquidity = FindNearestLiquidityBelow(current_price);
      result.nearest_sell_liquidity = FindNearestLiquidityAbove(current_price);

      // Check for recent liquidity sweep
      result.liquidity_swept = CheckRecentLiquiditySweep();

      // Calculate SMC score
      result.smc_score = CalculateSMCScore(result);

      // Determine directional support
      result.supports_long = (result.smc_score >= 30) ||
                             (result.in_bullish_ob && result.recent_bos == BOS_BULLISH) ||
                             (result.in_bullish_fvg && result.liquidity_swept);

      result.supports_short = (result.smc_score <= -30) ||
                              (result.in_bearish_ob && result.recent_bos == BOS_BEARISH) ||
                              (result.in_bearish_fvg && result.liquidity_swept);

      return result;
   }

   //+------------------------------------------------------------------+
   //| Check if long entry is supported by SMC                          |
   //+------------------------------------------------------------------+
   bool SupportsLongEntry(double entry_price, double stop_loss)
   {
      SSMCAnalysis analysis = GetAnalysis();

      // Strong support: In bullish OB with bullish BOS
      if(analysis.in_bullish_ob &&
         (analysis.recent_bos == BOS_BULLISH || analysis.recent_bos == CHOCH_BULLISH))
      {
         LogPrint("SMC: Long SUPPORTED - In Bullish OB with bullish BOS");
         return true;
      }

      // Good support: In bullish FVG with positive score
      if(analysis.in_bullish_fvg && analysis.smc_score >= 20)
      {
         LogPrint("SMC: Long SUPPORTED - In Bullish FVG with score ", analysis.smc_score);
         return true;
      }

      // Support: Near bullish OB (within 1 ATR)
      double atr = GetCurrentATR();
      if(analysis.nearest_bullish_ob.is_valid)
      {
         double distance = entry_price - analysis.nearest_bullish_ob.top;
         if(distance >= 0 && distance <= atr)
         {
            LogPrint("SMC: Long SUPPORTED - Near Bullish OB at ",
                     analysis.nearest_bullish_ob.bottom, "-", analysis.nearest_bullish_ob.top);
            return true;
         }
      }

      // Support: Liquidity sweep below followed by reversal
      if(analysis.liquidity_swept && analysis.smc_score > 0)
      {
         LogPrint("SMC: Long SUPPORTED - Liquidity sweep detected");
         return true;
      }

      // Weak/No support
      if(analysis.smc_score < -30)
      {
         LogPrint("SMC: Long NOT SUPPORTED - Bearish SMC score ", analysis.smc_score);
         return false;
      }

      // Neutral - allow trade but don't boost
      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if short entry is supported by SMC                         |
   //+------------------------------------------------------------------+
   bool SupportsShortEntry(double entry_price, double stop_loss)
   {
      SSMCAnalysis analysis = GetAnalysis();

      // Strong support: In bearish OB with bearish BOS
      if(analysis.in_bearish_ob &&
         (analysis.recent_bos == BOS_BEARISH || analysis.recent_bos == CHOCH_BEARISH))
      {
         LogPrint("SMC: Short SUPPORTED - In Bearish OB with bearish BOS");
         return true;
      }

      // Good support: In bearish FVG with negative score
      if(analysis.in_bearish_fvg && analysis.smc_score <= -20)
      {
         LogPrint("SMC: Short SUPPORTED - In Bearish FVG with score ", analysis.smc_score);
         return true;
      }

      // Support: Near bearish OB (within 1 ATR)
      double atr = GetCurrentATR();
      if(analysis.nearest_bearish_ob.is_valid)
      {
         double distance = analysis.nearest_bearish_ob.bottom - entry_price;
         if(distance >= 0 && distance <= atr)
         {
            LogPrint("SMC: Short SUPPORTED - Near Bearish OB at ",
                     analysis.nearest_bearish_ob.bottom, "-", analysis.nearest_bearish_ob.top);
            return true;
         }
      }

      // Support: Liquidity sweep above followed by reversal
      if(analysis.liquidity_swept && analysis.smc_score < 0)
      {
         LogPrint("SMC: Short SUPPORTED - Liquidity sweep detected");
         return true;
      }

      // Weak/No support
      if(analysis.smc_score > 30)
      {
         LogPrint("SMC: Short NOT SUPPORTED - Bullish SMC score ", analysis.smc_score);
         return false;
      }

      // Neutral - allow trade but don't boost
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get SMC confluence score for entry (0-100)                       |
   //+------------------------------------------------------------------+
   int GetConfluenceScore(ENUM_SIGNAL_TYPE signal, double entry_price)
   {
      SSMCAnalysis analysis = GetAnalysis();
      int score = 50;  // Base score

      if(signal == SIGNAL_LONG)
      {
         // In bullish OB: +25
         if(analysis.in_bullish_ob)
            score += 25;

         // In bullish FVG: +15
         if(analysis.in_bullish_fvg)
            score += 15;

         // Bullish BOS: +20
         if(analysis.recent_bos == BOS_BULLISH || analysis.recent_bos == CHOCH_BULLISH)
            score += 20;

         // Near bullish OB: +10
         double atr = GetCurrentATR();
         if(analysis.nearest_bullish_ob.is_valid)
         {
            double distance = entry_price - analysis.nearest_bullish_ob.top;
            if(distance >= 0 && distance <= atr * 2)
               score += 10;
         }

         // Liquidity swept below: +15
         if(analysis.liquidity_swept && analysis.smc_score > 0)
            score += 15;

         // In bearish zone: -20
         if(analysis.in_bearish_ob || analysis.in_bearish_fvg)
            score -= 20;

         // Bearish BOS: -15
         if(analysis.recent_bos == BOS_BEARISH || analysis.recent_bos == CHOCH_BEARISH)
            score -= 15;
      }
      else if(signal == SIGNAL_SHORT)
      {
         // In bearish OB: +25
         if(analysis.in_bearish_ob)
            score += 25;

         // In bearish FVG: +15
         if(analysis.in_bearish_fvg)
            score += 15;

         // Bearish BOS: +20
         if(analysis.recent_bos == BOS_BEARISH || analysis.recent_bos == CHOCH_BEARISH)
            score += 20;

         // Near bearish OB: +10
         double atr = GetCurrentATR();
         if(analysis.nearest_bearish_ob.is_valid)
         {
            double distance = analysis.nearest_bearish_ob.bottom - entry_price;
            if(distance >= 0 && distance <= atr * 2)
               score += 10;
         }

         // Liquidity swept above: +15
         if(analysis.liquidity_swept && analysis.smc_score < 0)
            score += 15;

         // In bullish zone: -20
         if(analysis.in_bullish_ob || analysis.in_bullish_fvg)
            score -= 20;

         // Bullish BOS: -15
         if(analysis.recent_bos == BOS_BULLISH || analysis.recent_bos == CHOCH_BULLISH)
            score -= 15;
      }

      // Clamp to 0-100
      score = MathMax(0, MathMin(100, score));

      return score;
   }

   //+------------------------------------------------------------------+
   //| Get nearest order block for stop loss placement                  |
   //+------------------------------------------------------------------+
   double GetOrderBlockStopLevel(ENUM_SIGNAL_TYPE signal, double entry_price)
   {
      if(signal == SIGNAL_LONG)
      {
         // Find bullish OB below entry for stop placement
         SSMCZone ob = FindNearestZoneBelow(entry_price, true);
         if(ob.is_valid)
            return ob.bottom - (GetCurrentATR() * 0.5);  // Place stop below OB
      }
      else if(signal == SIGNAL_SHORT)
      {
         // Find bearish OB above entry for stop placement
         SSMCZone ob = FindNearestZoneAbove(entry_price, true);
         if(ob.is_valid)
            return ob.top + (GetCurrentATR() * 0.5);  // Place stop above OB
      }

      return 0;  // No suitable OB found
   }

   //+------------------------------------------------------------------+
   //| Get order block target level                                     |
   //+------------------------------------------------------------------+
   double GetOrderBlockTargetLevel(ENUM_SIGNAL_TYPE signal, double entry_price)
   {
      if(signal == SIGNAL_LONG)
      {
         // Target bearish OB above for longs
         SSMCZone ob = FindNearestZoneAbove(entry_price, false);  // bearish
         if(ob.is_valid)
            return ob.bottom;  // Target bottom of supply zone
      }
      else if(signal == SIGNAL_SHORT)
      {
         // Target bullish OB below for shorts
         SSMCZone ob = FindNearestZoneBelow(entry_price, false);  // bullish
         if(ob.is_valid)
            return ob.top;  // Target top of demand zone
      }

      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get zone counts for display                                      |
   //+------------------------------------------------------------------+
   int GetBullishOBCount() { return m_bullish_ob_count; }
   int GetBearishOBCount() { return m_bearish_ob_count; }
   int GetFVGCount() { return m_bullish_fvg_count + m_bearish_fvg_count; }
   ENUM_BOS_TYPE GetLastBOS() { return m_last_bos; }

private:
   //+------------------------------------------------------------------+
   //| Scan for Order Blocks                                            |
   //+------------------------------------------------------------------+
   void ScanForOrderBlocks()
   {
      double high[], low[], open[], close[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(close, true);

      int bars_to_copy = m_config.ob_lookback + 5;
      if(CopyHigh(_Symbol, PERIOD_H1, 0, bars_to_copy, high) <= 0) return;
      if(CopyLow(_Symbol, PERIOD_H1, 0, bars_to_copy, low) <= 0) return;
      if(CopyOpen(_Symbol, PERIOD_H1, 0, bars_to_copy, open) <= 0) return;
      if(CopyClose(_Symbol, PERIOD_H1, 0, bars_to_copy, close) <= 0) return;

      double atr = GetCurrentATR();
      if(atr <= 0) return;

      // Scan for new order blocks (start from bar 3 to have context)
      for(int i = 3; i < m_config.ob_lookback; i++)
      {
         // Check for Bullish Order Block
         // Pattern: Bearish candle followed by strong bullish impulse
         if(close[i+1] < open[i+1])  // Previous candle bearish
         {
            // Check for strong bullish impulse after
            double impulse = high[i] - low[i+1];
            if(impulse >= atr * m_config.ob_impulse_atr_mult)
            {
               // This bearish candle becomes a bullish OB
               double body_size = MathAbs(close[i+1] - open[i+1]);
               double candle_range = high[i+1] - low[i+1];

               if(candle_range > 0 && body_size / candle_range >= m_config.ob_min_body_pct)
               {
                  // Check if zone doesn't already exist
                  if(!ZoneExists(low[i+1], high[i+1], true))
                  {
                     AddBullishOB(low[i+1], high[i+1], iTime(_Symbol, PERIOD_H1, i+1), i+1);
                  }
               }
            }
         }

         // Check for Bearish Order Block
         // Pattern: Bullish candle followed by strong bearish impulse
         if(close[i+1] > open[i+1])  // Previous candle bullish
         {
            // Check for strong bearish impulse after
            double impulse = high[i+1] - low[i];
            if(impulse >= atr * m_config.ob_impulse_atr_mult)
            {
               // This bullish candle becomes a bearish OB
               double body_size = MathAbs(close[i+1] - open[i+1]);
               double candle_range = high[i+1] - low[i+1];

               if(candle_range > 0 && body_size / candle_range >= m_config.ob_min_body_pct)
               {
                  // Check if zone doesn't already exist
                  if(!ZoneExists(low[i+1], high[i+1], false))
                  {
                     AddBearishOB(low[i+1], high[i+1], iTime(_Symbol, PERIOD_H1, i+1), i+1);
                  }
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Scan for Fair Value Gaps                                         |
   //+------------------------------------------------------------------+
   void ScanForFairValueGaps()
   {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      int bars_to_copy = m_config.ob_lookback;
      if(CopyHigh(_Symbol, PERIOD_H1, 0, bars_to_copy, high) <= 0) return;
      if(CopyLow(_Symbol, PERIOD_H1, 0, bars_to_copy, low) <= 0) return;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      // Scan for FVGs (need 3 consecutive candles)
      for(int i = 1; i < m_config.ob_lookback - 2; i++)
      {
         // Bullish FVG: Gap between candle 1 high and candle 3 low
         // (in bearish impulse that creates a gap)
         double bullish_gap = low[i] - high[i+2];  // Gap up
         if(bullish_gap >= m_config.fvg_min_gap_points * point)
         {
            if(!FVGExists(high[i+2], low[i], true))
            {
               AddBullishFVG(high[i+2], low[i], iTime(_Symbol, PERIOD_H1, i), i);
            }
         }

         // Bearish FVG: Gap between candle 3 high and candle 1 low
         double bearish_gap = low[i+2] - high[i];  // Gap down
         if(bearish_gap >= m_config.fvg_min_gap_points * point)
         {
            if(!FVGExists(high[i], low[i+2], false))
            {
               AddBearishFVG(high[i], low[i+2], iTime(_Symbol, PERIOD_H1, i), i);
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Detect swing points                                              |
   //+------------------------------------------------------------------+
   void DetectSwingPoints()
   {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      int bars = m_config.ob_lookback;
      if(CopyHigh(_Symbol, PERIOD_H1, 0, bars, high) <= 0) return;
      if(CopyLow(_Symbol, PERIOD_H1, 0, bars, low) <= 0) return;

      m_swing_count = 0;
      int lookback = m_config.bos_swing_lookback / 2;

      for(int i = lookback; i < bars - lookback; i++)
      {
         // Check for swing high
         bool is_swing_high = true;
         for(int j = 1; j <= lookback; j++)
         {
            if(high[i] <= high[i-j] || high[i] <= high[i+j])
            {
               is_swing_high = false;
               break;
            }
         }

         if(is_swing_high && m_swing_count < 50)
         {
            m_swing_highs[m_swing_count] = high[i];
            m_swing_high_bars[m_swing_count] = i;
            m_swing_count++;
         }

         // Check for swing low
         bool is_swing_low = true;
         for(int j = 1; j <= lookback; j++)
         {
            if(low[i] >= low[i-j] || low[i] >= low[i+j])
            {
               is_swing_low = false;
               break;
            }
         }

         if(is_swing_low && m_swing_count < 50)
         {
            m_swing_lows[m_swing_count] = low[i];
            m_swing_low_bars[m_swing_count] = i;
         }
      }

      // Update last swing high/low
      if(m_swing_count > 0)
      {
         m_last_swing_high = m_swing_highs[0];
         m_last_swing_low = m_swing_lows[0];
      }
   }

   //+------------------------------------------------------------------+
   //| Detect Break of Structure                                        |
   //+------------------------------------------------------------------+
   void DetectBreakOfStructure()
   {
      DetectSwingPoints();

      double current_high = iHigh(_Symbol, PERIOD_H1, 0);
      double current_low = iLow(_Symbol, PERIOD_H1, 0);
      double prev_high = iHigh(_Symbol, PERIOD_H1, 1);
      double prev_low = iLow(_Symbol, PERIOD_H1, 1);

      // Check for bullish BOS (break above recent swing high)
      if(m_last_swing_high > 0 && current_high > m_last_swing_high && prev_high <= m_last_swing_high)
      {
         // Check if this is a CHoCH (change of character) from bearish
         if(m_last_bos == BOS_BEARISH || m_last_bos == CHOCH_BEARISH)
         {
            m_last_bos = CHOCH_BULLISH;
            LogPrint("SMC: CHoCH BULLISH detected - Price broke above ", m_last_swing_high);
         }
         else
         {
            m_last_bos = BOS_BULLISH;
            LogPrint("SMC: BOS BULLISH detected - Price broke above ", m_last_swing_high);
         }
         m_last_bos_time = TimeCurrent();
         m_last_bos_level = m_last_swing_high;
      }

      // Check for bearish BOS (break below recent swing low)
      if(m_last_swing_low > 0 && current_low < m_last_swing_low && prev_low >= m_last_swing_low)
      {
         // Check if this is a CHoCH from bullish
         if(m_last_bos == BOS_BULLISH || m_last_bos == CHOCH_BULLISH)
         {
            m_last_bos = CHOCH_BEARISH;
            LogPrint("SMC: CHoCH BEARISH detected - Price broke below ", m_last_swing_low);
         }
         else
         {
            m_last_bos = BOS_BEARISH;
            LogPrint("SMC: BOS BEARISH detected - Price broke below ", m_last_swing_low);
         }
         m_last_bos_time = TimeCurrent();
         m_last_bos_level = m_last_swing_low;
      }
   }

   //+------------------------------------------------------------------+
   //| Scan for liquidity pools (equal highs/lows)                      |
   //+------------------------------------------------------------------+
   void ScanForLiquidityPools()
   {
      double high[], low[];
      datetime time[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(time, true);

      int bars = m_config.ob_lookback;
      if(CopyHigh(_Symbol, PERIOD_H1, 0, bars, high) <= 0) return;
      if(CopyLow(_Symbol, PERIOD_H1, 0, bars, low) <= 0) return;
      if(CopyTime(_Symbol, PERIOD_H1, 0, bars, time) <= 0) return;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double tolerance = m_config.liquidity_equal_tolerance * point;

      m_liquidity_count = 0;

      // Find equal highs
      for(int i = 0; i < bars - 1 && m_liquidity_count < 20; i++)
      {
         int touches = 1;
         datetime first_time = time[i];
         datetime last_time = time[i];

         for(int j = i + 1; j < bars; j++)
         {
            if(MathAbs(high[i] - high[j]) <= tolerance)
            {
               touches++;
               if(time[j] < first_time) first_time = time[j];
               if(time[j] > last_time) last_time = time[j];
            }
         }

         if(touches >= m_config.liquidity_min_touches)
         {
            m_liquidity_pools[m_liquidity_count].price = high[i];
            m_liquidity_pools[m_liquidity_count].is_high = true;
            m_liquidity_pools[m_liquidity_count].touch_count = touches;
            m_liquidity_pools[m_liquidity_count].first_touch = first_time;
            m_liquidity_pools[m_liquidity_count].last_touch = last_time;
            m_liquidity_pools[m_liquidity_count].is_swept = false;
            m_liquidity_pools[m_liquidity_count].strength = MathMin(100, touches * 20);
            m_liquidity_count++;
         }
      }

      // Find equal lows
      for(int i = 0; i < bars - 1 && m_liquidity_count < 20; i++)
      {
         int touches = 1;
         datetime first_time = time[i];
         datetime last_time = time[i];

         for(int j = i + 1; j < bars; j++)
         {
            if(MathAbs(low[i] - low[j]) <= tolerance)
            {
               touches++;
               if(time[j] < first_time) first_time = time[j];
               if(time[j] > last_time) last_time = time[j];
            }
         }

         if(touches >= m_config.liquidity_min_touches)
         {
            m_liquidity_pools[m_liquidity_count].price = low[i];
            m_liquidity_pools[m_liquidity_count].is_high = false;
            m_liquidity_pools[m_liquidity_count].touch_count = touches;
            m_liquidity_pools[m_liquidity_count].first_touch = first_time;
            m_liquidity_pools[m_liquidity_count].last_touch = last_time;
            m_liquidity_pools[m_liquidity_count].is_swept = false;
            m_liquidity_pools[m_liquidity_count].strength = MathMin(100, touches * 20);
            m_liquidity_count++;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Update liquidity pools (check for sweeps)                        |
   //+------------------------------------------------------------------+
   void UpdateLiquidityPools()
   {
      double current_high = iHigh(_Symbol, PERIOD_H1, 0);
      double current_low = iLow(_Symbol, PERIOD_H1, 0);

      for(int i = 0; i < m_liquidity_count; i++)
      {
         if(!m_liquidity_pools[i].is_swept)
         {
            // Check if high liquidity was swept
            if(m_liquidity_pools[i].is_high && current_high > m_liquidity_pools[i].price)
            {
               m_liquidity_pools[i].is_swept = true;
               LogPrint("SMC: Sell-side liquidity SWEPT at ", m_liquidity_pools[i].price);
            }

            // Check if low liquidity was swept
            if(!m_liquidity_pools[i].is_high && current_low < m_liquidity_pools[i].price)
            {
               m_liquidity_pools[i].is_swept = true;
               LogPrint("SMC: Buy-side liquidity SWEPT at ", m_liquidity_pools[i].price);
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check for recent liquidity sweep                                 |
   //+------------------------------------------------------------------+
   bool CheckRecentLiquiditySweep()
   {
      for(int i = 0; i < m_liquidity_count; i++)
      {
         if(m_liquidity_pools[i].is_swept)
            return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Invalidate mitigated zones                                       |
   //+------------------------------------------------------------------+
   void InvalidateMitigatedZones()
   {
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Check bullish OBs - invalidate if price closes below
      for(int i = 0; i < m_bullish_ob_count; i++)
      {
         if(m_bullish_obs[i].is_valid)
         {
            double close = iClose(_Symbol, PERIOD_H1, 0);
            if(close < m_bullish_obs[i].bottom)
            {
               m_bullish_obs[i].is_valid = false;
               LogPrint("SMC: Bullish OB INVALIDATED at ", m_bullish_obs[i].bottom);
            }
         }
      }

      // Check bearish OBs - invalidate if price closes above
      for(int i = 0; i < m_bearish_ob_count; i++)
      {
         if(m_bearish_obs[i].is_valid)
         {
            double close = iClose(_Symbol, PERIOD_H1, 0);
            if(close > m_bearish_obs[i].top)
            {
               m_bearish_obs[i].is_valid = false;
               LogPrint("SMC: Bearish OB INVALIDATED at ", m_bearish_obs[i].top);
            }
         }
      }

      // Mark FVGs as mitigated when price fills them
      for(int i = 0; i < m_bullish_fvg_count; i++)
      {
         if(m_bullish_fvgs[i].is_valid && current_price <= m_bullish_fvgs[i].bottom)
         {
            m_bullish_fvgs[i].is_valid = false;
         }
      }

      for(int i = 0; i < m_bearish_fvg_count; i++)
      {
         if(m_bearish_fvgs[i].is_valid && current_price >= m_bearish_fvgs[i].top)
         {
            m_bearish_fvgs[i].is_valid = false;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Remove expired zones                                             |
   //+------------------------------------------------------------------+
   void RemoveExpiredZones()
   {
      int current_bar = 0;

      // Remove old bullish OBs
      for(int i = m_bullish_ob_count - 1; i >= 0; i--)
      {
         if(current_bar - m_bullish_obs[i].formed_bar > m_config.zone_max_age_bars)
         {
            // Shift array
            for(int j = i; j < m_bullish_ob_count - 1; j++)
               m_bullish_obs[j] = m_bullish_obs[j+1];
            m_bullish_ob_count--;
         }
      }

      // Remove old bearish OBs
      for(int i = m_bearish_ob_count - 1; i >= 0; i--)
      {
         if(current_bar - m_bearish_obs[i].formed_bar > m_config.zone_max_age_bars)
         {
            for(int j = i; j < m_bearish_ob_count - 1; j++)
               m_bearish_obs[j] = m_bearish_obs[j+1];
            m_bearish_ob_count--;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Add bullish order block                                          |
   //+------------------------------------------------------------------+
   void AddBullishOB(double bottom, double top, datetime time, int bar)
   {
      if(m_bullish_ob_count >= 20) return;

      m_bullish_obs[m_bullish_ob_count].type = SMC_ZONE_BULLISH_OB;
      m_bullish_obs[m_bullish_ob_count].bottom = bottom;
      m_bullish_obs[m_bullish_ob_count].top = top;
      m_bullish_obs[m_bullish_ob_count].formed_time = time;
      m_bullish_obs[m_bullish_ob_count].formed_bar = bar;
      m_bullish_obs[m_bullish_ob_count].is_valid = true;
      m_bullish_obs[m_bullish_ob_count].touch_count = 0;
      m_bullish_obs[m_bullish_ob_count].strength = 70;
      m_bullish_obs[m_bullish_ob_count].timeframe = PERIOD_H1;
      m_bullish_ob_count++;
   }

   //+------------------------------------------------------------------+
   //| Add bearish order block                                          |
   //+------------------------------------------------------------------+
   void AddBearishOB(double bottom, double top, datetime time, int bar)
   {
      if(m_bearish_ob_count >= 20) return;

      m_bearish_obs[m_bearish_ob_count].type = SMC_ZONE_BEARISH_OB;
      m_bearish_obs[m_bearish_ob_count].bottom = bottom;
      m_bearish_obs[m_bearish_ob_count].top = top;
      m_bearish_obs[m_bearish_ob_count].formed_time = time;
      m_bearish_obs[m_bearish_ob_count].formed_bar = bar;
      m_bearish_obs[m_bearish_ob_count].is_valid = true;
      m_bearish_obs[m_bearish_ob_count].touch_count = 0;
      m_bearish_obs[m_bearish_ob_count].strength = 70;
      m_bearish_obs[m_bearish_ob_count].timeframe = PERIOD_H1;
      m_bearish_ob_count++;
   }

   //+------------------------------------------------------------------+
   //| Add bullish FVG                                                  |
   //+------------------------------------------------------------------+
   void AddBullishFVG(double bottom, double top, datetime time, int bar)
   {
      if(m_bullish_fvg_count >= 20) return;

      m_bullish_fvgs[m_bullish_fvg_count].type = SMC_ZONE_BULLISH_FVG;
      m_bullish_fvgs[m_bullish_fvg_count].bottom = bottom;
      m_bullish_fvgs[m_bullish_fvg_count].top = top;
      m_bullish_fvgs[m_bullish_fvg_count].formed_time = time;
      m_bullish_fvgs[m_bullish_fvg_count].formed_bar = bar;
      m_bullish_fvgs[m_bullish_fvg_count].is_valid = true;
      m_bullish_fvgs[m_bullish_fvg_count].touch_count = 0;
      m_bullish_fvgs[m_bullish_fvg_count].strength = 50;
      m_bullish_fvgs[m_bullish_fvg_count].timeframe = PERIOD_H1;
      m_bullish_fvg_count++;
   }

   //+------------------------------------------------------------------+
   //| Add bearish FVG                                                  |
   //+------------------------------------------------------------------+
   void AddBearishFVG(double bottom, double top, datetime time, int bar)
   {
      if(m_bearish_fvg_count >= 20) return;

      m_bearish_fvgs[m_bearish_fvg_count].type = SMC_ZONE_BEARISH_FVG;
      m_bearish_fvgs[m_bearish_fvg_count].bottom = bottom;
      m_bearish_fvgs[m_bearish_fvg_count].top = top;
      m_bearish_fvgs[m_bearish_fvg_count].formed_time = time;
      m_bearish_fvgs[m_bearish_fvg_count].formed_bar = bar;
      m_bearish_fvgs[m_bearish_fvg_count].is_valid = true;
      m_bearish_fvgs[m_bearish_fvg_count].touch_count = 0;
      m_bearish_fvgs[m_bearish_fvg_count].strength = 50;
      m_bearish_fvgs[m_bearish_fvg_count].timeframe = PERIOD_H1;
      m_bearish_fvg_count++;
   }

   //+------------------------------------------------------------------+
   //| Check if zone already exists                                     |
   //+------------------------------------------------------------------+
   bool ZoneExists(double bottom, double top, bool is_bullish)
   {
      double tolerance = GetCurrentATR() * 0.2;

      if(is_bullish)
      {
         for(int i = 0; i < m_bullish_ob_count; i++)
         {
            if(MathAbs(m_bullish_obs[i].bottom - bottom) < tolerance &&
               MathAbs(m_bullish_obs[i].top - top) < tolerance)
               return true;
         }
      }
      else
      {
         for(int i = 0; i < m_bearish_ob_count; i++)
         {
            if(MathAbs(m_bearish_obs[i].bottom - bottom) < tolerance &&
               MathAbs(m_bearish_obs[i].top - top) < tolerance)
               return true;
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Check if FVG already exists                                      |
   //+------------------------------------------------------------------+
   bool FVGExists(double bottom, double top, bool is_bullish)
   {
      double tolerance = GetCurrentATR() * 0.1;

      if(is_bullish)
      {
         for(int i = 0; i < m_bullish_fvg_count; i++)
         {
            if(MathAbs(m_bullish_fvgs[i].bottom - bottom) < tolerance &&
               MathAbs(m_bullish_fvgs[i].top - top) < tolerance)
               return true;
         }
      }
      else
      {
         for(int i = 0; i < m_bearish_fvg_count; i++)
         {
            if(MathAbs(m_bearish_fvgs[i].bottom - bottom) < tolerance &&
               MathAbs(m_bearish_fvgs[i].top - top) < tolerance)
               return true;
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Find nearest zone below price                                    |
   //+------------------------------------------------------------------+
   SSMCZone FindNearestZoneBelow(double price, bool is_bullish)
   {
      SSMCZone nearest;
      nearest.is_valid = false;
      double min_distance = DBL_MAX;

      if(is_bullish)
      {
         for(int i = 0; i < m_bullish_ob_count; i++)
         {
            if(m_bullish_obs[i].is_valid && m_bullish_obs[i].top < price)
            {
               double distance = price - m_bullish_obs[i].top;
               if(distance < min_distance)
               {
                  min_distance = distance;
                  nearest = m_bullish_obs[i];
               }
            }
         }
      }
      else
      {
         for(int i = 0; i < m_bearish_ob_count; i++)
         {
            if(m_bearish_obs[i].is_valid && m_bearish_obs[i].top < price)
            {
               double distance = price - m_bearish_obs[i].top;
               if(distance < min_distance)
               {
                  min_distance = distance;
                  nearest = m_bearish_obs[i];
               }
            }
         }
      }

      return nearest;
   }

   //+------------------------------------------------------------------+
   //| Find nearest zone above price                                    |
   //+------------------------------------------------------------------+
   SSMCZone FindNearestZoneAbove(double price, bool is_bearish)
   {
      SSMCZone nearest;
      nearest.is_valid = false;
      double min_distance = DBL_MAX;

      if(is_bearish)
      {
         for(int i = 0; i < m_bearish_ob_count; i++)
         {
            if(m_bearish_obs[i].is_valid && m_bearish_obs[i].bottom > price)
            {
               double distance = m_bearish_obs[i].bottom - price;
               if(distance < min_distance)
               {
                  min_distance = distance;
                  nearest = m_bearish_obs[i];
               }
            }
         }
      }
      else
      {
         for(int i = 0; i < m_bullish_ob_count; i++)
         {
            if(m_bullish_obs[i].is_valid && m_bullish_obs[i].bottom > price)
            {
               double distance = m_bullish_obs[i].bottom - price;
               if(distance < min_distance)
               {
                  min_distance = distance;
                  nearest = m_bullish_obs[i];
               }
            }
         }
      }

      return nearest;
   }

   //+------------------------------------------------------------------+
   //| Find nearest liquidity below                                     |
   //+------------------------------------------------------------------+
   SLiquidityPool FindNearestLiquidityBelow(double price)
   {
      SLiquidityPool nearest;
      nearest.price = 0;
      nearest.touch_count = 0;
      double min_distance = DBL_MAX;

      for(int i = 0; i < m_liquidity_count; i++)
      {
         if(!m_liquidity_pools[i].is_high &&  // Equal lows (buy-side liquidity)
            m_liquidity_pools[i].price < price &&
            !m_liquidity_pools[i].is_swept)
         {
            double distance = price - m_liquidity_pools[i].price;
            if(distance < min_distance)
            {
               min_distance = distance;
               nearest = m_liquidity_pools[i];
            }
         }
      }

      return nearest;
   }

   //+------------------------------------------------------------------+
   //| Find nearest liquidity above                                     |
   //+------------------------------------------------------------------+
   SLiquidityPool FindNearestLiquidityAbove(double price)
   {
      SLiquidityPool nearest;
      nearest.price = 0;
      nearest.touch_count = 0;
      double min_distance = DBL_MAX;

      for(int i = 0; i < m_liquidity_count; i++)
      {
         if(m_liquidity_pools[i].is_high &&  // Equal highs (sell-side liquidity)
            m_liquidity_pools[i].price > price &&
            !m_liquidity_pools[i].is_swept)
         {
            double distance = m_liquidity_pools[i].price - price;
            if(distance < min_distance)
            {
               min_distance = distance;
               nearest = m_liquidity_pools[i];
            }
         }
      }

      return nearest;
   }

   //+------------------------------------------------------------------+
   //| Calculate overall SMC score                                      |
   //+------------------------------------------------------------------+
   int CalculateSMCScore(SSMCAnalysis &analysis)
   {
      int score = 0;

      // Order Block positioning
      if(analysis.in_bullish_ob) score += 30;
      if(analysis.in_bearish_ob) score -= 30;

      // FVG positioning
      if(analysis.in_bullish_fvg) score += 20;
      if(analysis.in_bearish_fvg) score -= 20;

      // Break of structure
      if(analysis.recent_bos == BOS_BULLISH) score += 25;
      if(analysis.recent_bos == BOS_BEARISH) score -= 25;
      if(analysis.recent_bos == CHOCH_BULLISH) score += 35;
      if(analysis.recent_bos == CHOCH_BEARISH) score -= 35;

      // Liquidity sweep (context dependent)
      // Note: A sweep typically precedes reversal, so we need current price action

      // Clamp to -100 to +100
      score = MathMax(-100, MathMin(100, score));

      return score;
   }

   //+------------------------------------------------------------------+
   //| Get current ATR                                                  |
   //+------------------------------------------------------------------+
   double GetCurrentATR()
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(m_handle_atr, 0, 0, 1, atr_buffer) <= 0)
         return 10.0;  // Default fallback for gold

      return atr_buffer[0];
   }
};
