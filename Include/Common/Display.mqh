//+------------------------------------------------------------------+
//| Display.mqh                                                       |
//| Chart Display and UI Management                                   |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "Utils.mqh"
#include "../Components/TrendDetector.mqh"
#include "../Components/RegimeClassifier.mqh"
#include "../Components/MacroBias.mqh"
#include "../Management/RiskManager.mqh"

//+------------------------------------------------------------------+
//| CDisplay - Manages chart display and UI                          |
//+------------------------------------------------------------------+
class CDisplay
{
private:
   // External references
   CTrendDetector*      m_trend_detector;
   CRegimeClassifier*   m_regime_classifier;
   CMacroBias*          m_macro_bias;
   CRiskManager*        m_risk_manager;

   // Configuration
   double               m_max_exposure;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CDisplay(CTrendDetector* trend, CRegimeClassifier* regime,
            CMacroBias* macro, CRiskManager* risk, double max_exposure)
   {
      m_trend_detector = trend;
      m_regime_classifier = regime;
      m_macro_bias = macro;
      m_risk_manager = risk;
      m_max_exposure = max_exposure;
   }

   //+------------------------------------------------------------------+
   //| Update chart display                                             |
   //+------------------------------------------------------------------+
   void UpdateDisplay(int position_count)
   {
      string display = "Stack1.7 EA\n";
      display += "================\n";

      // Market state
      display += StringFormat("D1: %s | H4: %s | H1: %s\n",
                              EnumToString(m_trend_detector.GetDailyTrend()),
                              EnumToString(m_trend_detector.GetH4Trend()),
                              EnumToString(m_trend_detector.GetH1Trend()));

      display += StringFormat("Regime: %s | ADX: %.1f\n",
                              EnumToString(m_regime_classifier.GetRegime()),
                              m_regime_classifier.GetADX());

      display += StringFormat("Macro Score: %+d\n", m_macro_bias.GetBiasScore());

      // Risk status
      display += "================\n";
      display += StringFormat("Daily P&L: %s\n", FormatPercent(m_risk_manager.GetDailyPnL()));
      display += StringFormat("Exposure: %.1f%% / %.1f%%\n",
                              m_risk_manager.GetCurrentExposure(),
                              m_max_exposure);
      display += StringFormat("Positions: %d\n", position_count);

      if (m_risk_manager.GetConsecutiveLosses() >= 3)
         display += StringFormat("WARNING: %d consecutive losses - Risk reduced\n",
                                 m_risk_manager.GetConsecutiveLosses());

      if (m_risk_manager.IsTradingHalted())
         display += "WARNING: TRADING HALTED\n";

      Comment(display);
   }
};
