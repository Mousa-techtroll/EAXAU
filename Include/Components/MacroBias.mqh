//+------------------------------------------------------------------+
//| MacroBias.mqh                                                     |
//| Component 3: Macro/Intermarket Bias Analysis                      |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"

//+------------------------------------------------------------------+
//| Macro Bias Class                                                  |
//+------------------------------------------------------------------+
class CMacroBias
{
private:
   // Parameters
   string               m_dxy_symbol;
   string               m_vix_symbol;
   double               m_vix_elevated_level;
   double               m_vix_low_level;
   
   // Indicator handles
   int                  m_handle_dxy_ma50;
   int                  m_handle_price_d1_ema200;
   int                  m_handle_price_h4_fast;
   int                  m_handle_price_h4_slow;
   
   // Macro data
   SMacroBiasData       m_macro_data;
   bool                 m_dxy_available;
   bool                 m_vix_available;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CMacroBias(string dxy_symbol = "DXY", string vix_symbol = "VIX",
              double vix_elevated = 20.0, double vix_low = 15.0)
   {
      m_dxy_symbol = dxy_symbol;
      m_vix_symbol = vix_symbol;
      m_vix_elevated_level = vix_elevated;
      m_vix_low_level = vix_low;
      
      m_dxy_available = false;
      m_vix_available = false;
      m_handle_price_d1_ema200 = INVALID_HANDLE;
      m_handle_price_h4_fast = INVALID_HANDLE;
      m_handle_price_h4_slow = INVALID_HANDLE;
   }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CMacroBias()
   {
      if(m_dxy_available)
         IndicatorRelease(m_handle_dxy_ma50);
      if(m_handle_price_d1_ema200 != INVALID_HANDLE)
         IndicatorRelease(m_handle_price_d1_ema200);
      if(m_handle_price_h4_fast != INVALID_HANDLE)
         IndicatorRelease(m_handle_price_h4_fast);
      if(m_handle_price_h4_slow != INVALID_HANDLE)
         IndicatorRelease(m_handle_price_h4_slow);
   }
   
   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init()
   {
      // Try to enable DXY symbol
      m_dxy_available = SymbolSelect(m_dxy_symbol, true);
      
      if(m_dxy_available)
      {
         m_handle_dxy_ma50 = iMA(m_dxy_symbol, PERIOD_H4, 50, 0, MODE_SMA, PRICE_CLOSE);
         if(m_handle_dxy_ma50 == INVALID_HANDLE)
         {
            LogPrint("WARNING: DXY MA failed to create");
            m_dxy_available = false;
         }
      }
      else
      {
         LogPrint("WARNING: DXY symbol not available. Macro bias will be neutral.");
      }
      
      // Try to enable VIX symbol (optional)
      m_vix_available = SymbolSelect(m_vix_symbol, true);
      if(!m_vix_available)
      {
         LogPrint("INFO: VIX symbol not available. Will operate without VIX data.");
      }
      // Price-based fallback handles (for when DXY/VIX unavailable)
      m_handle_price_d1_ema200 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
      m_handle_price_h4_fast = iMA(_Symbol, PERIOD_H4, 20, 0, MODE_EMA, PRICE_CLOSE);
      m_handle_price_h4_slow = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(m_handle_price_d1_ema200 == INVALID_HANDLE || m_handle_price_h4_fast == INVALID_HANDLE || m_handle_price_h4_slow == INVALID_HANDLE)
      {
         LogPrint("WARNING: Price-based macro fallback handles failed to create");
      }
      
      // Initialize bias as neutral
      m_macro_data.bias = BIAS_NEUTRAL;
      m_macro_data.bias_score = 0;
      
      LogPrint("MacroBias initialized (DXY: ", m_dxy_available, ", VIX: ", m_vix_available, ")");
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update macro bias                                                |
   //+------------------------------------------------------------------+
   void Update()
   {
      int score = 0;
      
      // Update DXY analysis
      if(m_dxy_available)
         score += AnalyzeDXY();
      
      // Update VIX analysis
      if(m_vix_available)
         score += AnalyzeVIX();
      else
         LogPrint("INFO: VIX unavailable - skipping VIX component");

      // Fallback: price-based macro when no external data
      if(!m_dxy_available && !m_vix_available)
         score += AnalyzePriceFallback();
      
      // Store score
      m_macro_data.bias_score = score;
      
      // Determine bias
      if(score >= 2)
         m_macro_data.bias = BIAS_BULLISH;
      else if(score <= -2)
         m_macro_data.bias = BIAS_BEARISH;
      else
         m_macro_data.bias = BIAS_NEUTRAL;
      
      m_macro_data.last_update = TimeCurrent();
   }
   
   //+------------------------------------------------------------------+
   //| Get bias data                                                     |
   //+------------------------------------------------------------------+
   ENUM_MACRO_BIAS GetBias() const { return m_macro_data.bias; }
   int GetBiasScore() const { return m_macro_data.bias_score; }
   bool IsDXYAvailable() const { return m_dxy_available; }

private:
   //+------------------------------------------------------------------+
   //| Analyze DXY (returns score contribution -3 to +3)                |
   //+------------------------------------------------------------------+
   int AnalyzeDXY()
   {
      double dxy_close[], dxy_ma[], dxy_high[];
      ArraySetAsSeries(dxy_close, true);
      ArraySetAsSeries(dxy_ma, true);
      ArraySetAsSeries(dxy_high, true);
      
      // Get DXY data
      if(CopyClose(m_dxy_symbol, PERIOD_H4, 0, 1, dxy_close) <= 0 ||
         CopyBuffer(m_handle_dxy_ma50, 0, 0, 1, dxy_ma) <= 0)
      {
         return 0;
      }
      
      m_macro_data.dxy_price = dxy_close[0];
      m_macro_data.dxy_ma50 = dxy_ma[0];
      
      // Determine DXY trend
      if(dxy_close[0] > dxy_ma[0])
         m_macro_data.dxy_trend = TREND_BULLISH;
      else if(dxy_close[0] < dxy_ma[0])
         m_macro_data.dxy_trend = TREND_BEARISH;
      else
         m_macro_data.dxy_trend = TREND_NEUTRAL;
      
      // Detect DXY higher highs
      if(CopyHigh(m_dxy_symbol, PERIOD_H4, 0, 30, dxy_high) > 0)
      {
         m_macro_data.dxy_making_hh = false;
         
         // Simple check: recent high > previous high
         double recent_high = dxy_high[0];
         for(int i = 1; i < 30; i++)
            recent_high = MathMax(recent_high, dxy_high[i]);
         
         if(dxy_high[0] >= recent_high * 0.999) // Within 0.1%
            m_macro_data.dxy_making_hh = true;
      }
      
      // Calculate score contribution
      int dxy_score = 0;
      
      // DXY bearish = Gold bullish
      if(m_macro_data.dxy_trend == TREND_BEARISH)
      {
         dxy_score += 1;
         if(!m_macro_data.dxy_making_hh) // Not making higher highs
            dxy_score += 1;
      }
      // DXY bullish = Gold bearish
      else if(m_macro_data.dxy_trend == TREND_BULLISH)
      {
         dxy_score -= 1;
         if(m_macro_data.dxy_making_hh) // Making higher highs
            dxy_score -= 1;
      }
      
      return dxy_score;
   }
   
   //+------------------------------------------------------------------+
   //| Analyze VIX (returns score contribution -1 to +1)                |
   //+------------------------------------------------------------------+
   int AnalyzeVIX()
   {
      double vix_close[];
      ArraySetAsSeries(vix_close, true);
      
      if(CopyClose(m_vix_symbol, PERIOD_H4, 0, 1, vix_close) <= 0)
         return 0;
      
      m_macro_data.vix_level = vix_close[0];
      m_macro_data.vix_elevated = (vix_close[0] > m_vix_elevated_level);
      
      // VIX elevated = Risk-off = Gold bullish
      if(m_macro_data.vix_elevated)
         return +1;

      // VIX very low = Extreme risk-on = Gold bearish
      if(vix_close[0] < m_vix_low_level)
         return -1;
      
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Price-based fallback macro score (when DXY/VIX missing)         |
   //+------------------------------------------------------------------+
   int AnalyzePriceFallback()
   {
      if (m_handle_price_d1_ema200 == INVALID_HANDLE || m_handle_price_h4_fast == INVALID_HANDLE || m_handle_price_h4_slow == INVALID_HANDLE)
         return 0;

      double ema200_d1[], ema_fast[], ema_slow[];
      ArraySetAsSeries(ema200_d1, true);
      ArraySetAsSeries(ema_fast, true);
      ArraySetAsSeries(ema_slow, true);

      if (CopyBuffer(m_handle_price_d1_ema200, 0, 0, 1, ema200_d1) <= 0 ||
          CopyBuffer(m_handle_price_h4_fast, 0, 0, 2, ema_fast) < 2 ||
          CopyBuffer(m_handle_price_h4_slow, 0, 0, 2, ema_slow) < 2)
         return 0;

      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool above_200 = current_price > ema200_d1[0];
      bool h4_up = ema_fast[0] > ema_slow[0] && ema_fast[0] > ema_fast[1];
      bool h4_down = ema_fast[0] < ema_slow[0] && ema_fast[0] < ema_fast[1];

      int price_score = 0;
      if (above_200 && h4_up)
         price_score += 2;
      else if (!above_200 && h4_down)
         price_score -= 2;
      else if (above_200)
         price_score += 1;
      else
         price_score -= 1;

      LogPrint("Price-based macro fallback: price ", (above_200 ? "above" : "below"), " D1 200 | H4 slope ",
               h4_up ? "UP" : h4_down ? "DOWN" : "FLAT", " => score ", price_score);
      return price_score;
   }
};
