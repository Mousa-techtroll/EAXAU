//+------------------------------------------------------------------+
//| MarketFilters.mqh                                                |
//| Market Regime Filters to Prevent Losses in Unfavorable Conditions|
//| Implements Confidence Scoring and Regime Classification           |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

//+------------------------------------------------------------------+
//| Helper: Find Recent Swing Low                                    |
//+------------------------------------------------------------------+
double FindRecentSwingLow(int lookback)
{
    double low_array[];
    ArraySetAsSeries(low_array, true);

    int copied = CopyLow(_Symbol, PERIOD_H1, 0, lookback + 1, low_array);
    if (copied <= 0)
        return 0.0;

    double lowest = DBL_MAX;
    for (int i = 1; i <= lookback; i++)
    {
        if (i < ArraySize(low_array) && low_array[i] < lowest)
            lowest = low_array[i];
    }

    return lowest;
}

//+------------------------------------------------------------------+
//| Helper: Find Recent Swing High                                   |
//+------------------------------------------------------------------+
double FindRecentSwingHigh(int lookback)
{
    double high_array[];
    ArraySetAsSeries(high_array, true);

    int copied = CopyHigh(_Symbol, PERIOD_H1, 0, lookback + 1, high_array);
    if (copied <= 0)
        return 0.0;

    double highest = 0;
    for (int i = 1; i <= lookback; i++)
    {
        if (i < ArraySize(high_array) && high_array[i] > highest)
            highest = high_array[i];
    }

    return highest;
}

