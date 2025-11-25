//+------------------------------------------------------------------+
//| VolatilityBreakout.mqh                                           |
//| Trend Breakout Detector (Donchian/Keltner + ADX + H4 Slope)      |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property strict

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| CVolatilityBreakout - Detects expansion breakouts for trend      |
//+------------------------------------------------------------------+
class CVolatilityBreakout
{
private:
   int      m_donchian_period;
   int      m_keltner_ema_period;
   int      m_keltner_atr_period;
   double   m_keltner_mult;
   double   m_adx_min;
   double   m_entry_buffer_pts;
   double   m_pullback_atr_frac;
   int      m_cooldown_bars;
   bool     m_allow_adds;
   int      m_h4_fast_period;
   int      m_h4_slow_period;
   double   m_slope_buffer;

   int      m_handle_h4_fast;
   int      m_handle_h4_slow;
   int      m_handle_keltner_ema;
   int      m_handle_keltner_atr;

   datetime m_last_long_signal;
   datetime m_last_short_signal;
   double   m_last_long_break;
   double   m_last_short_break;

public:
   CVolatilityBreakout(int donchian_period = 20,
                       int keltner_ema_period = 20,
                       int keltner_atr_period = 20,
                       double keltner_mult = 1.5,
                       double adx_min = 25.0,
                       double entry_buffer_pts = 50.0,
                       double pullback_atr_frac = 0.5,
                       int cooldown_bars = 4,
                       int h4_fast = 20,
                       int h4_slow = 50,
                       double slope_buffer = 0.0,
                       bool allow_adds = true)
   {
      m_donchian_period = donchian_period;
      m_keltner_ema_period = keltner_ema_period;
      m_keltner_atr_period = keltner_atr_period;
      m_keltner_mult = keltner_mult;
      m_adx_min = adx_min;
      m_entry_buffer_pts = entry_buffer_pts;
      m_pullback_atr_frac = pullback_atr_frac;
      m_cooldown_bars = cooldown_bars;
      m_allow_adds = allow_adds;
      m_h4_fast_period = h4_fast;
      m_h4_slow_period = h4_slow;
      m_slope_buffer = slope_buffer;

      m_handle_h4_fast = INVALID_HANDLE;
      m_handle_h4_slow = INVALID_HANDLE;
      m_handle_keltner_ema = INVALID_HANDLE;
      m_handle_keltner_atr = INVALID_HANDLE;

      m_last_long_signal = 0;
      m_last_short_signal = 0;
      m_last_long_break = 0.0;
      m_last_short_break = 0.0;
   }

   bool Init()
   {
      m_handle_h4_fast = iMA(_Symbol, PERIOD_H4, m_h4_fast_period, 0, MODE_EMA, PRICE_CLOSE);
      m_handle_h4_slow = iMA(_Symbol, PERIOD_H4, m_h4_slow_period, 0, MODE_EMA, PRICE_CLOSE);
      m_handle_keltner_ema = iMA(_Symbol, PERIOD_H1, m_keltner_ema_period, 0, MODE_EMA, PRICE_TYPICAL);
      m_handle_keltner_atr = iATR(_Symbol, PERIOD_H1, m_keltner_atr_period);

      if (m_handle_h4_fast == INVALID_HANDLE || m_handle_h4_slow == INVALID_HANDLE ||
          m_handle_keltner_ema == INVALID_HANDLE || m_handle_keltner_atr == INVALID_HANDLE)
      {
         LogPrint("ERROR: VolatilityBreakout indicator init failed");
         return false;
      }

      LogPrint("VolatilityBreakout initialized (Donchian ", m_donchian_period, ", Keltner EMA ",
               m_keltner_ema_period, " / ATR ", m_keltner_atr_period, ")");
      return true;
   }

   ~CVolatilityBreakout()
   {
      if (m_handle_h4_fast != INVALID_HANDLE) IndicatorRelease(m_handle_h4_fast);
      if (m_handle_h4_slow != INVALID_HANDLE) IndicatorRelease(m_handle_h4_slow);
      if (m_handle_keltner_ema != INVALID_HANDLE) IndicatorRelease(m_handle_keltner_ema);
      if (m_handle_keltner_atr != INVALID_HANDLE) IndicatorRelease(m_handle_keltner_atr);
   }

