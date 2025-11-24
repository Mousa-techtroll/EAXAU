//+------------------------------------------------------------------+
//| TradeOrchestrator.mqh                                             |
//| Orchestrates Trade Execution and Confirmation Processing          |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"
#include "../Management/TradeExecutor.mqh"
#include "../Management/RiskManager.mqh"
#include "../Management/SignalManager.mqh"
#include "../Management/AdaptiveTPManager.mqh"
#include "../Management/DynamicPositionSizer.mqh"
#include "../Common/TradeLogger.mqh"
#include "PositionCoordinator.mqh"
#include "RiskMonitor.mqh"

//+------------------------------------------------------------------+
//| CTradeOrchestrator - Coordinates trade execution                 |
//+------------------------------------------------------------------+
class CTradeOrchestrator
{
private:
   CTradeExecutor*      m_trade_executor;
   CRiskManager*        m_risk_manager;
   CTradeLogger*        m_trade_logger;
   CPositionCoordinator* m_position_coordinator;
   CRiskMonitor*        m_risk_monitor;
   CAdaptiveTPManager*  m_adaptive_tp_manager;
   CDynamicPositionSizer* m_dynamic_sizer;
   CRegimeClassifier*   m_regime_classifier;

   int                  m_handle_ma_200;
   bool                 m_use_adaptive_tp;
   bool                 m_use_dynamic_sizing;

   // Input parameters
   double               m_min_rr_ratio;
   bool                 m_use_daily_200ema;
   double               m_tp1_distance;
   double               m_tp2_distance;
   bool                 m_enable_alerts;
   bool                 m_enable_push;
   bool                 m_enable_email;

   // Risk tiers
   double               m_risk_aplus;
   double               m_risk_a;
   double               m_risk_bplus;
   double               m_risk_b;
   double               m_short_risk_multiplier;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CTradeOrchestrator(CTradeExecutor* executor, CRiskManager* risk_mgr,
                      CTradeLogger* logger, CPositionCoordinator* pos_coordinator,
                      CRiskMonitor* risk_monitor, int handle_ma200,
                     double min_rr, bool use_200ema, double tp1_dist, double tp2_dist,
                     bool alerts, bool push, bool email,
                     double risk_aplus, double risk_a, double risk_bplus, double risk_b,
                     double short_risk_multiplier,
                     CAdaptiveTPManager* adaptive_tp = NULL, CRegimeClassifier* regime = NULL,
                     bool use_adaptive_tp = false,
                     CDynamicPositionSizer* dynamic_sizer = NULL, bool use_dynamic_sizing = false)
   {
      m_trade_executor = executor;
      m_risk_manager = risk_mgr;
      m_trade_logger = logger;
      m_position_coordinator = pos_coordinator;
      m_risk_monitor = risk_monitor;
      m_adaptive_tp_manager = adaptive_tp;
      m_dynamic_sizer = dynamic_sizer;
      m_regime_classifier = regime;
      m_handle_ma_200 = handle_ma200;
      m_min_rr_ratio = min_rr;
      m_use_daily_200ema = use_200ema;
      m_use_adaptive_tp = use_adaptive_tp;
      m_use_dynamic_sizing = use_dynamic_sizing;
      m_tp1_distance = tp1_dist;
      m_tp2_distance = tp2_dist;
      m_enable_alerts = alerts;
      m_enable_push = push;
      m_enable_email = email;
      m_risk_aplus = risk_aplus;
      m_risk_a = risk_a;
      m_risk_bplus = risk_bplus;
      m_risk_b = risk_b;
      m_short_risk_multiplier = MathMax(0.0, short_risk_multiplier);
   }

   //+------------------------------------------------------------------+
   //| Get risk percentage for quality tier                             |
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
      // Bearish MA Cross
      else if (StringFind(pattern, "Bearish MA") >= 0 || StringFind(pattern, "MACross") >= 0)
      {
         multiplier = 1.15;
      }
      // Bearish Pin Bar
      else if (StringFind(pattern, "Bearish Pin") >= 0)
      {
         multiplier = 1.05;
      }
      // Bearish Engulfing
      else if (StringFind(pattern, "Bearish Engulf") >= 0)
      {
         multiplier = 1.05;
      }

