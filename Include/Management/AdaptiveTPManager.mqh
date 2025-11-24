//+------------------------------------------------------------------+
//| AdaptiveTPManager.mqh                                            |
//| Adaptive Take Profit Management System                           |
//| v1.0 - Dynamic TP calculation based on market conditions        |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| Adaptive TP Configuration Structure                              |
//+------------------------------------------------------------------+
struct SAdaptiveTPConfig
{
   // Volatility-based multipliers
   double   low_vol_tp1_mult;       // TP1 multiplier in low volatility (default 1.5)
   double   low_vol_tp2_mult;       // TP2 multiplier in low volatility (default 2.5)
   double   normal_vol_tp1_mult;    // TP1 multiplier in normal volatility (default 2.0)
   double   normal_vol_tp2_mult;    // TP2 multiplier in normal volatility (default 3.5)
   double   high_vol_tp1_mult;      // TP1 multiplier in high volatility (default 2.5)
   double   high_vol_tp2_mult;      // TP2 multiplier in high volatility (default 5.0)

   // Trend strength adjustments
   double   strong_trend_tp_boost;  // Additional multiplier for strong trends (default 1.3)
   double   weak_trend_tp_cut;      // Reduction for weak trends (default 0.8)

   // Structure-based targeting
   bool     use_structure_targets;  // Use S/R levels for TP targets
   double   structure_tp1_pct;      // % of distance to next level for TP1 (default 0.75)
   double   structure_tp2_pct;      // % of distance to next level for TP2 (default 1.0)

   // ADX thresholds
   double   strong_trend_adx;       // ADX level for strong trend (default 35)
   double   weak_trend_adx;         // ADX level for weak trend (default 20)

   // ATR percentile thresholds
   double   low_vol_atr_pct;        // ATR percentile for low vol (default 0.7)
   double   high_vol_atr_pct;       // ATR percentile for high vol (default 1.3)
};

//+------------------------------------------------------------------+
//| Adaptive TP Result Structure                                     |
//+------------------------------------------------------------------+
struct SAdaptiveTPResult
{
   double   tp1;                    // Calculated TP1 price
   double   tp2;                    // Calculated TP2 price
   double   tp1_multiplier;         // Final TP1 multiplier used
   double   tp2_multiplier;         // Final TP2 multiplier used
   string   tp_mode;                // Description of TP mode used
   double   next_resistance;        // Detected resistance level (for longs)
   double   next_support;           // Detected support level (for shorts)
};

//+------------------------------------------------------------------+
//| Adaptive TP Manager Class                                        |
//+------------------------------------------------------------------+
class CAdaptiveTPManager
{
private:
   SAdaptiveTPConfig    m_config;

   // Indicator handles
   int                  m_handle_atr_h1;
   int                  m_handle_atr_h4;
   int                  m_handle_adx_h4;

   // Cached ATR values for percentile calculation
   double               m_atr_history[];
   int                  m_atr_history_size;
   double               m_atr_average;

   // Fallback TP multipliers (original values)
   double               m_fallback_tp1;
   double               m_fallback_tp2;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CAdaptiveTPManager(double fallback_tp1 = 1.3, double fallback_tp2 = 1.8)
   {
      m_fallback_tp1 = fallback_tp1;
      m_fallback_tp2 = fallback_tp2;

      // Initialize default configuration
      m_config.low_vol_tp1_mult = 1.5;
      m_config.low_vol_tp2_mult = 2.5;
      m_config.normal_vol_tp1_mult = 2.0;
      m_config.normal_vol_tp2_mult = 3.5;
      m_config.high_vol_tp1_mult = 2.5;
      m_config.high_vol_tp2_mult = 5.0;

      m_config.strong_trend_tp_boost = 1.3;
      m_config.weak_trend_tp_cut = 0.8;

      m_config.use_structure_targets = true;
      m_config.structure_tp1_pct = 0.75;
      m_config.structure_tp2_pct = 1.0;

      m_config.strong_trend_adx = 35.0;
      m_config.weak_trend_adx = 20.0;

      m_config.low_vol_atr_pct = 0.7;
      m_config.high_vol_atr_pct = 1.3;

      m_atr_history_size = 50;
      ArrayResize(m_atr_history, m_atr_history_size);
      ArrayInitialize(m_atr_history, 0);
      m_atr_average = 0;
   }

