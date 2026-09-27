//+------------------------------------------------------------------+
//| PremiumGoldSafeEA.mq5                                           |
//| Controlled XAUUSD multi-entry EA - DEMO TESTING ONLY             |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES SignalTF = PERIOD_M5;
input int FastEMA = 20;
input int SlowEMA = 50;
input int RSIPeriod = 14;
input double BuyRSI = 55.0;
input double SellRSI = 45.0;

input double LotSize = 0.01;
input int MaxPositions = 4;
input int GridStepPoints = 500;
input int BasketTPPoints = 300;
input double MaxBasketLossPercent = 2.0;

input int MaxSpreadPoints = 80;
input double DailyLossLimitPercent = 3.0;
input int StartHour = 7;
input int EndHour = 20;
input bool AllowBuy = true;
input bool AllowSell = true;

input ulong MagicNumber = 26092701;
input string TradeComment = "PremiumGoldSafeEA";

int fastHandle, slowHandle, rsiHandle;
datetime lastBar = 0;
double dayStartEquity = 0.0;
int storedDay = -1;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   fastHandle = iMA(_Symbol, SignalTF, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, SignalTF, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, SignalTF, RSIPeriod, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDaily();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
   IndicatorRelease(rsiHandle);
}

void OnTick()
{
   ResetDaily();

   if(DailyLossExceeded() || BasketLossExceeded())
   {
      CloseAll();
      return;
   }

   ManageBasket();

   datetime t = iTime(_Symbol, SignalTF, 0);
   if(t == lastBar) return;
   lastBar = t;

   if(!TradingWindow() || !SpreadOK()) return;

   int count = CountPositions();
   if(count >= MaxPositions) return;

   if(count > 0)
   {
      TryGridAdd();
      return;
   }

   int signal = GetSignal();
   if(signal == 1 && AllowBuy) OpenBuy();
   if(signal == -1 && AllowSell) OpenSell();
}

int GetSignal()
{
   double fast[1], slow[1], rsi[1];
   if(CopyBuffer(fastHandle,0,1,1,fast) != 1) return 0;
   if(CopyBuffer(slowHandle,0,1,1,slow) != 1) return 0;
   if(CopyBuffer(rsiHandle,0,1,1,rsi) != 1) return 0;

   if(fast[0] > slow[0] && rsi[0] >= BuyRSI) return 1;
   if(fast[0] < slow[0] && rsi[0] <= SellRSI) return -1;
   return 0;
}

void OpenBuy()
{
   double v = NormalizeVolume(LotSize);
   if(v > 0 && !trade.Buy(v,_Symbol,0,0,0,TradeComment))
      Print("BUY failed: ",trade.ResultRetcodeDescription());
}

void OpenSell()
{
   double v = NormalizeVolume(LotSize);
   if(v > 0 && !trade.Sell(v,_Symbol,0,0,0,TradeComment))
      Print("SELL failed: ",trade.ResultRetcodeDescription());
}

void TryGridAdd()
{
   int d = BasketDirection();
   if(d == 0) return;

   double last = LatestEntryPrice(d);
   if(last <= 0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double p = d > 0 ? tick.bid : tick.ask;
   double distance = MathAbs(p-last)/_Point;

   if(d > 0 && p < last && distance >= GridStepPoints && AllowBuy) OpenBuy();
   if(d < 0 && p > last && distance >= GridStepPoints && AllowSell) OpenSell();
}

void ManageBasket()
{
   int d = BasketDirection();
   if(d == 0) return;

   double avg = AveragePrice(d);
   if(avg <= 0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double target = d > 0 ? avg + BasketTPPoints*_Point : avg - BasketTPPoints*_Point;

   if((d > 0 && tick.bid >= target) || (d < 0 && tick.ask <= target))
      CloseAll();
}

int CountPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      n++;
   }
   return n;
}

int BasketDirection()
{
   int b=0,s=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type==POSITION_TYPE_BUY) b++;
      if(type==POSITION_TYPE_SELL) s++;
   }
   if(b>0 && s==0) return 1;
   if(s>0 && b==0) return -1;
   return 0;
}

double LatestEntryPrice(int d)
{
   double price=0;
   datetime latest=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(d>0 && type!=POSITION_TYPE_BUY) continue;
      if(d<0 && type!=POSITION_TYPE_SELL) continue;

      datetime t=(datetime)PositionGetInteger(POSITION_TIME);
      if(t>=latest)
      {
         latest=t;
         price=PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   return price;
}

double AveragePrice(int d)
{
   double vol=0,val=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(d>0 && type!=POSITION_TYPE_BUY) continue;
      if(d<0 && type!=POSITION_TYPE_SELL) continue;

      double v=PositionGetDouble(POSITION_VOLUME);
      val += v*PositionGetDouble(POSITION_PRICE_OPEN);
      vol += v;
   }
   return vol>0 ? val/vol : 0;
}

double BasketProfit()
{
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      p += PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

bool BasketLossExceeded()
{
   if(dayStartEquity<=0) return false;
   return BasketProfit() <= -(dayStartEquity*MaxBasketLossPercent/100.0);
}

bool DailyLossExceeded()
{
   if(dayStartEquity<=0) return false;
   return AccountInfoDouble(ACCOUNT_EQUITY) <= dayStartEquity*(1.0-DailyLossLimitPercent/100.0);
}

void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      trade.PositionClose(ticket);
   }
}

bool SpreadOK()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   return ((tick.ask-tick.bid)/_Point <= MaxSpreadPoints);
}

bool TradingWindow()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);
   if(StartHour==EndHour) return true;
   if(StartHour<EndHour) return tm.hour>=StartHour && tm.hour<EndHour;
   return tm.hour>=StartHour || tm.hour<EndHour;
}

double NormalizeVolume(double requested)
{
   double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) return 0;

   double v=MathMax(minV,MathMin(maxV,requested));
   v=MathFloor(v/step)*step;
   return NormalizeDouble(v,2);
}

void ResetDaily()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);
   if(tm.day!=storedDay)
   {
      storedDay=tm.day;
      dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   }
}
//+------------------------------------------------------------------+