//+------------------------------------------------------------------+
//| TrailingStopOptimizer.mqh                                         |
//| Advanced Trailing Stop Management with Multiple Strategies        |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| Trailing Stop Strategy Enum                                       |
//+------------------------------------------------------------------+
enum ENUM_TRAIL_STRATEGY
{
   TRAIL_NONE,           // No trailing (use fixed SL)
   TRAIL_ATR,            // ATR-based trailing
   TRAIL_SWING,          // Swing high/low trailing
   TRAIL_PARABOLIC,      // Parabolic SAR trailing
   TRAIL_CHANDELIER,     // Chandelier Exit
   TRAIL_STEPPED,        // Stepped trailing (move in increments)
   TRAIL_HYBRID          // Hybrid (best of multiple)
};

//+------------------------------------------------------------------+
//| Trailing Stop State Structure                                     |
//+------------------------------------------------------------------+
struct STrailState
{
   ulong             ticket;
   ENUM_TRAIL_STRATEGY strategy;
   double            current_trail;
   double            highest_price;    // For longs
   double            lowest_price;     // For shorts
   double            last_swing;       // Last swing level used
   int               step_count;       // Steps moved for stepped trailing
   datetime          last_update;
};

//+------------------------------------------------------------------+
//| CTrailingStopOptimizer - Advanced trailing stop management       |
//+------------------------------------------------------------------+
class CTrailingStopOptimizer
{
private:
   // Indicator handles
   int               m_handle_atr;
   int               m_handle_sar;

   // Configuration
   ENUM_TRAIL_STRATEGY m_default_strategy;
   int               m_atr_period;
   double            m_atr_multiplier;
   int               m_swing_lookback;
   double            m_sar_step;
   double            m_sar_max;
   double            m_chandelier_mult;
   double            m_step_size_atr;    // Step size as ATR multiple
   int               m_min_profit_to_trail; // Min profit in points before trailing starts
   double            m_breakeven_trigger;   // ATR multiple to trigger breakeven
   double            m_breakeven_offset;    // Points to add above/below entry for BE

   // State tracking
   STrailState       m_trail_states[];
   int               m_state_count;

   // Cached values
   double            m_current_atr;
   double            m_current_sar;

