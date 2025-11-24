//+------------------------------------------------------------------+
//| SignalManager.mqh                                                 |
//| Manages pending signals and confirmation candle logic             |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

// Forward declaration or define SPendingSignal structure
struct SPendingSignal
{
   datetime    detection_time;
   ENUM_SIGNAL_TYPE signal_type;
   string      pattern_name;
   ENUM_PATTERN_TYPE pattern_type;
   double      entry_price;
   double      stop_loss;
   double      take_profit1;
   double      take_profit2;
   ENUM_SETUP_QUALITY quality;
   ENUM_REGIME_TYPE regime;
   ENUM_TREND_DIRECTION daily_trend;
   ENUM_TREND_DIRECTION h4_trend;
   int         macro_score;
   double      pattern_high;
   double      pattern_low;
};

//+------------------------------------------------------------------+
//| CSignalManager - Manages pending signal confirmation             |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
   // Pending signal state
   SPendingSignal    m_pending_signal;
   bool              m_has_pending;
   double            m_confirmation_strictness;
   double            m_tp1_distance;
   double            m_tp2_distance;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSignalManager(double confirmation_strictness, double tp1_dist, double tp2_dist)
   {
      m_has_pending = false;
      m_confirmation_strictness = confirmation_strictness;
      m_tp1_distance = tp1_dist;
      m_tp2_distance = tp2_dist;
   }

   //+------------------------------------------------------------------+
   //| Check if has pending signal                                      |
   //+------------------------------------------------------------------+
   bool HasPendingSignal() { return m_has_pending; }

   //+------------------------------------------------------------------+
   //| Get pending signal                                                |
   //+------------------------------------------------------------------+
   SPendingSignal GetPendingSignal() { return m_pending_signal; }

   //+------------------------------------------------------------------+
   //| Clear pending signal                                              |
   //+------------------------------------------------------------------+
   void ClearPendingSignal() { m_has_pending = false; }

   //+------------------------------------------------------------------+
   //| Store signal as pending (waiting for confirmation)               |
   //+------------------------------------------------------------------+
   void StorePendingSignal(ENUM_SIGNAL_TYPE sig_type, string pattern, ENUM_PATTERN_TYPE pat_type,
                           double entry, double sl, double tp1, double tp2,
                           ENUM_SETUP_QUALITY qual, ENUM_REGIME_TYPE reg,
                           ENUM_TREND_DIRECTION daily, ENUM_TREND_DIRECTION h4, int macro)
   {
      // Get the high/low of the pattern detection candle
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      if (CopyRates(_Symbol, PERIOD_H1, 0, 2, rates) >= 2)
      {
         m_pending_signal.detection_time = TimeCurrent();
         m_pending_signal.signal_type    = sig_type;
         m_pending_signal.pattern_name   = pattern;
         m_pending_signal.pattern_type   = pat_type;
         m_pending_signal.entry_price    = entry;
         m_pending_signal.stop_loss      = sl;
         m_pending_signal.take_profit1   = tp1;
         m_pending_signal.take_profit2   = tp2;
         m_pending_signal.quality        = qual;
         m_pending_signal.regime         = reg;
         m_pending_signal.daily_trend    = daily;
         m_pending_signal.h4_trend       = h4;
         m_pending_signal.macro_score    = macro;
         m_pending_signal.pattern_high   = rates[1].high;
         m_pending_signal.pattern_low    = rates[1].low;

         m_has_pending = true;

         LogPrint(">>> PENDING: ", pattern, " detected - waiting for confirmation candle");
         LogPrint("    Pattern High: ", m_pending_signal.pattern_high, " | Pattern Low: ", m_pending_signal.pattern_low);
      }
      else
      {
         LogPrint("ERROR: Cannot store pending signal - failed to get pattern candle data");
      }
   }

   //+------------------------------------------------------------------+
   //| Check if pattern is confirmed by next candle                     |
   //+------------------------------------------------------------------+
   bool CheckPatternConfirmation()
   {
      if (!m_has_pending) return false;

      // Get the candles: [0]=current forming, [1]=last completed (confirmation), [2]=pattern detection
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      if (CopyRates(_Symbol, PERIOD_H1, 0, 3, rates) < 3)
      {
         LogPrint("ERROR: Cannot copy rates for confirmation check");
         return false;
      }

      double conf_open  = rates[1].open;
      double conf_high  = rates[1].high;
      double conf_low   = rates[1].low;
      double conf_close = rates[1].close;

      double pattern_high = m_pending_signal.pattern_high;
      double pattern_low  = m_pending_signal.pattern_low;

      // For LONG signals
      if (m_pending_signal.signal_type == SIGNAL_LONG)
      {
         bool closed_higher = (conf_close > pattern_high * m_confirmation_strictness);
         bool is_bullish    = (conf_close > conf_open);
         bool no_break_low  = (conf_low >= pattern_low * 0.998);

         LogPrint(">>> LONG Confirmation Check:");
         LogPrint("    Pattern High: ", pattern_high, " | Conf Close: ", conf_close);
         LogPrint("    Closed Higher: ", closed_higher, " | Is Bullish: ", is_bullish, " | No Break Low: ", no_break_low);

         return (closed_higher && is_bullish && no_break_low);
      }
      // For SHORT signals
      else if (m_pending_signal.signal_type == SIGNAL_SHORT)
      {
         bool closed_lower  = (conf_close < pattern_low / m_confirmation_strictness);
         bool is_bearish    = (conf_close < conf_open);
         bool no_break_high = (conf_high <= pattern_high * 1.002);

         LogPrint(">>> SHORT Confirmation Check:");
         LogPrint("    Pattern Low: ", pattern_low, " | Conf Close: ", conf_close);
         LogPrint("    Closed Lower: ", closed_lower, " | Is Bearish: ", is_bearish, " | No Break High: ", no_break_high);

         return (closed_lower && is_bearish && no_break_high);
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Recalculate TPs for confirmed signal                             |
   //+------------------------------------------------------------------+
   void RecalculateTPs(double &tp1_out, double &tp2_out)
   {
      if (!m_has_pending) return;

      double current_entry = (m_pending_signal.signal_type == SIGNAL_LONG) ?
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                             SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double risk_distance = 0;

      if(m_pending_signal.signal_type == SIGNAL_LONG)
      {
         risk_distance = current_entry - m_pending_signal.stop_loss;
         tp1_out = current_entry + (risk_distance * m_tp1_distance);
         tp2_out = current_entry + (risk_distance * m_tp2_distance);
      }
      else
      {
         risk_distance = m_pending_signal.stop_loss - current_entry;
         tp1_out = current_entry - (risk_distance * m_tp1_distance);
         tp2_out = current_entry - (risk_distance * m_tp2_distance);
      }

      LogPrint("    Original Entry: ", m_pending_signal.entry_price, " | Current Entry: ", current_entry);
      LogPrint("    SL: ", m_pending_signal.stop_loss, " | Risk: ", DoubleToString(risk_distance, 2), " pts");
      LogPrint("    TP1 recalculated: ", m_pending_signal.take_profit1, " -> ", tp1_out);
      LogPrint("    TP2 recalculated: ", m_pending_signal.take_profit2, " -> ", tp2_out);
   }
};
