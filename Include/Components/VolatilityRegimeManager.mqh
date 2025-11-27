//+------------------------------------------------------------------+
//| VolatilityRegimeManager.mqh                                       |
//| Enhancement 6: Volatility-Based Regime Risk Management            |
//| Adjusts risk based on current vs historical volatility            |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| Volatility Regime Enumeration                                     |
//+------------------------------------------------------------------+
enum ENUM_VOLATILITY_REGIME
{
   VOL_REGIME_VERY_LOW,     // ATR < 50th percentile - reduce risk, tighter TPs
   VOL_REGIME_LOW,          // ATR 50-70th percentile - slightly conservative
   VOL_REGIME_NORMAL,       // ATR 70-100th percentile - standard risk
   VOL_REGIME_HIGH,         // ATR 100-130th percentile - normal or slight boost
   VOL_REGIME_EXTREME       // ATR > 130th percentile - reduce risk (too chaotic)
};

//+------------------------------------------------------------------+
//| Volatility Regime Configuration                                   |
//+------------------------------------------------------------------+
struct SVolatilityRegimeConfig
{
   // ATR percentile thresholds (relative to 50-bar average)
   double   very_low_threshold;      // Below this = VERY_LOW (default 0.5)
   double   low_threshold;           // Below this = LOW (default 0.7)
   double   normal_threshold;        // Below this = NORMAL (default 1.0)
   double   high_threshold;          // Below this = HIGH (default 1.3)
   // Above high_threshold = EXTREME

   // Risk multipliers per regime
   double   very_low_risk_mult;      // Risk multiplier for very low vol (default 0.7)
   double   low_risk_mult;           // Risk multiplier for low vol (default 0.85)
   double   normal_risk_mult;        // Risk multiplier for normal vol (default 1.0)
   double   high_risk_mult;          // Risk multiplier for high vol (default 1.0)
   double   extreme_risk_mult;       // Risk multiplier for extreme vol (default 0.6)

   // Volatility expansion detection
   double   expansion_threshold;     // % increase from prev bar to detect expansion (default 1.5)
   double   expansion_risk_cut;      // Risk cut when vol expanding rapidly (default 0.7)

   // Volatility contraction bonus
   double   contraction_threshold;   // % decrease to detect contraction (default 0.7)
   double   contraction_risk_boost;  // Risk boost during contraction (default 1.1)

   // Stop loss tightening in high volatility
   bool     enable_sl_adjust;        // Enable SL tightening (default true)
   double   high_vol_sl_mult;        // SL multiplier in high vol (default 0.85)
   double   extreme_vol_sl_mult;     // SL multiplier in extreme vol (default 0.70)
   double   expansion_sl_mult;       // SL multiplier when vol expanding (default 0.75)
};

//+------------------------------------------------------------------+
//| Volatility Regime Analysis Result                                 |
//+------------------------------------------------------------------+
struct SVolatilityAnalysis
{
   ENUM_VOLATILITY_REGIME regime;
   double   current_atr;
   double   average_atr;
   double   atr_ratio;              // current / average
   double   risk_multiplier;        // Final multiplier to apply
   double   sl_multiplier;          // Stop loss ATR multiplier adjustment
   bool     is_expanding;           // Volatility rapidly expanding
   bool     is_contracting;         // Volatility contracting (good for entries)
   string   regime_description;
};

//+------------------------------------------------------------------+
//| Volatility Regime Manager Class                                   |
//+------------------------------------------------------------------+
class CVolatilityRegimeManager
{
private:
   SVolatilityRegimeConfig  m_config;

   // Indicator handles
   int                      m_handle_atr_h1;
   int                      m_handle_atr_h4;
   int                      m_handle_adx_h4;

   // Historical ATR data
   double                   m_atr_history[];
   int                      m_history_size;
   double                   m_atr_average;
   double                   m_atr_prev;

   // Current analysis
   SVolatilityAnalysis      m_current_analysis;
   datetime                 m_last_update;