   // Detect breakout or pullback add entries
   bool CheckBreakout(ENUM_TREND_DIRECTION daily_trend,
                      ENUM_TREND_DIRECTION h4_trend,
                      ENUM_REGIME_TYPE regime,
                      double adx_current,
                      SPriceActionData &out_signal)
   {
      // Filters: regime and ADX
      if (adx_current < m_adx_min)
         return false;
      if (regime != REGIME_TRENDING && regime != REGIME_VOLATILE)
         return false;

      // H4 slope/stack filter
      double ema_fast[2], ema_slow[2];
      ArraySetAsSeries(ema_fast, true);
      ArraySetAsSeries(ema_slow, true);
      if (CopyBuffer(m_handle_h4_fast, 0, 0, 2, ema_fast) < 2 ||
          CopyBuffer(m_handle_h4_slow, 0, 0, 2, ema_slow) < 2)
         return false;

      bool long_slope = (ema_fast[0] > ema_slow[0]) && (ema_fast[0] > ema_fast[1] + m_slope_buffer);
      bool short_slope = (ema_fast[0] < ema_slow[0]) && (ema_fast[0] < ema_fast[1] - m_slope_buffer);

      // Keltner channel (last closed H1 bar)
      double ema_mid[2], atr_val[2];
      ArraySetAsSeries(ema_mid, true);
      ArraySetAsSeries(atr_val, true);
      if (CopyBuffer(m_handle_keltner_ema, 0, 0, 2, ema_mid) < 2 ||
          CopyBuffer(m_handle_keltner_atr, 0, 0, 2, atr_val) < 2)
         return false;

      double last_ema = ema_mid[1];
      double last_atr = atr_val[1];
      double upper_k = last_ema + last_atr * m_keltner_mult;
      double lower_k = last_ema - last_atr * m_keltner_mult;

      // Donchian bands (use completed bars)
      double highs[], lows[], closes[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      ArraySetAsSeries(closes, true);

      int bars_needed = m_donchian_period + 2;
      if (CopyHigh(_Symbol, PERIOD_H1, 0, bars_needed, highs) < bars_needed ||
          CopyLow(_Symbol, PERIOD_H1, 0, bars_needed, lows) < bars_needed ||
          CopyClose(_Symbol, PERIOD_H1, 0, bars_needed, closes) < bars_needed)
         return false;

      double last_close = closes[1];
      double donchian_high = highs[1];
      double donchian_low = lows[1];
      for (int i = 1; i <= m_donchian_period; i++)
      {
         donchian_high = MathMax(donchian_high, highs[i]);
         donchian_low = MathMin(donchian_low, lows[i]);
      }

      datetime last_bar_time = (datetime)SeriesInfoInteger(_Symbol, PERIOD_H1, SERIES_LASTBAR_DATE);
      int cooldown_seconds = m_cooldown_bars * 3600;

      // LONG breakout / add
      if (long_slope && (h4_trend == TREND_BULLISH || h4_trend == TREND_NEUTRAL || daily_trend == TREND_BULLISH))
      {
         bool cooldown_ok = (m_last_long_signal == 0) || (TimeCurrent() - m_last_long_signal >= cooldown_seconds);
         bool is_break = (last_close > (donchian_high + m_entry_buffer_pts * _Point)) ||
                         (last_close > (upper_k + m_entry_buffer_pts * _Point));
         bool is_pullback_add = m_allow_adds &&
                                (m_last_long_break > 0.0) &&
                                (MathAbs(last_close - m_last_long_break) <= last_atr * m_pullback_atr_frac) &&
                                cooldown_ok;

         if ((is_break || is_pullback_add) && cooldown_ok)
         {
            double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double stop = MathMin(donchian_low, lower_k) - m_entry_buffer_pts * _Point;
            if (stop <= 0 || entry - stop <= 0)
               return false;

            double tp = entry + (entry - stop) * 4.0; // generous TP anchor; trailing will take over

            out_signal.signal = SIGNAL_LONG;
            out_signal.pattern_type = PATTERN_VOLATILITY_BREAKOUT;
            out_signal.pattern_name = is_pullback_add ? "Volatility Breakout Add Long" : "Volatility Breakout Long";
            out_signal.entry_price = entry;
            out_signal.stop_loss = stop;
            out_signal.take_profit = tp;
            out_signal.risk_reward = (tp - entry) / (entry - stop);
            out_signal.signal_time = last_bar_time;

            m_last_long_signal = TimeCurrent();
            m_last_long_break = (is_break ? MathMax(donchian_high, upper_k) : m_last_long_break);
            LogPrint("Volatility Breakout LONG detected (Close=", last_close, ", Donchian=", donchian_high, ", KeltnerUp=", upper_k, ")");
            return true;
         }
      }

      // SHORT breakout / add
      if (short_slope && (h4_trend == TREND_BEARISH || h4_trend == TREND_NEUTRAL || daily_trend == TREND_BEARISH))
      {
         bool cooldown_ok = (m_last_short_signal == 0) || (TimeCurrent() - m_last_short_signal >= cooldown_seconds);
         bool is_break = (last_close < (donchian_low - m_entry_buffer_pts * _Point)) ||
                         (last_close < (lower_k - m_entry_buffer_pts * _Point));
         bool is_pullback_add = m_allow_adds &&
                                (m_last_short_break > 0.0) &&
                                (MathAbs(last_close - m_last_short_break) <= last_atr * m_pullback_atr_frac) &&
                                cooldown_ok;

         if ((is_break || is_pullback_add) && cooldown_ok)
         {
            double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double stop = MathMax(donchian_high, upper_k) + m_entry_buffer_pts * _Point;
            if (stop <= 0 || stop - entry <= 0)
               return false;

            double tp = entry - (stop - entry) * 4.0;

            out_signal.signal = SIGNAL_SHORT;
            out_signal.pattern_type = PATTERN_VOLATILITY_BREAKOUT;
            out_signal.pattern_name = is_pullback_add ? "Volatility Breakout Add Short" : "Volatility Breakout Short";
            out_signal.entry_price = entry;
            out_signal.stop_loss = stop;
            out_signal.take_profit = tp;
            out_signal.risk_reward = (entry - tp) / (stop - entry);
            out_signal.signal_time = last_bar_time;

            m_last_short_signal = TimeCurrent();
            m_last_short_break = (is_break ? MathMin(donchian_low, lower_k) : m_last_short_break);
            LogPrint("Volatility Breakout SHORT detected (Close=", last_close, ", Donchian=", donchian_low, ", KeltnerLow=", lower_k, ")");
            return true;
         }
      }

      return false;
   }
};