   //+------------------------------------------------------------------+
   //| Configure with custom parameters                                  |
   //+------------------------------------------------------------------+
   void Configure(double low_tp1, double low_tp2, double norm_tp1, double norm_tp2,
                  double high_tp1, double high_tp2, double trend_boost, double trend_cut,
                  bool use_structure, double struct_tp1_pct, double struct_tp2_pct,
                  double strong_adx, double weak_adx, double low_atr_pct, double high_atr_pct)
   {
      m_config.low_vol_tp1_mult = low_tp1;
      m_config.low_vol_tp2_mult = low_tp2;
      m_config.normal_vol_tp1_mult = norm_tp1;
      m_config.normal_vol_tp2_mult = norm_tp2;
      m_config.high_vol_tp1_mult = high_tp1;
      m_config.high_vol_tp2_mult = high_tp2;

      m_config.strong_trend_tp_boost = trend_boost;
      m_config.weak_trend_tp_cut = trend_cut;

      m_config.use_structure_targets = use_structure;
      m_config.structure_tp1_pct = struct_tp1_pct;
      m_config.structure_tp2_pct = struct_tp2_pct;

      m_config.strong_trend_adx = strong_adx;
      m_config.weak_trend_adx = weak_adx;

      m_config.low_vol_atr_pct = low_atr_pct;
      m_config.high_vol_atr_pct = high_atr_pct;
   }

