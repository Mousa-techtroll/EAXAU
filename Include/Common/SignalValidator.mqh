//+------------------------------------------------------------------+
//| SignalValidator.mqh                                               |
//| Signal Validation Logic - Pattern Type and Entry Condition Checks|
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "Enums.mqh"
#include "Structs.mqh"
#include "Utils.mqh"
#include "../Components/TrendDetector.mqh"
#include "../Components/RegimeClassifier.mqh"
#include "../Components/PriceAction.mqh"
#include "../Components/PriceActionLowVol.mqh"
#include "../Components/SMCOrderBlocks.mqh"

//+------------------------------------------------------------------+
//| CSignalValidator - Validates trading signals and conditions      |
//+------------------------------------------------------------------+
class CSignalValidator
{
private:
   // External references needed for validation
   CTrendDetector*      m_trend_detector;
   CRegimeClassifier*   m_regime_classifier;
   CPriceAction*        m_price_action;
   CPriceActionLowVol*  m_price_action_lowvol;
   CSMCOrderBlocks*     m_smc_order_blocks;

   // Indicator handles
   int                  m_handle_ma_200;

   // Configuration parameters
   bool                 m_use_h4_primary;
   bool                 m_use_daily_200ema;
   double               m_rsi_overbought;
   double               m_rsi_oversold;
   double               m_validation_strong_adx;
   int                  m_validation_macro_strong;

   // SMC Configuration
   bool                 m_smc_enabled;
   int                  m_smc_min_confluence;
   bool                 m_smc_block_counter;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSignalValidator(CTrendDetector* trend, CRegimeClassifier* regime,
                    CPriceAction* pa, CPriceActionLowVol* pa_lowvol,
                    int ma_200_handle, bool use_h4, bool use_200ema,
                    double rsi_ob, double rsi_os, double strong_adx, int macro_strong)
   {
      m_trend_detector = trend;
      m_regime_classifier = regime;
      m_price_action = pa;
      m_price_action_lowvol = pa_lowvol;
      m_handle_ma_200 = ma_200_handle;
      m_use_h4_primary = use_h4;
      m_use_daily_200ema = use_200ema;
      m_rsi_overbought = rsi_ob;
      m_rsi_oversold = rsi_os;
      m_validation_strong_adx = strong_adx;
      m_validation_macro_strong = macro_strong;

      // SMC defaults (disabled until configured)
      m_smc_order_blocks = NULL;
      m_smc_enabled = false;
      m_smc_min_confluence = 60;
      m_smc_block_counter = true;
   }

   //+------------------------------------------------------------------+
   //| Configure SMC Order Blocks integration                            |
   //+------------------------------------------------------------------+
   void ConfigureSMC(CSMCOrderBlocks* smc, bool enabled, int min_confluence, bool block_counter)
   {
      m_smc_order_blocks = smc;
      m_smc_enabled = enabled;
      m_smc_min_confluence = min_confluence;
      m_smc_block_counter = block_counter;

      if(m_smc_enabled && m_smc_order_blocks != NULL)
         LogPrint("SignalValidator: SMC integration ENABLED (min confluence: ", min_confluence, ")");
   }

