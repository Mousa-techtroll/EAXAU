//+------------------------------------------------------------------+
//| Stack17_Main.mq5                                                  |
//| Stack1.7 - Gold Trading EA                                        |
//| v4.6                                                              |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "4.60"
#property strict

// Include all components
#include "Include/Common/Enums.mqh"
#include "Include/Common/Structs.mqh"
#include "Include/Common/Utils.mqh"
#include "Include/Common/SignalValidator.mqh"
#include "Include/Common/SetupEvaluator.mqh"
#include "Include/Common/Display.mqh"
#include "Include/Common/TradeLogger.mqh"
#include "Include/Components/TrendDetector.mqh"
#include "Include/Components/RegimeClassifier.mqh"
#include "Include/Components/MacroBias.mqh"
#include "Include/Components/PriceAction.mqh"
#include "Include/Components/PriceActionLowVol.mqh"
#include "Include/Management/RiskManager.mqh"
#include "Include/Management/TradeExecutor.mqh"
#include "Include/Management/PositionManager.mqh"
#include "Include/Management/SignalManager.mqh"
#include "Include/Management/AdaptiveTPManager.mqh"
#include "Include/Management/TrailingStopOptimizer.mqh"
#include "Include/Filters/MarketFilters.mqh"
#include "Include/Components/SMCOrderBlocks.mqh"
#include "Include/Components/MomentumFilter.mqh"

// Include Core orchestration classes
#include "Include/Core/MarketStateManager.mqh"
#include "Include/Core/RiskMonitor.mqh"
#include "Include/Core/PositionCoordinator.mqh"
#include "Include/Core/TradeOrchestrator.mqh"
#include "Include/Core/SignalProcessor.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input string InpVersion = "4.6";                          // EA Version

input group "=== RISK MANAGEMENT ==="
input double InpRiskAPlusSetup = 1.8;                 // Risk % for A+ setups
input double InpRiskASetup = 1.5;                     // Risk % for A setups
input double InpRiskBPlusSetup = 1.2;                 // Risk % for B+ setups
input double InpRiskBSetup = 1.0;                     // Risk % for B setups
input double InpMaxTotalExposure = 5.0;               // Maximum total exposure %
input double InpDailyLossLimit = 3.0;                 // Daily loss limit %
input double InpMaxLotMultiplier = 10.0;              // Max lot size (x min lot)
input int InpMaxPositions = 5;                        // Maximum concurrent positions
input double InpMaxMarginUsage = 80.0;                // Max margin usage %
input bool InpAutoCloseOnChoppy = true;               // Auto-close positions in CHOPPY regime
input int InpMaxPositionAgeHours = 72;                // Max position age before auto-close (prevents swap accumulation)
input bool InpCloseBeforeWeekend = true;              // Close positions before weekend
input int InpWeekendCloseHour = 20;                   // Hour to close positions on Friday (server time)
input int InpMaxTradesPerDay = 5;                     // Max trades per day (0 = unlimited)

input group "=== SHORT PROTECTION ==="
input double InpShortRiskMultiplier = 0.35;           // Risk multiplier for all short trades (cuts drawdown when gold trends up)
input double InpBullMRShortAdxCap = 30.0;             // Max ADX to allow MR shorts above D1 200 EMA
input int    InpBullMRShortMacroMax = -1;             // Max macro bias to allow MR shorts above D1 200 EMA (<=-1 = bearish required)
input double InpShortTrendMinADX = 18.0;              // Min ADX to allow trend shorts (avoid chop)
input double InpShortTrendMaxADX = 60.0;              // Max ADX to allow trend shorts (avoid exhaustion)
input int    InpShortMRMacroMax = -2;                 // Max macro bias to allow MR shorts (needs clear bearish)

input group "=== CONSECUTIVE LOSS PROTECTION ==="
input bool InpEnableLossScaling = true;               // Enable risk scaling after losses
input int InpLossesLevel1 = 2;                        // Consecutive losses to trigger Level 1 reduction
input int InpLossesLevel2 = 3;                        // Consecutive losses to trigger Level 2 reduction
input double InpRiskReductionLevel1 = 75.0;           // Risk % at Level 1 (75% of base risk)
input double InpRiskReductionLevel2 = 50.0;           // Risk % at Level 2 (50% of base risk)

input group "=== TREND DETECTION ==="
input int InpMAFastPeriod = 10;                       // Fast MA period
input int InpMASlowPeriod = 21;                       // Slow MA period
input int InpSwingLookback = 20;                      // Swing detection lookback
input bool InpUseH4AsPrimary = true;                  // Use H4 as primary trend (faster than D1)

input group "=== REGIME CLASSIFICATION ==="
input int InpADXPeriod = 14;                          // ADX period
input double InpADXTrending = 23.0;                   // ADX trending level
input double InpADXRanging = 20.0;                    // ADX ranging level
input int InpATRPeriod = 14;                          // ATR period

