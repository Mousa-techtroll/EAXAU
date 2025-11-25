//+------------------------------------------------------------------+
//| SignalProcessor.mqh                                               |
//| Processes Signals and Applies All Validation Filters              |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"
#include "../Components/TrendDetector.mqh"
#include "../Components/RegimeClassifier.mqh"
#include "../Components/MacroBias.mqh"
#include "../Components/PriceAction.mqh"
#include "../Components/PriceActionLowVol.mqh"
#include "../Common/SignalValidator.mqh"
#include "../Common/SetupEvaluator.mqh"
#include "../Management/SignalManager.mqh"
#include "../Management/RiskManager.mqh"
#include "../Filters/MarketFilters.mqh"
#include "../Components/MomentumFilter.mqh"
#include "RiskMonitor.mqh"
#include "TradeOrchestrator.mqh"

//+------------------------------------------------------------------+
//| CSignalProcessor - Main signal detection and filtering          |
//+------------------------------------------------------------------+
class CSignalProcessor
{
private:
   // Component references
   CTrendDetector*       m_trend_detector;
   CRegimeClassifier*    m_regime_classifier;
   CMacroBias*           m_macro_bias;
   CPriceAction*         m_price_action;
   CPriceActionLowVol*   m_price_action_lowvol;
   CSignalValidator*     m_signal_validator;
   CSetupEvaluator*      m_setup_evaluator;
   CSignalManager*       m_signal_manager;
   CRiskManager*         m_risk_manager;
   CRiskMonitor*         m_risk_monitor;
   CTradeOrchestrator*   m_trade_orchestrator;
   CMomentumFilter*      m_momentum_filter;

   int                   m_handle_ma_200;
   int                   m_handle_adx_h1;

   // Momentum filter settings
   bool                  m_momentum_enabled;

   // Session/Time filters
   bool                  m_trade_asia;
   bool                  m_trade_london;
   bool                  m_trade_ny;
   int                   m_skip_start_hour;
   int                   m_skip_end_hour;

   // Mean reversion parameters
   double                m_mr_min_atr;
   double                m_mr_max_atr;
   double                m_mr_max_adx;
   double                m_mr_max_adx_filter;
   double                m_tf_min_atr;

   // 200 EMA filter
   bool                  m_use_daily_200ema;
   double                m_200ema_rsi_overbought;
   double                m_200ema_rsi_oversold;

   // Market filters (Simplified)
   bool                  m_enable_confidence_scoring;
   double                m_adx_ranging;


   // Hybrid session logic
   bool                  m_enable_hybrid_logic;
   double                m_asia_min_adx;
   double                m_asia_max_adx;
   double                m_london_min_adx;
   double                m_london_max_adx;
   double                m_ny_min_adx;
   double                m_ny_max_adx;

   // Pattern confidence
   int                   m_ma_fast_period;
   int                   m_ma_slow_period;
   int                   m_min_pattern_confidence;

   // Dynamic SL
   bool                  m_use_dynamic_sl;
   int                   m_min_sl_points;
   double                m_atr_multiplier_sl;

   // Take profits
   double                m_tp1_distance;
   double                m_tp2_distance;

   // Confirmation
   bool                  m_enable_confirmation;

