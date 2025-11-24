//+------------------------------------------------------------------+
//|  TradeExecutor.mqh                                               |
//|  Order Execution and Management                                  |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//|  Trade Executor Class                                            |
//+------------------------------------------------------------------+
class CTradeExecutor
{
private:
    CTrade                                                m_trade;
    int                                                   m_magic_number;
    int                                                   m_slippage;
    int                                                   m_max_retries;
    int                                                   m_slippage_warn_threshold;  // Warn if slippage exceeds this (points)

public:
    //+------------------------------------------------------------------+
    //|  Constructor                                                     |
    //+------------------------------------------------------------------+
    CTradeExecutor(int magic = 170717, int slippage = 10, int slippage_warn = 5)
    {
        m_magic_number = magic;
        m_slippage = slippage;
        m_max_retries = 3;
        m_slippage_warn_threshold = slippage_warn;
    }

    //+------------------------------------------------------------------+
    //|  Initialize                                                      |
    //+------------------------------------------------------------------+
    bool Init()
    {
        m_trade.SetExpertMagicNumber(m_magic_number);

        // CRITICAL FIX: Adjust slippage based on broker's point definition
        // Gold can be 2-digit (2300.50) or 3-digit (2300.500)
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        int adjusted_slippage = m_slippage;

        if(digits == 3) // 3-digit broker (e.g., 2300.500)
        {
            adjusted_slippage = m_slippage * 10; // 10 points = $0.10 instead of $0.01
            LogPrint("SLIPPAGE AUTO-ADJUSTED: 3-digit broker detected, slippage: ", m_slippage, " -> ", adjusted_slippage, " points");
        }

        m_trade.SetDeviationInPoints(adjusted_slippage);
        m_trade.SetTypeFilling(ORDER_FILLING_FOK);
        m_trade.SetAsyncMode(false);

        LogPrint("TradeExecutor initialized (Magic: ", m_magic_number, ", Slippage: ", adjusted_slippage, " pts, Warn: ", m_slippage_warn_threshold, " pts)");
        return true;
    }

    //+------------------------------------------------------------------+
    //|  Open Long Position                                              |
    //+------------------------------------------------------------------+
    ulong OpenLong(double lots, double stop_loss, double tp1, double tp2, string comment = "")
    {
        double planned_entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // Normalize prices
        planned_entry = NormalizePrice(planned_entry);
        stop_loss = NormalizePrice(stop_loss);

        // Validate stop loss
        if(stop_loss >= planned_entry)
        {
            LogPrint("ERROR: Invalid stop loss for LONG: SL=", stop_loss, " Entry=", planned_entry);
            return 0;
        }

        // Validate broker's minimum stop level
        if(!ValidateStopLevel(planned_entry, stop_loss, true))
        {
            LogPrint("ERROR: Stop loss violates broker minimum distance");
            return 0;
        }

        // Prepare comment
        string full_comment =  comment;

        // Execute order with retry logic
        ulong ticket = 0;
        for(int attempt = 1; attempt <= m_max_retries; attempt++)
        {
            double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            if(m_trade.Buy(lots, _Symbol, entry_price, stop_loss, 0, full_comment))
            {
                ticket = m_trade.ResultOrder();
                double actual_price = m_trade.ResultPrice();

                // Calculate slippage
                double slippage_points = MathAbs(actual_price - planned_entry) / _Point;

                // Log the trade
                LogPrint("LONG opened: Ticket=", ticket, " | Lots=", lots,
                            " | Planned=", planned_entry, " | Actual=", actual_price, " | SL=", stop_loss);

                // Warn if slippage exceeds threshold
                if(slippage_points > m_slippage_warn_threshold)
                {
                    LogPrint("WARNING: Entry slippage detected! ", slippage_points, " points (threshold: ",
                          m_slippage_warn_threshold, "). Planned: ", planned_entry, " Actual: ", actual_price);

                    // Calculate impact on R:R
                    double planned_risk = planned_entry - stop_loss;
                    double actual_risk = actual_price - stop_loss;
                    double risk_increase_pct = ((actual_risk - planned_risk) / planned_risk) * 100;

                    if(risk_increase_pct > 10)
                    {
                        LogPrint("ALERT: Slippage increased risk by ", DoubleToString(risk_increase_pct, 1),
                              "% (", DoubleToString(planned_risk, 2), " -> ", DoubleToString(actual_risk, 2), " points)");
                    }
                }

                return ticket;
            }
            else
            {
                uint error_code = m_trade.ResultRetcode();
                LogPrint("Attempt ", attempt, " failed. Error: ", error_code, " - ",
                            m_trade.ResultRetcodeDescription());

                if(error_code == TRADE_RETCODE_REQUOTE)
                {
                    Sleep(100);     // Wait and retry
                    continue;
                }
                else if(error_code == TRADE_RETCODE_INVALID_STOPS)
                {
                    // Adjust stop loss
                    stop_loss = AdjustStopLoss(entry_price, stop_loss, true);
                    continue;
                }
                else
                {
                    break;      // Other errors, don't retry
                }
            }
        }

        LogPrint("ERROR: Failed to open LONG after ", m_max_retries, " attempts");
        return 0;
    }

