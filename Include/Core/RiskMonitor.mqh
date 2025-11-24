//+------------------------------------------------------------------+
//| RiskMonitor.mqh                                                   |
//| Monitors Risk Limits and Daily Trade Constraints                 |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Management/RiskManager.mqh"
#include "../Management/TradeExecutor.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| CRiskMonitor - Monitors and enforces risk limits                 |
//+------------------------------------------------------------------+
class CRiskMonitor
{
private:
   CRiskManager*     m_risk_manager;
   CTradeExecutor*   m_trade_executor;

   int               m_trades_today;
   datetime          m_last_trade_date;
   int               m_max_trades_per_day;

   bool              m_enable_alerts;
   bool              m_enable_push;
   bool              m_enable_email;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CRiskMonitor(CRiskManager* risk_mgr, CTradeExecutor* executor,
                int max_trades_per_day, bool alerts, bool push, bool email)
   {
      m_risk_manager = risk_mgr;
      m_trade_executor = executor;
      m_max_trades_per_day = max_trades_per_day;
      m_enable_alerts = alerts;
      m_enable_push = push;
      m_enable_email = email;

      m_trades_today = 0;
      m_last_trade_date = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Init()
   {
      m_trades_today = 0;
      m_last_trade_date = 0;
   }

   //+------------------------------------------------------------------+
   //| Get trades today count                                           |
   //+------------------------------------------------------------------+
   int GetTradesToday() { return m_trades_today; }

   //+------------------------------------------------------------------+
   //| Increment daily trade counter                                    |
   //+------------------------------------------------------------------+
   void IncrementTradesToday()
   {
      m_trades_today++;
      m_last_trade_date = TimeCurrent();
   }

   //+------------------------------------------------------------------+
   //| Check if daily trade limit allows new trades                     |
   //+------------------------------------------------------------------+
   bool CanTrade()
   {
      if (m_max_trades_per_day <= 0)
         return true;  // No limit

      // Check if it's a new day
      MqlDateTime current_time;
      TimeToStruct(TimeCurrent(), current_time);
      MqlDateTime last_trade_time;
      TimeToStruct(m_last_trade_date, last_trade_time);

      if (current_time.day != last_trade_time.day ||
          current_time.mon != last_trade_time.mon ||
          current_time.year != last_trade_time.year)
      {
         m_trades_today = 0;  // Reset counter for new day
      }

      if (m_trades_today >= m_max_trades_per_day)
      {
         LogPrint("Daily trade limit reached (", m_trades_today, "/", m_max_trades_per_day, ")");
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check risk limits and enforce halts                              |
   //+------------------------------------------------------------------+
   void CheckRiskLimits()
   {
      if (m_risk_manager.IsTradingHalted())
      {
         double daily_pnl = m_risk_manager.GetDailyPnL();

         LogPrint("========================================");
         LogPrint("DAILY LOSS LIMIT HIT: ", FormatPercent(daily_pnl));
         LogPrint("Closing all positions and halting trading");
         LogPrint("========================================");

         m_trade_executor.CloseAllPositions("Daily loss limit");

         if (m_enable_alerts || m_enable_push || m_enable_email)
         {
            string msg = "DAILY LOSS LIMIT HIT! Trading halted.";
            SendNotificationAll(msg, true, m_enable_push, m_enable_email);
         }
      }
   }
};
