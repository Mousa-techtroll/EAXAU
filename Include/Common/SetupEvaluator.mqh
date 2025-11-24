//+------------------------------------------------------------------+
//| SetupEvaluator.mqh                                                |
//| Setup Quality Evaluation and Risk Calculation                     |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "Enums.mqh"
#include "Utils.mqh"
#include "../Components/TrendDetector.mqh"
#include "../Components/PriceAction.mqh"
#include "../Components/PriceActionLowVol.mqh"

//+------------------------------------------------------------------+
//| CSetupEvaluator - Evaluates setup quality and calculates risk    |
//+------------------------------------------------------------------+
class CSetupEvaluator
{
private:
   // External references
   CTrendDetector*      m_trend_detector;
   CPriceAction*        m_price_action;
   CPriceActionLowVol*  m_price_action_lowvol;

   // Configuration parameters
   double               m_risk_aplus;
   double               m_risk_a;
   double               m_risk_bplus;
   double               m_risk_b;
   int                  m_points_aplus;
   int                  m_points_a;
   int                  m_points_bplus;
   int                  m_points_b;
   double               m_rsi_overbought;
   double               m_rsi_oversold;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSetupEvaluator(CTrendDetector* trend, CPriceAction* pa, CPriceActionLowVol* pa_lowvol,
                   double risk_aplus, double risk_a, double risk_bplus, double risk_b,
                   int points_aplus, int points_a, int points_bplus, int points_b,
                   double rsi_ob, double rsi_os)
   {
      m_trend_detector = trend;
      m_price_action = pa;
      m_price_action_lowvol = pa_lowvol;
      m_risk_aplus = risk_aplus;
      m_risk_a = risk_a;
      m_risk_bplus = risk_bplus;
      m_risk_b = risk_b;
      m_points_aplus = points_aplus;
      m_points_a = points_a;
      m_points_bplus = points_bplus;
      m_points_b = points_b;
      m_rsi_overbought = rsi_ob;
      m_rsi_oversold = rsi_os;
   }

   //+------------------------------------------------------------------+
   //| Evaluate setup quality (0-10 points) - RELAXED VERSION           |
   //+------------------------------------------------------------------+
   ENUM_SETUP_QUALITY EvaluateSetupQuality(ENUM_TREND_DIRECTION daily, ENUM_TREND_DIRECTION h4,
                                           ENUM_REGIME_TYPE regime, int macro_score, string pattern)
   {
      int points = 0;

      bool pattern_bullish = (StringFind(pattern, "Bullish") >= 0);
      bool pattern_bearish = (StringFind(pattern, "Bearish") >= 0);

      // Factor 1: Trend alignment (0-3 points)
      if (daily == h4 && daily != TREND_NEUTRAL)
         points += 2;
      else if (daily == TREND_NEUTRAL && h4 != TREND_NEUTRAL)
         points += 1;  // give credit when only H4 trend exists

      if (m_trend_detector.IsAligned())
         points += 1;

      // Bonus for pattern direction matching primary (H4) trend
      if (pattern_bullish && h4 == TREND_BULLISH)
         points += 1;
      if (pattern_bearish && h4 == TREND_BEARISH)
         points += 1;

      // Factor 1.5: Counter-Trend / RSI Bonus
      double rsi = m_price_action_lowvol.GetRSI();
      if (rsi > m_rsi_overbought || rsi < m_rsi_oversold)
      {
         points += 3; // Bonus points to compensate for "Bad Trend Alignment"
         LogPrint("   +3 Quality Points for Extreme RSI (", DoubleToString(rsi, 1), ")");
      }

      // Factor 2: Regime (0-2 points)
      if (regime == REGIME_TRENDING)
         points += 2;
      else if (regime == REGIME_VOLATILE)
         points += 1;
      else if (regime == REGIME_RANGING)
         points += 1;
      else if (regime == REGIME_CHOPPY)
         points += 0;
      else if (regime == REGIME_UNKNOWN && daily == h4 && daily != TREND_NEUTRAL)
         points += 1;

      // Factor 3: Macro alignment (0-3 points)
      if (MathAbs(macro_score) >= 3)
         points += 3;
      else if (MathAbs(macro_score) >= 1)
         points += 1;
      else if (macro_score == 0)  // FALLBACK: When macro unavailable
         points += 1;

      // Factor 4: Pattern quality (0-2 points)
      if (StringFind(pattern, "LiquiditySweep") >= 0)
         points += 2;
      else if (StringFind(pattern, "Engulfing") >= 0 || StringFind(pattern, "Pin") >= 0)
         points += 1;
      else if (StringFind(pattern, "MACross") >= 0)
         points += 1;
      else if (StringFind(pattern, "BB Mean") >= 0) // Add points for Mean Reversion patterns
         points += 2;
      else if (StringFind(pattern, "Range Box") >= 0)
          points += 2;

      // Determine quality tier
      if (points >= m_points_aplus) return SETUP_A_PLUS;
      if (points >= m_points_a) return SETUP_A;
      if (points >= m_points_bplus) return SETUP_B_PLUS;
      if (points >= m_points_b) return SETUP_B;

      return SETUP_NONE;
   }

   //+------------------------------------------------------------------+
   //| Get risk percentage for setup quality with pattern multiplier    |
   //+------------------------------------------------------------------+
   double GetRiskForQuality(ENUM_SETUP_QUALITY quality, string pattern = "")
   {
      // Get base risk for quality tier
      double base_risk = 0.0;
      switch(quality)
      {
         case SETUP_A_PLUS: base_risk = m_risk_aplus; break;
         case SETUP_A:      base_risk = m_risk_a;     break;
         case SETUP_B_PLUS: base_risk = m_risk_bplus; break;
         case SETUP_B:      base_risk = m_risk_b;     break;
         default:           return 0.0;
      }

      // Apply pattern-specific multiplier
      double multiplier = 1.0;

      // Bullish MA Cross
      if (StringFind(pattern, "Bullish MA") >= 0 || StringFind(pattern, "MACross") >= 0)
      {
         multiplier = 1.15;
      }
      // Bullish Pin Bar
      else if (StringFind(pattern, "Bullish Pin") >= 0)
      {
         multiplier = 1.05;
      }
      // Bullish Engulfing
      else if (StringFind(pattern, "Bullish Engulf") >= 0)
      {
         multiplier = 1.05;
      }
      // Bearish Patterns
      else if (StringFind(pattern, "Bearish") >= 0)
      {
         multiplier = 0.50;
      }

      double final_risk = base_risk * multiplier;
      return final_risk;
   }
};