   // Short protection
   double                m_bull_mr_short_adx_cap;
   int                   m_bull_mr_short_macro_max;
   double                m_short_risk_multiplier;
   double                m_short_trend_min_adx;
   double                m_short_trend_max_adx;
   int                   m_short_mr_macro_max;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSignalProcessor(CTrendDetector* trend, CRegimeClassifier* regime, CMacroBias* macro,
                    CPriceAction* pa, CPriceActionLowVol* pa_lowvol,
                    CSignalValidator* validator, CSetupEvaluator* evaluator,
                    CSignalManager* sig_mgr, CRiskManager* risk_mgr,
                    CRiskMonitor* risk_mon, CTradeOrchestrator* orchestrator,
                    int handle_ma200, int handle_adx_h1,
                    // Session/Time
                    bool trade_asia, bool trade_london, bool trade_ny,
                    int skip_start, int skip_end,
                    // Mean reversion
                    double mr_min_atr, double mr_max_atr, double mr_max_adx, double mr_max_adx_filter, double tf_min_atr,
                    // 200 EMA
                    bool use_200ema, double rsi_overbought, double rsi_oversold,
                    // Market filters (Simplified)
                    bool confidence_filter, double adx_ranging,
                    // Hybrid logic
                    bool hybrid_logic, double asia_min, double asia_max, double london_min, double london_max,
                    double ny_min, double ny_max,
                    // Confidence
                    int ma_fast, int ma_slow, int min_confidence,
                    // Dynamic SL
                    bool dynamic_sl, int min_sl_pts, double atr_mult_sl,
                    // TPs
                    double tp1_dist, double tp2_dist,
                    // Confirmation
                    bool enable_confirm,
                    // Short protection
                    double bull_mr_short_adx_cap, int bull_mr_short_macro_max, double short_risk_multiplier,
                    double short_trend_min_adx, double short_trend_max_adx, int short_mr_macro_max)
   {
      m_trend_detector = trend;
      m_regime_classifier = regime;
      m_macro_bias = macro;
      m_price_action = pa;
      m_price_action_lowvol = pa_lowvol;
      m_signal_validator = validator;
      m_setup_evaluator = evaluator;
      m_signal_manager = sig_mgr;
      m_risk_manager = risk_mgr;
      m_risk_monitor = risk_mon;
      m_trade_orchestrator = orchestrator;
      m_handle_ma_200 = handle_ma200;
      m_handle_adx_h1 = handle_adx_h1;

      m_trade_asia = trade_asia;
      m_trade_london = trade_london;
      m_trade_ny = trade_ny;
      m_skip_start_hour = skip_start;
      m_skip_end_hour = skip_end;

      m_mr_min_atr = mr_min_atr;
      m_mr_max_atr = mr_max_atr;
      m_mr_max_adx = mr_max_adx;
      m_mr_max_adx_filter = mr_max_adx_filter;
      m_tf_min_atr = tf_min_atr;

      m_use_daily_200ema = use_200ema;
      m_200ema_rsi_overbought = rsi_overbought;
      m_200ema_rsi_oversold = rsi_oversold;

      m_enable_confidence_scoring = confidence_filter;
      m_adx_ranging = adx_ranging;

      m_enable_hybrid_logic = hybrid_logic;
      m_asia_min_adx = asia_min;
      m_asia_max_adx = asia_max;
      m_london_min_adx = london_min;
      m_london_max_adx = london_max;
      m_ny_min_adx = ny_min;
      m_ny_max_adx = ny_max;

      m_ma_fast_period = ma_fast;
      m_ma_slow_period = ma_slow;
      m_min_pattern_confidence = min_confidence;

      m_use_dynamic_sl = dynamic_sl;
      m_min_sl_points = min_sl_pts;
      m_atr_multiplier_sl = atr_mult_sl;

      m_tp1_distance = tp1_dist;
      m_tp2_distance = tp2_dist;
      m_enable_confirmation = enable_confirm;
      m_bull_mr_short_adx_cap = bull_mr_short_adx_cap;
      m_bull_mr_short_macro_max = bull_mr_short_macro_max;
      m_short_risk_multiplier = short_risk_multiplier;
      m_short_trend_min_adx = short_trend_min_adx;
      m_short_trend_max_adx = short_trend_max_adx;
      m_short_mr_macro_max = short_mr_macro_max;

      // Default momentum to disabled
      m_momentum_filter = NULL;
      m_momentum_enabled = false;
   }

   //+------------------------------------------------------------------+
   //| Configure momentum filter                                         |
   //+------------------------------------------------------------------+
   void ConfigureMomentumFilter(CMomentumFilter* momentum, bool enabled)
   {
      m_momentum_filter = momentum;
      m_momentum_enabled = enabled;

      if(m_momentum_enabled && m_momentum_filter != NULL)
         LogPrint("SignalProcessor: Momentum Filter ENABLED");
   }