    //+------------------------------------------------------------------+
    //|  Open Short Position                                             |
    //+------------------------------------------------------------------+
    ulong OpenShort(double lots, double stop_loss, double tp1, double tp2, string comment = "")
    {
        double planned_entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Normalize prices
        planned_entry = NormalizePrice(planned_entry);
        stop_loss = NormalizePrice(stop_loss);

        // Validate stop loss
        if(stop_loss <= planned_entry)
        {
            LogPrint("ERROR: Invalid stop loss for SHORT: SL=", stop_loss, " Entry=", planned_entry);
            return 0;
        }

        // Validate broker's minimum stop level
        if(!ValidateStopLevel(planned_entry, stop_loss, false))
        {
            LogPrint("ERROR: Stop loss violates broker minimum distance");
            return 0;
        }

        // Prepare comment
        string full_comment =  comment;

        // Execute order with retry logic
        ulong ticket = 0;
        for(int attempt = 1; attempt <= m_max_retries; attempt++)
        {
            double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            if(m_trade.Sell(lots, _Symbol, entry_price, stop_loss, 0, full_comment))
            {
                ticket = m_trade.ResultOrder();
                double actual_price = m_trade.ResultPrice();

                // Calculate slippage
                double slippage_points = MathAbs(actual_price - planned_entry) / _Point;

                // Log the trade
                LogPrint("SHORT opened: Ticket=", ticket, " | Lots=", lots,
                            " | Planned=", planned_entry, " | Actual=", actual_price, " | SL=", stop_loss);

                // Warn if slippage exceeds threshold
                if(slippage_points > m_slippage_warn_threshold)
                {
                    LogPrint("WARNING: Entry slippage detected! ", slippage_points, " points (threshold: ",
                          m_slippage_warn_threshold, "). Planned: ", planned_entry, " Actual: ", actual_price);

                    // Calculate impact on R:R
                    double planned_risk = stop_loss - planned_entry;
                    double actual_risk = stop_loss - actual_price;
                    double risk_increase_pct = ((actual_risk - planned_risk) / planned_risk) * 100;

                    if(risk_increase_pct > 10)
                    {
                        LogPrint("ALERT: Slippage increased risk by ", DoubleToString(risk_increase_pct, 1),
                              "% (", DoubleToString(planned_risk, 2), " -> ", DoubleToString(actual_risk, 2), " points)");
                    }
                }

                return ticket;
            }
            else
            {
                uint error_code = m_trade.ResultRetcode();
                LogPrint("Attempt ", attempt, " failed. Error: ", error_code, " - ",
                            m_trade.ResultRetcodeDescription());

                if(error_code == TRADE_RETCODE_REQUOTE)
                {
                    Sleep(100);
                    continue;
                }
                else if(error_code == TRADE_RETCODE_INVALID_STOPS)
                {
                    stop_loss = AdjustStopLoss(entry_price, stop_loss, false);
                    continue;
                }
                else
                {
                    break;
                }
            }
        }

        LogPrint("ERROR: Failed to open SHORT after ", m_max_retries, " attempts");
        return 0;
    }

    //+------------------------------------------------------------------+
    //|  Close position by ticket                                        |
    //+------------------------------------------------------------------+
    bool ClosePosition(ulong ticket, string reason = "")
    {
        if(!PositionSelectByTicket(ticket))
        {
            LogPrint("Position not found: ", ticket);
            return false;
        }

        if(m_trade.PositionClose(ticket))
        {
            LogPrint("Position closed: ", ticket, " | Reason: ", reason);
            return true;
        }
        else
        {
            LogPrint("Failed to close position: ", ticket, " | Error: ", m_trade.ResultRetcode());
            return false;
        }
    }