   bool                     m_enabled;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CVolatilityRegimeManager()
   {
      m_enabled = true;
      m_history_size = 50;
      m_atr_average = 0;
      m_atr_prev = 0;
      m_last_update = 0;

      // Initialize default configuration
      m_config.very_low_threshold = 0.5;
      m_config.low_threshold = 0.7;
      m_config.normal_threshold = 1.0;
      m_config.high_threshold = 1.3;

      m_config.very_low_risk_mult = 0.7;
      m_config.low_risk_mult = 0.85;
      m_config.normal_risk_mult = 1.0;
      m_config.high_risk_mult = 1.0;
      m_config.extreme_risk_mult = 0.6;

      m_config.expansion_threshold = 1.5;
      m_config.expansion_risk_cut = 0.7;
      m_config.contraction_threshold = 0.7;
      m_config.contraction_risk_boost = 1.1;

      // Stop loss tightening defaults
      m_config.enable_sl_adjust = true;
      m_config.high_vol_sl_mult = 0.85;
      m_config.extreme_vol_sl_mult = 0.70;
      m_config.expansion_sl_mult = 0.75;

      ArrayResize(m_atr_history, m_history_size);
      ArrayInitialize(m_atr_history, 0);
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CVolatilityRegimeManager()
   {
      if(m_handle_atr_h1 != INVALID_HANDLE) IndicatorRelease(m_handle_atr_h1);
      if(m_handle_atr_h4 != INVALID_HANDLE) IndicatorRelease(m_handle_atr_h4);
      if(m_handle_adx_h4 != INVALID_HANDLE) IndicatorRelease(m_handle_adx_h4);
   }

   //+------------------------------------------------------------------+
   //| Configure with custom parameters                                  |
   //+------------------------------------------------------------------+
   void Configure(double very_low_thresh, double low_thresh, double normal_thresh, double high_thresh,
                  double very_low_risk, double low_risk, double normal_risk, double high_risk, double extreme_risk,
                  double expansion_thresh, double expansion_cut, double contraction_thresh, double contraction_boost,
                  bool enable_sl_adjust = true, double high_sl_mult = 0.85, double extreme_sl_mult = 0.70, double expansion_sl_mult = 0.75)
   {
      m_config.very_low_threshold = very_low_thresh;
      m_config.low_threshold = low_thresh;
      m_config.normal_threshold = normal_thresh;
      m_config.high_threshold = high_thresh;

      m_config.very_low_risk_mult = very_low_risk;
      m_config.low_risk_mult = low_risk;
      m_config.normal_risk_mult = normal_risk;
      m_config.high_risk_mult = high_risk;
      m_config.extreme_risk_mult = extreme_risk;

      m_config.expansion_threshold = expansion_thresh;
      m_config.expansion_risk_cut = expansion_cut;
      m_config.contraction_threshold = contraction_thresh;
      m_config.contraction_risk_boost = contraction_boost;

      // Stop loss tightening config
      m_config.enable_sl_adjust = enable_sl_adjust;
      m_config.high_vol_sl_mult = high_sl_mult;
      m_config.extreme_vol_sl_mult = extreme_sl_mult;
      m_config.expansion_sl_mult = expansion_sl_mult;
   }

   //+------------------------------------------------------------------+
   //| Enable/Disable                                                    |
   //+------------------------------------------------------------------+
   void SetEnabled(bool enabled) { m_enabled = enabled; }
   bool IsEnabled() const { return m_enabled; }

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
         LogPrint("ERROR: VolatilityRegimeManager failed to create indicators");
         return false;
      }

      // Initialize ATR history
      UpdateATRHistory();

      LogPrint("VolatilityRegimeManager initialized successfully");
      LogPrint("  Thresholds: VeryLow=", m_config.very_low_threshold,
               " | Low=", m_config.low_threshold,
               " | Normal=", m_config.normal_threshold,
               " | High=", m_config.high_threshold);
      LogPrint("  Risk Multipliers: VeryLow=", m_config.very_low_risk_mult,
               " | Low=", m_config.low_risk_mult,
               " | Normal=", m_config.normal_risk_mult,
               " | High=", m_config.high_risk_mult,
               " | Extreme=", m_config.extreme_risk_mult);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Update volatility analysis                                        |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(!m_enabled) return;

      // Only update once per bar
      datetime current_bar = iTime(_Symbol, PERIOD_H1, 0);
      if(current_bar == m_last_update) return;

      // Store previous ATR for expansion/contraction detection
      m_atr_prev = m_current_analysis.current_atr;

      // Update ATR history
      UpdateATRHistory();