   bool              m_initialized;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CTrailingStopOptimizer()
   {
      m_handle_atr = INVALID_HANDLE;
      m_handle_sar = INVALID_HANDLE;

      m_default_strategy = TRAIL_ATR;
      m_atr_period = 14;
      m_atr_multiplier = 2.0;
      m_swing_lookback = 10;
      m_sar_step = 0.02;
      m_sar_max = 0.2;
      m_chandelier_mult = 3.0;
      m_step_size_atr = 0.5;
      m_min_profit_to_trail = 100;
      m_breakeven_trigger = 1.5;
      m_breakeven_offset = 10;

      m_state_count = 0;
      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CTrailingStopOptimizer()
   {
      if(m_handle_atr != INVALID_HANDLE) IndicatorRelease(m_handle_atr);
      if(m_handle_sar != INVALID_HANDLE) IndicatorRelease(m_handle_sar);
   }

   //+------------------------------------------------------------------+
   //| Configure parameters                                              |
   //+------------------------------------------------------------------+
   void Configure(ENUM_TRAIL_STRATEGY strategy, int atr_period, double atr_mult,
                  int swing_lookback, double sar_step, double sar_max,
                  double chandelier_mult, double step_size,
                  int min_profit, double be_trigger, double be_offset)
   {
      m_default_strategy = strategy;
      m_atr_period = atr_period;
      m_atr_multiplier = atr_mult;
      m_swing_lookback = swing_lookback;
      m_sar_step = sar_step;
      m_sar_max = sar_max;
      m_chandelier_mult = chandelier_mult;
      m_step_size_atr = step_size;
      m_min_profit_to_trail = min_profit;
      m_breakeven_trigger = be_trigger;
      m_breakeven_offset = be_offset;
   }

   //+------------------------------------------------------------------+
   //| Initialize indicators                                             |
   //+------------------------------------------------------------------+
   bool Init()
   {
      m_handle_atr = iATR(_Symbol, PERIOD_H1, m_atr_period);
      m_handle_sar = iSAR(_Symbol, PERIOD_H1, m_sar_step, m_sar_max);

      if(m_handle_atr == INVALID_HANDLE || m_handle_sar == INVALID_HANDLE)
      {
         LogPrint("ERROR: TrailingStopOptimizer - Failed to create indicator handles");
         return false;
      }

      ArrayResize(m_trail_states, 0);
      m_state_count = 0;
      m_initialized = true;

      LogPrint("TrailingStopOptimizer initialized: Strategy=", EnumToString(m_default_strategy),
               " | ATR(", m_atr_period, ")x", m_atr_multiplier);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update indicator values                                           |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(!m_initialized) return;

      double atr[], sar[];
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(sar, true);

      if(CopyBuffer(m_handle_atr, 0, 0, 1, atr) > 0)
         m_current_atr = atr[0];

      if(CopyBuffer(m_handle_sar, 0, 0, 1, sar) > 0)
         m_current_sar = sar[0];
   }

   //+------------------------------------------------------------------+
   //| Calculate optimal trailing stop for position                      |
   //+------------------------------------------------------------------+
   double CalculateTrailingStop(SPosition &position, ENUM_TRAIL_STRATEGY strategy = TRAIL_NONE)
   {
      if(!m_initialized) return position.stop_loss;

      Update();

      if(strategy == TRAIL_NONE)
         strategy = m_default_strategy;

      double current_price = (position.direction == SIGNAL_LONG) ?
                             SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profit_points = 0;

      if(position.direction == SIGNAL_LONG)
         profit_points = (current_price - position.entry_price) / point;
      else
         profit_points = (position.entry_price - current_price) / point;

      // Don't trail if not enough profit
      if(profit_points < m_min_profit_to_trail)
         return position.stop_loss;

      double new_sl = position.stop_loss;

      switch(strategy)
      {
         case TRAIL_ATR:
            new_sl = CalculateATRTrail(position, current_price);
            break;

         case TRAIL_SWING:
            new_sl = CalculateSwingTrail(position, current_price);
            break;

         case TRAIL_PARABOLIC:
            new_sl = CalculateSARTrail(position, current_price);
            break;

         case TRAIL_CHANDELIER:
            new_sl = CalculateChandelierTrail(position, current_price);
            break;

         case TRAIL_STEPPED:
            new_sl = CalculateSteppedTrail(position, current_price, profit_points);
            break;

         case TRAIL_HYBRID:
            new_sl = CalculateHybridTrail(position, current_price, profit_points);
            break;

         default:
            return position.stop_loss;
      }

      // Ensure we only move SL in profit direction
      if(position.direction == SIGNAL_LONG)
      {
         if(new_sl > position.stop_loss)
            return new_sl;
      }
      else
      {
         if(new_sl < position.stop_loss && new_sl > 0)
            return new_sl;
      }

      return position.stop_loss;
   }

   //+------------------------------------------------------------------+
   //| ATR-based trailing stop                                           |
   //+------------------------------------------------------------------+
   double CalculateATRTrail(SPosition &position, double current_price)
   {
      double trail_distance = m_current_atr * m_atr_multiplier;

      if(position.direction == SIGNAL_LONG)
         return current_price - trail_distance;
      else
         return current_price + trail_distance;
   }

   //+------------------------------------------------------------------+
   //| Swing high/low trailing stop                                      |
   //+------------------------------------------------------------------+
   double CalculateSwingTrail(SPosition &position, double current_price)
   {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      if(CopyHigh(_Symbol, PERIOD_H1, 0, m_swing_lookback, high) < m_swing_lookback)
         return position.stop_loss;

      if(CopyLow(_Symbol, PERIOD_H1, 0, m_swing_lookback, low) < m_swing_lookback)
         return position.stop_loss;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      if(position.direction == SIGNAL_LONG)
      {
         // Find lowest low in lookback (excluding current bar)
         double swing_low = low[1];
         for(int i = 2; i < m_swing_lookback; i++)
         {
            if(low[i] < swing_low)
               swing_low = low[i];
         }
         // Add small buffer
         return swing_low - (10 * point);
      }
      else
      {
         // Find highest high in lookback (excluding current bar)
         double swing_high = high[1];
         for(int i = 2; i < m_swing_lookback; i++)
         {
            if(high[i] > swing_high)
               swing_high = high[i];
         }
         // Add small buffer
         return swing_high + (10 * point);
      }
   }

   //+------------------------------------------------------------------+
   //| Parabolic SAR trailing stop                                       |
   //+------------------------------------------------------------------+
   double CalculateSARTrail(SPosition &position, double current_price)
   {
      // SAR is already calculated, use it directly
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      if(position.direction == SIGNAL_LONG)
      {
         // For longs, SAR should be below price
         if(m_current_sar < current_price)
            return m_current_sar - (5 * point);  // Small buffer
      }
      else
      {
         // For shorts, SAR should be above price
         if(m_current_sar > current_price)
            return m_current_sar + (5 * point);  // Small buffer
      }

      return position.stop_loss;
   }

   //+------------------------------------------------------------------+
   //| Chandelier Exit trailing stop                                     |
   //+------------------------------------------------------------------+
   double CalculateChandelierTrail(SPosition &position, double current_price)
   {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      if(CopyHigh(_Symbol, PERIOD_H1, 0, m_swing_lookback, high) < m_swing_lookback)
         return position.stop_loss;

      if(CopyLow(_Symbol, PERIOD_H1, 0, m_swing_lookback, low) < m_swing_lookback)
         return position.stop_loss;

      double chandelier_dist = m_current_atr * m_chandelier_mult;

      if(position.direction == SIGNAL_LONG)
      {
         // Find highest high in lookback
         double highest = high[0];
         for(int i = 1; i < m_swing_lookback; i++)
         {
            if(high[i] > highest)
               highest = high[i];
         }
         return highest - chandelier_dist;
      }
      else
      {
         // Find lowest low in lookback
         double lowest = low[0];
         for(int i = 1; i < m_swing_lookback; i++)
         {
            if(low[i] < lowest)
               lowest = low[i];
         }
         return lowest + chandelier_dist;
      }
   }

   //+------------------------------------------------------------------+
   //| Stepped trailing stop (moves in discrete steps)                   |
   //+------------------------------------------------------------------+
   double CalculateSteppedTrail(SPosition &position, double current_price, double profit_points)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double step_size = m_current_atr * m_step_size_atr;

      // Calculate how many steps we've moved
      int steps = (int)(profit_points * point / step_size);

      if(steps <= 0)
         return position.stop_loss;

      // Each step moves SL by half a step size
      double sl_move = steps * (step_size * 0.5);

      if(position.direction == SIGNAL_LONG)
         return position.entry_price + sl_move - step_size;
      else
         return position.entry_price - sl_move + step_size;
   }

