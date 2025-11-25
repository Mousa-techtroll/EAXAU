//+------------------------------------------------------------------+
//| MomentumFilter.mqh                                                |
//| Multi-Timeframe Momentum Confirmation Filter                      |
//+------------------------------------------------------------------+
#property copyright "Stack1.7"
#property strict

#include "../Common/Enums.mqh"
#include "../Common/Utils.mqh"

//+------------------------------------------------------------------+
//| Momentum Analysis Structure                                       |
//+------------------------------------------------------------------+
struct SMomentumAnalysis
{
   double            rsi_h1;           // H1 RSI value
   double            rsi_h4;           // H4 RSI value
   double            macd_main;        // MACD main line
   double            macd_signal;      // MACD signal line
   double            macd_histogram;   // MACD histogram
   double            stoch_main;       // Stochastic main
   double            stoch_signal;     // Stochastic signal
   double            cci_value;        // CCI value
   double            mfi_value;        // Money Flow Index
   int               momentum_score;   // Overall score (-100 to +100)
   bool              bullish_momentum; // True if momentum favors longs
   bool              bearish_momentum; // True if momentum favors shorts
   bool              momentum_divergence; // RSI/Price divergence detected
};

//+------------------------------------------------------------------+
//| CMomentumFilter - Multi-indicator momentum confirmation          |
//+------------------------------------------------------------------+
class CMomentumFilter
{
private:
   // Indicator handles
   int               m_handle_rsi_h1;
   int               m_handle_rsi_h4;
   int               m_handle_macd;
   int               m_handle_stoch;
   int               m_handle_cci;
   int               m_handle_mfi;

   // Configuration
   int               m_rsi_period;
   int               m_macd_fast;
   int               m_macd_slow;
   int               m_macd_signal;
   int               m_stoch_k;
   int               m_stoch_d;
   int               m_stoch_slowing;
   int               m_cci_period;
   int               m_mfi_period;

   // Thresholds
   double            m_rsi_overbought;
   double            m_rsi_oversold;
   double            m_stoch_overbought;
   double            m_stoch_oversold;
   double            m_cci_overbought;
   double            m_cci_oversold;
   int               m_min_momentum_score;

   // State
   SMomentumAnalysis m_analysis;
   bool              m_initialized;