input group "=== STOP LOSS & ATR CONFIGURATION ==="
input double InpATRMultiplierSL = 3.0;                // ATR multiplier for SL
input double InpMinSLPoints = 800.0;                  // Minimum SL distance (points)
// NOTE: InpScoringRRTarget only affects R:R scoring. Actual TPs use InpTP1Distance/InpTP2Distance below
input double InpScoringRRTarget = 2.5;                // TP multiplier for R:R scoring ONLY (not actual TPs)
input double InpMinRRRatio = 1.5;                     // Minimum R:R ratio to execute trade
input int InpRSIPeriod = 14;                          // RSI period for price action

input group "=== TRAILING STOP SETTINGS ==="
input double InpATRMultiplierTrail = 2.0;             // ATR multiplier for trailing
input double InpMinTrailMovement = 100.0;             // Min movement to modify SL (points)
input double InpTP1Distance = 1.3;                    // TP1 distance (x risk) - fallback if adaptive disabled
input double InpTP2Distance = 1.8;                    // TP2 distance (x risk) - fallback if adaptive disabled
input double InpTP1Volume = 50.0;                     // TP1 volume % to close
input double InpTP2Volume = 40.0;                     // TP2 volume % to close
input double InpBreakevenOffset = 50.0;               // Breakeven offset (points, ~$0.50 for Gold)

input group "=== SMC ORDER BLOCKS ==="
input bool   InpEnableSMC = true;                     // Enable SMC Order Block Analysis
input int    InpSMCOBLookback = 50;                   // OB Detection Lookback (bars)
input double InpSMCOBBodyPct = 0.5;                   // OB Min Body % (0.0-1.0)
input double InpSMCOBImpulseMult = 1.5;               // OB Impulse ATR Multiplier
input int    InpSMCFVGMinPoints = 50;                 // FVG Min Gap (points)
input int    InpSMCBOSLookback = 20;                  // BOS Swing Detection Lookback
input double InpSMCLiqTolerance = 30.0;               // Liquidity Equal Tolerance (points)
input int    InpSMCLiqMinTouches = 2;                 // Liquidity Min Touches
input int    InpSMCZoneMaxAge = 200;                  // Zone Max Age (bars)
input bool   InpSMCUseHTFConfluence = true;           // Require HTF Confluence
input int    InpSMCMinConfluence = 55;                // Min SMC Confluence Score to Trade (0-100)
input bool   InpSMCBlockCounterSMC = true;            // Block trades against SMC bias

input group "=== MOMENTUM FILTER ==="
input bool   InpEnableMomentum = true;                // Enable Momentum Filter
input int    InpMomRSIPeriod = 14;                    // RSI Period
input double InpMomRSIOverbought = 70.0;              // RSI Overbought Level
input double InpMomRSIOversold = 30.0;                // RSI Oversold Level
input int    InpMomMACDFast = 12;                     // MACD Fast Period
input int    InpMomMACDSlow = 26;                     // MACD Slow Period
input int    InpMomMACDSignal = 9;                    // MACD Signal Period
input int    InpMomStochK = 14;                       // Stochastic %K Period
input int    InpMomStochD = 3;                        // Stochastic %D Period
input double InpMomStochOB = 80.0;                    // Stochastic Overbought
input double InpMomStochOS = 20.0;                    // Stochastic Oversold
input int    InpMomMinScore = 20;                     // Min Momentum Score to Trade

input group "=== TRAILING STOP OPTIMIZER ==="
input bool   InpEnableTrailOptimizer = true;          // Enable Trailing Stop Optimizer
input int    InpTrailStrategy = 5;                    // Trail Strategy (0=None,1=ATR,2=Swing,3=SAR,4=Chandelier,5=Stepped,6=Hybrid)
input double InpTrailATRMult = 2.0;                   // ATR Multiplier for Trailing
input int    InpTrailSwingLookback = 10;              // Swing Lookback Bars
input double InpTrailChandelierMult = 3.0;            // Chandelier ATR Multiplier
input double InpTrailStepSize = 0.5;                  // Step Size (ATR multiple)
input int    InpTrailMinProfit = 100;                 // Min Profit Points to Start Trailing
input double InpTrailBETrigger = 1.5;                 // Breakeven Trigger (ATR multiple)
input double InpTrailBEOffset = 10.0;                 // Breakeven Offset (points)

input group "=== ADAPTIVE TAKE PROFIT SYSTEM ==="
input bool   InpEnableAdaptiveTP = true;              // Enable Adaptive TP System
input double InpLowVolTP1Mult = 1.5;                  // Low Volatility: TP1 multiplier
input double InpLowVolTP2Mult = 2.5;                  // Low Volatility: TP2 multiplier
input double InpNormalVolTP1Mult = 2.0;               // Normal Volatility: TP1 multiplier
input double InpNormalVolTP2Mult = 3.5;               // Normal Volatility: TP2 multiplier
input double InpHighVolTP1Mult = 2.5;                 // High Volatility: TP1 multiplier
input double InpHighVolTP2Mult = 5.0;                 // High Volatility: TP2 multiplier
input double InpStrongTrendTPBoost = 1.3;             // Strong Trend: TP boost multiplier (ADX>35)
input double InpWeakTrendTPCut = 0.8;                 // Weak Trend: TP reduction multiplier (ADX<20)
input bool   InpUseStructureTargets = true;           // Use S/R levels for TP targets
input double InpStructureTP1Pct = 0.75;               // Structure: TP1 at % of distance to level
input double InpStructureTP2Pct = 1.0;                // Structure: TP2 at % of distance to level
input double InpAdaptiveStrongADX = 35.0;             // ADX threshold for strong trend
input double InpAdaptiveWeakADX = 20.0;               // ADX threshold for weak trend
input double InpLowVolATRPct = 0.7;                   // ATR ratio for low volatility (<= this)
input double InpHighVolATRPct = 1.3;                  // ATR ratio for high volatility (>= this)