   //+------------------------------------------------------------------+
   //| Hybrid trailing - uses best of multiple methods                   |
   //+------------------------------------------------------------------+
   double CalculateHybridTrail(SPosition &position, double current_price, double profit_points)
   {
      double atr_sl = CalculateATRTrail(position, current_price);
      double swing_sl = CalculateSwingTrail(position, current_price);
      double chandelier_sl = CalculateChandelierTrail(position, current_price);

      double best_sl = position.stop_loss;

      if(position.direction == SIGNAL_LONG)
      {
         // For longs, use the highest (tightest but still valid) SL
         best_sl = MathMax(position.stop_loss, atr_sl);
         best_sl = MathMax(best_sl, swing_sl);
         best_sl = MathMax(best_sl, chandelier_sl);

         // But don't go higher than entry (would close in profit immediately)
         if(best_sl >= position.entry_price)
            best_sl = position.entry_price - (m_breakeven_offset * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      }
      else
      {
         // For shorts, use the lowest (tightest) SL
         best_sl = (atr_sl > 0) ? MathMin(position.stop_loss > 0 ? position.stop_loss : atr_sl, atr_sl) : position.stop_loss;
         if(swing_sl > 0) best_sl = MathMin(best_sl, swing_sl);
         if(chandelier_sl > 0) best_sl = MathMin(best_sl, chandelier_sl);

         // But don't go lower than entry
         if(best_sl <= position.entry_price)
            best_sl = position.entry_price + (m_breakeven_offset * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      }

      return best_sl;
   }

   //+------------------------------------------------------------------+
   //| Check if position should move to breakeven                        |
   //+------------------------------------------------------------------+
   bool ShouldMoveToBreakeven(SPosition &position)
   {
      if(!m_initialized) return false;

      Update();

      double current_price = (position.direction == SIGNAL_LONG) ?
                             SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profit_distance = 0;
      if(position.direction == SIGNAL_LONG)
         profit_distance = current_price - position.entry_price;
      else
         profit_distance = position.entry_price - current_price;

      double trigger_distance = m_current_atr * m_breakeven_trigger;

      return (profit_distance >= trigger_distance);
   }

   //+------------------------------------------------------------------+
   //| Get breakeven price                                               |
   //+------------------------------------------------------------------+
   double GetBreakevenPrice(SPosition &position)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      if(position.direction == SIGNAL_LONG)
         return position.entry_price + (m_breakeven_offset * point);
      else
         return position.entry_price - (m_breakeven_offset * point);
   }

   //+------------------------------------------------------------------+
   //| Get current ATR value                                             |
   //+------------------------------------------------------------------+
   double GetATR() { return m_current_atr; }

   //+------------------------------------------------------------------+
   //| Get recommended strategy based on market conditions               |
   //+------------------------------------------------------------------+
   ENUM_TRAIL_STRATEGY GetRecommendedStrategy(ENUM_REGIME_TYPE regime)
   {
      switch(regime)
      {
         case REGIME_TRENDING:
            return TRAIL_CHANDELIER;  // Wide trail for trends

         case REGIME_RANGING:
            return TRAIL_SWING;  // Swing-based for ranges

         case REGIME_VOLATILE:
            return TRAIL_ATR;  // ATR adapts to volatility

         case REGIME_CHOPPY:
            return TRAIL_STEPPED;  // Conservative stepping

         default:
            return m_default_strategy;
      }
   }
};
