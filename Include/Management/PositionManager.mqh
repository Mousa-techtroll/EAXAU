//+------------------------------------------------------------------+
//| PositionManager.mqh                                               |
//| Active Position Management and Trailing                           |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"
#include "TradeExecutor.mqh" 
//+------------------------------------------------------------------+
//| Position Manager Class                                            |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   CTradeExecutor*      m_executor;
   int                  m_handle_ma_h1;
   int                  m_handle_atr_trail;  // PERFORMANCE FIX: Cached ATR handle for trailing

   // Trailing stop configuration
   int                  m_atr_period_trail;
   double               m_atr_multiplier_trail;
   double               m_min_trail_movement;

   // Auto-close configuration
   bool                 m_auto_close_choppy;
   int                  m_max_position_age_hours;

   // Take profit volume configuration
   double               m_tp1_volume_pct;
   double               m_tp2_volume_pct;

   // Breakeven configuration
   double               m_breakeven_offset_points;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CPositionManager(CTradeExecutor* executor, int atr_period = 14, double atr_mult = 2.0,
                    double min_movement = 50.0, bool auto_close_choppy = true, int max_age = 120,
                    double tp1_volume = 40.0, double tp2_volume = 30.0, double be_offset = 50.0)
   {
      m_executor = executor;
      m_atr_period_trail = atr_period;
      m_atr_multiplier_trail = atr_mult;
      m_min_trail_movement = min_movement;
      m_auto_close_choppy = auto_close_choppy;
      m_max_position_age_hours = max_age;
      m_tp1_volume_pct = tp1_volume / 100.0;
      m_tp2_volume_pct = tp2_volume / 100.0;
      m_breakeven_offset_points = be_offset;  // RISK FIX: Configurable BE offset (default 50 points = $0.50)
   }
   
   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init()
   {
      // Create H1 MA for trailing
      m_handle_ma_h1 = iMA(_Symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);

      if(m_handle_ma_h1 == INVALID_HANDLE)
      {
         LogPrint("ERROR: Failed to create MA in PositionManager");
         return false;
      }

      // PERFORMANCE FIX: Create H1 ATR for trailing (cached, not recreated every tick)
      m_handle_atr_trail = iATR(_Symbol, PERIOD_H1, m_atr_period_trail);

      if(m_handle_atr_trail == INVALID_HANDLE)
      {
         LogPrint("ERROR: Failed to create ATR in PositionManager");
         return false;
      }

      LogPrint("PositionManager initialized successfully");
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CPositionManager()
   {
      IndicatorRelease(m_handle_ma_h1);
      IndicatorRelease(m_handle_atr_trail);
   }
   
   //+------------------------------------------------------------------+
   //| Manage position (call every tick)                                |
   //+------------------------------------------------------------------+
   void ManagePosition(SPosition &position)
   {
      if(!PositionSelectByTicket(position.ticket))
         return; // Position already closed
      
      double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
      double entry_price = position.entry_price;
      double stop_loss = PositionGetDouble(POSITION_SL);
      
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool is_long = (type == POSITION_TYPE_BUY);
      
      // Calculate profit in points
      double profit_points;
      if(is_long)
         profit_points = (current_price - entry_price) / _Point;
      else
         profit_points = (entry_price - current_price) / _Point;
      
      // Step 1: Check TP1 (40% position)
      if(!position.tp1_closed)
      {
         bool tp1_hit = false;
         if(is_long && current_price >= position.tp1)
            tp1_hit = true;
         if(!is_long && current_price <= position.tp1)
            tp1_hit = true;
         
         if(tp1_hit)
         {
            double current_lots = PositionGetDouble(POSITION_VOLUME);
            double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

            double close_lots = current_lots * m_tp1_volume_pct;

            // FIX: Round to step
            close_lots = MathFloor(close_lots / lot_step) * lot_step;

            // FIX: Ensure we don't close 0, and leave at least min_lot open if we are not closing all
            if (close_lots < min_lot) close_lots = min_lot;
            if (current_lots - close_lots < min_lot) close_lots = current_lots; // Close all if remainder is invalid

            if(close_lots > 0 && m_executor.PartialClose(position.ticket, close_lots, "TP1 hit"))
            {
               position.tp1_closed = true;

               // RISK FIX: Move to breakeven + offset (default 50 points to clear spread/commission)
               double be_stop = is_long ? entry_price + m_breakeven_offset_points * _Point :
                                          entry_price - m_breakeven_offset_points * _Point;
               m_executor.ModifyStopLoss(position.ticket, be_stop);
               position.at_breakeven = true;

               LogPrint("TP1 reached for #", position.ticket, " | Remaining: ",
                     NormalizeLots(current_lots - close_lots), " lots at BE");
            }
         }
      }
      
      // Step 2: Check TP2 (30% position)
      if(position.tp1_closed && !position.tp2_closed)
      {
         bool tp2_hit = false;
         if(is_long && current_price >= position.tp2)
            tp2_hit = true;
         if(!is_long && current_price <= position.tp2)
            tp2_hit = true;
         
         if(tp2_hit)
         {
            double current_lots = PositionGetDouble(POSITION_VOLUME);
            double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

            // Calculate what percentage of remaining to close to achieve tp2_volume of original
            double tp2_of_remaining = m_tp2_volume_pct / (1.0 - m_tp1_volume_pct);
            double close_lots = current_lots * tp2_of_remaining;

            // FIX: Round to step
            close_lots = MathFloor(close_lots / lot_step) * lot_step;

            // FIX: Ensure we don't close 0, and leave at least min_lot open if we are not closing all
            if (close_lots < min_lot) close_lots = min_lot;
            if (current_lots - close_lots < min_lot) close_lots = current_lots; // Close all if remainder is invalid

            if(close_lots > 0 && m_executor.PartialClose(position.ticket, close_lots, "TP2 hit"))
            {
               position.tp2_closed = true;
               double remaining_pct = (1.0 - m_tp1_volume_pct - m_tp2_volume_pct) * 100;
               LogPrint("TP2 reached for #", position.ticket, " | Trailing final ", remaining_pct, "%");
            }
         }
      }
      
      // Step 3: Trail remaining position with ATR-based trailing stop
      // NOTE: Function named "TrailWithMA" is misleading - it actually uses ATR (m_handle_atr_trail)
      if(position.tp1_closed)
      {
         TrailWithATR(position, is_long);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Trail stop with ATR (after TP1)                                  |
   //+------------------------------------------------------------------+
   void TrailWithATR(SPosition &position, bool is_long)
   {
      // RISK FIX: Use H1 ATR to match entry timeframe (H4 ATR was too wide, giving back profits)
      // PERFORMANCE FIX: Use cached ATR handle (not creating/destroying every tick)
      double atr[];
      ArraySetAsSeries(atr, true);

      if(CopyBuffer(m_handle_atr_trail, 0, 0, 1, atr) <= 0)
      {
         return;
      }

      double current_price = is_long ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double current_sl = PositionGetDouble(POSITION_SL);
      double trail_distance = atr[0] * m_atr_multiplier_trail;

      double new_sl;
      if(is_long)
      {
         new_sl = NormalizePrice(current_price - trail_distance);

         // Only modify if new SL moved enough
         if(new_sl > current_sl && (new_sl - current_sl) >= m_min_trail_movement * _Point)
         {
            m_executor.ModifyStopLoss(position.ticket, new_sl);
         }
      }
      else // Short
      {
         new_sl = NormalizePrice(current_price + trail_distance);

         // Only modify if new SL is an improvement (lower)
         if(new_sl < current_sl || current_sl == 0)
         {
            // And only if the move is significant enough (or if there was no SL before)
            if(current_sl == 0 || (current_sl - new_sl) >= m_min_trail_movement * _Point)
            {
               m_executor.ModifyStopLoss(position.ticket, new_sl);
            }
         }
      }

      // No need to release handle - using cached m_handle_atr_trail
   }
   
   //+------------------------------------------------------------------+
   //| Check if position should be closed (regime/macro change)         |
   //+------------------------------------------------------------------+
   bool ShouldClosePosition(const SPosition &position,
                            ENUM_REGIME_TYPE current_regime,
                            int macro_score)
   {
      // AUTO-CLOSE LOGIC 1: Close TREND-FOLLOWING positions in CHOPPY markets (if enabled)
      // LOGIC FIX: Mean reversion patterns THRIVE in choppy markets - only close trend positions
      // Choppy = erratic, low conviction - unfavorable for trend-following, but IDEAL for mean reversion
      if(m_auto_close_choppy && current_regime == REGIME_CHOPPY)
      {
         // Only close trend-following positions (Engulfing, Pin Bar, MA Cross, Liquidity Sweep)
         // Keep mean reversion positions (BB Mean Reversion, Range Box, False Breakout Fade)
         if(position.pattern_type != PATTERN_BB_MEAN_REVERSION &&
            position.pattern_type != PATTERN_RANGE_BOX &&
            position.pattern_type != PATTERN_FALSE_BREAKOUT_FADE)
         {
            LogPrint("AUTO-CLOSE: CHOPPY regime - closing trend position #", position.ticket, " (",
                  EnumToString(position.pattern_type), ") to avoid whipsaw");
            return true;
         }
         else
         {
            // Mean reversion position in choppy market - this is ideal, keep it
            LogPrint("KEEP: Mean reversion position #", position.ticket, " in CHOPPY regime (favorable conditions)");
         }
      }

      // AUTO-CLOSE LOGIC 2: Close trending positions when market goes RANGING
      // If position was opened in trending regime but market is now ranging
      if(current_regime == REGIME_RANGING &&
         (position.direction == SIGNAL_LONG || position.direction == SIGNAL_SHORT))
      {
         // Keep positions - let trailing stops handle it
         // S/R bounce positions can still work in ranging markets
         return false;
      }

      // AUTO-CLOSE LOGIC 3: UNKNOWN regime - keep positions, let stops work
      if(current_regime == REGIME_UNKNOWN)
      {
         return false; // Keep positions, trailing stops will protect
      }

      // AUTO-CLOSE LOGIC 4: Macro opposition - close if strongly against position
      if(position.direction == SIGNAL_LONG && macro_score <= -3)
      {
         LogPrint("AUTO-CLOSE: Macro strongly bearish (", macro_score, ") - closing long #", position.ticket);
         return true;
      }

      if(position.direction == SIGNAL_SHORT && macro_score >= 3)
      {
         LogPrint("AUTO-CLOSE: Macro strongly bullish (+", macro_score, ") - closing short #", position.ticket);
         return true;
      }

      // AUTO-CLOSE LOGIC 5: Maximum position age (if enabled)
      if(m_max_position_age_hours > 0)
      {
         datetime now = TimeCurrent();
         int position_age_hours = (int)((now - position.open_time) / 3600);

         if(position_age_hours > m_max_position_age_hours)
         {
            LogPrint("AUTO-CLOSE: Position #", position.ticket, " exceeded max age (",
                  position_age_hours, " / ", m_max_position_age_hours, " hours)");
            return true;
         }
      }

      return false;
   }
};