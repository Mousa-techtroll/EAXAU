//+------------------------------------------------------------------+
//| Enums.mqh                                                         |
//| Stack 1.7 - Common Enumerations                                   |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Trend Direction Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIRECTION
{
   TREND_BULLISH,      // Bullish trend
   TREND_BEARISH,      // Bearish trend
   TREND_NEUTRAL       // No clear trend
};

//+------------------------------------------------------------------+
//| Regime Type Enumeration                                           |
//+------------------------------------------------------------------+
enum ENUM_REGIME_TYPE
{
   REGIME_TRENDING,    // Strong directional movement
   REGIME_RANGING,     // Sideways consolidation
   REGIME_VOLATILE,    // High volatility / Breakout expansion
   REGIME_CHOPPY,      // Erratic price action / Low conviction
   REGIME_UNKNOWN      // Transitional/unclear
};

//+------------------------------------------------------------------+
//| Macro Bias Enumeration                                            |
//+------------------------------------------------------------------+
enum ENUM_MACRO_BIAS
{
   BIAS_BULLISH,       // Favorable for gold longs
   BIAS_NEUTRAL,       // Mixed signals
   BIAS_BEARISH        // Favorable for gold shorts
};

//+------------------------------------------------------------------+
//| Signal Type Enumeration                                           |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE,        // No valid signal
   SIGNAL_LONG,        // Buy signal
   SIGNAL_SHORT        // Sell signal
};

//+------------------------------------------------------------------+
//| Setup Quality Enumeration                                         |
//+------------------------------------------------------------------+
enum ENUM_SETUP_QUALITY
{
   SETUP_NONE,         // Below minimum quality (< 3 points)
   SETUP_B,            // Marginal (3 points) - v4.1 NEW
   SETUP_B_PLUS,       // Acceptable (4-5 points)
   SETUP_A,            // Good (6-7 points)
   SETUP_A_PLUS        // Excellent (8-10 points)
};

//+------------------------------------------------------------------+
//| Pattern Type Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_PATTERN_TYPE
{
   PATTERN_NONE,
   // Trend-following patterns (for trending/volatile markets)
   PATTERN_LIQUIDITY_SWEEP,
   PATTERN_ENGULFING,
   PATTERN_PIN_BAR,
   PATTERN_BREAKOUT_RETEST,
   PATTERN_VOLATILITY_BREAKOUT,
   PATTERN_SR_BOUNCE,
   PATTERN_MA_CROSS_ANOMALY,

   // Low volatility patterns (for consolidation/ranging markets)
   PATTERN_BB_MEAN_REVERSION,      // Bollinger Band bounce to mean
   PATTERN_RANGE_BOX,              // Range box trading
   PATTERN_FALSE_BREAKOUT_FADE     // Fade low volatility breakouts
};
