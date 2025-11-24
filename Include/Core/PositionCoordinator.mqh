//+------------------------------------------------------------------+
//| PositionCoordinator.mqh                                           |
//| Coordinates Position Lifecycle and Management                     |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"
#include "../Management/PositionManager.mqh"
#include "../Management/TradeExecutor.mqh"
#include "../Management/RiskManager.mqh"
#include "../Components/RegimeClassifier.mqh"
#include "../Components/MacroBias.mqh"
#include "../Common/TradeLogger.mqh"

//+------------------------------------------------------------------+
//| CPositionCoordinator - Manages position array and lifecycle      |
//+------------------------------------------------------------------+
class CPositionCoordinator
{
private:
   CPositionManager*    m_position_manager;
   CTradeExecutor*      m_trade_executor;
   CRiskManager*        m_risk_manager;
   CRegimeClassifier*   m_regime_classifier;
   CMacroBias*          m_macro_bias;
   CTradeLogger*        m_trade_logger;

   SPosition            m_positions[];
   int                  m_position_count;
   int                  m_magic_number;

   bool                 m_close_before_weekend;
   int                  m_weekend_close_hour;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CPositionCoordinator(CPositionManager* pos_mgr, CTradeExecutor* executor,
                        CRiskManager* risk_mgr, CRegimeClassifier* regime,
                        CMacroBias* macro, CTradeLogger* logger,
                        int magic_number, bool close_weekend, int weekend_hour)
   {
      m_position_manager = pos_mgr;
      m_trade_executor = executor;
      m_risk_manager = risk_mgr;
      m_regime_classifier = regime;
      m_macro_bias = macro;
      m_trade_logger = logger;
      m_magic_number = magic_number;
      m_close_before_weekend = close_weekend;
      m_weekend_close_hour = weekend_hour;

      m_position_count = 0;
      ArrayResize(m_positions, 0);
   }

   //+------------------------------------------------------------------+
   //| Initialize position array                                        |
   //+------------------------------------------------------------------+
   void Init()
   {
      m_position_count = 0;
      ArrayResize(m_positions, 0);
   }

   //+------------------------------------------------------------------+
   //| Get position count                                               |
   //+------------------------------------------------------------------+
   int GetPositionCount() { return m_position_count; }

   //+------------------------------------------------------------------+
   //| Get position by index                                            |
   //+------------------------------------------------------------------+
   SPosition GetPosition(int index)
   {
      if (index >= 0 && index < m_position_count)
         return m_positions[index];
      SPosition empty;
      return empty;
   }

   //+------------------------------------------------------------------+
   //| Add position to tracking                                         |
   //+------------------------------------------------------------------+
   void AddPosition(SPosition &position)
   {
      ArrayResize(m_positions, m_position_count + 1);
      m_positions[m_position_count] = position;
      m_position_count++;
   }

   //+------------------------------------------------------------------+
   //| Load existing open positions                                     |
   //+------------------------------------------------------------------+
   void LoadOpenPositions()
   {
      int total = PositionsTotal();

      for (int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);

         if (PositionGetInteger(POSITION_MAGIC) == m_magic_number)
         {
            SPosition position;
            position.ticket = ticket;
            position.direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                                 SIGNAL_LONG : SIGNAL_SHORT;
            position.pattern_type = PATTERN_NONE;
            position.lot_size = PositionGetDouble(POSITION_VOLUME);
            position.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            position.stop_loss = PositionGetDouble(POSITION_SL);
            position.tp1 = 0.0;
            position.tp2 = 0.0;
            position.open_time = (datetime)PositionGetInteger(POSITION_TIME);
            position.setup_quality = SETUP_NONE;
            position.pattern_name = "";
            position.tp1_closed = false;
            position.tp2_closed = false;
            position.at_breakeven = false;
            position.initial_risk_pct = (m_risk_manager != NULL)
                                        ? m_risk_manager.ComputeRiskPercent(position.lot_size, position.entry_price, position.stop_loss)
                                        : 0.0;

            ArrayResize(m_positions, m_position_count + 1);
            m_positions[m_position_count] = position;
            m_position_count++;
            
            // LOGIC FIX: Notify Risk Manager of the loaded position's existence
            if (m_risk_manager != NULL)
            {
               m_risk_manager.AddPosition(position);
            }

            LogPrint("Loaded existing position: Ticket = ", ticket);
         }
      }

      if (m_position_count > 0)
         LogPrint("Loaded ", m_position_count, " existing position(s)");
   }

   //+------------------------------------------------------------------+
   //| Manage all open positions                                        |
   //+------------------------------------------------------------------+
   void ManageOpenPositions()
   {
      // Weekend position closure
      if (m_close_before_weekend && m_position_count > 0)
      {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);

         if (dt.day_of_week == 5 && dt.hour >= m_weekend_close_hour)
         {
            LogPrint("WEEKEND CLOSURE: Closing all positions before weekend (Friday ", dt.hour, ":00)");

            // Log all positions before closing
            for (int i = m_position_count - 1; i >= 0; i--)
            {
               double exit_price = (m_positions[i].direction == SIGNAL_LONG) ?
                                   SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                                   SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double profit = PositionSelectByTicket(m_positions[i].ticket) ?
                              PositionGetDouble(POSITION_PROFIT) : 0;

               if (m_trade_logger != NULL)
                  m_trade_logger.LogTradeExit(m_positions[i], profit, exit_price);
            }

            m_trade_executor.CloseAllPositions("Weekend closure");

            // Clear position tracking
            for (int i = m_position_count - 1; i >= 0; i--)
            {
               m_risk_manager.RemovePosition(m_positions[i].ticket, false);
            }
            m_position_count = 0;
            ArrayResize(m_positions, 0);
            return;
         }
      }

      ENUM_REGIME_TYPE regime = m_regime_classifier.GetRegime();
      int macro_score = m_macro_bias.GetBiasScore();

      for (int i = m_position_count - 1; i >= 0; i--)
      {
         if (!PositionSelectByTicket(m_positions[i].ticket))
         {
            // Position closed (by SL/TP)
            double profit = 0;
            double exit_price = 0;

            if (HistorySelectByPosition(m_positions[i].ticket))
            {
               int deals = HistoryDealsTotal();
               if (deals > 0)
               {
                  ulong deal_ticket = HistoryDealGetTicket(deals - 1);
                  profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                  exit_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
               }
            }

            // Log trade exit
            if (m_trade_logger != NULL)
               m_trade_logger.LogTradeExit(m_positions[i], profit, exit_price);

            bool is_winner = (profit > 0);
            m_risk_manager.RemovePosition(m_positions[i].ticket, is_winner);

            // Remove from array
            for (int j = i; j < m_position_count - 1; j++)
            {
               m_positions[j] = m_positions[j + 1];
            }
            m_position_count--;
            ArrayResize(m_positions, m_position_count);

            continue;
         }

         // Manage active position
         m_position_manager.ManagePosition(m_positions[i]);

         // Check if should close due to regime/macro change
         if (m_position_manager.ShouldClosePosition(m_positions[i], regime, macro_score))
         {
            m_trade_executor.ClosePosition(m_positions[i].ticket, "Regime/Macro change");
         }
      }
   }
};