      double final_risk = base_risk * multiplier;
      return final_risk;
   }

   //+------------------------------------------------------------------+
   //| Execute trade                                                     |
   //+------------------------------------------------------------------+
   void ExecuteTrade(ENUM_SIGNAL_TYPE trade_signal, double lots, double sl,
                     double tp1, double tp2, ENUM_SETUP_QUALITY quality,
                     string pattern_name, ENUM_PATTERN_TYPE pattern_type, double risk_percent = 0.0)
   {
      string pattern = pattern_name;

      // R:R validation before trade execution
      if(m_min_rr_ratio > 0)
      {
         double entry_price = (trade_signal == SIGNAL_LONG) ?
                              SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                              SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double risk = 0;
         double reward = 0;

         if(trade_signal == SIGNAL_LONG)
         {
            risk = entry_price - sl;
            reward = MathMax(tp1, tp2) - entry_price;
         }
         else
         {
            risk = sl - entry_price;
            reward = entry_price - MathMin(tp1, tp2);
         }

         double actual_rr = (risk > 0) ? reward / risk : 0;

         if(actual_rr < m_min_rr_ratio)
         {
            LogPrint("TRADE REJECTED: Insufficient R:R ratio");
            LogPrint("  Pattern: ", pattern);
            LogPrint("  Entry: ", entry_price, " | SL: ", sl, " | TP1: ", tp1);
            LogPrint("  Actual R:R = ", DoubleToString(actual_rr, 2), " (Min: ", m_min_rr_ratio, ")");
            return;
         }
         LogPrint("R:R Check PASSED: ", DoubleToString(actual_rr, 2), " >= ", m_min_rr_ratio);
      }

      // Check daily trade limit via RiskMonitor
      if (m_risk_monitor != NULL && !m_risk_monitor.CanTrade())
      {
         return;  // CanTrade() already logs the rejection
      }

      LogPrint("========================================");
      LogPrint("EXECUTING TRADE");
      LogPrint("Pattern: ", pattern);
      LogPrint("Quality: ", EnumToString(quality));
      LogPrint("Direction: ", EnumToString(trade_signal));
      LogPrint("Stop Loss: ", sl);
      LogPrint("========================================");

      // Use provided lot size by default
      double calc_entry = (trade_signal == SIGNAL_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double final_risk = risk_percent;

      // Derive risk% from sizing if not supplied
      if (final_risk <= 0.0)
         final_risk = m_risk_manager.ComputeRiskPercent(lots, calc_entry, sl);

      // COUNTER-TREND RISK CUTTER: optionally reduce risk (and resize) against D1 200 EMA
      if (m_use_daily_200ema)
      {
         double ma200_val = 0;
         double ma200_buf[];
         ArraySetAsSeries(ma200_buf, true);

         if (CopyBuffer(m_handle_ma_200, 0, 0, 1, ma200_buf) > 0)
            ma200_val = ma200_buf[0];

         double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool is_counter_trend = ( (int)trade_signal == (int)SIGNAL_SHORT && current_price > ma200_val ) ||
                                 ( (int)trade_signal == (int)SIGNAL_LONG && current_price < ma200_val );

         if (is_counter_trend)
         {
            final_risk *= 0.5;
            double resized = m_risk_manager.CalculateLotSize(final_risk, calc_entry, sl);
            if (resized > 0)
               lots = resized;
            LogPrint(">>> RISK ALERT: Counter-trend trade detected against 200 EMA. Risk reduced to ", final_risk, "%");
         }
      }

      if (lots <= 0)
      {
         LogPrint("Invalid lot size - rejected");
         return;
      }

      LogPrint("Final Lot Size: ", lots);

      ulong ticket = 0;
      if (trade_signal == SIGNAL_LONG)
         ticket = m_trade_executor.OpenLong(lots, sl, tp1, tp2, pattern);
      else if (trade_signal == SIGNAL_SHORT)
         ticket = m_trade_executor.OpenShort(lots, sl, tp1, tp2, pattern);

      if (ticket > 0)
      {
         // Create position tracking
         SPosition position;
         position.ticket = ticket;
         position.direction = trade_signal;
         position.pattern_type = pattern_type;
         position.lot_size = lots;
         position.entry_price = calc_entry;
         position.stop_loss = sl;
         position.tp1 = tp1;
         position.tp2 = tp2;
         position.tp1_closed = false;
         position.tp2_closed = false;
         position.open_time = TimeCurrent();
         position.setup_quality = quality;
         position.pattern_name = pattern;
         position.at_breakeven = false;
         if (final_risk <= 0.0)
            final_risk = m_risk_manager.ComputeRiskPercent(lots, position.entry_price, sl);

         position.initial_risk_pct = final_risk;

         // Add to position coordinator
         if (m_position_coordinator != NULL)
            m_position_coordinator.AddPosition(position);

         // Increment daily trade counter
         if (m_risk_monitor != NULL)
            m_risk_monitor.IncrementTradesToday();

         // Add to risk manager
         m_risk_manager.AddPosition(position);

         // Calculate risk amount for stats
         double risk_amount = final_risk * AccountInfoDouble(ACCOUNT_BALANCE) / 100.0;
         if (m_trade_logger != NULL)
            m_trade_logger.LogTradeEntry(position, risk_amount);

         // Send notification
         if (m_enable_alerts || m_enable_push || m_enable_email)
         {
            string msg = StringFormat("%s opened: %s | Quality: %s",
                                      EnumToString(trade_signal),
                                      pattern,
                                      EnumToString(quality));
            SendNotificationAll(msg, m_enable_alerts, m_enable_push, m_enable_email);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Process confirmed signal                                         |
   //+------------------------------------------------------------------+
   void ProcessConfirmedSignal(SPendingSignal &pending_signal)
   {
      LogPrint(">>> EXECUTING CONFIRMED TRADE: ", pending_signal.pattern_name);
      LogPrint("    Quality: ", EnumToString(pending_signal.quality));

      // Recalculate TPs based on CURRENT entry price
      double current_entry = (pending_signal.signal_type == SIGNAL_LONG) ?
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                             SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double risk_distance = 0;
      double tp1_recalc = 0;
      double tp2_recalc = 0;

      if(pending_signal.signal_type == SIGNAL_LONG)
         risk_distance = current_entry - pending_signal.stop_loss;
      else
         risk_distance = pending_signal.stop_loss - current_entry;

      LogPrint("    Original Entry: ", pending_signal.entry_price, " | Current Entry: ", current_entry);
      LogPrint("    SL: ", pending_signal.stop_loss, " | Risk: ", DoubleToString(risk_distance, 2), " pts");

      // Use recalculated TPs
      double final_tp1 = 0;
      double final_tp2 = 0;

      // === ADAPTIVE TP SYSTEM ===
      if(m_use_adaptive_tp && m_adaptive_tp_manager != NULL && m_regime_classifier != NULL)
      {
         LogPrint("    Using ADAPTIVE TP System...");

         // Get current regime
         ENUM_REGIME_TYPE current_regime = m_regime_classifier.GetRegime();

         // Calculate adaptive TPs
         SAdaptiveTPResult adaptive_result = m_adaptive_tp_manager.CalculateAdaptiveTPs(
            pending_signal.signal_type,
            current_entry,
            pending_signal.stop_loss,
            current_regime,
            pending_signal.pattern_type
         );

         final_tp1 = adaptive_result.tp1;
         final_tp2 = adaptive_result.tp2;

         LogPrint("    Adaptive TP Mode: ", adaptive_result.tp_mode);
         LogPrint("    Adaptive Multipliers: TP1=", DoubleToString(adaptive_result.tp1_multiplier, 2),
                  "x | TP2=", DoubleToString(adaptive_result.tp2_multiplier, 2), "x");
         if(adaptive_result.next_resistance > 0)
            LogPrint("    Next Resistance: ", DoubleToString(adaptive_result.next_resistance, 2));
         if(adaptive_result.next_support > 0)
            LogPrint("    Next Support: ", DoubleToString(adaptive_result.next_support, 2));
      }
      else
      {
         // === FALLBACK: Original fixed TP calculation ===
         LogPrint("    Using FIXED TP multipliers (", m_tp1_distance, "x / ", m_tp2_distance, "x)");

         if(pending_signal.signal_type == SIGNAL_LONG)
         {
            tp1_recalc = current_entry + (risk_distance * m_tp1_distance);
            tp2_recalc = current_entry + (risk_distance * m_tp2_distance);
         }
         else
         {
            tp1_recalc = current_entry - (risk_distance * m_tp1_distance);
            tp2_recalc = current_entry - (risk_distance * m_tp2_distance);
         }

         final_tp1 = tp1_recalc;
         final_tp2 = tp2_recalc;
      }

      LogPrint("    Final TPs: TP1=", DoubleToString(final_tp1, 2), " | TP2=", DoubleToString(final_tp2, 2));

      // Ensure R:R meets minimum by using the farther TP distance
      double reward = MathAbs(MathMax(final_tp1, final_tp2) - current_entry);
      if (risk_distance > 0 && (reward / risk_distance) < m_min_rr_ratio)
      {
         double sign = (pending_signal.signal_type == SIGNAL_LONG) ? 1.0 : -1.0;
         double tp1_mult_needed = m_min_rr_ratio;
         final_tp1 = current_entry + sign * risk_distance * tp1_mult_needed;

         double tp2_mult = MathMax(m_tp2_distance, tp1_mult_needed + 0.3); // keep TP2 beyond TP1
         final_tp2 = current_entry + sign * risk_distance * tp2_mult;

         LogPrint("    R:R boosted to meet minimum: TP1=", DoubleToString(final_tp1, 2),
                  " TP2=", DoubleToString(final_tp2, 2), " (min RR ", m_min_rr_ratio, ")");
      }

      // Get risk percentage for this quality tier
      double base_risk = GetRiskForQuality(pending_signal.quality, pending_signal.pattern_name);
      double adjusted_risk = base_risk;

      // === DYNAMIC POSITION SIZING ===
      if(m_use_dynamic_sizing && m_dynamic_sizer != NULL && m_regime_classifier != NULL)
      {
         LogPrint("    Using DYNAMIC POSITION SIZING...");

         // Get current regime
         ENUM_REGIME_TYPE current_regime = m_regime_classifier.GetRegime();

         // Calculate dynamic risk
         adjusted_risk = m_dynamic_sizer.CalculateDynamicRisk(
            base_risk,
            pending_signal.pattern_type,
            pending_signal.quality,
            current_regime
         );

         LogPrint("    Dynamic Risk: ", DoubleToString(adjusted_risk, 2), "% (base: ", DoubleToString(base_risk, 2), "%)");
      }
      else
      {
         // Fallback to standard streak adjustment
         adjusted_risk = m_risk_manager.AdjustRiskForStreak(base_risk);
         LogPrint("    Using FIXED position sizing with streak adjustment");
      }

      // Apply short risk multiplier
      if (pending_signal.signal_type == SIGNAL_SHORT && m_short_risk_multiplier > 0)
      {
         adjusted_risk *= m_short_risk_multiplier;
         LogPrint("    Short risk bias applied: x", DoubleToString(m_short_risk_multiplier, 2),
                  " => ", DoubleToString(adjusted_risk, 2), "%");
      }

      LogPrint("    Final Risk: ", DoubleToString(adjusted_risk, 2), "%");

      // Calculate lot size based on CURRENT entry and SL
      double lot_size = m_risk_manager.CalculateLotSize(adjusted_risk, current_entry, pending_signal.stop_loss);

      if (lot_size <= 0)
      {
         LogPrint("ERROR: Invalid lot size calculated - trade rejected");
         return;
      }

      LogPrint("    Lot Size: ", lot_size);

      // Check if we can open new position
      if (!m_risk_manager.CanOpenNewPosition())
      {
         LogPrint("REJECT: Risk limits prevent new positions");
         return;
      }

      // Execute the confirmed trade
      string confirmed_pattern_name = pending_signal.pattern_name + " (Confirmed)";

      ExecuteTrade(pending_signal.signal_type, lot_size, pending_signal.stop_loss,
                   final_tp1, final_tp2,
                   pending_signal.quality, confirmed_pattern_name, pending_signal.pattern_type, adjusted_risk);
   }
};