   //+------------------------------------------------------------------+
   //| Main signal processing function                                  |
   //+------------------------------------------------------------------+
   void CheckForNewSignals()
   {
      // Pre-flight checks
      // Check 1: Session-based filtering (Asia/London/NY)
      if (!IsSessionAllowed(m_trade_asia, m_trade_london, m_trade_ny))
      {
         LogPrint("Outside allowed trading session");
         return;
      }

      // Check 2: Hour-based filtering (skip specific hours)
      if (!IsTradingHourAllowed(m_skip_start_hour, m_skip_end_hour))
      {
         LogPrint("Inside skip hours zone (", m_skip_start_hour, "-", m_skip_end_hour, ")");
         return;
      }

      if (!m_risk_manager.CanOpenNewPosition())
      {
         LogPrint("Risk limits prevent new positions");
         return;
      }

      // Get current state
      ENUM_TREND_DIRECTION daily_trend = m_trend_detector.GetDailyTrend();
      ENUM_TREND_DIRECTION h4_trend = m_trend_detector.GetH4Trend();
      ENUM_REGIME_TYPE regime = m_regime_classifier.GetRegime();
      int macro_score = m_macro_bias.GetBiasScore();
      double current_adx = m_regime_classifier.GetADX();

      // Check for signals (prioritize low vol patterns in low vol environments)
      SPriceActionData signal_data;
      ENUM_SIGNAL_TYPE pa_signal = SIGNAL_NONE;
      string pattern_name = "";
      ENUM_PATTERN_TYPE pattern_type = PATTERN_NONE;

      // Get current ATR to determine which patterns to try first
      double current_atr = m_price_action_lowvol.GetATR();

      LogPrint("=== SIGNAL CHECK ===");
      LogPrint("Daily: ", EnumToString(daily_trend), " | H4: ", EnumToString(h4_trend));
      LogPrint("Regime: ", EnumToString(regime), " | Macro: ", macro_score, " | ATR: ", current_atr);

      // Strategy Selection: Check if ATR is within Mean Reversion range
      bool try_mean_reversion = (current_atr > 0 && current_atr >= m_mr_min_atr && current_atr <= m_mr_max_atr);

      if (try_mean_reversion)
      {
         LogPrint(">>> ATR IN MEAN REVERSION RANGE (", m_mr_min_atr, "-", m_mr_max_atr, ") - Trying low vol patterns first...");

         if (m_price_action_lowvol.CheckAllPatterns())
         {
            signal_data = m_price_action_lowvol.GetSignal();
            pa_signal = signal_data.signal;
            pattern_name = signal_data.pattern_name;
            pattern_type = signal_data.pattern_type;
            LogPrint(">>> MEAN REVERSION PATTERN DETECTED: ", pattern_name);
         }
         else
         {
            LogPrint(">>> No mean reversion pattern found, trying trend-following patterns...");
            pa_signal = m_price_action.GetSignal();
            pattern_name = m_price_action.GetPatternName();
            pattern_type = m_price_action.GetPatternType();
         }
      }
      else
      {
         // ATR outside mean reversion range: Use trend-following patterns
         LogPrint(">>> ATR OUTSIDE MR RANGE (ATR=", current_atr, " vs ", m_mr_min_atr, "-", m_mr_max_atr, ") - Using trend-following patterns");
         pa_signal = m_price_action.GetSignal();
         pattern_name = m_price_action.GetPatternName();
         pattern_type = m_price_action.GetPatternType();
      }

      LogPrint("PA Signal: ", EnumToString(pa_signal), " | Pattern: ", pattern_name, " | Type: ", EnumToString(pattern_type));

      // Check if valid signal
      if (pa_signal == SIGNAL_NONE)
      {
         LogPrint("NO SIGNAL - No pattern detected");
         return;
      }

      /*if (daily_trend == TREND_NEUTRAL)
      {
         LogPrint("NO TRADE - Daily trend neutral");
         return;
      }*/

      // Short-specific strategy filter (Gold bias bullish; shorts must be selective)
      if (pa_signal == SIGNAL_SHORT)
      {
         bool is_mr = m_signal_validator.IsMeanReversionPattern(pattern_type);
         bool session_ok = IsLondonSession() || IsNewYorkSession();
         if (!session_ok)
         {
            LogPrint("REJECT: Shorts restricted to London/NY sessions");
            return;
         }

         // D1 200 EMA context
         double ma200_buf[];
         ArraySetAsSeries(ma200_buf, true);
         double d1_ema_200 = 0;
         if (CopyBuffer(m_handle_ma_200, 0, 0, 1, ma200_buf) > 0)
            d1_ema_200 = ma200_buf[0];
         double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool above_200 = (d1_ema_200 > 0 && current_price > d1_ema_200);

         if (is_mr)
         {
            if (above_200)
            {
               LogPrint("REJECT: MR short blocked above D1 200 EMA");
               return;
            }
            if (macro_score > m_short_mr_macro_max)
            {
               LogPrint("REJECT: MR short blocked (macro not bearish enough: ", macro_score, " > ", m_short_mr_macro_max, ")");
               return;
            }
            if (m_bull_mr_short_adx_cap > 0 && current_adx > m_bull_mr_short_adx_cap)
            {
               LogPrint("REJECT: MR short ADX too high (", DoubleToString(current_adx,1), " > ", m_bull_mr_short_adx_cap, ")");
               return;
            }
         }
         else // Trend-following shorts
         {
            bool trend_ok = (h4_trend == TREND_BEARISH) && (daily_trend == TREND_BEARISH || macro_score <= -1);
            if (!trend_ok)
            {
               LogPrint("REJECT: Trend short requires H4 Bearish and (D1 Bearish or macro<=-1)");
               return;
            }
            if (current_adx < m_short_trend_min_adx || current_adx > m_short_trend_max_adx)
            {
               LogPrint("REJECT: Trend short ADX filter (", DoubleToString(current_adx,1), " not in ", m_short_trend_min_adx, "-", m_short_trend_max_adx, ")");
               return;
            }
            if (regime == REGIME_CHOPPY || regime == REGIME_UNKNOWN)
            {
               LogPrint("REJECT: Trend short blocked in choppy/unknown regime");
               return;
            }
         }
      }

      // CONDITIONAL VALIDATION BY PATTERN TYPE
      bool validation_passed = false;

      if (m_signal_validator.IsMeanReversionPattern(pattern_type))
      {
         LogPrint(">>> MEAN REVERSION PATTERN - Using mean reversion validation");
         validation_passed = m_signal_validator.ValidateMeanReversionConditions(pattern_type, regime, pa_signal, current_atr, current_adx,
                                                                                m_mr_max_adx, m_mr_min_atr, m_mr_max_atr);
      }
      else
      {
         LogPrint(">>> TREND-FOLLOWING PATTERN - Using trend-following validation");
         validation_passed = m_signal_validator.ValidateTrendFollowingConditions(daily_trend, h4_trend, regime, macro_score, pa_signal, pattern_type, current_atr, m_tf_min_atr);
      }

      if (!validation_passed)
      {
         LogPrint(">>> VALIDATION FAILED - Trade rejected");
         return;
      }

      // Range Box should only trade in clear ranging regimes
      if (pattern_type == PATTERN_RANGE_BOX && regime != REGIME_RANGING)
      {
         LogPrint("REJECT: Range Box allowed only in RANGING regime (current ", EnumToString(regime), ")");
         return;
      }

      // Extra guard: MR shorts need bearish macro backdrop
      if (pa_signal == SIGNAL_SHORT && m_signal_validator.IsMeanReversionPattern(pattern_type) && macro_score > -1)
      {
         LogPrint("REJECT: MR short blocked (macro not bearish enough: ", macro_score, ")");
         return;
      }

      // Block weak MR shorts in strong bulls (price > D1 200 EMA) unless macro + ADX are supportive
      if (pa_signal == SIGNAL_SHORT && m_signal_validator.IsMeanReversionPattern(pattern_type) && m_use_daily_200ema)
      {
         double ma200_buf[];
         ArraySetAsSeries(ma200_buf, true);
         if (CopyBuffer(m_handle_ma_200, 0, 0, 1, ma200_buf) > 0)
         {
            double d1_ema_200 = ma200_buf[0];
            double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if (current_price > d1_ema_200)
            {
               double adx_cap = (m_bull_mr_short_adx_cap > 0) ? m_bull_mr_short_adx_cap : m_mr_max_adx_filter;
               if (macro_score > m_bull_mr_short_macro_max || current_adx > adx_cap)
               {
                  LogPrint("REJECT: MR short above 200 EMA blocked (Macro ", macro_score,
                           " / ADX ", DoubleToString(current_adx, 1), " > cap ", adx_cap, ")");
                  return;
               }
            }
         }
      }

      LogPrint(">>> VALIDATION PASSED - Proceeding with trade");

      // SMC Order Block Validation
      if (m_signal_validator.IsSMCEnabled())
      {
         double smc_entry = (pa_signal == SIGNAL_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double smc_sl = 0;
         if (m_signal_validator.IsMeanReversionPattern(pattern_type))
         {
            SPriceActionData lowvol_data = m_price_action_lowvol.GetSignal();
            smc_sl = lowvol_data.stop_loss;
         }
         else
         {
            smc_sl = m_price_action.GetStopLoss();
         }

         int smc_confluence = 0;
         if (!m_signal_validator.ValidateSMCConditions(pa_signal, smc_entry, smc_sl, smc_confluence))
         {
            LogPrint(">>> SMC VALIDATION FAILED - Trade rejected");
            return;
         }
         LogPrint(">>> SMC VALIDATION PASSED - Confluence Score: ", smc_confluence);
      }

      // Momentum Filter Validation
      if (m_momentum_enabled && m_momentum_filter != NULL)
      {
         bool momentum_ok = false;
         if (pa_signal == SIGNAL_LONG)
            momentum_ok = m_momentum_filter.ValidateLongMomentum();
         else if (pa_signal == SIGNAL_SHORT)
            momentum_ok = m_momentum_filter.ValidateShortMomentum();

         if (!momentum_ok)
         {
            LogPrint(">>> MOMENTUM VALIDATION FAILED - Trade rejected");
            return;
         }
         LogPrint(">>> MOMENTUM VALIDATION PASSED - Score: ", m_momentum_filter.GetMomentumScore());
      }

      // Evaluate setup quality
      ENUM_SETUP_QUALITY quality = m_setup_evaluator.EvaluateSetupQuality(daily_trend, h4_trend, regime, macro_score, pattern_name);

      if (quality == SETUP_NONE)
      {
         LogPrint("Setup quality too low - rejected");
         return;
      }

      // Determine risk with pattern-specific allocation
      double base_risk = m_trade_orchestrator.GetRiskForQuality(quality, pattern_name);
      double adjusted_risk = m_risk_manager.AdjustRiskForStreak(base_risk);
      if (pa_signal == SIGNAL_SHORT && m_short_risk_multiplier > 0)
      {
         adjusted_risk *= m_short_risk_multiplier;
         LogPrint(">>> Short risk bias applied: x", DoubleToString(m_short_risk_multiplier, 2),
                  " => ", adjusted_risk, "%");
      }

      // Calculate position size - use correct source based on pattern type
      double entry_price, stop_loss, take_profit;

      if (m_signal_validator.IsMeanReversionPattern(pattern_type))
      {
         // Mean reversion pattern was used
         SPriceActionData lowvol_data = m_price_action_lowvol.GetSignal();
         entry_price = lowvol_data.entry_price;
         stop_loss = lowvol_data.stop_loss;
         take_profit = lowvol_data.take_profit;
         LogPrint(">>> Using Mean Reversion pattern prices: Entry=", entry_price, " SL=", stop_loss, " TP=", take_profit);
      }
      else
      {
         // Trend-following pattern was used
         entry_price = m_price_action.GetEntryPrice();
         stop_loss = m_price_action.GetStopLoss();
         take_profit = m_price_action.GetTakeProfit();
         LogPrint(">>> Using Trend-Following pattern prices: Entry=", entry_price, " SL=", stop_loss, " TP=", take_profit);
      }

      // =================================================================
      // UNIFIED FILTERING LOGIC
      // =================================================================
      
      // --- Get H1 ADX Data (used by multiple filters) ---
      double filter_adx = 0.0;
      double adx_buffer[];
      ArraySetAsSeries(adx_buffer, true);
      if (CopyBuffer(m_handle_adx_h1, 0, 0, 1, adx_buffer) > 0)
      {
         filter_adx = adx_buffer[0];
      }

      // --- Filter 1: Hybrid Session Logic (Primary Filter) ---
      if (m_enable_hybrid_logic)
      {
         LogPrint(">>> Applying Hybrid Session Filters (ADX: ", DoubleToString(filter_adx, 1), ")...");
         if (IsAsiaSession())
         {
            if (filter_adx > m_asia_max_adx) {
               LogPrint(">>> HYBRID REJECT: Asia Session + High ADX (", DoubleToString(filter_adx,1), " > ", m_asia_max_adx, ")");
               return;
            }
            if (filter_adx < m_asia_min_adx) {
               LogPrint(">>> HYBRID REJECT: Asia Session + Dead Market (", DoubleToString(filter_adx,1), " < ", m_asia_min_adx, ")");
               return;
            }
         }
         else if (IsLondonSession())
         {
            if (filter_adx < m_london_min_adx) {
               LogPrint(">>> HYBRID REJECT: London Session + Low ADX (", DoubleToString(filter_adx,1), " < ", m_london_min_adx, ")");
               return;
            }
            if (filter_adx > m_london_max_adx) {
               LogPrint(">>> HYBRID REJECT: London Session + Max ADX (", DoubleToString(filter_adx,1), " > ", m_london_max_adx, ")");
               return;
            }
         }
         else if (IsNewYorkSession())
         {
            if (filter_adx < m_ny_min_adx) {
               LogPrint(">>> HYBRID REJECT: NY Session + Low ADX (", DoubleToString(filter_adx,1), " < ", m_ny_min_adx, ")");
               return;
            }
            if (filter_adx > m_ny_max_adx) {
               LogPrint(">>> HYBRID REJECT: NY Session + Max ADX (", DoubleToString(filter_adx,1), " > ", m_ny_max_adx, ")");
               return;
            }
         }
         LogPrint(">>> Hybrid Filter: PASS");
      }
      
      // --- Filter 2: Pattern Confidence Scoring ---
      if (m_enable_confidence_scoring && !m_signal_validator.IsMeanReversionPattern(pattern_type))
      {
         int confidence = CalculatePatternConfidence(pattern_name, entry_price, m_ma_fast_period, m_ma_slow_period, current_atr, filter_adx);
         if (confidence < m_min_pattern_confidence)
         {
            LogPrint(">>> CONFIDENCE REJECT: Pattern confidence too low (", confidence, "/100 < ", m_min_pattern_confidence, ")");
            return;
         }
         LogPrint(">>> Confidence Filter: PASS (", confidence, "/100)");
      }

      LogPrint(">>> ALL FILTERS PASSED");

      // --- Dynamic Stop Loss Calculation ---
      if (m_use_dynamic_sl)
      {
         int dir = (pa_signal == SIGNAL_LONG) ? 1 : -1;
         double improved_sl = CalculateImprovedStopLoss(entry_price, dir, m_min_sl_points, m_atr_multiplier_sl, current_atr);
         LogPrint(">>> Dynamic SL: Original=", stop_loss, " | Improved=", improved_sl);
         stop_loss = improved_sl;
      }

      double lot_size = m_risk_manager.CalculateLotSize(adjusted_risk, entry_price, stop_loss);

      if (lot_size <= 0)
      {
         LogPrint("Invalid lot size - rejected");
         return;
      }

      // Calculate take profits - different logic for mean reversion vs trend-following
      double tp1, tp2;

      if (m_signal_validator.IsMeanReversionPattern(pattern_type))
      {
         // Mean reversion targets BB middle for quicker profits
         LogPrint(">>> Calculating MEAN REVERSION take profits (targeting BB middle)...");

         double bb_middle = m_price_action_lowvol.GetBBMiddle();

         // Fallback if BB middle failed
         if(bb_middle == 0.0)
         {
            LogPrint(">>> WARNING: Could not get BB middle, using pattern TP");
            bb_middle = take_profit;
         }

         if (pa_signal == SIGNAL_LONG)
         {
            tp1 = bb_middle;
            double middle_distance = bb_middle - entry_price;
            tp2 = bb_middle + (middle_distance * 0.5);
         }
         else  // SHORT
         {
            tp1 = bb_middle;
            double middle_distance = entry_price - bb_middle;
            tp2 = bb_middle - (middle_distance * 0.5);
         }

         LogPrint(">>> Mean Reversion TPs: Entry=", entry_price, " | BB Middle=", bb_middle, " | TP1=", tp1, " | TP2=", tp2);
      }
      else
      {
         // Trend-following: Use standard logic
         double stop_distance = MathAbs(entry_price - stop_loss);

         double tp1_mult = m_tp1_distance;
         double tp2_mult = m_tp2_distance;

         tp1 = (pa_signal == SIGNAL_LONG) ? entry_price + stop_distance * tp1_mult : entry_price - stop_distance * tp1_mult;
         tp2 = (pa_signal == SIGNAL_LONG) ? entry_price + stop_distance * tp2_mult : entry_price - stop_distance * tp2_mult;

         LogPrint(">>> Trend-Following TPs: Entry=", entry_price, " | TP1=", tp1, " (", tp1_mult, "x SL) | TP2=", tp2, " (", tp2_mult, "x SL)");
      }

      // Check if confirmation candle is required
      if (m_enable_confirmation)
      {
         // Store signal as pending - will be confirmed on next bar
         if (m_signal_manager != NULL)
         {
            m_signal_manager.StorePendingSignal(pa_signal, pattern_name, pattern_type, entry_price, stop_loss, tp1, tp2,
                                                quality, regime, daily_trend, h4_trend, macro_score);
         }
      }
      else
      {
         // Execute trade immediately
         LogPrint(">>> IMMEDIATE EXECUTION (confirmation disabled)");
         m_trade_orchestrator.ExecuteTrade(pa_signal, lot_size, stop_loss, tp1, tp2, quality, pattern_name, pattern_type, adjusted_risk);
      }
   }

   //+------------------------------------------------------------------+
   //| Revalidate a pending signal before execution (confirmation bar) |
   //+------------------------------------------------------------------+
   bool RevalidatePending(SPendingSignal &pending)
   {
      // Update core state to use the latest bar data
      m_trend_detector.Update();
      m_regime_classifier.Update();
      m_macro_bias.Update();

      // Session / hour filters
      if (!IsSessionAllowed(m_trade_asia, m_trade_london, m_trade_ny))
      {
         LogPrint("CONFIRMATION REJECT: Outside allowed trading session");
         return false;
      }

      if (!IsTradingHourAllowed(m_skip_start_hour, m_skip_end_hour))
      {
         LogPrint("CONFIRMATION REJECT: Inside skip hours zone");
         return false;
      }

      // Hybrid ADX filters (use current H1 ADX)
      double filter_adx = 0.0;
      double adx_buffer[];
      ArraySetAsSeries(adx_buffer, true);
      if (CopyBuffer(m_handle_adx_h1, 0, 0, 1, adx_buffer) > 0)
         filter_adx = adx_buffer[0];

      if (m_enable_hybrid_logic)
      {
         if (IsAsiaSession())
         {
            if (filter_adx > m_asia_max_adx || filter_adx < m_asia_min_adx)
            {
               LogPrint("CONFIRMATION REJECT: Asia hybrid filter (ADX=", DoubleToString(filter_adx,1), ")");
               return false;
            }
         }
         else if (IsLondonSession())
         {
            if (filter_adx < m_london_min_adx || filter_adx > m_london_max_adx)
            {
               LogPrint("CONFIRMATION REJECT: London hybrid filter (ADX=", DoubleToString(filter_adx,1), ")");
               return false;
            }
         }
         else if (IsNewYorkSession())
         {
            if (filter_adx < m_ny_min_adx || filter_adx > m_ny_max_adx)
            {
               LogPrint("CONFIRMATION REJECT: NY hybrid filter (ADX=", DoubleToString(filter_adx,1), ")");
               return false;
            }
         }
      }

      // Fresh state for validation
      ENUM_TREND_DIRECTION daily_trend = m_trend_detector.GetDailyTrend();
      ENUM_TREND_DIRECTION h4_trend = m_trend_detector.GetH4Trend();
      ENUM_REGIME_TYPE regime = m_regime_classifier.GetRegime();
      int macro_score = m_macro_bias.GetBiasScore();
      double current_atr = m_price_action_lowvol.GetATR();
      double current_adx = m_regime_classifier.GetADX();

      bool validation_passed = false;
      if (m_signal_validator.IsMeanReversionPattern(pending.pattern_type))
      {
         validation_passed = m_signal_validator.ValidateMeanReversionConditions(pending.pattern_type, regime,
                                                                                pending.signal_type, current_atr, current_adx,
                                                                                m_mr_max_adx, m_mr_min_atr, m_mr_max_atr);
      }
      else
      {
         validation_passed = m_signal_validator.ValidateEntryConditions(daily_trend, h4_trend, regime,
                                                                        macro_score, pending.signal_type, pending.pattern_type);
      }

      if (!validation_passed)
      {
         LogPrint("CONFIRMATION REJECT: Validation failed on latest data");
         return false;
      }

      if (pending.signal_type == SIGNAL_SHORT)
      {
         bool is_mr = m_signal_validator.IsMeanReversionPattern(pending.pattern_type);
         bool session_ok = IsLondonSession() || IsNewYorkSession();
         if (!session_ok)
         {
            LogPrint("CONFIRMATION REJECT: Shorts restricted to London/NY sessions");
            return false;
         }

         double ma200_buf[];
         ArraySetAsSeries(ma200_buf, true);
         double d1_ema_200 = 0;
         if (CopyBuffer(m_handle_ma_200, 0, 0, 1, ma200_buf) > 0)
            d1_ema_200 = ma200_buf[0];
         double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool above_200 = (d1_ema_200 > 0 && current_price > d1_ema_200);

         if (is_mr)
         {
            if (above_200)
            {
               LogPrint("CONFIRMATION REJECT: MR short blocked above D1 200 EMA");
               return false;
            }
            if (macro_score > m_short_mr_macro_max)
            {
               LogPrint("CONFIRMATION REJECT: MR short blocked (macro not bearish enough: ", macro_score, " > ", m_short_mr_macro_max, ")");
               return false;
            }
            if (m_bull_mr_short_adx_cap > 0 && current_adx > m_bull_mr_short_adx_cap)
            {
               LogPrint("CONFIRMATION REJECT: MR short ADX too high (", DoubleToString(current_adx,1), " > ", m_bull_mr_short_adx_cap, ")");
               return false;
            }
         }
         else
         {
            bool trend_ok = (h4_trend == TREND_BEARISH) && (daily_trend == TREND_BEARISH || macro_score <= -1);
            if (!trend_ok)
            {
               LogPrint("CONFIRMATION REJECT: Trend short requires H4 Bearish and (D1 Bearish or macro<=-1)");
               return false;
            }
            if (current_adx < m_short_trend_min_adx || current_adx > m_short_trend_max_adx)
            {
               LogPrint("CONFIRMATION REJECT: Trend short ADX filter (", DoubleToString(current_adx,1), " not in ", m_short_trend_min_adx, "-", m_short_trend_max_adx, ")");
               return false;
            }
            if (regime == REGIME_CHOPPY || regime == REGIME_UNKNOWN)
            {
               LogPrint("CONFIRMATION REJECT: Trend short blocked in choppy/unknown regime");
               return false;
            }
         }
      }

      if (pending.pattern_type == PATTERN_RANGE_BOX && regime != REGIME_RANGING)
      {
         LogPrint("CONFIRMATION REJECT: Range Box allowed only in RANGING regime (current ", EnumToString(regime), ")");
         return false;
      }

      // Optional confidence filter on confirmation
      if (m_enable_confidence_scoring && !m_signal_validator.IsMeanReversionPattern(pending.pattern_type))
      {
         int confidence = CalculatePatternConfidence(pending.pattern_name, pending.entry_price,
                                                     m_ma_fast_period, m_ma_slow_period,
                                                     current_atr, filter_adx);
         if (confidence < m_min_pattern_confidence)
         {
            LogPrint("CONFIRMATION REJECT: Confidence ", confidence, " < ", m_min_pattern_confidence);
            return false;
         }
      }

      // SMC validation on confirmation
      if (m_signal_validator.IsSMCEnabled())
      {
         double smc_entry = (pending.signal_type == SIGNAL_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int smc_confluence = 0;
         if (!m_signal_validator.ValidateSMCConditions(pending.signal_type, smc_entry, pending.stop_loss, smc_confluence))
         {
            LogPrint("CONFIRMATION REJECT: SMC validation failed");
            return false;
         }
         LogPrint("CONFIRMATION: SMC validation passed (confluence: ", smc_confluence, ")");
      }

      return true;
   }
};