input group "=== MACRO BIAS ==="
input string InpDXYSymbol = "USDX";                    // DXY symbol name
input string InpVIXSymbol = "VIX";                    // VIX symbol name
input double InpVIXElevated = 20.0;                   // VIX elevated threshold (risk-off)
input double InpVIXLow = 15.0;                        // VIX low threshold (extreme risk-on)

input group "=== EXECUTION ==="
input int InpMagicNumber = 170717;                    // EA magic number
input int InpSlippage = 10;                           // Maximum slippage
input int InpSlippageWarnThreshold = 5;               // Warn if entry slippage exceeds this (points)
input bool InpEnableAlerts = true;                    // Enable alerts
input bool InpEnablePush = false;                     // Enable push notifications
input bool InpEnableEmail = false;                    // Enable email notifications
input bool InpEnableLogging = true;                   // Enable LogPrint() logging/debugging

input group "=== TRADING HOURS ==="
input bool InpTradeLondon = true;                     // Trade London session
input bool InpTradeNY = true;                         // Trade New York session
input bool InpTradeAsia = true;                      // Trade Asia session
input int InpSkipStartHour = 0;                       // Skip from hour (0 = no skip)
input int InpSkipEndHour = 0;                         // Skip to hour (0 = no skip)

input group "=== SETUP QUALITY THRESHOLDS ==="
input int InpPointsAPlusSetup = 8;                    // Points needed for A+ setup
input int InpPointsASetup = 7;                        // Points needed for A setup
input int InpPointsBPlusSetup = 6;                    // Points needed for B+ setup
input int InpPointsBSetup = 5;                        // Points needed for B setup

input group "=== PATTERN ENABLE/DISABLE ==="
input bool InpEnableBullishEngulfing = true;          // Enable Bullish Engulfing
input bool InpEnableBullishPinBar = true;             // Enable Bullish Pin Bar
input bool InpEnableBullishMAAnomaly = true;          // Enable Bullish MA Cross
input bool InpEnableBearishEngulfing = true;          // Enable Bearish Engulfing
input bool InpEnableBearishPinBar = true;             // Enable Bearish Pin Bar
input bool InpEnableBearishMAAnomaly = true;         // Enable Bearish MA Cross
input bool InpEnableBullishLiquiditySweep = true;    // Enable Bullish Liquidity Sweep
input bool InpEnableBearishLiquiditySweep = true;    // Enable Bearish Liquidity Sweep
input bool InpEnableSupportBounce = true;            // Enable Support Bounce

input group "=== LOW VOLATILITY PATTERNS ==="
input bool InpEnableBBMeanReversion = true;          // Enable BB Mean Reversion
input bool InpEnableRangeBoxTrading = true;          // Enable Range Box Trading
input bool InpEnableFalseBreakoutFade = true;        // Enable False Breakout Fade
input int InpLowVolBBPeriod = 20;                     // Low Vol: Bollinger Bands period
input double InpLowVolBBDeviation = 2.5;              // Low Vol: Bollinger Bands deviation
input int InpLowVolRSIPeriod = 14;                    // Low Vol: RSI period
input double InpMRMaxADX = 35.0;                      // MR: Max ADX (weak trend only, loosened)
input double InpMRMinATR = 3.0;                       // MR: Min ATR (avoid dead market)
input double InpMRMaxATR = 50.0;                      // MR: Max ATR (increased to 50 - Gold ATR often hits 30-40 in active sessions)
input double InpMRMaxADXFilter = 35.0;                // MR: Filter Max ADX (2024 adjusted)
input double InpTFMinATR = 3.0;                       // TF: Min ATR (trend-following)

input group "=== PATTERN SCORE ADJUSTMENTS ==="
input int InpScoreBullishMAAnomaly = 90;              // Bullish MA Cross score
input int InpScoreBullishEngulfing = 70;              // Bullish Engulfing score
input int InpScoreBullishPinBar = 60;                 // Bullish Pin Bar score
input int InpScoreBearishEngulfing = 70;              // Bearish Engulfing score
input int InpScoreBearishPinBar = 60;                 // Bearish Pin Bar score
input int InpScoreBearishMAAnomaly = 90;              // Bearish MA Cross score
input int InpScoreBullishLiquiditySweep = 40;         // Bullish Liquidity Sweep score
input int InpScoreBearishLiquiditySweep = 40;         // Bearish Liquidity Sweep score
input int InpScoreSupportBounce = 50;                 // Support Bounce score