   //+------------------------------------------------------------------+
   //| Validate SMC conditions for entry                                 |
   //+------------------------------------------------------------------+
   bool ValidateSMCConditions(ENUM_SIGNAL_TYPE signal, double entry_price, double stop_loss, int &confluence_score)
   {
      if(!m_smc_enabled || m_smc_order_blocks == NULL)
      {
         confluence_score = 50;  // Neutral score when SMC disabled
         return true;  // Pass if SMC not enabled
      }

      // Get confluence score
      confluence_score = m_smc_order_blocks.GetConfluenceScore(signal, entry_price);

      // Check if entry is supported by SMC
      bool smc_supports = false;
      if(signal == SIGNAL_LONG)
         smc_supports = m_smc_order_blocks.SupportsLongEntry(entry_price, stop_loss);
      else if(signal == SIGNAL_SHORT)
         smc_supports = m_smc_order_blocks.SupportsShortEntry(entry_price, stop_loss);

      // Log SMC analysis
      SSMCAnalysis analysis = m_smc_order_blocks.GetAnalysis();
      LogPrint(">>> SMC Analysis: Score=", analysis.smc_score, " | Confluence=", confluence_score);
      LogPrint(">>> SMC Zones: In Bullish OB=", analysis.in_bullish_ob ? "YES" : "NO",
               " | In Bearish OB=", analysis.in_bearish_ob ? "YES" : "NO");
      LogPrint(">>> SMC BOS: ", EnumToString(analysis.recent_bos));

      // Block counter-SMC trades if enabled
      if(m_smc_block_counter)
      {
         // Only block on STRONG opposing bias (score <= -50 or >= 50)
         if(signal == SIGNAL_LONG && analysis.smc_score <= -50)
         {
            LogPrint(">>> SMC REJECT: Long blocked - strong bearish SMC bias (", analysis.smc_score, ")");
            return false;
         }
         if(signal == SIGNAL_SHORT && analysis.smc_score >= 50)
         {
            LogPrint(">>> SMC REJECT: Short blocked - strong bullish SMC bias (", analysis.smc_score, ")");
            return false;
         }

         // Block trades directly in opposing zones (but only if also against BOS)
         if(signal == SIGNAL_LONG && analysis.in_bearish_ob &&
            (analysis.recent_bos == BOS_BEARISH || analysis.recent_bos == CHOCH_BEARISH))
         {
            LogPrint(">>> SMC REJECT: Long blocked - in bearish OB with bearish structure");
            return false;
         }
         if(signal == SIGNAL_SHORT && analysis.in_bullish_ob &&
            (analysis.recent_bos == BOS_BULLISH || analysis.recent_bos == CHOCH_BULLISH))
         {
            LogPrint(">>> SMC REJECT: Short blocked - in bullish OB with bullish structure");
            return false;
         }
      }

      // Only reject on very low confluence (below 40) - allow most trades through
      if(confluence_score < 40)
      {
         LogPrint(">>> SMC REJECT: Very low confluence (", confluence_score, " < 40)");
         return false;
      }

      LogPrint(">>> SMC PASSED: Confluence=", confluence_score, " | Supports=", smc_supports ? "YES" : "NO");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get SMC confluence score for current conditions                   |
   //+------------------------------------------------------------------+
   int GetSMCConfluenceScore(ENUM_SIGNAL_TYPE signal, double entry_price)
   {
      if(!m_smc_enabled || m_smc_order_blocks == NULL)
         return 50;  // Neutral score

      return m_smc_order_blocks.GetConfluenceScore(signal, entry_price);
   }

   //+------------------------------------------------------------------+
   //| Check if SMC is enabled                                           |
   //+------------------------------------------------------------------+
   bool IsSMCEnabled() { return m_smc_enabled && m_smc_order_blocks != NULL; }

   //+------------------------------------------------------------------+
   //| Check if pattern is mean reversion type                          |
   //+------------------------------------------------------------------+
   bool IsMeanReversionPattern(ENUM_PATTERN_TYPE pattern)
   {
      return (pattern == PATTERN_BB_MEAN_REVERSION ||
              pattern == PATTERN_RANGE_BOX ||
              pattern == PATTERN_FALSE_BREAKOUT_FADE);
   }

   //+------------------------------------------------------------------+
   //| Check if pattern is trend-following type                         |
   //+------------------------------------------------------------------+
   bool IsTrendFollowingPattern(ENUM_PATTERN_TYPE pattern)
   {
      return (pattern == PATTERN_LIQUIDITY_SWEEP ||
              pattern == PATTERN_ENGULFING ||
              pattern == PATTERN_PIN_BAR ||
              pattern == PATTERN_BREAKOUT_RETEST ||
              pattern == PATTERN_VOLATILITY_BREAKOUT ||
              pattern == PATTERN_MA_CROSS_ANOMALY ||
              pattern == PATTERN_SR_BOUNCE);
   }

   //+------------------------------------------------------------------+
   //| Validate mean reversion pattern conditions                       |
   //+------------------------------------------------------------------+
   bool ValidateMeanReversionConditions(ENUM_PATTERN_TYPE pattern, ENUM_REGIME_TYPE regime,
                                       ENUM_SIGNAL_TYPE signal, double atr, double adx,
                                       double max_adx, double min_atr, double max_atr)
   {
      LogPrint(">>> Validating MEAN REVERSION conditions...");

      // ADX filter - allows ranging AND weak trending
      if (adx >= max_adx)
      {
         LogPrint(">>> REJECT: ADX too high (", DoubleToString(adx, 2), " >= ", max_adx, ") - strong trend, mean reversion risky");
         return false;
      }
      LogPrint(">>> ADX Filter: PASS (ADX=", DoubleToString(adx, 2), " < ", max_adx, ") - ranging/weak trend OK for MR");

      // Check ATR range
      if (atr < min_atr)
      {
         LogPrint(">>> REJECT: ATR too low (", DoubleToString(atr, 2), " < ", min_atr, ") - market too dead for mean reversion");
         return false;
      }

      if (atr > max_atr)
      {
         LogPrint(">>> REJECT: ATR too high (", DoubleToString(atr, 2), " > ", max_atr, ") - use trend-following instead");
         return false;
      }

      // Pattern-specific validation
      if (pattern == PATTERN_BB_MEAN_REVERSION)
      {
         LogPrint(">>> BB Mean Reversion: Counter-trend signal is EXPECTED and ALLOWED");
      }
      else if (pattern == PATTERN_RANGE_BOX)
      {
         LogPrint(">>> Range Box: Consolidation will be verified by regime filter");
      }
      else if (pattern == PATTERN_FALSE_BREAKOUT_FADE)
      {
         LogPrint(">>> False Breakout Fade: Low volatility confirmed");
      }

      LogPrint(">>> MEAN REVERSION VALIDATION PASSED - ATR: ", DoubleToString(atr, 2));
      return true;
   }

   //+------------------------------------------------------------------+
   //| Validate trend-following pattern conditions                      |
   //+------------------------------------------------------------------+
   bool ValidateTrendFollowingConditions(ENUM_TREND_DIRECTION daily, ENUM_TREND_DIRECTION h4,
                                        ENUM_REGIME_TYPE regime, int macro_score,
                                        ENUM_SIGNAL_TYPE signal, ENUM_PATTERN_TYPE pattern_type, 
                                        double atr, double min_atr)
   {
      LogPrint(">>> Validating TREND-FOLLOWING conditions...");

      // ATR minimum check
      if (atr < min_atr)
      {
         LogPrint(">>> REJECT: ATR too low (", DoubleToString(atr, 2), " < ", min_atr, ") for trend-following - market too quiet");
         return false;
      }
      LogPrint(">>> ATR Filter: PASS (ATR=", DoubleToString(atr, 2), " >= ", min_atr, ") - sufficient volatility for TF");

      // Call main validation logic
      LogPrint(">>> Calling existing ValidateEntryConditions for trend-following pattern...");
      return ValidateEntryConditions(daily, h4, regime, macro_score, signal, pattern_type);
   }

   //+------------------------------------------------------------------+
   //| Validate entry conditions (Full Logic + Smart Filters)           |
   //+------------------------------------------------------------------+
   bool ValidateEntryConditions(ENUM_TREND_DIRECTION daily, ENUM_TREND_DIRECTION h4,
                                ENUM_REGIME_TYPE regime, int macro_score,
                                ENUM_SIGNAL_TYPE signal, ENUM_PATTERN_TYPE pattern_type)
   {
      // Gather data
      double current_rsi = m_price_action_lowvol.GetRSI();
      double current_adx = m_regime_classifier.GetADX();

      bool is_extreme_overbought = (current_rsi > m_rsi_overbought);
      bool is_extreme_oversold = (current_rsi < m_rsi_oversold);

      ENUM_TREND_DIRECTION primary_trend = m_use_h4_primary ? h4 : daily;
      string primary_name = m_use_h4_primary ? "H4" : "D1";

      // Daily 200 EMA Smart Filter
      if (m_use_daily_200ema)
      {
         double ma200_buffer[];
         ArraySetAsSeries(ma200_buffer, true);

         if (CopyBuffer(m_handle_ma_200, 0, 0, 1, ma200_buffer) > 0)
         {
            double d1_ema_200 = ma200_buffer[0];
            double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            // Bull Market Context (Price > 200 EMA)
            if (current_bid > d1_ema_200)
            {
            if (signal == SIGNAL_SHORT)
            {
               double ct_adx_cap = MathMin(m_validation_strong_adx - 5.0, 32.0);
               bool macro_bearish = (macro_score <= -1);
               bool macro_strong_bear = (macro_score <= -m_validation_macro_strong);
               bool allow_short = false;

               // Breakout exception: allow short if H4 bearish or macro bearish despite D1 bull
               if (pattern_type == PATTERN_VOLATILITY_BREAKOUT && (h4 == TREND_BEARISH || macro_bearish))
               {
                  LogPrint(">>> ALLOW: Breakout short against 200 EMA (H4/macro bearish)");
                  allow_short = true;
               }

               if (current_adx > m_validation_strong_adx)
               {
                  LogPrint("REJECT: Bull Trend too strong (ADX ", DoubleToString(current_adx,1), ") to short.");
                  return false;
                  }

                  if (macro_strong_bear)
                  {
                     LogPrint(">>> ALLOW: Short allowed (Macro strongly bearish overrides D1 bull)");
                     allow_short = true;
                  }
                  else if (IsMeanReversionPattern(pattern_type) && current_adx <= ct_adx_cap)
                  {
                     if (macro_bearish)
                     {
                        LogPrint(">>> ALLOW: MR short with bearish macro + low ADX against 200 EMA");
                        allow_short = true;
                     }
                     else if (IsAsiaSession() && is_extreme_overbought)
                     {
                        LogPrint(">>> ALLOW: Asia MR short with RSI extreme and low ADX");
                        allow_short = true;
                     }
                  }

                  if (!allow_short)
                  {
                     if (h4 == TREND_BEARISH && current_adx <= m_validation_strong_adx)
                     {
                        LogPrint(">>> ALLOW: Short allowed (H4 is Bearish against D1 Bull with controlled ADX)");
                        allow_short = true;
                     }
                     else if (is_extreme_overbought && current_adx <= m_validation_strong_adx)
                     {
                        LogPrint(">>> ALLOW: Short allowed (RSI Extreme ", DoubleToString(current_rsi,1), " > ", m_rsi_overbought, ")");
                        allow_short = true;
                     }
                     else if (IsAsiaSession() && current_adx <= ct_adx_cap && macro_score <= 1)
                     {
                        LogPrint(">>> ALLOW: Short allowed (Asia Session exception with low ADX)");
                        allow_short = true;
                     }
                  }

                  if (!allow_short)
                  {
                     LogPrint("REJECT: Short against 200 EMA. No valid exception found.");
                     return false;
                  }
               }
            }
            // Bear Market Context (Price < 200 EMA)
            else if (current_bid < d1_ema_200)
            {
               if (signal == SIGNAL_LONG)
               {
                  if (current_adx > m_validation_strong_adx)
                  {
                     LogPrint("REJECT: Bear Trend too strong (ADX ", DoubleToString(current_adx,1), ") to buy.");
                     return false;
                  }

                  if (pattern_type == PATTERN_VOLATILITY_BREAKOUT && (h4 == TREND_BULLISH || macro_score >= 1))
                  {
                     LogPrint(">>> ALLOW: Breakout long against 200 EMA (H4/macro bullish)");
                  }
                  else
                  {
                     if (h4 == TREND_BULLISH || is_extreme_oversold || (IsMeanReversionPattern(pattern_type) && macro_score >= 1))
                     {
                        LogPrint(">>> ALLOW: Long allowed against 200 EMA (H4 Bullish/RSI Oversold/MR + macro)");
                     }
                     else if (IsAsiaSession())
                     {
                        LogPrint(">>> ALLOW: Long allowed (Asia Session exception)");
                     }
                     else if (macro_score >= 2)
                     {
                        LogPrint(">>> ALLOW: Long allowed (Macro strongly bullish against D1 bear)");
                     }
                     else
                     {
                        LogPrint("REJECT: Long against 200 EMA. No valid exception found.");
                        return false;
                     }
                  }
               }
            }
         }
      }

      // Trend Alignment Check
      if (daily != TREND_NEUTRAL && h4 != TREND_NEUTRAL && daily != h4)
      {
         bool signal_matches_h4 = (signal == SIGNAL_LONG && h4 == TREND_BULLISH) ||
                                  (signal == SIGNAL_SHORT && h4 == TREND_BEARISH);

         if (m_use_h4_primary && signal_matches_h4)
         {
            // Trust H4, proceed to regime checks
         }
         else
         {
            // RSI Exceptions for trend disagreement
            if (signal == SIGNAL_SHORT && is_extreme_overbought)
            {
               LogPrint(">>> TREND CONFLICT IGNORED: RSI Overbought -> Allowing Short");
            }
            else if (signal == SIGNAL_LONG && is_extreme_oversold)
            {
               LogPrint(">>> TREND CONFLICT IGNORED: RSI Oversold -> Allowing Long");
            }
            else
            {
               LogPrint("REJECT: Trend Misalignment (D1 vs H4) and no RSI exception");
               return false;
            }
         }
      }

      // Regime Specific Logic
      if (regime == REGIME_TRENDING)
      {
         if (primary_trend == TREND_BULLISH && signal != SIGNAL_LONG)
         {
            if (is_extreme_overbought || pattern_type == PATTERN_LIQUIDITY_SWEEP)
            {
               LogPrint(">>> TRENDING EXCEPTION: RSI Overbought or Liquidity Sweep -> Allowing Counter-Trend Short");
            }
            else
            {
               LogPrint("REJECT: Trending ", primary_name, " BULLISH - Short blocked");
               return false;
            }
         }

         if (primary_trend == TREND_BEARISH && signal != SIGNAL_SHORT)
         {
            if (is_extreme_oversold || pattern_type == PATTERN_LIQUIDITY_SWEEP)
            {
               LogPrint(">>> TRENDING EXCEPTION: RSI Oversold or Liquidity Sweep -> Allowing Counter-Trend Long");
            }
            else
            {
               LogPrint("REJECT: Trending ", primary_name, " BEARISH - Long blocked");
               return false;
            }
         }

         // Macro checks
         if (primary_trend == TREND_BULLISH && macro_score <= -m_validation_macro_strong && !is_extreme_oversold)
         {
            LogPrint("REJECT: Trending Regime but Macro Strongly Bearish");
            return false;
         }
         if (primary_trend == TREND_BEARISH && macro_score >= m_validation_macro_strong && !is_extreme_overbought)
         {
            LogPrint("REJECT: Trending Regime but Macro Strongly Bullish");
            return false;
         }
         if (primary_trend == TREND_BULLISH && signal == SIGNAL_SHORT &&
             macro_score >= (m_validation_macro_strong - 1) && !is_extreme_overbought)
         {
            LogPrint("REJECT: Trending Bullish + Bullish Macro - Short filtered");
            return false;
         }

         return true;
      }

      if (regime == REGIME_RANGING)
      {
         if (primary_trend == TREND_BULLISH && signal == SIGNAL_SHORT)
         {
            if (!is_extreme_overbought)
            {
               LogPrint("REJECT: Ranging but ", primary_name, " BULLISH - avoiding Short (no RSI exception)");
               return false;
            }
            LogPrint(">>> RANGING EXCEPTION: RSI Overbought -> Allowing Counter-Trend Short (pending macro check)");
         }

         if (primary_trend == TREND_BEARISH && signal == SIGNAL_LONG)
         {
            if (!is_extreme_oversold)
            {
               LogPrint("REJECT: Ranging but ", primary_name, " BEARISH - avoiding Long (no RSI exception)");
               return false;
            }
            LogPrint(">>> RANGING EXCEPTION: RSI Oversold -> Allowing Counter-Trend Long (pending macro check)");
         }

         // Strict Macro check in Ranging
         if (signal == SIGNAL_LONG && macro_score <= -m_validation_macro_strong && !is_extreme_oversold) return false;
         if (signal == SIGNAL_SHORT && macro_score >= m_validation_macro_strong && !is_extreme_overbought) return false;

         return true;
      }

      if (regime == REGIME_VOLATILE)
      {
         bool primary_aligned = (primary_trend == TREND_BULLISH && signal == SIGNAL_LONG) ||
                                (primary_trend == TREND_BEARISH && signal == SIGNAL_SHORT) ||
                                (primary_trend == TREND_NEUTRAL);

         if (!primary_aligned)
         {
            if (signal == SIGNAL_SHORT && is_extreme_overbought) return true;
            if (signal == SIGNAL_LONG && is_extreme_oversold) return true;

            LogPrint("REJECT: Volatile Regime - Trade must align with ", primary_name);
            return false;
         }

         return true;
      }

      if (regime == REGIME_CHOPPY || regime == REGIME_UNKNOWN)
      {
         if (primary_trend == TREND_BULLISH && signal != SIGNAL_LONG && !is_extreme_overbought)
         {
            LogPrint("REJECT: Choppy/Unknown - Only Longs allowed (Trend Bias)");
            return false;
         }
         if (primary_trend == TREND_BEARISH && signal != SIGNAL_SHORT && !is_extreme_oversold)
         {
            LogPrint("REJECT: Choppy/Unknown - Only Shorts allowed (Trend Bias)");
            return false;
         }

         return true;
      }

      return true;
   }
};