   // Divergence detection
   double            m_price_highs[];
   double            m_price_lows[];
   double            m_rsi_highs[];
   double            m_rsi_lows[];
   int               m_divergence_lookback;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CMomentumFilter()
   {
      m_handle_rsi_h1 = INVALID_HANDLE;
      m_handle_rsi_h4 = INVALID_HANDLE;
      m_handle_macd = INVALID_HANDLE;
      m_handle_stoch = INVALID_HANDLE;
      m_handle_cci = INVALID_HANDLE;
      m_handle_mfi = INVALID_HANDLE;

      // Default parameters
      m_rsi_period = 14;
      m_macd_fast = 12;
      m_macd_slow = 26;
      m_macd_signal = 9;
      m_stoch_k = 14;
      m_stoch_d = 3;
      m_stoch_slowing = 3;
      m_cci_period = 20;
      m_mfi_period = 14;

      // Default thresholds
      m_rsi_overbought = 70.0;
      m_rsi_oversold = 30.0;
      m_stoch_overbought = 80.0;
      m_stoch_oversold = 20.0;
      m_cci_overbought = 100.0;
      m_cci_oversold = -100.0;
      m_min_momentum_score = 20;
      m_divergence_lookback = 20;

      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CMomentumFilter()
   {
      if(m_handle_rsi_h1 != INVALID_HANDLE) IndicatorRelease(m_handle_rsi_h1);
      if(m_handle_rsi_h4 != INVALID_HANDLE) IndicatorRelease(m_handle_rsi_h4);
      if(m_handle_macd != INVALID_HANDLE) IndicatorRelease(m_handle_macd);
      if(m_handle_stoch != INVALID_HANDLE) IndicatorRelease(m_handle_stoch);
      if(m_handle_cci != INVALID_HANDLE) IndicatorRelease(m_handle_cci);
      if(m_handle_mfi != INVALID_HANDLE) IndicatorRelease(m_handle_mfi);
   }

   //+------------------------------------------------------------------+
   //| Configure parameters                                              |
   //+------------------------------------------------------------------+
   void Configure(int rsi_period, double rsi_ob, double rsi_os,
                  int macd_fast, int macd_slow, int macd_sig,
                  int stoch_k, int stoch_d, double stoch_ob, double stoch_os,
                  int cci_period, double cci_ob, double cci_os,
                  int mfi_period, int min_score, int div_lookback)
   {
      m_rsi_period = rsi_period;
      m_rsi_overbought = rsi_ob;
      m_rsi_oversold = rsi_os;
      m_macd_fast = macd_fast;
      m_macd_slow = macd_slow;
      m_macd_signal = macd_sig;
      m_stoch_k = stoch_k;
      m_stoch_d = stoch_d;
      m_stoch_overbought = stoch_ob;
      m_stoch_oversold = stoch_os;
      m_cci_period = cci_period;
      m_cci_overbought = cci_ob;
      m_cci_oversold = cci_os;
      m_mfi_period = mfi_period;
      m_min_momentum_score = min_score;
      m_divergence_lookback = div_lookback;
   }

   //+------------------------------------------------------------------+
   //| Initialize indicators                                             |
   //+------------------------------------------------------------------+
   bool Init()
   {
      // RSI on H1 and H4
      m_handle_rsi_h1 = iRSI(_Symbol, PERIOD_H1, m_rsi_period, PRICE_CLOSE);
      m_handle_rsi_h4 = iRSI(_Symbol, PERIOD_H4, m_rsi_period, PRICE_CLOSE);

      // MACD on H1
      m_handle_macd = iMACD(_Symbol, PERIOD_H1, m_macd_fast, m_macd_slow, m_macd_signal, PRICE_CLOSE);

      // Stochastic on H1
      m_handle_stoch = iStochastic(_Symbol, PERIOD_H1, m_stoch_k, m_stoch_d, m_stoch_slowing, MODE_SMA, STO_LOWHIGH);

      // CCI on H1
      m_handle_cci = iCCI(_Symbol, PERIOD_H1, m_cci_period, PRICE_TYPICAL);

      // MFI on H1
      m_handle_mfi = iMFI(_Symbol, PERIOD_H1, m_mfi_period, VOLUME_TICK);

      if(m_handle_rsi_h1 == INVALID_HANDLE || m_handle_rsi_h4 == INVALID_HANDLE ||
         m_handle_macd == INVALID_HANDLE || m_handle_stoch == INVALID_HANDLE ||
         m_handle_cci == INVALID_HANDLE || m_handle_mfi == INVALID_HANDLE)
      {
         LogPrint("ERROR: MomentumFilter - Failed to create indicator handles");
         return false;
      }

      // Initialize divergence arrays
      ArrayResize(m_price_highs, m_divergence_lookback);
      ArrayResize(m_price_lows, m_divergence_lookback);
      ArrayResize(m_rsi_highs, m_divergence_lookback);
      ArrayResize(m_rsi_lows, m_divergence_lookback);

      m_initialized = true;
      LogPrint("MomentumFilter initialized: RSI(", m_rsi_period, ") MACD(", m_macd_fast, ",", m_macd_slow, ",", m_macd_signal, ")");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update momentum analysis                                          |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(!m_initialized) return;

      // Get RSI values
      double rsi_h1[], rsi_h4[];
      ArraySetAsSeries(rsi_h1, true);
      ArraySetAsSeries(rsi_h4, true);

      if(CopyBuffer(m_handle_rsi_h1, 0, 0, 3, rsi_h1) > 0)
         m_analysis.rsi_h1 = rsi_h1[0];

      if(CopyBuffer(m_handle_rsi_h4, 0, 0, 3, rsi_h4) > 0)
         m_analysis.rsi_h4 = rsi_h4[0];

      // Get MACD values
      double macd_main[], macd_signal[];
      ArraySetAsSeries(macd_main, true);
      ArraySetAsSeries(macd_signal, true);

      if(CopyBuffer(m_handle_macd, 0, 0, 3, macd_main) > 0)
         m_analysis.macd_main = macd_main[0];

      if(CopyBuffer(m_handle_macd, 1, 0, 3, macd_signal) > 0)
         m_analysis.macd_signal = macd_signal[0];

      m_analysis.macd_histogram = m_analysis.macd_main - m_analysis.macd_signal;

      // Get Stochastic values
      double stoch_main[], stoch_signal[];
      ArraySetAsSeries(stoch_main, true);
      ArraySetAsSeries(stoch_signal, true);

      if(CopyBuffer(m_handle_stoch, 0, 0, 3, stoch_main) > 0)
         m_analysis.stoch_main = stoch_main[0];

      if(CopyBuffer(m_handle_stoch, 1, 0, 3, stoch_signal) > 0)
         m_analysis.stoch_signal = stoch_signal[0];

      // Get CCI value
      double cci[];
      ArraySetAsSeries(cci, true);

      if(CopyBuffer(m_handle_cci, 0, 0, 3, cci) > 0)
         m_analysis.cci_value = cci[0];

      // Get MFI value
      double mfi[];
      ArraySetAsSeries(mfi, true);

      if(CopyBuffer(m_handle_mfi, 0, 0, 3, mfi) > 0)
         m_analysis.mfi_value = mfi[0];

      // Calculate momentum score
      CalculateMomentumScore();

      // Check for divergence
      CheckDivergence();
   }

   //+------------------------------------------------------------------+
   //| Calculate overall momentum score (-100 to +100)                   |
   //+------------------------------------------------------------------+
   void CalculateMomentumScore()
   {
      int score = 0;
      int factors = 0;

      // RSI H1 contribution (-25 to +25)
      if(m_analysis.rsi_h1 > 0)
      {
         if(m_analysis.rsi_h1 > 50)
            score += (int)((m_analysis.rsi_h1 - 50) / 2);  // Max +25
         else
            score -= (int)((50 - m_analysis.rsi_h1) / 2);  // Max -25
         factors++;
      }

      // RSI H4 contribution (-25 to +25)
      if(m_analysis.rsi_h4 > 0)
      {
         if(m_analysis.rsi_h4 > 50)
            score += (int)((m_analysis.rsi_h4 - 50) / 2);
         else
            score -= (int)((50 - m_analysis.rsi_h4) / 2);
         factors++;
      }

      // MACD contribution (-20 to +20)
      if(m_analysis.macd_histogram > 0)
         score += MathMin(20, (int)(m_analysis.macd_histogram * 1000));
      else
         score += MathMax(-20, (int)(m_analysis.macd_histogram * 1000));
      factors++;

      // Stochastic contribution (-15 to +15)
      if(m_analysis.stoch_main > 50)
         score += (int)((m_analysis.stoch_main - 50) * 0.3);
      else
         score -= (int)((50 - m_analysis.stoch_main) * 0.3);
      factors++;

      // CCI contribution (-15 to +15)
      if(m_analysis.cci_value > 0)
         score += MathMin(15, (int)(m_analysis.cci_value / 10));
      else
         score += MathMax(-15, (int)(m_analysis.cci_value / 10));
      factors++;

      // MFI contribution (volume-weighted momentum)
      if(m_analysis.mfi_value > 50)
         score += (int)((m_analysis.mfi_value - 50) * 0.2);
      else
         score -= (int)((50 - m_analysis.mfi_value) * 0.2);

      // Normalize score to -100 to +100
      m_analysis.momentum_score = MathMax(-100, MathMin(100, score));

      // Determine momentum direction
      m_analysis.bullish_momentum = (m_analysis.momentum_score >= m_min_momentum_score);
      m_analysis.bearish_momentum = (m_analysis.momentum_score <= -m_min_momentum_score);
   }

   //+------------------------------------------------------------------+
   //| Check for RSI divergence                                          |
   //+------------------------------------------------------------------+
   void CheckDivergence()
   {
      m_analysis.momentum_divergence = false;

      // Get price and RSI data for divergence check
      double close[], rsi[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(rsi, true);

      if(CopyClose(_Symbol, PERIOD_H1, 0, m_divergence_lookback, close) < m_divergence_lookback)
         return;

      if(CopyBuffer(m_handle_rsi_h1, 0, 0, m_divergence_lookback, rsi) < m_divergence_lookback)
         return;

      // Find recent swing highs/lows in price and RSI
      int price_high1 = -1, price_high2 = -1;
      int price_low1 = -1, price_low2 = -1;

      // Simple swing detection
      for(int i = 2; i < m_divergence_lookback - 2; i++)
      {
         // Swing high
         if(close[i] > close[i-1] && close[i] > close[i-2] &&
            close[i] > close[i+1] && close[i] > close[i+2])
         {
            if(price_high1 < 0) price_high1 = i;
            else if(price_high2 < 0) price_high2 = i;
         }

         // Swing low
         if(close[i] < close[i-1] && close[i] < close[i-2] &&
            close[i] < close[i+1] && close[i] < close[i+2])
         {
            if(price_low1 < 0) price_low1 = i;
            else if(price_low2 < 0) price_low2 = i;
         }
      }

      // Check for bearish divergence (higher price high, lower RSI high)
      if(price_high1 > 0 && price_high2 > 0)
      {
         if(close[price_high1] > close[price_high2] && rsi[price_high1] < rsi[price_high2])
         {
            m_analysis.momentum_divergence = true;
            LogPrint(">>> MOMENTUM: Bearish divergence detected");
         }
      }

      // Check for bullish divergence (lower price low, higher RSI low)
      if(price_low1 > 0 && price_low2 > 0)
      {
         if(close[price_low1] < close[price_low2] && rsi[price_low1] > rsi[price_low2])
         {
            m_analysis.momentum_divergence = true;
            LogPrint(">>> MOMENTUM: Bullish divergence detected");
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Validate momentum for long entry                                  |
   //+------------------------------------------------------------------+
   bool ValidateLongMomentum()
   {
      if(!m_initialized) return true;

      Update();

      LogPrint(">>> Momentum Check LONG: Score=", m_analysis.momentum_score,
               " | RSI H1=", DoubleToString(m_analysis.rsi_h1, 1),
               " | RSI H4=", DoubleToString(m_analysis.rsi_h4, 1),
               " | MACD=", DoubleToString(m_analysis.macd_histogram, 5));

      // Block longs if strong bearish momentum
      if(m_analysis.momentum_score <= -40)
      {
         LogPrint(">>> MOMENTUM REJECT: Long blocked - strong bearish momentum (", m_analysis.momentum_score, ")");
         return false;
      }

      // Block longs if both RSI timeframes are overbought
      if(m_analysis.rsi_h1 > m_rsi_overbought && m_analysis.rsi_h4 > m_rsi_overbought)
      {
         LogPrint(">>> MOMENTUM REJECT: Long blocked - RSI overbought on H1 & H4");
         return false;
      }

      // Block longs if MACD strongly bearish and stochastic overbought
      if(m_analysis.macd_histogram < -0.001 && m_analysis.stoch_main > m_stoch_overbought)
      {
         LogPrint(">>> MOMENTUM REJECT: Long blocked - MACD bearish + Stoch overbought");
         return false;
      }

      LogPrint(">>> MOMENTUM PASSED: Long momentum OK");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Validate momentum for short entry                                 |
   //+------------------------------------------------------------------+
   bool ValidateShortMomentum()
   {
      if(!m_initialized) return true;

      Update();

      LogPrint(">>> Momentum Check SHORT: Score=", m_analysis.momentum_score,
               " | RSI H1=", DoubleToString(m_analysis.rsi_h1, 1),
               " | RSI H4=", DoubleToString(m_analysis.rsi_h4, 1),
               " | MACD=", DoubleToString(m_analysis.macd_histogram, 5));

      // Block shorts if strong bullish momentum
      if(m_analysis.momentum_score >= 40)
      {
         LogPrint(">>> MOMENTUM REJECT: Short blocked - strong bullish momentum (", m_analysis.momentum_score, ")");
         return false;
      }

      // Block shorts if both RSI timeframes are oversold
      if(m_analysis.rsi_h1 < m_rsi_oversold && m_analysis.rsi_h4 < m_rsi_oversold)
      {
         LogPrint(">>> MOMENTUM REJECT: Short blocked - RSI oversold on H1 & H4");
         return false;
      }

      // Block shorts if MACD strongly bullish and stochastic oversold
      if(m_analysis.macd_histogram > 0.001 && m_analysis.stoch_main < m_stoch_oversold)
      {
         LogPrint(">>> MOMENTUM REJECT: Short blocked - MACD bullish + Stoch oversold");
         return false;
      }

      LogPrint(">>> MOMENTUM PASSED: Short momentum OK");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get momentum analysis                                             |
   //+------------------------------------------------------------------+
   SMomentumAnalysis GetAnalysis() { return m_analysis; }

   //+------------------------------------------------------------------+
   //| Get momentum score                                                |
   //+------------------------------------------------------------------+
   int GetMomentumScore() { return m_analysis.momentum_score; }

   //+------------------------------------------------------------------+
   //| Check if divergence detected                                      |
   //+------------------------------------------------------------------+
   bool HasDivergence() { return m_analysis.momentum_divergence; }

   //+------------------------------------------------------------------+
   //| Check if momentum supports direction                              |
   //+------------------------------------------------------------------+
   bool SupportsBullish() { return m_analysis.bullish_momentum; }
   bool SupportsBearish() { return m_analysis.bearish_momentum; }
};
