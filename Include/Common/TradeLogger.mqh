//+------------------------------------------------------------------+
//| TradeLogger.mqh                                                   |
//| CSV Trade Statistics Logger                                       |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "Structs.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| CTradeLogger - Logs trade statistics to CSV file                 |
//+------------------------------------------------------------------+
class CTradeLogger
{
private:
   string   m_filename;
   int      m_file_handle;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CTradeLogger()
   {
      m_filename = "";
      m_file_handle = INVALID_HANDLE;
   }

   //+------------------------------------------------------------------+
   //| Initialize pattern stats CSV file                                |
   //+------------------------------------------------------------------+
   bool Init()
   {
      // Create filename with date for easy identification
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      m_filename = StringFormat("PatternStats_%04d%02d%02d_%02d%02d.csv",
                                dt.year, dt.mon, dt.day, dt.hour, dt.min);

      m_file_handle = FileOpen(m_filename, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');

      if(m_file_handle != INVALID_HANDLE)
      {
         // Write header
         FileWrite(m_file_handle,
                   "Ticket", "Pattern", "Direction", "EntryTime", "EntryPrice",
                   "StopLoss", "TP1", "TP2", "RiskPct", "RiskAmount", "LotSize",
                   "Quality", "ExitTime", "ExitPrice", "PnL_Money", "PnL_R", "Result");
         LogPrint("Pattern stats file created: ", m_filename);
         return true;
      }
      else
      {
         LogPrint("ERROR: Could not create pattern stats file: ", m_filename);
         return false;
      }
   }

   //+------------------------------------------------------------------+
   //| Log trade entry to CSV                                           |
   //+------------------------------------------------------------------+
   void LogTradeEntry(SPosition &pos, double risk_amount)
   {
      if(m_file_handle == INVALID_HANDLE) return;

      string direction = (pos.direction == SIGNAL_LONG) ? "LONG" : "SHORT";
      string quality = EnumToString(pos.setup_quality);

      // Write entry data (exit fields will be empty for now)
      FileWrite(m_file_handle,
                (long)pos.ticket,
                pos.pattern_name,
                direction,
                TimeToString(pos.open_time, TIME_DATE|TIME_MINUTES),
                DoubleToString(pos.entry_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.stop_loss, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.tp1, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.tp2, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.initial_risk_pct, 2),
                DoubleToString(risk_amount, 2),
                DoubleToString(pos.lot_size, 2),
                quality,
                "", "", "", "", "");  // Exit fields empty

      FileFlush(m_file_handle);
      LogPrint(">>> STATS: Entry logged for ", pos.pattern_name, " ticket #", pos.ticket);
   }

   //+------------------------------------------------------------------+
   //| Log trade exit to CSV                                            |
   //+------------------------------------------------------------------+
   void LogTradeExit(SPosition &pos, double profit, double exit_price)
   {
      if(m_file_handle == INVALID_HANDLE) return;

      string direction = (pos.direction == SIGNAL_LONG) ? "LONG" : "SHORT";
      string quality = EnumToString(pos.setup_quality);

      // Calculate R-multiple
      double risk_amount = pos.initial_risk_pct * AccountInfoDouble(ACCOUNT_BALANCE) / 100.0;
      double pnl_r = 0;
      if(risk_amount > 0)
         pnl_r = profit / risk_amount;

      string result = "BE";  // Breakeven
      if(profit > 0) result = "WIN";
      else if(profit < 0) result = "LOSS";

      // Write complete trade record
      FileWrite(m_file_handle,
                (long)pos.ticket,
                pos.pattern_name,
                direction,
                TimeToString(pos.open_time, TIME_DATE|TIME_MINUTES),
                DoubleToString(pos.entry_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.stop_loss, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.tp1, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.tp2, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(pos.initial_risk_pct, 2),
                DoubleToString(risk_amount, 2),
                DoubleToString(pos.lot_size, 2),
                quality,
                TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
                DoubleToString(exit_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(profit, 2),
                DoubleToString(pnl_r, 2),
                result);

      FileFlush(m_file_handle);
      LogPrint(">>> STATS: Exit logged for ", pos.pattern_name, " | PnL: $", DoubleToString(profit, 2),
               " | R: ", DoubleToString(pnl_r, 2), " | ", result);
   }

   //+------------------------------------------------------------------+
   //| Close pattern stats file                                         |
   //+------------------------------------------------------------------+
   void Close()
   {
      if(m_file_handle != INVALID_HANDLE)
      {
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
         LogPrint("Pattern stats file closed: ", m_filename);
      }
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CTradeLogger()
   {
      Close();
   }
};