   //+------------------------------------------------------------------+
   //| Initialize indicator handles                                      |
   //+------------------------------------------------------------------+
   bool Init()
   {
      m_handle_atr_h1 = iATR(_Symbol, PERIOD_H1, 14);
      m_handle_atr_h4 = iATR(_Symbol, PERIOD_H4, 14);
      m_handle_adx_h4 = iADX(_Symbol, PERIOD_H4, 14);

      if(m_handle_atr_h1 == INVALID_HANDLE ||
         m_handle_atr_h4 == INVALID_HANDLE ||
         m_handle_adx_h4 == INVALID_HANDLE)
      {
         LogPrint("ERROR: AdaptiveTPManager failed to create indicators");
         return false;
      }

      // Initialize ATR history
      UpdateATRHistory();

      LogPrint("AdaptiveTPManager initialized successfully");
      LogPrint("  Low Vol TPs: ", m_config.low_vol_tp1_mult, "x / ", m_config.low_vol_tp2_mult, "x");
      LogPrint("  Normal Vol TPs: ", m_config.normal_vol_tp1_mult, "x / ", m_config.normal_vol_tp2_mult, "x");
      LogPrint("  High Vol TPs: ", m_config.high_vol_tp1_mult, "x / ", m_config.high_vol_tp2_mult, "x");
      LogPrint("  Structure Targeting: ", m_config.use_structure_targets ? "ENABLED" : "DISABLED");

      return true;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CAdaptiveTPManager()
   {
      if(m_handle_atr_h1 != INVALID_HANDLE) IndicatorRelease(m_handle_atr_h1);
      if(m_handle_atr_h4 != INVALID_HANDLE) IndicatorRelease(m_handle_atr_h4);
      if(m_handle_adx_h4 != INVALID_HANDLE) IndicatorRelease(m_handle_adx_h4);
   }

   //+------------------------------------------------------------------+
   //| Calculate adaptive TPs for a trade                               |
   //+------------------------------------------------------------------+
   SAdaptiveTPResult CalculateAdaptiveTPs(ENUM_SIGNAL_TYPE signal, double entry_price,
                                          double stop_loss, ENUM_REGIME_TYPE regime,
                                          ENUM_PATTERN_TYPE pattern_type)
   {
      SAdaptiveTPResult result;
      result.tp1 = 0;
      result.tp2 = 0;
      result.tp_mode = "Fallback";
      result.next_resistance = 0;
      result.next_support = 0;

      // Calculate risk distance
      double risk_distance = MathAbs(entry_price - stop_loss);
      if(risk_distance <= 0)
      {
         LogPrint("ERROR: Invalid risk distance for adaptive TP calculation");
         result.tp1_multiplier = m_fallback_tp1;
         result.tp2_multiplier = m_fallback_tp2;
         ApplyMultipliersToResult(result, signal, entry_price, risk_distance);
         return result;
      }

      // Update ATR history
      UpdateATRHistory();

      // Get current market metrics
      double current_atr = GetCurrentATR();
      double current_adx = GetCurrentADX();
      double atr_ratio = (m_atr_average > 0) ? current_atr / m_atr_average : 1.0;

      LogPrint("AdaptiveTP Analysis:");
      LogPrint("  ATR: ", DoubleToString(current_atr, 2), " | ATR Avg: ", DoubleToString(m_atr_average, 2),
               " | Ratio: ", DoubleToString(atr_ratio, 2));
      LogPrint("  ADX: ", DoubleToString(current_adx, 1), " | Regime: ", EnumToString(regime));

      // Step 1: Determine base multipliers from volatility
      double base_tp1_mult = 0;
      double base_tp2_mult = 0;

      if(atr_ratio <= m_config.low_vol_atr_pct)
      {
         // Low volatility - conservative targets
         base_tp1_mult = m_config.low_vol_tp1_mult;
         base_tp2_mult = m_config.low_vol_tp2_mult;
         result.tp_mode = "LowVol";
         LogPrint("  Volatility Mode: LOW (ATR ratio ", DoubleToString(atr_ratio, 2), " <= ", m_config.low_vol_atr_pct, ")");
      }
      else if(atr_ratio >= m_config.high_vol_atr_pct)
      {
         // High volatility - extended targets
         base_tp1_mult = m_config.high_vol_tp1_mult;
         base_tp2_mult = m_config.high_vol_tp2_mult;
         result.tp_mode = "HighVol";
         LogPrint("  Volatility Mode: HIGH (ATR ratio ", DoubleToString(atr_ratio, 2), " >= ", m_config.high_vol_atr_pct, ")");
      }
      else
      {
         // Normal volatility - standard targets
         base_tp1_mult = m_config.normal_vol_tp1_mult;
         base_tp2_mult = m_config.normal_vol_tp2_mult;
         result.tp_mode = "NormalVol";
         LogPrint("  Volatility Mode: NORMAL");
      }

      // Step 2: Apply trend strength adjustment
      double trend_adjustment = 1.0;

      if(current_adx >= m_config.strong_trend_adx)
      {
         // Strong trend - extend targets
         trend_adjustment = m_config.strong_trend_tp_boost;
         result.tp_mode += "+StrongTrend";
         LogPrint("  Trend Adjustment: STRONG (+", DoubleToString((trend_adjustment - 1.0) * 100, 0), "%)");
      }
      else if(current_adx <= m_config.weak_trend_adx)
      {
         // Weak trend - reduce targets
         trend_adjustment = m_config.weak_trend_tp_cut;
         result.tp_mode += "+WeakTrend";
         LogPrint("  Trend Adjustment: WEAK (-", DoubleToString((1.0 - trend_adjustment) * 100, 0), "%)");
      }

      // Step 3: Apply regime-specific adjustments
      double regime_adjustment = 1.0;

      switch(regime)
      {
         case REGIME_TRENDING:
            // Trending - allow extended runs
            regime_adjustment = 1.15;
            result.tp_mode += "+Trending";
            break;

         case REGIME_VOLATILE:
            // Volatile - quick profits
            regime_adjustment = 0.9;
            result.tp_mode += "+Volatile";
            break;

         case REGIME_RANGING:
            // Ranging - conservative targets
            regime_adjustment = 0.85;
            result.tp_mode += "+Ranging";
            break;

         case REGIME_CHOPPY:
            // Choppy - very conservative
            regime_adjustment = 0.75;
            result.tp_mode += "+Choppy";
            break;

         default:
            regime_adjustment = 1.0;
            break;
      }

      // Step 4: Apply pattern-specific adjustments
      double pattern_adjustment = GetPatternAdjustment(pattern_type);

      // Step 5: Calculate final multipliers
      result.tp1_multiplier = base_tp1_mult * trend_adjustment * regime_adjustment * pattern_adjustment;
      result.tp2_multiplier = base_tp2_mult * trend_adjustment * regime_adjustment * pattern_adjustment;

      // Ensure minimum R:R ratios
      if(result.tp1_multiplier < 1.2) result.tp1_multiplier = 1.2;
      if(result.tp2_multiplier < 1.5) result.tp2_multiplier = 1.5;

      // Ensure TP2 > TP1
      if(result.tp2_multiplier <= result.tp1_multiplier)
         result.tp2_multiplier = result.tp1_multiplier + 0.5;

      LogPrint("  Final Multipliers: TP1=", DoubleToString(result.tp1_multiplier, 2),
               "x | TP2=", DoubleToString(result.tp2_multiplier, 2), "x");

      // Step 6: Check for structure-based targets
      if(m_config.use_structure_targets)
      {
         double structure_tp1 = 0, structure_tp2 = 0;

         if(signal == SIGNAL_LONG)
         {
            double next_resistance = FindNextResistance(entry_price);
            result.next_resistance = next_resistance;

            if(next_resistance > entry_price)
            {
               double distance_to_level = next_resistance - entry_price;
               structure_tp1 = entry_price + (distance_to_level * m_config.structure_tp1_pct);
               structure_tp2 = next_resistance;

               // Use structure targets if they're better
               double struct_tp1_mult = (structure_tp1 - entry_price) / risk_distance;
               double struct_tp2_mult = (structure_tp2 - entry_price) / risk_distance;

               if(struct_tp1_mult >= 1.2 && struct_tp2_mult >= result.tp1_multiplier)
               {
                  LogPrint("  Structure Target Found: Resistance at ", DoubleToString(next_resistance, 2));
                  LogPrint("  Structure TPs: ", DoubleToString(struct_tp1_mult, 2), "x / ",
                           DoubleToString(struct_tp2_mult, 2), "x");

                  // Blend structure with volatility-based targets
                  result.tp1_multiplier = (result.tp1_multiplier + struct_tp1_mult) / 2.0;
                  result.tp2_multiplier = MathMax(result.tp2_multiplier, struct_tp2_mult);
                  result.tp_mode += "+Structure";
               }
            }
         }
         else if(signal == SIGNAL_SHORT)
         {
            double next_support = FindNextSupport(entry_price);
            result.next_support = next_support;

            if(next_support < entry_price && next_support > 0)
            {
               double distance_to_level = entry_price - next_support;
               structure_tp1 = entry_price - (distance_to_level * m_config.structure_tp1_pct);
               structure_tp2 = next_support;

               // Use structure targets if they're better
               double struct_tp1_mult = (entry_price - structure_tp1) / risk_distance;
               double struct_tp2_mult = (entry_price - structure_tp2) / risk_distance;

               if(struct_tp1_mult >= 1.2 && struct_tp2_mult >= result.tp1_multiplier)
               {
                  LogPrint("  Structure Target Found: Support at ", DoubleToString(next_support, 2));
                  LogPrint("  Structure TPs: ", DoubleToString(struct_tp1_mult, 2), "x / ",
                           DoubleToString(struct_tp2_mult, 2), "x");

                  // Blend structure with volatility-based targets
                  result.tp1_multiplier = (result.tp1_multiplier + struct_tp1_mult) / 2.0;
                  result.tp2_multiplier = MathMax(result.tp2_multiplier, struct_tp2_mult);
                  result.tp_mode += "+Structure";
               }
            }
         }
      }

      // Step 7: Apply final multipliers to calculate actual prices
      ApplyMultipliersToResult(result, signal, entry_price, risk_distance);

      LogPrint("  Adaptive TP Result: TP1=", DoubleToString(result.tp1, 2),
               " | TP2=", DoubleToString(result.tp2, 2), " | Mode=", result.tp_mode);

      return result;
   }

   //+------------------------------------------------------------------+
   //| Get current ATR value                                            |
   //+------------------------------------------------------------------+
   double GetCurrentATR()
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(m_handle_atr_h1, 0, 0, 1, atr_buffer) <= 0)
         return 0.0;

