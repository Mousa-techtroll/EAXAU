//+------------------------------------------------------------------+
//| RegimeClassifier.mqh                                              |
//| Component 2: Market Regime Classification                         |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"

//+------------------------------------------------------------------+
//| Regime Classifier Class                                           |
//+------------------------------------------------------------------+
class CRegimeClassifier
{
private:
      // Parameters
      int                  m_adx_period;
      int                  m_atr_period;
      double               m_adx_trending_level;
      double               m_adx_ranging_level;

      // Indicator handles
      int                  m_handle_adx;
      int                  m_handle_atr;
      int                  m_handle_bb;

      // Regime data
      SRegimeData          m_regime_data;
      ENUM_REGIME_TYPE     m_previous_regime;

public:
      //+------------------------------------------------------------------+
      //| Constructor                                                      |
      //+------------------------------------------------------------------+
      CRegimeClassifier(int adx_period = 14, int atr_period = 14,
                        double adx_trending = 23.0, double adx_ranging = 20.0)
      {
            m_adx_period = adx_period;
            m_atr_period = atr_period;
            m_adx_trending_level = adx_trending;
            m_adx_ranging_level = adx_ranging;

            m_previous_regime = REGIME_UNKNOWN;
      }

      //+------------------------------------------------------------------+
      //| Destructor                                                        |
      //+------------------------------------------------------------------+
      ~CRegimeClassifier()
      {
            IndicatorRelease(m_handle_adx);
            IndicatorRelease(m_handle_atr);
            IndicatorRelease(m_handle_bb);
      }

      //+------------------------------------------------------------------+
      //| Initialize indicators                                             |
      //+------------------------------------------------------------------+
      bool Init()
      {
            // Create indicators (H4 timeframe for regime)
            m_handle_adx = iADX(_Symbol, PERIOD_H4, m_adx_period);
            m_handle_atr = iATR(_Symbol, PERIOD_H4, m_atr_period);
            m_handle_bb = iBands(_Symbol, PERIOD_H4, 20, 0, 2.0, PRICE_CLOSE);

            if(m_handle_adx == INVALID_HANDLE || m_handle_atr == INVALID_HANDLE ||
               m_handle_bb == INVALID_HANDLE)
            {
                  LogPrint("ERROR: Failed to create indicators in RegimeClassifier");
                  return false;
            }

            LogPrint("RegimeClassifier initialized successfully");
            return true;
      }

      //+------------------------------------------------------------------+
      //| Update regime                                                     |
      //+------------------------------------------------------------------+
      void Update()
      {
            double adx[], atr[], bb_upper[], bb_lower[], close[];
            ArraySetAsSeries(adx, true);
            ArraySetAsSeries(atr, true);
            ArraySetAsSeries(bb_upper, true);
            ArraySetAsSeries(bb_lower, true);
            ArraySetAsSeries(close, true);

            // Copy indicator data
            if(CopyBuffer(m_handle_adx, 0, 0, 3, adx) <= 0 ||
               CopyBuffer(m_handle_atr, 0, 0, 50, atr) <= 0 ||
               CopyBuffer(m_handle_bb, 1, 0, 3, bb_upper) <= 0 ||
               CopyBuffer(m_handle_bb, 2, 0, 3, bb_lower) <= 0 ||
               CopyClose(_Symbol, PERIOD_H4, 0, 1, close) <= 0)
            {
                  LogPrint("ERROR: Failed to copy regime data");
                  return;
            }

            // Store values
            m_regime_data.adx_value = adx[0];
            m_regime_data.atr_current = atr[0];

            // Calculate ATR average
            double atr_sum = 0;
            for(int i = 0; i < 50; i++)
                  atr_sum += atr[i];
            m_regime_data.atr_average = atr_sum / 50;

            // Calculate BB width
            double bb_width = bb_upper[0] - bb_lower[0];
            m_regime_data.bb_width = (bb_width / close[0]) * 100;

            // Detect volatility expansion
            m_regime_data.volatility_expanding = (m_regime_data.atr_current > m_regime_data.atr_average * 1.3);

            // Classify regime
            ClassifyRegime();

            m_regime_data.last_update = TimeCurrent();

            // Log regime change
            if(m_regime_data.regime != m_previous_regime && m_previous_regime != REGIME_UNKNOWN)
            {
                  LogPrint("REGIME CHANGE: ", EnumToString(m_previous_regime), " -> ", EnumToString(m_regime_data.regime));
            }

            m_previous_regime = m_regime_data.regime;
      }

      //+------------------------------------------------------------------+
      //| Get regime                                                        |
      //+------------------------------------------------------------------+
      ENUM_REGIME_TYPE GetRegime() const { return m_regime_data.regime; }
      double GetADX() const { return m_regime_data.adx_value; }
      double GetATR() const { return m_regime_data.atr_current; }
      bool IsVolatilityExpanding() const { return m_regime_data.volatility_expanding; }

private:
      //+------------------------------------------------------------------+
      //| Classify regime based on indicators                              |
      //+------------------------------------------------------------------+
      void ClassifyRegime()
      {
            double atr_ratio = m_regime_data.atr_current / m_regime_data.atr_average;

            // Priority 1: Check for VOLATILE (volatility spike/expansion)
            if(m_regime_data.volatility_expanding || atr_ratio > 1.3)
            {
                  m_regime_data.regime = REGIME_VOLATILE;
                  return;
            }

            // Priority 2: Check for CHOPPY (low ADX + erratic price action)
            if(m_regime_data.adx_value < m_adx_ranging_level &&
               atr_ratio >= 0.9 && atr_ratio <= 1.1 && m_regime_data.bb_width < 1.5)
            {
                  m_regime_data.regime = REGIME_CHOPPY;
                  return;
            }

            // Priority 3: Check for TRENDING (strong ADX + stable ATR)
            if(m_regime_data.adx_value > m_adx_trending_level &&
               atr_ratio >= 0.8 && atr_ratio <= 1.3)
            {
                  m_regime_data.regime = REGIME_TRENDING;
                  return;
            }

            // Priority 4: Check for RANGING (low ADX + low volatility)
            if(m_regime_data.adx_value < m_adx_ranging_level &&
               m_regime_data.atr_current < m_regime_data.atr_average * 0.9)
            {
                  m_regime_data.regime = REGIME_RANGING;
                  return;
            }

            // Priority 5: TRANSITION ZONE (ADX between ranging and trending thresholds)
            // This handles the gap where ADX is 20-23 (between m_adx_ranging_level and m_adx_trending_level)
            if(m_regime_data.adx_value >= m_adx_ranging_level &&
               m_regime_data.adx_value <= m_adx_trending_level)
            {
                  // In transition zone: classify based on ATR behavior
                  if(atr_ratio >= 1.0)
                  {
                     // ATR expanding or stable-high: lean toward trending
                     m_regime_data.regime = REGIME_TRENDING;
                  }
                  else
                  {
                     // ATR contracting: lean toward ranging
                     m_regime_data.regime = REGIME_RANGING;
                  }
                  return;
            }

            // Priority 6: Check for RANGING with normal ATR (ADX < ranging threshold)
            // This catches cases where ATR is normal (0.9-1.1) but ADX is low
            if(m_regime_data.adx_value < m_adx_ranging_level)
            {
                  m_regime_data.regime = REGIME_RANGING;
                  return;
            }

            // Default: UNKNOWN (truly undefined conditions)
            m_regime_data.regime = REGIME_UNKNOWN;
      }
};
