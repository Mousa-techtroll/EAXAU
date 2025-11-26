//+------------------------------------------------------------------+
//| RiskManager.mqh                                                   |
//| Risk Management and Position Sizing                               |
//+------------------------------------------------------------------+
#property copyright "Stack 1.7"
#property version   "1.00"

#include "../Common/Enums.mqh"
#include "../Common/Structs.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| Lightweight position risk data (avoids full SPosition duplication)|
//+------------------------------------------------------------------+
struct SPositionRisk
{
   ulong    ticket;
   double   initial_risk_pct;
};

//+------------------------------------------------------------------+
//| Risk Manager Class                                                |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
      // Risk parameters
      double                  m_max_total_exposure;
      double                  m_daily_loss_limit;
      double                  m_max_lot_multiplier;
      int                     m_max_positions;
      double                  m_max_margin_usage;

      // Consecutive loss protection
      bool                    m_enable_loss_scaling;
      int                     m_losses_level1;
      int                     m_losses_level2;
      double                  m_risk_reduction_level1;
      double                  m_risk_reduction_level2;

      // Risk statistics
      SRiskStats              m_stats;

      // Position risk tracking (lightweight - only tracks risk data, not full position state)
      // Full position state (TP flags, trailing, etc.) is managed by PositionCoordinator
      // This avoids state desync between two full SPosition arrays
      SPositionRisk           m_position_risks[];
      int                     m_position_count;