      return atr_buffer[0];
   }

   //+------------------------------------------------------------------+
   //| Get current ADX value                                            |
   //+------------------------------------------------------------------+
   double GetCurrentADX()
   {
      double adx_buffer[];
      ArraySetAsSeries(adx_buffer, true);

      if(CopyBuffer(m_handle_adx_h4, 0, 0, 1, adx_buffer) <= 0)
         return 25.0; // Default neutral value

      return adx_buffer[0];
   }

   //+------------------------------------------------------------------+
   //| Get configuration for external access                            |
   //+------------------------------------------------------------------+
   SAdaptiveTPConfig GetConfig() { return m_config; }

private:
   //+------------------------------------------------------------------+
   //| Update ATR history for average calculation                       |
   //+------------------------------------------------------------------+
   void UpdateATRHistory()
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(m_handle_atr_h1, 0, 0, m_atr_history_size, atr_buffer) > 0)
      {
         double sum = 0;
         for(int i = 0; i < m_atr_history_size; i++)
         {
            m_atr_history[i] = atr_buffer[i];
            sum += atr_buffer[i];
         }
         m_atr_average = sum / m_atr_history_size;
      }
   }

   //+------------------------------------------------------------------+
   //| Get pattern-specific TP adjustment                               |
   //+------------------------------------------------------------------+
   double GetPatternAdjustment(ENUM_PATTERN_TYPE pattern)
   {
      switch(pattern)
      {
         // Mean reversion patterns - conservative targets
         case PATTERN_BB_MEAN_REVERSION:
            return 0.8;  // Mean reversion targets middle, don't overshoot

         case PATTERN_RANGE_BOX:
            return 0.85; // Range trading has defined boundaries

         case PATTERN_FALSE_BREAKOUT_FADE:
            return 0.9;  // Fades often reverse quickly

         // Trend-following patterns - can extend
         case PATTERN_MA_CROSS_ANOMALY:
            return 1.2;  // MA crosses can run

         case PATTERN_LIQUIDITY_SWEEP:
            return 1.15; // Sweeps often trigger trends

         case PATTERN_ENGULFING:
            return 1.1;  // Strong reversal signal

         case PATTERN_PIN_BAR:
            return 1.05; // Moderate extension

         case PATTERN_SR_BOUNCE:
            return 1.0;  // Standard targets

         default:
            return 1.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Find next resistance level above price                           |
   //+------------------------------------------------------------------+
   double FindNextResistance(double current_price)
   {
      double high[];
      ArraySetAsSeries(high, true);

      // Get H4 highs for structure detection
      if(CopyHigh(_Symbol, PERIOD_H4, 0, 100, high) <= 0)
         return 0;

      // Find swing highs above current price
      double resistance_levels[];
      ArrayResize(resistance_levels, 0);

      for(int i = 2; i < 98; i++)
      {
         // Swing high detection (higher than 2 bars on each side)
         if(high[i] > high[i-1] && high[i] > high[i-2] &&
            high[i] > high[i+1] && high[i] > high[i+2])
         {
            if(high[i] > current_price)
            {
               int size = ArraySize(resistance_levels);
               ArrayResize(resistance_levels, size + 1);
               resistance_levels[size] = high[i];
            }
         }
      }

      // Find the nearest resistance
      if(ArraySize(resistance_levels) == 0)
         return 0;

      double nearest = resistance_levels[0];
      for(int i = 1; i < ArraySize(resistance_levels); i++)
      {
         if(resistance_levels[i] < nearest && resistance_levels[i] > current_price)
            nearest = resistance_levels[i];
      }

      return nearest;
   }

   //+------------------------------------------------------------------+
   //| Find next support level below price                              |
   //+------------------------------------------------------------------+
   double FindNextSupport(double current_price)
   {
      double low[];
      ArraySetAsSeries(low, true);

      // Get H4 lows for structure detection
      if(CopyLow(_Symbol, PERIOD_H4, 0, 100, low) <= 0)
         return 0;

      // Find swing lows below current price
      double support_levels[];
      ArrayResize(support_levels, 0);

      for(int i = 2; i < 98; i++)
      {
         // Swing low detection (lower than 2 bars on each side)
         if(low[i] < low[i-1] && low[i] < low[i-2] &&
            low[i] < low[i+1] && low[i] < low[i+2])
         {
            if(low[i] < current_price)
            {
               int size = ArraySize(support_levels);
               ArrayResize(support_levels, size + 1);
               support_levels[size] = low[i];
            }
         }
      }

      // Find the nearest support
      if(ArraySize(support_levels) == 0)
         return 0;

      double nearest = support_levels[0];
      for(int i = 1; i < ArraySize(support_levels); i++)
      {
         if(support_levels[i] > nearest && support_levels[i] < current_price)
            nearest = support_levels[i];
      }

      return nearest;
   }

   //+------------------------------------------------------------------+
   //| Apply calculated multipliers to get actual TP prices             |
   //+------------------------------------------------------------------+
   void ApplyMultipliersToResult(SAdaptiveTPResult &result, ENUM_SIGNAL_TYPE signal,
                                  double entry_price, double risk_distance)
   {
      if(signal == SIGNAL_LONG)
      {
         result.tp1 = NormalizePrice(entry_price + (risk_distance * result.tp1_multiplier));
         result.tp2 = NormalizePrice(entry_price + (risk_distance * result.tp2_multiplier));
      }
      else if(signal == SIGNAL_SHORT)
      {
         result.tp1 = NormalizePrice(entry_price - (risk_distance * result.tp1_multiplier));
         result.tp2 = NormalizePrice(entry_price - (risk_distance * result.tp2_multiplier));
      }
   }
};