      // Get current ATR
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(m_handle_atr_h1, 0, 0, 2, atr_buffer) <= 0)
      {
         LogPrint("ERROR: Failed to get current ATR");
         return;
      }

      m_current_analysis.current_atr = atr_buffer[0];
      m_current_analysis.average_atr = m_atr_average;

      // Calculate ATR ratio
      if(m_atr_average > 0)
         m_current_analysis.atr_ratio = m_current_analysis.current_atr / m_atr_average;
      else
         m_current_analysis.atr_ratio = 1.0;

      // Classify volatility regime
      ClassifyRegime();

      // Detect expansion/contraction
      DetectVolatilityDynamics();

      // Calculate final risk multiplier
      CalculateRiskMultiplier();

      m_last_update = current_bar;
   }

   //+------------------------------------------------------------------+
   //| Get current volatility analysis                                   |
   //+------------------------------------------------------------------+
   SVolatilityAnalysis GetAnalysis()
   {
      Update();
      return m_current_analysis;
   }

   //+------------------------------------------------------------------+
   //| Get risk multiplier for current volatility regime                 |
   //+------------------------------------------------------------------+
   double GetRiskMultiplier()
   {
      if(!m_enabled) return 1.0;

      Update();
      return m_current_analysis.risk_multiplier;
   }

   //+------------------------------------------------------------------+
   //| Apply volatility-based risk adjustment                            |
   //+------------------------------------------------------------------+
   double AdjustRiskForVolatility(double base_risk)
   {
      if(!m_enabled) return base_risk;

      Update();

      double adjusted = base_risk * m_current_analysis.risk_multiplier;

      // Log significant adjustments
      if(MathAbs(m_current_analysis.risk_multiplier - 1.0) > 0.05)
      {
         LogPrint("VolatilityRegime Risk Adjustment:");
         LogPrint("  Regime: ", m_current_analysis.regime_description);
         LogPrint("  ATR Ratio: ", DoubleToString(m_current_analysis.atr_ratio, 2));
         LogPrint("  Risk: ", DoubleToString(base_risk, 2), "% -> ",
                  DoubleToString(adjusted, 2), "% (x",
                  DoubleToString(m_current_analysis.risk_multiplier, 2), ")");
      }

      return adjusted;
   }

   //+------------------------------------------------------------------+
   //| Get current regime                                                |
   //+------------------------------------------------------------------+
   ENUM_VOLATILITY_REGIME GetRegime()
   {
      Update();
      return m_current_analysis.regime;
   }

   //+------------------------------------------------------------------+
   //| Check if volatility is expanding                                  |
   //+------------------------------------------------------------------+
   bool IsVolatilityExpanding()
   {
      Update();
      return m_current_analysis.is_expanding;
   }

   //+------------------------------------------------------------------+
   //| Check if volatility is contracting                                |
   //+------------------------------------------------------------------+
   bool IsVolatilityContracting()
   {
      Update();
      return m_current_analysis.is_contracting;
   }

   //+------------------------------------------------------------------+
   //| Get ATR ratio                                                     |
   //+------------------------------------------------------------------+
   double GetATRRatio()
   {
      Update();
      return m_current_analysis.atr_ratio;
   }

   //+------------------------------------------------------------------+
   //| Get stop loss multiplier for current volatility regime            |
   //| Returns < 1.0 in high vol to tighten stops                        |
   //+------------------------------------------------------------------+
   double GetSLMultiplier()
   {
      if(!m_enabled || !m_config.enable_sl_adjust) return 1.0;

      Update();
      return m_current_analysis.sl_multiplier;
   }

   //+------------------------------------------------------------------+
   //| Apply volatility-based SL adjustment to ATR multiplier            |
   //+------------------------------------------------------------------+
   double AdjustSLForVolatility(double base_atr_mult)
   {
      if(!m_enabled || !m_config.enable_sl_adjust) return base_atr_mult;

      Update();

      double adjusted = base_atr_mult * m_current_analysis.sl_multiplier;

      // Log significant adjustments
      if(MathAbs(m_current_analysis.sl_multiplier - 1.0) > 0.05)
      {
         LogPrint("VolatilityRegime SL Adjustment:");
         LogPrint("  Regime: ", m_current_analysis.regime_description);
         LogPrint("  ATR Ratio: ", DoubleToString(m_current_analysis.atr_ratio, 2));
         LogPrint("  SL ATR Mult: ", DoubleToString(base_atr_mult, 2), " -> ",
                  DoubleToString(adjusted, 2), " (x",
                  DoubleToString(m_current_analysis.sl_multiplier, 2), ")");
      }

      return adjusted;
   }