public:
      //+------------------------------------------------------------------+
      //| Constructor                                                      |
      //+------------------------------------------------------------------+
      CRiskManager(double max_exposure = 6.5, double daily_limit = 4.0, double max_lot_mult = 3.0,
                   int max_pos = 3, double max_margin = 80.0,
                   bool enable_scaling = true, int level1_losses = 2, int level2_losses = 3,
                   double level1_reduction = 75.0, double level2_reduction = 50.0)
      {
            m_max_total_exposure = max_exposure;
            m_daily_loss_limit = daily_limit;
            m_max_lot_multiplier = max_lot_mult;
            m_max_positions = max_pos;
            m_max_margin_usage = max_margin;

            m_enable_loss_scaling = enable_scaling;
            m_losses_level1 = level1_losses;
            m_losses_level2 = level2_losses;
            m_risk_reduction_level1 = level1_reduction;
            m_risk_reduction_level2 = level2_reduction;

            m_position_count = 0;
            ArrayResize(m_position_risks, 0);
      }

      //+------------------------------------------------------------------+
      //| Initialize                                                        |
      //+------------------------------------------------------------------+
      bool Init()
      {
            // Initialize stats
            m_stats.current_exposure = 0;
            m_stats.daily_pnl_pct = 0;
            m_stats.consecutive_losses = 0;
            m_stats.consecutive_wins = 0;
            m_stats.positions_count = 0;
            m_stats.trading_halted = false;
            // REMOVED: m_stats.daily_start_balance - now calculated from history in UpdateDailyStats()
            m_stats.last_day_reset = TimeCurrent();

            return true;
      }

      //+------------------------------------------------------------------+
      //| Get daily realized P&L from history (Robust against restarts)    |
      //+------------------------------------------------------------------+
      double GetDailyRealizedPnL()
      {
            datetime start_of_day = iTime(_Symbol, PERIOD_D1, 0);
            HistorySelect(start_of_day, TimeCurrent());

            double daily_profit = 0;
            int deals = HistoryDealsTotal();

            for(int i = 0; i < deals; i++)
            {
                  ulong ticket = HistoryDealGetTicket(i);
                  if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT ||
                     HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_INOUT)
                  {
                        daily_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
                        daily_profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
                        daily_profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                  }
            }
            return daily_profit;
      }

      //+------------------------------------------------------------------+
      //| Update daily statistics - REVISED: History-based calculation     |
      //+------------------------------------------------------------------+
      void UpdateDailyStats()
      {
            // 1. Get Realized PnL from History (Robust against restarts)
            double realized_pnl = GetDailyRealizedPnL();

            // 2. Get Floating PnL from Open Positions
            double floating_pnl = AccountInfoDouble(ACCOUNT_PROFIT);

            // 3. Total Equity Change for the day
            double daily_total_pnl = realized_pnl + floating_pnl;

            // 4. Calculate % based on Balance at start of day (Balance - Realized PnL)
            // Note: This assumes no deposits/withdrawals today.
            // For perfect accuracy with deposits, you'd need to scan history for DEAL_TYPE_BALANCE.
            double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            double start_balance = current_balance - realized_pnl;

            if(start_balance > 0)
                  m_stats.daily_pnl_pct = (daily_total_pnl / start_balance) * 100.0;
            else
                  m_stats.daily_pnl_pct = 0.0;

            // Check if new day to reset flags (Optional, purely for logging)
            MqlDateTime dt_current, dt_last;
            TimeToStruct(TimeCurrent(), dt_current);
            TimeToStruct(m_stats.last_day_reset, dt_last);

            if(dt_current.day != dt_last.day)
            {
                  m_stats.trading_halted = false; // Reset halt on new day
                  m_stats.last_day_reset = TimeCurrent();
                  LogPrint("=== NEW DAY === Daily stats reset. Realized PnL: ", realized_pnl, " | Start Balance: ", start_balance);
            }
      }

      //+------------------------------------------------------------------+
      //| Check if can open new position                                   |
      //+------------------------------------------------------------------+
      bool CanOpenNewPosition()
      {
            UpdateDailyStats();

            // Check 1: Trading halted?
            if(m_stats.trading_halted)
            {
                  LogPrint("Trading is halted");
                  return false;
            }

            // Check 2: Daily loss limit
            if(m_stats.daily_pnl_pct <= -m_daily_loss_limit)
            {
                  LogPrint("Daily loss limit hit: ", FormatPercent(m_stats.daily_pnl_pct));
                  m_stats.trading_halted = true;
                  return false;
            }

            // Check 3: Max exposure
            if(m_stats.current_exposure >= m_max_total_exposure)
            {
                  LogPrint("Max exposure reached: ", m_stats.current_exposure, "%");
                  return false;
            }

            // Check 4: Max positions
            if(m_stats.positions_count >= m_max_positions)
            {
                  LogPrint("Max positions reached: ", m_stats.positions_count, " / ", m_max_positions);
                  return false;
            }

            return true;
      }

      //+------------------------------------------------------------------+
      //| Calculate lot size based on risk                                 |
      //+------------------------------------------------------------------+
      double CalculateLotSize(double risk_percent, double entry_price, double stop_loss)
      {
            // Get account info
            double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            double account_currency_rate = 1.0;

            // Calculate risk amount in account currency
            double risk_amount = account_balance * (risk_percent / 100.0);

            // Calculate stop distance in points
            double stop_distance = MathAbs(entry_price - stop_loss);
            if(stop_distance <= 0)
            {
                  LogPrint("ERROR: Invalid stop distance: ", stop_distance);
                  return 0;
            }

            // Get symbol info
            double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
            double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

            // Calculate point value
            double point_value = tick_value * (_Point / tick_size);

            // Calculate lot size
            double lots = risk_amount / (stop_distance / _Point * point_value);

            // Normalize lots
            lots = NormalizeLots(lots);

            // Validate minimum
            double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(lots < min_lot)
            {
                  LogPrint("Calculated lot size too small: ", lots, " (min: ", min_lot, ")");
                  return 0;
            }

            // SAFETY: Cap maximum lot size to prevent blow-up risk
            double max_lot = min_lot * m_max_lot_multiplier;
            if(lots > max_lot)
            {
                  LogPrint("WARNING: Lot size capped from ", lots, " to ", max_lot, " (", m_max_lot_multiplier, "x min lot)");
                  lots = max_lot;
            }

            // Check margin requirements
            if(!CheckMarginRequirements(lots, entry_price))
            {
                  LogPrint("Insufficient margin for lot size: ", lots);
                  return 0;
            }

            LogPrint("Position sizing: Risk $", DoubleToString(risk_amount, 2),
                  " (", DoubleToString(risk_percent, 2), "%) = ",
                  DoubleToString(lots, 2), " lots");

            return lots;
      }

      //+------------------------------------------------------------------+
      //| Compute risk percent for an open position                        |
      //+------------------------------------------------------------------+
      double ComputeRiskPercent(double lots, double entry_price, double stop_loss)
      {
            double stop_distance = MathAbs(entry_price - stop_loss);
            if (stop_distance <= 0 || lots <= 0)
                  return 0.0;

            double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double point_value = tick_value * (_Point / tick_size);

            double risk_amount = (stop_distance / _Point) * point_value * lots;
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            if (balance <= 0)
                  return 0.0;

            return (risk_amount / balance) * 100.0;
      }

      //+------------------------------------------------------------------+
      //| Adjust risk for consecutive losses                               |
      //+------------------------------------------------------------------+
      double AdjustRiskPercent(double base_risk)
      {
            // Return base risk if scaling is disabled
            if(!m_enable_loss_scaling)
                  return base_risk;

            // Reduce risk after consecutive losses (configurable)
            if(m_stats.consecutive_losses >= m_losses_level2)
            {
                  double scaled = base_risk * (m_risk_reduction_level2 / 100.0);
                  LogPrint("Risk scaled to ", m_risk_reduction_level2, "% (Level 2) after ", m_stats.consecutive_losses, " losses");
                  return scaled;
            }
            else if(m_stats.consecutive_losses >= m_losses_level1)
            {
                  double scaled = base_risk * (m_risk_reduction_level1 / 100.0);
                  LogPrint("Risk scaled to ", m_risk_reduction_level1, "% (Level 1) after ", m_stats.consecutive_losses, " losses");
                  return scaled;
            }

            return base_risk;
      }

      //+------------------------------------------------------------------+
      //| Check margin requirements                                         |
      //+------------------------------------------------------------------+
      bool CheckMarginRequirements(double lots, double price)
      {
            double margin_required;
            if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, price, margin_required))
            {
                  LogPrint("ERROR: Failed to calculate margin");
                  return false;
            }

            double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            double max_margin_allowed = free_margin * (m_max_margin_usage / 100.0);
            if(margin_required > max_margin_allowed)
            {
                  LogPrint("Insufficient margin: Required=", margin_required, " Max=", max_margin_allowed, " (", m_max_margin_usage, "% of ", free_margin, ")");
                  return false;
            }

            return true;
      }

      //+------------------------------------------------------------------+
      //| Update position tracking and calculate risk-based exposure      |
      //+------------------------------------------------------------------+
      void UpdatePositions()
      {
            // Reset stats
            double total_risk_exposure_pct = 0;

            // Iterate through the lightweight risk tracking array
            for(int i = 0; i < m_position_count; i++)
            {
                  // Sum the initial risk percentage of each open position
                  total_risk_exposure_pct += m_position_risks[i].initial_risk_pct;
            }

            // Update stats
            m_stats.current_exposure = total_risk_exposure_pct;
            m_stats.positions_count = m_position_count;
      }

      //+------------------------------------------------------------------+
      //| Record trade result                                               |
      //+------------------------------------------------------------------+
      void RecordTradeResult(double profit)
      {
            if(profit > 0)
            {
                  m_stats.consecutive_wins++;
                  m_stats.consecutive_losses = 0;
            }
            else if(profit < 0)
            {
                  m_stats.consecutive_losses++;
                  m_stats.consecutive_wins = 0;
            }
      }

      //+------------------------------------------------------------------+
      //| Adjust risk for consecutive losses (alias for compatibility)     |
      //+------------------------------------------------------------------+
      double AdjustRiskForStreak(double base_risk)
      {
            return AdjustRiskPercent(base_risk);
      }

      //+------------------------------------------------------------------+
      //| Add position to tracking (lightweight - only risk data)           |
      //| Full position state is managed by PositionCoordinator             |
      //+------------------------------------------------------------------+
      void AddPosition(SPosition &position)
      {
            // Add only risk-relevant data to lightweight array
            ArrayResize(m_position_risks, m_position_count + 1);
            m_position_risks[m_position_count].ticket = position.ticket;
            m_position_risks[m_position_count].initial_risk_pct = position.initial_risk_pct;
            m_position_count++;

            // Update aggregate stats
            UpdatePositions();
      }

      //+------------------------------------------------------------------+
      //| Remove position from tracking                                     |
      //+------------------------------------------------------------------+
      void RemovePosition(ulong ticket, bool is_winner)
      {
            double profit = 0;
            // Find the position in our lightweight risk array
            for (int i = 0; i < m_position_count; i++)
            {
                if (m_position_risks[i].ticket == ticket)
                {
                    // Position found, record result using history (position is likely already closed)
                    if (HistorySelectByPosition(ticket))
                    {
                        int deals = HistoryDealsTotal();
                        for (int d = 0; d < deals; d++)
                        {
                            ulong deal_ticket = HistoryDealGetTicket(d);
                            if (HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID) == (long)ticket)
                            {
                                profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                                profit += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
                                profit += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
                            }
                        }
                    }
                    else if (PositionSelectByTicket(ticket))
                    {
                        profit = PositionGetDouble(POSITION_PROFIT);
                    }
                    RecordTradeResult(profit);

                    // Remove from lightweight array
                    for (int j = i; j < m_position_count - 1; j++)
                    {
                        m_position_risks[j] = m_position_risks[j + 1];
                    }
                    m_position_count--;
                    ArrayResize(m_position_risks, m_position_count);
                    break; // Exit loop once found and removed
                }
            }

            // Update aggregate stats
            UpdatePositions();
      }

      //+------------------------------------------------------------------+
      //| Get daily P&L percentage                                          |
      //+------------------------------------------------------------------+
      double GetDailyPnL()
      {
            UpdateDailyStats();
            return m_stats.daily_pnl_pct;
      }

      //+------------------------------------------------------------------+
      //| Get current exposure percentage                                   |
      //+------------------------------------------------------------------+
      double GetCurrentExposure()
      {
            UpdatePositions();
            return m_stats.current_exposure;
      }

      //+------------------------------------------------------------------+
      //| Get consecutive losses count                                      |
      //+------------------------------------------------------------------+
      int GetConsecutiveLosses()
      {
            return m_stats.consecutive_losses;
      }

      //+------------------------------------------------------------------+
      //| Check if trading is halted                                        |
      //+------------------------------------------------------------------+
      bool IsTradingHalted()
      {
            UpdateDailyStats();
            return m_stats.trading_halted;
      }

      //+------------------------------------------------------------------+
      //| Get risk statistics                                               |
      //+------------------------------------------------------------------+
      SRiskStats GetStats() { return m_stats; }
};