//+------------------------------------------------------------------+
//| FILTER 3: Improved Stop Loss Placement                           |
//| Widens SL in volatile conditions to avoid premature stop-outs    |
//+------------------------------------------------------------------+
double CalculateImprovedStopLoss(double entry_price, int direction, double min_sl_points, double base_multiplier = 3.0, double atr = 0.0)
{
    // PERFORMANCE FIX: Use passed ATR if provided, otherwise calculate inline
    if (atr == 0.0)
    {
        // Inline ATR calculation (avoid function call overhead)
        int atr_handle = iATR(_Symbol, PERIOD_H1, 14);
        if (atr_handle != INVALID_HANDLE)
        {
            double atr_buffer[];
            ArraySetAsSeries(atr_buffer, true);
            if (CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
            {
                atr = atr_buffer[0];
            }
            IndicatorRelease(atr_handle);
        }

        if (atr == 0.0)
        {
            LogPrint("Error getting ATR for improved SL - using fallback");
            atr = 20.0;  // Fallback value
        }
    }

    // v4.1: Use base_multiplier parameter (from InpDynamicSLMultiplier or InpATRMultiplierSL)
    // Then adjust based on volatility conditions
    double min_sl_multiplier = base_multiplier;  // Start with configured multiplier

    // Adaptive adjustments based on ATR
    if (atr > 30.0)
        min_sl_multiplier = base_multiplier * 1.15;  // +15% wider in high volatility
    else if (atr < 15.0)
        min_sl_multiplier = base_multiplier * 0.95;  // -5% tighter in low volatility (but still respects base)

    double min_sl_distance = atr * min_sl_multiplier;

    // Also check recent swing points
    double swing_distance = 0;
    if (direction > 0)  // Bullish
    {
        double swing_low = FindRecentSwingLow(20);  // 20 bars lookback
        swing_distance = MathAbs(entry_price - swing_low) + (atr * 0.5);  // Add buffer
    }
    else  // Bearish
    {
        double swing_high = FindRecentSwingHigh(20);
        swing_distance = MathAbs(swing_high - entry_price) + (atr * 0.5);
    }

    // Use wider of the two
    double final_sl_distance = MathMax(min_sl_distance, swing_distance);

    // Also respect configured limits
    final_sl_distance = MathMax(final_sl_distance, min_sl_points * _Point);

    double sl_price;
    if (direction > 0)
        sl_price = entry_price - final_sl_distance;
    else
        sl_price = entry_price + final_sl_distance;

    return sl_price;
}

//+------------------------------------------------------------------+
//| FILTER 4: Pattern Confidence Scoring                             |
//| PERFORMANCE FIX: Now accepts ATR/ADX as parameters                |
//| Only take high-confidence setups                                 |
//+------------------------------------------------------------------+
int CalculatePatternConfidence(string pattern, double entry_price, int ma_fast_period, int ma_slow_period,
                               double atr = 0.0, double adx = 0.0)
{
    int confidence = 0;

    // A pattern that has passed the initial detection gets a solid base score.
    // The confidence score is now primarily about the quality of the market environment.
    confidence += 30;

    // Check ADX strength (using passed value if available)
    if (adx > 0.0)
    {
        if (adx > 25 && adx < 40)
            confidence += 20;  // Good trend strength
        else if (adx >= 20 && adx <= 50)
            confidence += 10;  // Acceptable trend
    }

    // Check ATR (volatility in normal range) - using passed value if available
    if (atr > 0.0)
    {
        // Gold ATR in $ (not points)
        if (atr > 10.0 && atr < 30.0)
            confidence += 20;  // Normal volatility for 2024
        else if (atr >= 6.0 && atr <= 35.0)
            confidence += 10;  // Acceptable range
    }
    
    // Pattern-specific checks removed for simplification and to avoid contradiction with detection logic.
    // The fact a pattern was detected is the primary 'quality' check.

    return confidence;  // Returns 0-100
}

//+------------------------------------------------------------------+
//| FILTER 5: Market Regime Classifier (DEPRECATED)                  |
//| NOTE: This is dead code - regime classification is now handled   |
//| by RegimeClassifier.mqh using ENUM_REGIME_TYPE. These functions  |
//| are kept for reference but should be removed in future cleanup.  |
//+------------------------------------------------------------------+
enum MarketRegime  // DEPRECATED - use ENUM_REGIME_TYPE from Enums.mqh
{
    REGIME_TRENDING_BULLISH,
    REGIME_TRENDING_BEARISH,
    REGIME_CHOPPY_RANGING,
    REGIME_HIGH_VOLATILITY,
    REGIME_LOW_VOLATILITY
};

// DEPRECATED: Use RegimeClassifier.mqh instead
// Kept for backward compatibility - not actively used
MarketRegime ClassifyMarketRegime(double atr = 0.0, double adx = 0.0,
                                 double high_vol_atr = 40.0, double low_vol_atr = 10.0,
                                 double range_adx = 20.0, double di_plus = 0.0, double di_minus = 0.0)
{
    // If ADX or DI values not provided, calculate them (performance penalty)
    if (adx == 0.0 || (di_plus == 0.0 && di_minus == 0.0))
    {
        int adx_handle = iADX(_Symbol, PERIOD_H1, 14);
        double adx_buffer[], plus_di_buffer[], minus_di_buffer[];
        ArraySetAsSeries(adx_buffer, true);
        ArraySetAsSeries(plus_di_buffer, true);
        ArraySetAsSeries(minus_di_buffer, true);

        if (adx_handle != INVALID_HANDLE)
        {
            if (CopyBuffer(adx_handle, 0, 0, 1, adx_buffer) > 0 &&
                CopyBuffer(adx_handle, 1, 0, 1, plus_di_buffer) > 0 &&
                CopyBuffer(adx_handle, 2, 0, 1, minus_di_buffer) > 0)
            {
                if (adx == 0.0) adx = adx_buffer[0];
                if (di_plus == 0.0) di_plus = plus_di_buffer[0];
                if (di_minus == 0.0) di_minus = minus_di_buffer[0];
            }
            IndicatorRelease(adx_handle);
        }
    }

    // If ATR not provided, calculate it (performance penalty)
    if (atr == 0.0)
    {
        // Inline ATR calculation (avoid function call overhead)
        int atr_handle = iATR(_Symbol, PERIOD_H1, 14);
        if (atr_handle != INVALID_HANDLE)
        {
            double atr_buffer[];
            ArraySetAsSeries(atr_buffer, true);
            if (CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
            {
                atr = atr_buffer[0];
            }
            IndicatorRelease(atr_handle);
        }
    }

    if (atr == 0.0)
        atr = 20.0;  // Fallback to assume normal volatility

    // Use configurable thresholds (not hardcoded)
    if (atr > high_vol_atr)
        return REGIME_HIGH_VOLATILITY;

    if (atr < low_vol_atr)
        return REGIME_LOW_VOLATILITY;

    // Choppy/ranging regime (low ADX)
    if (adx < range_adx)
        return REGIME_CHOPPY_RANGING;

    // Trending regimes (ADX above range threshold)
    if (adx >= range_adx)
    {
        // Check DI direction to determine trend direction
        if (di_plus > di_minus + 3.0)
            return REGIME_TRENDING_BULLISH;
        else if (di_minus > di_plus + 3.0)
            return REGIME_TRENDING_BEARISH;
        else
            return REGIME_CHOPPY_RANGING;  // Unclear trend (DI values too close)
    }

    return REGIME_CHOPPY_RANGING;  // Default fallback
}

// DEPRECATED: Use SignalValidator validation logic instead
// Kept for backward compatibility - not actively used
bool IsRegimeFavorable(MarketRegime regime, int trade_direction)
{
    // Block trading in choppy/ranging markets
    if (regime == REGIME_CHOPPY_RANGING)
    {
        LogPrint("Market regime: CHOPPY/RANGING - skipping trade");
        return false;
    }

    // Block trading in extreme volatility
    if (regime == REGIME_HIGH_VOLATILITY)
    {
        LogPrint("Market regime: HIGH VOLATILITY - skipping trade");
        return false;
    }

    // Check alignment with trend
    if (trade_direction > 0 && regime == REGIME_TRENDING_BEARISH)
    {
        LogPrint("Market regime: BEARISH TREND - skipping bullish trade");
        return false;
    }

    if (trade_direction < 0 && regime == REGIME_TRENDING_BULLISH)
    {
        LogPrint("Market regime: BULLISH TREND - skipping bearish trade");
        return false;
    }

    return true;  // Regime is favorable
}
