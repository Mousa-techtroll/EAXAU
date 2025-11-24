//+------------------------------------------------------------------+
//| MarketStateManager.mqh                                            |
//| Manages Market State Updates and Component Coordination          |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Components/TrendDetector.mqh"
#include "../Components/RegimeClassifier.mqh"
#include "../Components/MacroBias.mqh"
#include "../Components/PriceAction.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| CMarketStateManager - Coordinates market analysis components     |
//+------------------------------------------------------------------+
class CMarketStateManager
{
private:
   CTrendDetector*      m_trend_detector;
   CRegimeClassifier*   m_regime_classifier;
   CMacroBias*          m_macro_bias;
   CPriceAction*        m_price_action;
   bool                 m_use_h4_primary;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CMarketStateManager(CTrendDetector* trend, CRegimeClassifier* regime,
                       CMacroBias* macro, CPriceAction* pa, bool use_h4)
   {
      m_trend_detector = trend;
      m_regime_classifier = regime;
      m_macro_bias = macro;
      m_price_action = pa;
      m_use_h4_primary = use_h4;
   }

   //+------------------------------------------------------------------+
   //| Update all market components                                     |
   //+------------------------------------------------------------------+
   void UpdateMarketState()
   {
      // Update all 4 components
      m_trend_detector.Update();
      m_regime_classifier.Update();
      m_macro_bias.Update();

      // Use H4 trend if selected as primary, otherwise D1
      ENUM_TREND_DIRECTION bias_trend = m_use_h4_primary ?
                                        m_trend_detector.GetH4Trend() :
                                        m_trend_detector.GetDailyTrend();
      ENUM_REGIME_TYPE regime = m_regime_classifier.GetRegime();

      // Pass the preferred trend bias for scoring
      m_price_action.Update(bias_trend, regime);

      // Log state
      string state = StringFormat("State Updated | Bias: %s | Regime: %s | Macro: %+d",
                                  EnumToString(bias_trend),
                                  EnumToString(regime),
                                  m_macro_bias.GetBiasScore());
      LogPrint(state);
   }
};