private:
   //+------------------------------------------------------------------+
   //| Update ATR history for average calculation                        |
   //+------------------------------------------------------------------+
   void UpdateATRHistory()
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);

      if(CopyBuffer(m_handle_atr_h1, 0, 0, m_history_size, atr_buffer) > 0)
      {
         double sum = 0;
         for(int i = 0; i < m_history_size; i++)
         {
            m_atr_history[i] = atr_buffer[i];
            sum += atr_buffer[i];
         }
         m_atr_average = sum / m_history_size;
      }
   }

   //+------------------------------------------------------------------+
   //| Classify current volatility regime                                |
   //+------------------------------------------------------------------+
   void ClassifyRegime()
   {
      double ratio = m_current_analysis.atr_ratio;

      if(ratio < m_config.very_low_threshold)
      {
         m_current_analysis.regime = VOL_REGIME_VERY_LOW;
         m_current_analysis.regime_description = "VERY_LOW (ATR<" +
            DoubleToString(m_config.very_low_threshold * 100, 0) + "%)";
      }
      else if(ratio < m_config.low_threshold)
      {
         m_current_analysis.regime = VOL_REGIME_LOW;
         m_current_analysis.regime_description = "LOW (ATR " +
            DoubleToString(m_config.very_low_threshold * 100, 0) + "-" +
            DoubleToString(m_config.low_threshold * 100, 0) + "%)";
      }
      else if(ratio < m_config.normal_threshold)
      {
         m_current_analysis.regime = VOL_REGIME_NORMAL;
         m_current_analysis.regime_description = "NORMAL (ATR " +
            DoubleToString(m_config.low_threshold * 100, 0) + "-" +
            DoubleToString(m_config.normal_threshold * 100, 0) + "%)";
      }
      else if(ratio < m_config.high_threshold)
      {
         m_current_analysis.regime = VOL_REGIME_HIGH;
         m_current_analysis.regime_description = "HIGH (ATR " +
            DoubleToString(m_config.normal_threshold * 100, 0) + "-" +
            DoubleToString(m_config.high_threshold * 100, 0) + "%)";
      }
      else
      {
         m_current_analysis.regime = VOL_REGIME_EXTREME;
         m_current_analysis.regime_description = "EXTREME (ATR>" +
            DoubleToString(m_config.high_threshold * 100, 0) + "%)";
      }
   }

   //+------------------------------------------------------------------+
   //| Detect volatility expansion/contraction                           |
   //+------------------------------------------------------------------+
   void DetectVolatilityDynamics()
   {
      m_current_analysis.is_expanding = false;
      m_current_analysis.is_contracting = false;

      if(m_atr_prev <= 0) return;

      double change_ratio = m_current_analysis.current_atr / m_atr_prev;

      if(change_ratio >= m_config.expansion_threshold)
      {
         m_current_analysis.is_expanding = true;
         m_current_analysis.regime_description += "+EXPANDING";
      }
      else if(change_ratio <= m_config.contraction_threshold)
      {
         m_current_analysis.is_contracting = true;
         m_current_analysis.regime_description += "+CONTRACTING";
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate final risk multiplier                                   |
   //+------------------------------------------------------------------+
   void CalculateRiskMultiplier()
   {
      // Base multiplier from regime
      double base_mult = 1.0;

      switch(m_current_analysis.regime)
      {
         case VOL_REGIME_VERY_LOW:
            base_mult = m_config.very_low_risk_mult;
            break;
         case VOL_REGIME_LOW:
            base_mult = m_config.low_risk_mult;
            break;
         case VOL_REGIME_NORMAL:
            base_mult = m_config.normal_risk_mult;
            break;
         case VOL_REGIME_HIGH:
            base_mult = m_config.high_risk_mult;
            break;
         case VOL_REGIME_EXTREME:
            base_mult = m_config.extreme_risk_mult;
            break;
      }

      // Apply expansion/contraction adjustments
      if(m_current_analysis.is_expanding)
      {
         base_mult *= m_config.expansion_risk_cut;
      }
      else if(m_current_analysis.is_contracting)
      {
         // Only boost in normal/low vol regimes, not in extreme
         if(m_current_analysis.regime != VOL_REGIME_EXTREME)
            base_mult *= m_config.contraction_risk_boost;
      }

      // Clamp final multiplier to reasonable bounds
      m_current_analysis.risk_multiplier = MathMax(0.3, MathMin(1.5, base_mult));

      // Also calculate SL multiplier
      CalculateSLMultiplier();
   }

   //+------------------------------------------------------------------+
   //| Calculate stop loss multiplier for high volatility tightening     |
   //+------------------------------------------------------------------+
   void CalculateSLMultiplier()
   {
      // Default: no adjustment
      double sl_mult = 1.0;

      if(!m_config.enable_sl_adjust)
      {
         m_current_analysis.sl_multiplier = 1.0;
         return;
      }

      // Tighten stops in high/extreme volatility
      switch(m_current_analysis.regime)
      {
         case VOL_REGIME_VERY_LOW:
         case VOL_REGIME_LOW:
         case VOL_REGIME_NORMAL:
            // Normal SL in low/normal volatility
            sl_mult = 1.0;
            break;
         case VOL_REGIME_HIGH:
            // Tighter stops in high volatility
            sl_mult = m_config.high_vol_sl_mult;
            break;
         case VOL_REGIME_EXTREME:
            // Much tighter stops in extreme volatility
            sl_mult = m_config.extreme_vol_sl_mult;
            break;
      }

      // Additional tightening if volatility is rapidly expanding
      if(m_current_analysis.is_expanding)
      {
         sl_mult = MathMin(sl_mult, m_config.expansion_sl_mult);
      }

      // Clamp to reasonable bounds (50% to 100% of normal SL)
      m_current_analysis.sl_multiplier = MathMax(0.5, MathMin(1.0, sl_mult));
   }
};
