//+------------------------------------------------------------------+
//| Utils.mqh                                                         |
//| Stack 1.7 - Utility Functions                                     |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

// Global logging flag (set by main EA)
bool g_enable_logging = true;

// Conditional logging macro - supports multiple parameters like Print()
#define LogPrint if(g_enable_logging) Print

//+------------------------------------------------------------------+
//| Normalize price to symbol digits                                  |
//+------------------------------------------------------------------+
double NormalizePrice(double price, string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Normalize lot size to symbol step                                 |
//+------------------------------------------------------------------+
double NormalizeLots(double lots, string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;
   
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lot_step) * lot_step;
   lots = MathMax(lots, min_lot);
   lots = MathMin(lots, max_lot);
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Get current trading session                                       |
//+------------------------------------------------------------------+
string GetCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   
   int hour = dt.hour;
   
   // Tokyo: 23:00-08:00 GMT
   if(hour >= 23 || hour < 8) return "ASIA";
   
   // London: 08:00-16:00 GMT
   if(hour >= 8 && hour < 16) return "LONDON";
   
   // New York: 13:00-21:00 GMT
   if(hour >= 13 && hour < 21) return "NEWYORK";
   
   return "CLOSED";
}

//+------------------------------------------------------------------+
//| Check if trading allowed in current session                       |
//+------------------------------------------------------------------+
//| Check if current time is OUTSIDE skip zone (allowed to trade)    |
//+------------------------------------------------------------------+
bool IsTradingHourAllowed(int skip_start_hour, int skip_end_hour)
{
   // If both are 0, no skip zone defined - allow all hours
   if(skip_start_hour == 0 && skip_end_hour == 0)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int current_hour = dt.hour;

   // Check if current hour is INSIDE the skip zone
   bool in_skip_zone;

   // Handle case where skip zone crosses midnight (e.g., 22-6)
   if(skip_start_hour > skip_end_hour)
   {
      in_skip_zone = (current_hour >= skip_start_hour || current_hour < skip_end_hour);
   }
   else
   {
      in_skip_zone = (current_hour >= skip_start_hour && current_hour < skip_end_hour);
   }

   // Return TRUE if OUTSIDE skip zone (trading allowed)
   return !in_skip_zone;
}

//+------------------------------------------------------------------+
//| Helper: Check if hour is within range [start, end)               |
//+------------------------------------------------------------------+
bool IsHourInRange(int hour, int start_hour, int end_hour)
{
   // Standard range (e.g. 10 to 19)
   if(start_hour < end_hour)
      return (hour >= start_hour && hour < end_hour);

   // Wrapped range (e.g. 22 to 02) - useful if trading overnight
   return (hour >= start_hour || hour < end_hour);
}


//+------------------------------------------------------------------+
//| Session Helpers (Vantage Markets GMT+2/3)                        |
//+------------------------------------------------------------------+
bool IsAsiaSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // Asia (Tokyo): 01:00 - 11:00 Server
   return IsHourInRange(dt.hour, 1, 11);
}

bool IsLondonSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // London: 10:00 - 19:00 Server
   return IsHourInRange(dt.hour, 10, 19);
}

bool IsNewYorkSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // New York: 15:00 - 00:00 Server (Midnight)
   return IsHourInRange(dt.hour, 15, 24);
}

//+------------------------------------------------------------------+
//| Check Session Times (Optimized for Vantage Markets GMT+2/3)      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Check if current time is within allowed trading sessions         |
//+------------------------------------------------------------------+
bool IsSessionAllowed(bool trade_asia, bool trade_london, bool trade_ny)
{
   // Check strictly if the enabled session is currently active
   if(trade_asia && IsAsiaSession()) return true;
   if(trade_london && IsLondonSession()) return true;
   if(trade_ny && IsNewYorkSession()) return true;

   return false;
}

//+------------------------------------------------------------------+
//| Format percentage for display                                     |
//+------------------------------------------------------------------+
string FormatPercent(double value)
{
   string sign = (value >= 0) ? "+" : "";
   return sign + DoubleToString(value, 2) + "%";
}

//+------------------------------------------------------------------+
//| Send notification (Alert + Push + Email if enabled)               |
//+------------------------------------------------------------------+
void SendNotificationAll(string message, bool enable_alert = true, 
                        bool enable_push = false, bool enable_email = false)
{
   if(enable_alert)
      Alert("Stack 1.7: ", message);
   
   if(enable_push && TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      SendNotification("Stack 1.7: " + message);
   
   if(enable_email && TerminalInfoInteger(TERMINAL_EMAIL_ENABLED))
      SendMail("Stack 1.7 Notification", message);
}

//+------------------------------------------------------------------+
//| Calculate percentage change                                       |
//+------------------------------------------------------------------+
double CalculatePercent(double current, double previous)
{
   if(previous == 0) return 0;
   return ((current - previous) / previous) * 100.0;
}