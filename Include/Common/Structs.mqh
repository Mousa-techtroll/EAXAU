//+------------------------------------------------------------------+
//| Structs.mqh                                                       |
//| Stack 1.7 - Data Structures                                       |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "Enums.mqh"

//+------------------------------------------------------------------+
//| Trend Data Structure                                              |
//+------------------------------------------------------------------+
struct STrendData
{
   ENUM_TREND_DIRECTION direction;     // Trend direction
   double               strength;       // Trend strength (0-1)
   double               ma_fast;        // Fast MA value
   double               ma_slow;        // Slow MA value
   bool                 making_hh;      // Making higher highs
   bool                 making_ll;      // Making lower lows
   datetime             last_update;    // Last update time
};

//+------------------------------------------------------------------+
//| Regime Data Structure                                             |
//+------------------------------------------------------------------+
struct SRegimeData
{
   ENUM_REGIME_TYPE     regime;                // Current regime
   double               adx_value;             // ADX reading
   double               atr_current;           // Current ATR
   double               atr_average;           // Average ATR (50 period)
   double               bb_width;              // Bollinger Band width %
   bool                 volatility_expanding;  // Volatility spike detected
   datetime             last_update;           // Last update time
};

//+------------------------------------------------------------------+
//| Macro Bias Data Structure                                         |
//+------------------------------------------------------------------+
struct SMacroBiasData
{
   ENUM_MACRO_BIAS      bias;              // Overall bias
   int                  bias_score;        // Score: -4 to +4
   double               dxy_price;         // DXY current price
   double               dxy_ma50;          // DXY MA50
   ENUM_TREND_DIRECTION dxy_trend;         // DXY trend
   bool                 dxy_making_hh;     // DXY making higher highs
   double               vix_level;         // VIX level
   bool                 vix_elevated;      // VIX > threshold
   datetime             last_update;       // Last update time
};

//+------------------------------------------------------------------+
//| Price Action Signal Structure                                     |
//+------------------------------------------------------------------+
struct SPriceActionData
{
   ENUM_SIGNAL_TYPE     signal;            // Signal type
   ENUM_PATTERN_TYPE    pattern_type;      // Pattern detected
   string               pattern_name;      // Pattern description
   double               entry_price;       // Proposed entry
   double               stop_loss;         // Proposed stop
   double               take_profit;       // Proposed target
   double               risk_reward;       // RR ratio
   datetime             signal_time;       // When signal formed
};

//+------------------------------------------------------------------+
//| Position Tracking Structure                                       |
//+------------------------------------------------------------------+
struct SPosition
{
   ulong                ticket;             // Position ticket
   ENUM_SIGNAL_TYPE     direction;          // LONG or SHORT
   ENUM_PATTERN_TYPE    pattern_type;       // Pattern type (enum)
   double               lot_size;           // Position size
   double               entry_price;        // Actual entry
   double               stop_loss;          // Current SL
   double               tp1;                // Take profit 1
   double               tp2;                // Take profit 2
   bool                 tp1_closed;         // TP1 hit?
   bool                 tp2_closed;         // TP2 hit?
   datetime             open_time;          // Entry time
   ENUM_SETUP_QUALITY   setup_quality;      // Entry quality
   string               pattern_name;       // Entry pattern
   double               initial_risk_pct;   // Risk %
   bool                 at_breakeven;       // SL at breakeven?
};

//+------------------------------------------------------------------+
//| Risk Statistics Structure                                         |
//+------------------------------------------------------------------+
struct SRiskStats
{
   double               current_exposure;      // Total risk %
   double               daily_pnl_pct;        // Today's P&L %
   int                  consecutive_losses;    // Losing streak
   int                  consecutive_wins;      // Winning streak
   double               daily_start_balance;  // Balance at day start
   datetime             last_day_reset;       // Last daily reset
   int                  positions_count;      // Open positions
   bool                 trading_halted;       // Trading stopped?
};