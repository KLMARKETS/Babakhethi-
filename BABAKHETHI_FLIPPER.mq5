//+------------------------------------------------------------------+
//|                                      BABAKHETHI FLIPPER.mq5      |
//| Previous-candle breakout Expert Advisor for MetaTrader 5        |
//+------------------------------------------------------------------+
#property copyright "BABAKHETHI FLIPPER"
#property version   "2.00"
#property strict
#property description "M1 previous-candle breakout EA. One position at a time."
#property description "SL is placed at the previous candle extreme. Exit on first profitable candle close."

#include <Trade/Trade.mqh>

CTrade trade;

input string InpUserName        = "Babakhethi 23";
input ulong  InpMagicNumber     = 24112026;
input double InpLots            = 0.01;
input bool   InpEnableBuys      = true;
input bool   InpEnableSells     = true;
input int    InpMaxSpreadPoints = 0;       // 0 = disabled
input int    InpDeviationPoints = 20;
input bool   InpOnlyOnM1        = true;
input bool   InpShowChartStatus = true;

// One attempt per M1 candle prevents duplicate entries from the same breakout.
datetime g_last_signal_bar = 0;
datetime g_current_bar_time = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpLots <= 0.0)
   {
      Print("BABAKHETHI FLIPPER: Lot size must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpOnlyOnM1 && _Period != PERIOD_M1)
   {
      Print("BABAKHETHI FLIPPER: Attach this EA to an M1 chart.");
      return INIT_FAILED;
   }

   g_current_bar_time = iTime(_Symbol, PERIOD_M1, 0);
   Print("BABAKHETHI FLIPPER v2.00 initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(InpOnlyOnM1 && _Period != PERIOD_M1)
      return;

   // Exit only after a completed candle has closed in profit.
   if(CheckProfitClose())
   {
      UpdateStatus("Closed: profitable candle");
      return;
   }

   // Never hold more than one BABAKHETHI FLIPPER position on this symbol.
   if(CountOurPositions() > 0)
   {
      UpdateStatus("Holding trade; waiting for profitable candle close or SL");
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   if(InpMaxSpreadPoints > 0)
   {
      double spread_points = (tick.ask - tick.bid) / _Point;
      if(spread_points > InpMaxSpreadPoints)
      {
         UpdateStatus("Waiting: spread too high");
         return;
      }
   }

   datetime this_bar = iTime(_Symbol, PERIOD_M1, 0);
   if(this_bar <= 0 || this_bar == g_last_signal_bar)
   {
      UpdateStatus("Running; waiting for breakout");
      return;
   }

   double previous_high = iHigh(_Symbol, PERIOD_M1, 1);
   double previous_low  = iLow(_Symbol, PERIOD_M1, 1);
   if(previous_high <= 0.0 || previous_low <= 0.0 || previous_high <= previous_low)
      return;

   double volume = NormalizeVolume(InpLots);
   if(volume <= 0.0)
   {
      UpdateStatus("Error: invalid lot size for this symbol");
      return;
   }

   // SELL: current price breaks below the previous candle's low.
   if(InpEnableSells && tick.bid < previous_low)
   {
      g_last_signal_bar = this_bar;
      double sl = NormalizePriceUp(previous_high);
      if(!IsStopLossValid(ORDER_TYPE_SELL, tick, sl))
      {
         Print("BABAKHETHI FLIPPER: SELL skipped. Previous candle high is too close for a valid stop loss.");
         UpdateStatus("SELL skipped: stop loss too close");
         return;
      }

      if(trade.Sell(volume, _Symbol, 0.0, sl, 0.0, "BABAKHETHI FLIPPER SELL"))
         Print("BABAKHETHI FLIPPER: SELL opened. SL=", DoubleToString(sl, _Digits));
      else
         Print("BABAKHETHI FLIPPER: SELL failed. ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());

      UpdateStatus("SELL breakout processed");
      return;
   }

   // BUY: current price breaks above the previous candle's high.
   if(InpEnableBuys && tick.bid > previous_high)
   {
      g_last_signal_bar = this_bar;
      double sl = NormalizePriceDown(previous_low);
      if(!IsStopLossValid(ORDER_TYPE_BUY, tick, sl))
      {
         Print("BABAKHETHI FLIPPER: BUY skipped. Previous candle low is too close for a valid stop loss.");
         UpdateStatus("BUY skipped: stop loss too close");
         return;
      }

      if(trade.Buy(volume, _Symbol, 0.0, sl, 0.0, "BABAKHETHI FLIPPER BUY"))
         Print("BABAKHETHI FLIPPER: BUY opened. SL=", DoubleToString(sl, _Digits));
      else
         Print("BABAKHETHI FLIPPER: BUY failed. ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());

      UpdateStatus("BUY breakout processed");
      return;
   }

   UpdateStatus("Running; waiting for breakout");
}

//+------------------------------------------------------------------+
// Returns true when a profitable candle-close exit was successfully sent.
bool CheckProfitClose()
{
   ulong ticket = 0;
   ENUM_POSITION_TYPE position_type = POSITION_TYPE_BUY;
   double entry_price = 0.0;

   if(!GetOurPosition(ticket, position_type, entry_price))
      return false;

   // Shift 1 is the most recently completed candle; shift 0 is still forming.
   double completed_close = iClose(_Symbol, PERIOD_M1, 1);
   if(completed_close <= 0.0)
      return false;

   bool is_profitable_close = false;
   if(position_type == POSITION_TYPE_BUY && completed_close > entry_price)
      is_profitable_close = true;
   else if(position_type == POSITION_TYPE_SELL && completed_close < entry_price)
      is_profitable_close = true;

   if(!is_profitable_close)
      return false;

   if(trade.PositionClose(ticket))
   {
      Print("BABAKHETHI FLIPPER: Position #", ticket,
            " closed after candle close in profit. Candle close=",
            DoubleToString(completed_close, _Digits),
            " Entry=", DoubleToString(entry_price, _Digits));
      return true;
   }

   Print("BABAKHETHI FLIPPER: Profit exit failed for #", ticket,
         ". ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
bool GetOurPosition(ulong &ticket, ENUM_POSITION_TYPE &position_type, double &entry_price)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong candidate = PositionGetTicket(i);
      if(candidate == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ticket = candidate;
      position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
bool IsStopLossValid(const ENUM_ORDER_TYPE order_type, const MqlTick &tick, const double sl)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;

   double min_distance = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   if(order_type == ORDER_TYPE_BUY)
      return (sl < tick.bid && (tick.bid - sl) + 1e-10 >= min_distance);

   if(order_type == ORDER_TYPE_SELL)
      return (sl > tick.ask && (sl - tick.ask) + 1e-10 >= min_distance);

   return false;
}

//+------------------------------------------------------------------+
double NormalizePriceUp(const double price)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;
   double rounded = MathCeil(price / tick_size - 1e-10) * tick_size;
   return NormalizeDouble(rounded, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double NormalizePriceDown(const double price)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;
   double rounded = MathFloor(price / tick_size + 1e-10) * tick_size;
   return NormalizeDouble(rounded, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
double NormalizeVolume(const double requested)
{
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0 || max_volume <= 0.0)
      return 0.0;

   double volume = MathMax(min_volume, MathMin(max_volume, requested));
   volume = MathFloor(volume / step + 1e-9) * step;

   int digits = 2;
   if(step < 0.01) digits = 3;
   if(step < 0.001) digits = 4;
   if(step < 0.0001) digits = 5;

   return NormalizeDouble(volume, digits);
}

//+------------------------------------------------------------------+
void UpdateStatus(const string state)
{
   if(!InpShowChartStatus)
      return;

   string account_mode = "Unknown";
   ENUM_ACCOUNT_TRADE_MODE mode =
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);

   if(mode == ACCOUNT_TRADE_MODE_DEMO) account_mode = "DEMO";
   else if(mode == ACCOUNT_TRADE_MODE_REAL) account_mode = "LIVE";
   else if(mode == ACCOUNT_TRADE_MODE_CONTEST) account_mode = "CONTEST";

   ulong ticket = 0;
   ENUM_POSITION_TYPE ptype = POSITION_TYPE_BUY;
   double entry = 0.0;
   string position_text = "None";
   if(GetOurPosition(ticket, ptype, entry))
   {
      position_text = (ptype == POSITION_TYPE_BUY ? "BUY" : "SELL") +
                      " #" + (string)ticket + " @ " + DoubleToString(entry, _Digits);
   }

   Comment("BABAKHETHI FLIPPER v2.00\n",
           "User: ", InpUserName, "\n",
           "Account: ", account_mode, "\n",
           "Symbol: ", _Symbol, " | M1\n",
           "Status: ", state, "\n",
           "Position: ", position_text, "\n",
           "Lot size: ", DoubleToString(NormalizeVolume(InpLots), 2), "\n",
           "Entry: previous candle high/low breakout\n",
           "SL: previous candle opposite extreme\n",
           "Exit: first completed candle close in profit");
}
//+------------------------------------------------------------------+