    //+------------------------------------------------------------------+
    //|  Partially close position                                        |
    //+------------------------------------------------------------------+
    bool PartialClose(ulong ticket, double lots, string reason = "")
    {
        if(!PositionSelectByTicket(ticket))
        {
            LogPrint("Position not found: ", ticket);
            return false;
        }

        double current_lots = PositionGetDouble(POSITION_VOLUME);
        if(lots >= current_lots)
        {
            return ClosePosition(ticket, reason);
        }

        if(m_trade.PositionClosePartial(ticket, lots))
        {
            LogPrint("Partial close: ", ticket, " | Closed: ", lots, " | Remaining: ",
                        current_lots - lots, " | Reason: ", reason);
            return true;
        }
        else
        {
            LogPrint("Failed to partially close: ", ticket, " | Error: ", m_trade.ResultRetcode());
            return false;
        }
    }

    //+------------------------------------------------------------------+
    //|  Modify position stop loss                                       |
    //+------------------------------------------------------------------+
    bool ModifyStopLoss(ulong ticket, double new_sl)
    {
        if(!PositionSelectByTicket(ticket))
        {
            LogPrint("Position not found: ", ticket);
            return false;
        }

        double current_sl = PositionGetDouble(POSITION_SL);
        double current_tp = PositionGetDouble(POSITION_TP);

        new_sl = NormalizePrice(new_sl);

        // Validate: never move SL against position
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if(type == POSITION_TYPE_BUY && new_sl < current_sl && current_sl > 0)
        {
            LogPrint("WARNING: Not moving BUY stop loss down (", current_sl, " -> ", new_sl, ")");
            return false;
        }
        if(type == POSITION_TYPE_SELL && new_sl > current_sl && current_sl > 0)
        {
            LogPrint("WARNING: Not moving SELL stop loss up (", current_sl, " -> ", new_sl, ")");
            return false;
        }

        if(m_trade.PositionModify(ticket, new_sl, current_tp))
        {
            LogPrint("Stop loss modified: ", ticket, " | ", current_sl, " -> ", new_sl);
            return true;
        }
        else
        {
            LogPrint("Failed to modify SL: ", ticket, " | Error: ", m_trade.ResultRetcode());
            return false;
        }
    }

    //+------------------------------------------------------------------+
    //|  Close all positions with retry logic                            |
    //|  RISK FIX: Ensures all positions actually close (prevents orphaned positions)|
    //+------------------------------------------------------------------+
    void CloseAllPositions(string reason = "")
    {
        int max_attempts = 5;
        int attempt = 0;

        // Keep trying until all positions with our magic number are closed
        while(attempt < max_attempts)
        {
            int positions_closed = 0;
            int positions_remaining = 0;

            int total = PositionsTotal();

            for(int i = total - 1; i >= 0; i--)
            {
                ulong ticket = PositionGetTicket(i);
                if(PositionGetInteger(POSITION_MAGIC) == m_magic_number)
                {
                    positions_remaining++;
                    if(ClosePosition(ticket, reason))
                    {
                        positions_closed++;
                    }
                }
            }

            // If no positions with our magic number remain, we're done
            if(positions_remaining == 0)
            {
                LogPrint("All positions closed successfully. Reason: ", reason);
                return;
            }

            // If we closed at least one position, reset attempt counter (making progress)
            if(positions_closed > 0)
            {
                attempt = 0;
                LogPrint("Closed ", positions_closed, "/", positions_remaining, " positions. Retrying remaining...");
            }
            else
            {
                attempt++;
                LogPrint("WARNING: Failed to close any positions on attempt ", attempt, ". Retrying...");
            }

            // Small delay before retry to avoid spam
            Sleep(100);
        }

        // If we get here, we failed after max attempts
        LogPrint("ERROR: Failed to close all positions after ", max_attempts, " attempts. Manual intervention required!");
    }

private:
    //+------------------------------------------------------------------+
    //|  Validate stop level against broker requirements                 |
    //+------------------------------------------------------------------+
    bool ValidateStopLevel(double entry, double stop, bool is_long)
    {
        int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
        if(stops_level == 0) return true;     // No restriction

        double min_distance = stops_level * _Point;
        double actual_distance = MathAbs(entry - stop);

        if(actual_distance < min_distance)
        {
            LogPrint("Stop level too close. Min: ", min_distance, " | Actual: ", actual_distance);
            return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //|  Adjust stop loss to meet broker requirements                    |
    //+------------------------------------------------------------------+
    double AdjustStopLoss(double entry, double stop, bool is_long)
    {
        int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double min_distance = (stops_level + 5) * _Point;

        if(is_long)
            return NormalizePrice(entry - min_distance);
        else
            return NormalizePrice(entry + min_distance);
    }
};