input group "=== MARKET REGIME FILTERS ==="
input bool   InpEnableConfidenceScoring = true;       // Enable pattern confidence scoring
input int    InpMinPatternConfidence = 40;            // Minimum confidence (loosened)
input bool   InpUseDynamicStopLoss = true;            // Use improved dynamic SL calculation
input bool   InpUseDaily200EMA      = true;           // Filter direction by Daily 200 EMA (Block counter-trend)
input double Inp200EMA_RSI_Overbought   = 75.0;   // RSI level to allow counter-trend Short (Asia only)
input double Inp200EMA_RSI_Oversold     = 30.0;   // RSI level to allow counter-trend Long (Asia only)

input group "=== HYBRID SESSION FILTERS ==="
input bool   InpEnableHybridLogic = true;   // Master switch for Session Logic
// ASIA (Mean Reversion)
input double InpAsiaMinADX        = 0.0;    // Min ADX for Asia (0 = allow dead markets)
input double InpAsiaMaxADX        = 40.0;   // Max ADX for Asia (loosened)
// NEW YORK (Trend Following)
input double InpNYMinADX          = 20.0;   // Min ADX for NY (Block chop)
input double InpNYMaxADX          = 65.0;   // Max ADX for NY (Avoid exhaustion)
// LONDON (Trend/Volatility Focus)
input double InpLondonMinADX      = 18.0;   // Min ADX for London (Block dead markets)
input double InpLondonMaxADX      = 65.0;   // Max ADX for London (Avoid extreme exhaustion)

input group "=== ENTRY VALIDATION THRESHOLDS ==="
input double InpValidationStrongADX      = 40.0;   // ADX level = "Too Strong to Fade"
input int    InpValidationMacroStrong    = 3;      // Macro score threshold for "Strong Opposition"

input group "=== CONFIRMATION CANDLE SETTINGS ==="
input bool   InpEnableConfirmation = true;            // Require confirmation candle before entry
input double InpConfirmationStrictness = 0.995;       // Confirmation level (0.995=relaxed, 1.0=strict)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// Component objects
CTrendDetector *             g_trend_detector;
CRegimeClassifier *          g_regime_classifier;
CMacroBias *                 g_macro_bias;
CPriceAction *               g_price_action;
CPriceActionLowVol *         g_price_action_lowvol;
CRiskManager *               g_risk_manager;
CTradeExecutor *             g_trade_executor;
CPositionManager *           g_position_manager;
CAdaptiveTPManager *         g_adaptive_tp_manager;
CSMCOrderBlocks *            g_smc_order_blocks;
CMomentumFilter *            g_momentum_filter;
CTrailingStopOptimizer *     g_trailing_optimizer;

// New modular components
CSignalValidator *           g_signal_validator;
CSetupEvaluator *            g_setup_evaluator;
CSignalManager *             g_signal_manager;
CDisplay *                   g_display;
CTradeLogger *               g_trade_logger;

// Core orchestration classes
CMarketStateManager *        g_market_state_manager;
CRiskMonitor *               g_risk_monitor;
CPositionCoordinator *       g_position_coordinator;
CTradeOrchestrator *         g_trade_orchestrator;
CSignalProcessor *           g_signal_processor;

// State tracking
datetime                    g_last_bar_time;
SPosition                   g_positions[];
int                         g_position_count;

// Daily trade tracking
int g_trades_today = 0;
datetime g_last_trade_date = 0;

// PERFORMANCE FIX: Cached indicator handle for H1 ADX (DI+ and DI- access)
int g_handle_adx_h1 = INVALID_HANDLE;
int g_handle_ma_200 = INVALID_HANDLE; // Daily 200 EMA handle

// CSV logging functions moved to TradeLogger.mqh

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
      // Set global logging flag
      g_enable_logging = InpEnableLogging;

      LogPrint("========================================");
      LogPrint("Stack1.7 EA v4.6 Initializing");
      LogPrint("Multi-Strategy: Trend-Following + Low Volatility");
      LogPrint("ATR Period (unified): ", InpATRPeriod, " | SL Multiplier: ", InpATRMultiplierSL, "x | Min SL: ", InpMinSLPoints, " pts");
      LogPrint("Confirmation Candles: ", InpEnableConfirmation ? "ENABLED" : "DISABLED", " (Strictness: ", InpConfirmationStrictness, ")");
      LogPrint("TP Management: TP1=", InpTP1Volume, "% at ", InpTP1Distance, "x | TP2=", InpTP2Volume, "% at ", InpTP2Distance, "x");
      LogPrint("Adaptive TP System: ", InpEnableAdaptiveTP ? "ENABLED" : "DISABLED");
      if (InpEnableAdaptiveTP)
      {
            LogPrint("  Low Vol TPs: ", InpLowVolTP1Mult, "x / ", InpLowVolTP2Mult, "x");
            LogPrint("  Normal Vol TPs: ", InpNormalVolTP1Mult, "x / ", InpNormalVolTP2Mult, "x");
            LogPrint("  High Vol TPs: ", InpHighVolTP1Mult, "x / ", InpHighVolTP2Mult, "x");
            LogPrint("  Structure Targets: ", InpUseStructureTargets ? "ON" : "OFF");
      }
      LogPrint("SMC Order Blocks: ", InpEnableSMC ? "ENABLED" : "DISABLED");
      if (InpEnableSMC)
      {
            LogPrint("  OB Lookback: ", InpSMCOBLookback, " bars | Impulse Mult: ", InpSMCOBImpulseMult, "x");
            LogPrint("  Min Confluence: ", InpSMCMinConfluence, "/100 | Block Counter-SMC: ", InpSMCBlockCounterSMC ? "ON" : "OFF");
      }
      LogPrint("Momentum Filter: ", InpEnableMomentum ? "ENABLED" : "DISABLED");
      if (InpEnableMomentum)
      {
            LogPrint("  RSI(", InpMomRSIPeriod, ") OB:", InpMomRSIOverbought, " OS:", InpMomRSIOversold);
            LogPrint("  MACD(", InpMomMACDFast, ",", InpMomMACDSlow, ",", InpMomMACDSignal, ") | Stoch(", InpMomStochK, ",", InpMomStochD, ")");
      }
      LogPrint("Trailing Stop Optimizer: ", InpEnableTrailOptimizer ? "ENABLED" : "DISABLED");
      if (InpEnableTrailOptimizer)
      {
            LogPrint("  Strategy: ", InpTrailStrategy, " | ATR Mult: ", InpTrailATRMult, "x | Min Profit: ", InpTrailMinProfit, " pts");
      }
      if (InpEnableHybridLogic) // Simplified check
      {
            LogPrint("Filters: HYBRID SESSION LOGIC ENABLED");
            LogPrint("  Confidence: ", InpEnableConfidenceScoring ? "ON" : "OFF", " (min ", InpMinPatternConfidence, "/100)");
            LogPrint("  Dynamic SL: ", InpUseDynamicStopLoss ? "ON" : "OFF",
                  InpUseDynamicStopLoss ? StringFormat(" (%.1fx ATR base, adapts to volatility)", InpATRMultiplierSL) : "");
      }
      else
      {
            LogPrint("Filters: ALL FILTERS DISABLED");
      }
      LogPrint("Low Volatility Strategies:");
      LogPrint("  BB Mean Reversion: ", InpEnableBBMeanReversion ? "ON" : "OFF");
      LogPrint("  Range Box Trading: ", InpEnableRangeBoxTrading ? "ON" : "OFF");
      LogPrint("  False Breakout Fade: ", InpEnableFalseBreakoutFade ? "ON" : "OFF");
      LogPrint("========================================");

      // Validate symbol
      if (_Symbol != "XAUUSD" && _Symbol != "XAUUSDm" && _Symbol != "GOLD")
      {
            LogPrint("WARNING: EA designed for XAUUSD. Current symbol: ", _Symbol);
      }

      // Create component objects
      g_trend_detector = new CTrendDetector(InpMAFastPeriod, InpMASlowPeriod, InpSwingLookback);
      g_regime_classifier = new CRegimeClassifier(InpADXPeriod, InpATRPeriod, InpADXTrending, InpADXRanging);
      g_macro_bias = new CMacroBias(InpDXYSymbol, InpVIXSymbol, InpVIXElevated, InpVIXLow);
      g_price_action = new CPriceAction(InpATRPeriod, InpATRMultiplierSL, InpMinSLPoints, InpScoringRRTarget,
                                        InpEnableBullishEngulfing, InpEnableBullishPinBar, InpEnableBullishLiquiditySweep, InpEnableBullishMAAnomaly,
                                        InpEnableBearishEngulfing, InpEnableBearishPinBar, InpEnableBearishLiquiditySweep, InpEnableBearishMAAnomaly,
                                        InpEnableSupportBounce,
                                        InpScoreBullishEngulfing, InpScoreBullishPinBar, InpScoreBullishLiquiditySweep, InpScoreBullishMAAnomaly,
                                        InpScoreBearishEngulfing, InpScoreBearishPinBar, InpScoreBearishLiquiditySweep, InpScoreBearishMAAnomaly,
                                        InpScoreSupportBounce,
                                        InpRSIPeriod);
      g_price_action_lowvol = new CPriceActionLowVol(InpLowVolBBPeriod, InpLowVolBBDeviation, InpLowVolRSIPeriod,
                                        InpATRPeriod, InpScoringRRTarget, InpMinSLPoints,
                                        InpEnableBBMeanReversion, InpEnableRangeBoxTrading, InpEnableFalseBreakoutFade,
                                        InpMRMaxATR);
      g_risk_manager = new CRiskManager(InpMaxTotalExposure, InpDailyLossLimit, InpMaxLotMultiplier,
                                        InpMaxPositions, InpMaxMarginUsage,
                                        InpEnableLossScaling, InpLossesLevel1, InpLossesLevel2,
                                        InpRiskReductionLevel1, InpRiskReductionLevel2);
      g_trade_executor = new CTradeExecutor(InpMagicNumber, InpSlippage, InpSlippageWarnThreshold);
      g_position_manager = new CPositionManager(g_trade_executor, InpATRPeriod, InpATRMultiplierTrail,
                                                InpMinTrailMovement, InpAutoCloseOnChoppy, InpMaxPositionAgeHours,
                                                InpTP1Volume, InpTP2Volume, InpBreakevenOffset);

      // Create Adaptive TP Manager
      g_adaptive_tp_manager = new CAdaptiveTPManager(InpTP1Distance, InpTP2Distance);
      if(InpEnableAdaptiveTP)
      {
            g_adaptive_tp_manager.Configure(
                  InpLowVolTP1Mult, InpLowVolTP2Mult,
                  InpNormalVolTP1Mult, InpNormalVolTP2Mult,
                  InpHighVolTP1Mult, InpHighVolTP2Mult,
                  InpStrongTrendTPBoost, InpWeakTrendTPCut,
                  InpUseStructureTargets, InpStructureTP1Pct, InpStructureTP2Pct,
                  InpAdaptiveStrongADX, InpAdaptiveWeakADX,
                  InpLowVolATRPct, InpHighVolATRPct
            );
      }

      // Create SMC Order Blocks Module
      g_smc_order_blocks = new CSMCOrderBlocks();
      if(InpEnableSMC)
      {
            g_smc_order_blocks.Configure(
                  InpSMCOBLookback, InpSMCOBBodyPct, InpSMCOBImpulseMult,
                  InpSMCFVGMinPoints, InpSMCBOSLookback, InpSMCLiqTolerance,
                  InpSMCLiqMinTouches, InpSMCZoneMaxAge, InpSMCUseHTFConfluence
            );
      }

      // Create Momentum Filter Module
      g_momentum_filter = new CMomentumFilter();
      if(InpEnableMomentum)
      {
            g_momentum_filter.Configure(
                  InpMomRSIPeriod, InpMomRSIOverbought, InpMomRSIOversold,
                  InpMomMACDFast, InpMomMACDSlow, InpMomMACDSignal,
                  InpMomStochK, InpMomStochD, InpMomStochOB, InpMomStochOS,
                  20, 100.0, -100.0,  // CCI defaults
                  14, InpMomMinScore, 20  // MFI, min score, divergence lookback
            );
      }

      // Create Trailing Stop Optimizer Module
      g_trailing_optimizer = new CTrailingStopOptimizer();
      if(InpEnableTrailOptimizer)
      {
            g_trailing_optimizer.Configure(
                  (ENUM_TRAIL_STRATEGY)InpTrailStrategy,
                  14, InpTrailATRMult,
                  InpTrailSwingLookback, 0.02, 0.2,
                  InpTrailChandelierMult, InpTrailStepSize,
                  InpTrailMinProfit, InpTrailBETrigger, InpTrailBEOffset
            );
      }

      // Initialize all components
      if (!g_trend_detector.Init())
      {
            LogPrint("ERROR: TrendDetector initialization failed");
            return INIT_FAILED;
      }

      if (!g_regime_classifier.Init())
      {
            LogPrint("ERROR: RegimeClassifier initialization failed");
            return INIT_FAILED;
      }

      if (!g_macro_bias.Init())
      {
            LogPrint("ERROR: MacroBias initialization failed");
            return INIT_FAILED;
      }

      if (!g_price_action.Init())
      {
            LogPrint("ERROR: PriceAction initialization failed");
            return INIT_FAILED;
      }

      if (!g_risk_manager.Init())
      {
            LogPrint("ERROR: RiskManager initialization failed");
            return INIT_FAILED;
      }

      if (!g_trade_executor.Init())
      {
            LogPrint("ERROR: TradeExecutor initialization failed");
            return INIT_FAILED;
      }

      if (!g_position_manager.Init())
      {
            LogPrint("ERROR: PositionManager initialization failed");
            return INIT_FAILED;
      }

      // Configure Trailing Stop Optimizer for PositionManager
      if(InpEnableTrailOptimizer && g_trailing_optimizer != NULL)
      {
            g_position_manager.ConfigureTrailingOptimizer(g_trailing_optimizer, InpEnableTrailOptimizer);
      }

      // Initialize Adaptive TP Manager
      if(InpEnableAdaptiveTP && !g_adaptive_tp_manager.Init())
      {
            LogPrint("ERROR: AdaptiveTPManager initialization failed");
            return INIT_FAILED;
      }

      // Initialize SMC Order Blocks Module
      if(InpEnableSMC && !g_smc_order_blocks.Init())
      {
            LogPrint("ERROR: SMCOrderBlocks initialization failed");
            return INIT_FAILED;
      }

      // Initialize Momentum Filter Module
      if(InpEnableMomentum && !g_momentum_filter.Init())
      {
            LogPrint("ERROR: MomentumFilter initialization failed");
            return INIT_FAILED;
      }

      // Initialize Trailing Stop Optimizer Module
      if(InpEnableTrailOptimizer && !g_trailing_optimizer.Init())
      {
            LogPrint("ERROR: TrailingStopOptimizer initialization failed");
            return INIT_FAILED;
      }

      // PERFORMANCE FIX: Initialize H1 ADX handle for filter (DI+ and DI- access)
      g_handle_adx_h1 = iADX(_Symbol, PERIOD_H1, 14);
      if (g_handle_adx_h1 == INVALID_HANDLE)
      {
            LogPrint("ERROR: Failed to create H1 ADX indicator");
            return INIT_FAILED;
      }

      // Initialize Daily 200 EMA for Global Trend Bias
      g_handle_ma_200 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
      if (g_handle_ma_200 == INVALID_HANDLE)
      {
            LogPrint("ERROR: Failed to create Daily 200 EMA");
            return INIT_FAILED;
      }

      // Initialize new modular components
      g_signal_validator = new CSignalValidator(g_trend_detector, g_regime_classifier,
                                                g_price_action, g_price_action_lowvol,
                                                g_handle_ma_200, InpUseH4AsPrimary, InpUseDaily200EMA,
                                                Inp200EMA_RSI_Overbought, Inp200EMA_RSI_Oversold,
                                                InpValidationStrongADX, InpValidationMacroStrong);

      // Configure SMC integration with SignalValidator
      if(InpEnableSMC && g_smc_order_blocks != NULL)
      {
            g_signal_validator.ConfigureSMC(g_smc_order_blocks, InpEnableSMC,
                                            InpSMCMinConfluence, InpSMCBlockCounterSMC);
      }

      g_setup_evaluator = new CSetupEvaluator(g_trend_detector, g_price_action, g_price_action_lowvol,
                                              InpRiskAPlusSetup, InpRiskASetup, InpRiskBPlusSetup, InpRiskBSetup,
                                              InpPointsAPlusSetup, InpPointsASetup, InpPointsBPlusSetup, InpPointsBSetup,
                                              Inp200EMA_RSI_Overbought, Inp200EMA_RSI_Oversold);

      g_signal_manager = new CSignalManager(InpConfirmationStrictness, InpTP1Distance, InpTP2Distance);

      g_display = new CDisplay(g_trend_detector, g_regime_classifier,
                               g_macro_bias, g_risk_manager, InpMaxTotalExposure);

      g_trade_logger = new CTradeLogger();
      if (!g_trade_logger.Init())
      {
            LogPrint("WARNING: Trade logger initialization failed - stats logging disabled");
      }

      // Initialize Core orchestration classes
      g_market_state_manager = new CMarketStateManager(g_trend_detector, g_regime_classifier,
                                                       g_macro_bias, g_price_action, InpUseH4AsPrimary);

      g_risk_monitor = new CRiskMonitor(g_risk_manager, g_trade_executor,
                                        InpMaxTradesPerDay, InpEnableAlerts, InpEnablePush, InpEnableEmail);
      g_risk_monitor.Init();

      g_position_coordinator = new CPositionCoordinator(g_position_manager, g_trade_executor,
                                                        g_risk_manager, g_regime_classifier,
                                                        g_macro_bias, g_trade_logger,
                                                        InpMagicNumber, InpCloseBeforeWeekend, InpWeekendCloseHour);
      g_position_coordinator.Init();

      g_trade_orchestrator = new CTradeOrchestrator(g_trade_executor, g_risk_manager,
                                                    g_trade_logger, g_position_coordinator, g_risk_monitor,
                                                    g_handle_ma_200,
                                                    InpMinRRRatio, InpUseDaily200EMA,
                                                    InpTP1Distance, InpTP2Distance,
                                                    InpEnableAlerts, InpEnablePush, InpEnableEmail,
                                                    InpRiskAPlusSetup, InpRiskASetup, InpRiskBPlusSetup, InpRiskBSetup,
                                                    InpShortRiskMultiplier,
                                                    g_adaptive_tp_manager, g_regime_classifier,
                                                    InpEnableAdaptiveTP);

      g_signal_processor = new CSignalProcessor(g_trend_detector, g_regime_classifier, g_macro_bias,
                                                g_price_action, g_price_action_lowvol,
                                                g_signal_validator, g_setup_evaluator,
                                                g_signal_manager, g_risk_manager,
                                                g_risk_monitor, g_trade_orchestrator,
                                                g_handle_ma_200, g_handle_adx_h1,
                                                // Session/Time
                                                InpTradeAsia, InpTradeLondon, InpTradeNY,
                                                InpSkipStartHour, InpSkipEndHour,
                                                // Mean reversion
                                                InpMRMinATR, InpMRMaxATR, InpMRMaxADX, InpMRMaxADXFilter, InpTFMinATR,
                                                // 200 EMA
                                                InpUseDaily200EMA, Inp200EMA_RSI_Overbought, Inp200EMA_RSI_Oversold,
                                                // Market filters (Simplified)
                                                InpEnableConfidenceScoring, InpADXRanging,
                                                // Hybrid logic
                                                InpEnableHybridLogic, InpAsiaMinADX, InpAsiaMaxADX,
                                                InpLondonMinADX, InpLondonMaxADX, InpNYMinADX, InpNYMaxADX,
                                                // Confidence
                                                InpMAFastPeriod, InpMASlowPeriod, InpMinPatternConfidence,
                                                // Dynamic SL
                                                InpUseDynamicStopLoss, InpMinSLPoints, InpATRMultiplierSL,
                                                // TPs
                                                InpTP1Distance, InpTP2Distance,
                                                // Confirmation
                                                InpEnableConfirmation,
                                                // Short protection
                                                InpBullMRShortAdxCap, InpBullMRShortMacroMax, InpShortRiskMultiplier,
                                                InpShortTrendMinADX, InpShortTrendMaxADX, InpShortMRMacroMax);

      // Configure Momentum Filter for SignalProcessor
      if(InpEnableMomentum && g_momentum_filter != NULL)
      {
            g_signal_processor.ConfigureMomentumFilter(g_momentum_filter, InpEnableMomentum);
      }

      LogPrint("Core orchestration classes initialized");

      // Initialize state
      g_last_bar_time = 0;
      g_position_count = 0;
      ArrayResize(g_positions, 0);

      // Load existing positions via PositionCoordinator
      g_position_coordinator.LoadOpenPositions();

      LogPrint("========================================");
      LogPrint("Stack1.7 EA Initialized Successfully!");
      LogPrint("Risk A+: ", InpRiskAPlusSetup, "% | A: ", InpRiskASetup, "% | B+: ", InpRiskBPlusSetup, "%");
      LogPrint("Daily Loss Limit: ", InpDailyLossLimit, "%");
      LogPrint("Max Exposure: ", InpMaxTotalExposure, "%");
      LogPrint("========================================");

      return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
      LogPrint("Stack1.7 EA Deinitializing... Reason: ", reason);

      // Close pattern stats CSV file
      if (g_trade_logger != NULL)
            g_trade_logger.Close();

      // PERFORMANCE FIX: Release H1 ADX handle
      if (g_handle_adx_h1 != INVALID_HANDLE)
            IndicatorRelease(g_handle_adx_h1);

      // Release Daily 200 EMA handle
      if (g_handle_ma_200 != INVALID_HANDLE)
            IndicatorRelease(g_handle_ma_200);

      // Cleanup objects
      delete g_trend_detector;
      delete g_regime_classifier;
      delete g_macro_bias;
      delete g_price_action;
      delete g_price_action_lowvol;
      delete g_risk_manager;
      delete g_trade_executor;
      delete g_position_manager;
      delete g_adaptive_tp_manager;
      delete g_smc_order_blocks;
      delete g_momentum_filter;
      delete g_trailing_optimizer;

      // Cleanup new modular components
      delete g_signal_validator;
      delete g_setup_evaluator;
      delete g_signal_manager;
      delete g_display;
      delete g_trade_logger;

      // Cleanup Core orchestration classes
      delete g_market_state_manager;
      delete g_risk_monitor;
      delete g_position_coordinator;
      delete g_trade_orchestrator;
      delete g_signal_processor;

      Comment("");

      LogPrint("Stack1.7 EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
      // Check if new H1 bar formed
      datetime current_bar_time = iTime(_Symbol, PERIOD_H1, 0);
      bool is_new_bar = (current_bar_time != g_last_bar_time);

      if (is_new_bar)
      {
            g_last_bar_time = current_bar_time;

            // Check if we have a pending signal waiting for confirmation
            if (InpEnableConfirmation && g_signal_manager != NULL && g_signal_manager.HasPendingSignal())
            {
                  bool confirmed = g_signal_manager.CheckPatternConfirmation();
                  SPendingSignal pending = g_signal_manager.GetPendingSignal();

                  if (confirmed)
                  {
                        bool ok_to_execute = true;
                        if (g_signal_processor != NULL)
                              ok_to_execute = g_signal_processor.RevalidatePending(pending);

                        if (ok_to_execute)
                        {
                              LogPrint(">>> CONFIRMATION: ", pending.pattern_name, " confirmed - entering trade");
                              if (g_trade_orchestrator != NULL)
                                    g_trade_orchestrator.ProcessConfirmedSignal(pending);
                        }
                        else
                        {
                              LogPrint(">>> CONFIRMATION REJECTED: Conditions changed for ", pending.pattern_name);
                        }
                  }
                  else
                  {
                        LogPrint(">>> NO CONFIRMATION: ", pending.pattern_name, " - skipping trade");
                  }

                  // Clear pending signal
                  g_signal_manager.ClearPendingSignal();
            }

            // FULL ANALYSIS ON NEW BAR - Use Core orchestrators
            if (g_market_state_manager != NULL)
                  g_market_state_manager.UpdateMarketState();

            // Update SMC Order Block zones
            if (InpEnableSMC && g_smc_order_blocks != NULL)
                  g_smc_order_blocks.Update();

            if (g_signal_processor != NULL)
                  g_signal_processor.CheckForNewSignals();
      }

      // MANAGE EXISTING POSITIONS (every tick)
      if (g_position_coordinator != NULL)
            g_position_coordinator.ManageOpenPositions();

      // CHECK RISK LIMITS (every tick)
      if (g_risk_monitor != NULL)
            g_risk_monitor.CheckRiskLimits();

      // UPDATE DISPLAY
      if (g_display != NULL)
      {
            int pos_count = (g_position_coordinator != NULL) ? g_position_coordinator.GetPositionCount() : 0;
            g_display.UpdateDisplay(pos_count);
      }
}

