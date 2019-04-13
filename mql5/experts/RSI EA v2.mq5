//+------------------------------------------------------------------+
//|                                                    RSI EA v2.mq5 |
//|                              Copyright © 2018, Vladimir Karputov |
//|                                           http://wmua.ru/slesar/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2018, Vladimir Karputov"
#property link      "http://wmua.ru/slesar/"
#property version   "2.000"
//---
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>  
#include <Trade\AccountInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Expert\Money\MoneyFixedMargin.mqh>
CPositionInfo  m_position;                   // trade position object
CTrade         m_trade;                      // trading object
CSymbolInfo    m_symbol;                     // symbol info object
CAccountInfo   m_account;                    // account info wrapper
CDealInfo      m_deal;                       // deals object
COrderInfo     m_order;                      // pending orders object
CMoneyFixedMargin *m_money;
//+------------------------------------------------------------------+
//| Enum Lor or Risk                                                 |
//+------------------------------------------------------------------+
enum ENUM_LOT_OR_RISK
  {
   lot=0,   // Constant lot
   risk=1,  // Risk in percent for a deal
  };
input bool     OpenBUY           = true;     // Buy positions
input bool     OpenSELL          = true;     // Sell positions
input bool     CloseBySignal     = true;     // CloseBySignal
input ushort   InpStopLoss       = 50;       // Stop Loss, in pips (1.00045-1.00055=1 pips)
input ushort   InpTakeProfit     = 50;       // Take Profit, in pips (1.00045-1.00055=1 pips)
input ushort   InpTrailingStop   = 5;        // Trailing Stop (min distance from price to Stop Loss, in pips
input ushort   InpTrailingStep   = 5;        // Trailing Step, in pips (1.00045-1.00055=1 pips)
input int      RSIperiod         = 14;       // RSIperiod
input double   RsiBuyLevel       = 30.0;     // RsiBuyLevel
input double   RsiSellLevel      = 70.0;     // RsiSellLevel
input ENUM_LOT_OR_RISK IntLotOrRisk=lot;     // Money management: Lot OR Risk
input double   InpVolumeLorOrRisk= 1.0;      // The value for "Money management"
input ulong    m_magic           = 79506350; // Magic number
input bool     InpTimeControl    = true;     // Use time control
input uchar    InpStartHour      = 10;       // Start hour
input uchar    InpEndHour        = 5;        // End hour
input string   InpTradeComment="RSI EA v2";  // InpTradeComment
//---
ulong  m_slippage=10;                // slippage
double ExtStopLoss      = 0.0;
double ExtTakeProfit    = 0.0;
double ExtTrailingStop  = 0.0;
double ExtTrailingStep  = 0.0;
int    handle_iRSI;                          // variable for storing the handle of the iRSI indicator
double m_adjusted_point;                     // point value adjusted for 3 or 5 points
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpTrailingStop!=0 && InpTrailingStep==0)
     {
      string err_text=(TerminalInfoString(TERMINAL_LANGUAGE)=="Russian")?
                      "Трейлинг невозможен: параметр \"Trailing Step\" равен нулю!":
                      "Trailing is not possible: parameter \"Trailing Step\" is zero!";
      //--- when testing, we will only output to the log about incorrect input parameters
      if(MQLInfoInteger(MQL_TESTER))
        {
         Print(__FUNCTION__,", ERROR: ",err_text);
         return(INIT_FAILED);
        }
      else // if the Expert Advisor is run on the chart, tell the user about the error
        {
         Alert(__FUNCTION__,", ERROR: ",err_text);
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
//---
   if(!m_symbol.Name(Symbol())) // sets symbol 
      return(INIT_FAILED);
   RefreshRates();
//---
   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(m_symbol.Name());
//---
   m_trade.SetDeviationInPoints(m_slippage);
//--- tuning for 3 or 5 digits
   int digits_adjust=1;
   if(m_symbol.Digits()==3 || m_symbol.Digits()==5)
      digits_adjust=10;
   m_adjusted_point=m_symbol.Point()*digits_adjust;

   ExtStopLoss       = InpStopLoss        * m_adjusted_point;
   ExtTakeProfit     = InpTakeProfit      * m_adjusted_point;
   ExtTrailingStop   = InpTrailingStop    * m_adjusted_point;
   ExtTrailingStep   = InpTrailingStep    * m_adjusted_point;
//--- check the input parameter "Lots"
   string err_text="";
   if(IntLotOrRisk==lot)
     {
      if(!CheckVolumeValue(InpVolumeLorOrRisk,err_text))
        {
         //--- when testing, we will only output to the log about incorrect input parameters
         if(MQLInfoInteger(MQL_TESTER))
           {
            Print(__FUNCTION__,", ERROR: ",err_text);
            return(INIT_FAILED);
           }
         else // if the Expert Advisor is run on the chart, tell the user about the error
           {
            Alert(__FUNCTION__,", ERROR: ",err_text);
            return(INIT_PARAMETERS_INCORRECT);
           }
        }
     }
   else
     {
      if(m_money!=NULL)
         delete m_money;
      m_money=new CMoneyFixedMargin;
      if(m_money!=NULL)
        {
         if(!m_money.Init(GetPointer(m_symbol),Period(),m_symbol.Point()*digits_adjust))
            return(INIT_FAILED);
         m_money.Percent(InpVolumeLorOrRisk);
        }
      else
        {
         Print(__FUNCTION__,", ERROR: Object CMoneyFixedMargin is NULL");
         return(INIT_FAILED);
        }
     }
//--- create handle of the indicator iRSI
   handle_iRSI=iRSI(m_symbol.Name(),Period(),RSIperiod,PRICE_CLOSE);
//--- if the handle is not created 
   if(handle_iRSI==INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code 
      PrintFormat("Failed to create handle of the iRSI indicator for the symbol %s/%s, error code %d",
                  m_symbol.Name(),
                  EnumToString(Period()),
                  GetLastError());
      //--- the indicator is stopped early 
      return(INIT_FAILED);
     }
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   if(m_money!=NULL)
      delete m_money;
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- check Freeze and Stops levels
/*
   Type of order/position  |  Activation price  |  Check
   ------------------------|--------------------|--------------------------------------------
   Buy Limit order         |  Ask               |  Ask-OpenPrice  >= SYMBOL_TRADE_FREEZE_LEVEL
   Buy Stop order          |  Ask               |  OpenPrice-Ask  >= SYMBOL_TRADE_FREEZE_LEVEL
   Sell Limit order        |  Bid               |  OpenPrice-Bid  >= SYMBOL_TRADE_FREEZE_LEVEL
   Sell Stop order        |  Bid                |  Bid-OpenPrice  >= SYMBOL_TRADE_FREEZE_LEVEL
   Buy position            |  Bid               |  TakeProfit-Bid >= SYMBOL_TRADE_FREEZE_LEVEL 
                           |                    |  Bid-StopLoss   >= SYMBOL_TRADE_FREEZE_LEVEL
   Sell position           |  Ask               |  Ask-TakeProfit >= SYMBOL_TRADE_FREEZE_LEVEL
                           |                    |  StopLoss-Ask   >= SYMBOL_TRADE_FREEZE_LEVEL
                           
   Buying is done at the Ask price                 |  Selling is done at the Bid price
   ------------------------------------------------|----------------------------------
   TakeProfit        >= Bid                        |  TakeProfit        <= Ask
   StopLoss          <= Bid                      |  StopLoss          >= Ask
   TakeProfit - Bid  >= SYMBOL_TRADE_STOPS_LEVEL   |  Ask - TakeProfit  >= SYMBOL_TRADE_STOPS_LEVEL
   Bid - StopLoss    >= SYMBOL_TRADE_STOPS_LEVEL   |  StopLoss - Ask    >= SYMBOL_TRADE_STOPS_LEVEL
*/
   if(!RefreshRates() || !m_symbol.Refresh())
      return;
//--- FreezeLevel -> for pending order and modification
   double freeze_level=m_symbol.FreezeLevel()*m_symbol.Point();
   if(freeze_level==0.0)
      freeze_level=(m_symbol.Ask()-m_symbol.Bid())*3.0;
   freeze_level*=1.1;
//--- StopsLevel -> for TakeProfit and StopLoss
   double stop_level=m_symbol.StopsLevel()*m_symbol.Point();
   if(stop_level==0.0)
      stop_level=(m_symbol.Ask()-m_symbol.Bid())*3.0;
   stop_level*=1.1;

   if(freeze_level<=0.0 || stop_level<=0.0)
      return;
//--- считаем позиции Buy и Sell, а также модифицируем (если задано во входных параметрах)
   int count_buys=0,count_sells=0;
   double level=(stop_level>freeze_level)?stop_level:freeze_level;
   Trailing(level,count_buys,count_sells);
//---
   double rsi_0=iRSIGet(0);
   double rsi_1=iRSIGet(1);
//--- close position by signal
   if(CloseBySignal)
     {
      if(count_buys>0 && rsi_0<RsiSellLevel && rsi_1>RsiSellLevel)
         ClosePositions(POSITION_TYPE_BUY);
      if(count_sells>0 && rsi_0>RsiBuyLevel && rsi_1<RsiBuyLevel)
         ClosePositions(POSITION_TYPE_SELL);
     }
//--- open position
   if(TimeControl())
     {
      if(OpenBUY && count_buys<1 && rsi_0>RsiBuyLevel && rsi_1<RsiBuyLevel)
         OpenPosition(POSITION_TYPE_BUY);
      if(OpenSELL && count_sells<1 && rsi_0<RsiSellLevel && rsi_1>RsiSellLevel)
         OpenPosition(POSITION_TYPE_SELL);
     }
//---
   return;
  }
//+------------------------------------------------------------------+
//| Close Positions                                                  |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE pos_type)
  {
   for(int i=PositionsTotal()-1;i>=0;i--) // returns the number of current orders
      if(m_position.SelectByIndex(i))
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==m_magic)
            if(m_position.PositionType()==pos_type)
               m_trade.PositionClose(m_position.Ticket());
  }
//+------------------------------------------------------------------+
//| Lot Check                                                        |
//+------------------------------------------------------------------+
double LotCheck(double lots)
  {
//--- calculate maximum volume
   double volume=NormalizeDouble(lots,2);
   double stepvol=m_symbol.LotsStep();
   if(stepvol>0.0)
      volume=stepvol*MathFloor(volume/stepvol);
//---
   double minvol=m_symbol.LotsMin();
   if(volume<minvol)
      volume=0.0;
//---
   double maxvol=m_symbol.LotsMax();
   if(volume>maxvol)
      volume=maxvol;
   return(volume);
  }
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(void)
  {
//--- refresh rates
   if(!m_symbol.RefreshRates())
     {
      Print("RefreshRates error");
      return(false);
     }
//--- protection against the return value of "zero"
   if(m_symbol.Ask()==0 || m_symbol.Bid()==0)
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+
//| Check the correctness of the position volume                     |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume,string &error_description)
  {
//--- minimal allowed volume for trade operations
   double min_volume=m_symbol.LotsMin();
   if(volume<min_volume)
     {
      if(TerminalInfoString(TERMINAL_LANGUAGE)=="Russian")
         error_description=StringFormat("Объем меньше минимально допустимого SYMBOL_VOLUME_MIN=%.2f",min_volume);
      else
         error_description=StringFormat("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
      return(false);
     }
//--- maximal allowed volume of trade operations
   double max_volume=m_symbol.LotsMax();
   if(volume>max_volume)
     {
      if(TerminalInfoString(TERMINAL_LANGUAGE)=="Russian")
         error_description=StringFormat("Объем больше максимально допустимого SYMBOL_VOLUME_MAX=%.2f",max_volume);
      else
         error_description=StringFormat("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
      return(false);
     }
//--- get minimal step of volume changing
   double volume_step=m_symbol.LotsStep();
   int ratio=(int)MathRound(volume/volume_step);
   if(MathAbs(ratio*volume_step-volume)>0.0000001)
     {
      if(TerminalInfoString(TERMINAL_LANGUAGE)=="Russian")
         error_description=StringFormat("Объем не кратен минимальному шагу SYMBOL_VOLUME_STEP=%.2f, ближайший правильный объем %.2f",
                                        volume_step,ratio*volume_step);
      else
         error_description=StringFormat("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
                                        volume_step,ratio*volume_step);
      return(false);
     }
   error_description="Correct volume value";
   return(true);
  }
//+------------------------------------------------------------------+
//| Get value of buffers for the iRSI                                |
//+------------------------------------------------------------------+
double iRSIGet(const int index)
  {
   double RSI[1];
//--- reset error code 
   ResetLastError();
//--- fill a part of the iRSI array with values from the indicator buffer that has 0 index 
   if(CopyBuffer(handle_iRSI,0,index,1,RSI)<0)
     {
      //--- if the copying fails, tell the error code 
      PrintFormat("Failed to copy data from the iRSI indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated 
      return(0.0);
     }
   return(RSI[0]);
  }
//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(const ENUM_POSITION_TYPE pos_type)
  {
//--- check Freeze and Stops levels
/*
   Type of order/position  |  Activation price  |  Check
   ------------------------|--------------------|--------------------------------------------
   Buy Limit order         |  Ask               |  Ask-OpenPrice  >= SYMBOL_TRADE_FREEZE_LEVEL
   Buy Stop order          |  Ask               |  OpenPrice-Ask  >= SYMBOL_TRADE_FREEZE_LEVEL
   Sell Limit order        |  Bid               |  OpenPrice-Bid  >= SYMBOL_TRADE_FREEZE_LEVEL
   Sell Stop order        |  Bid                |  Bid-OpenPrice  >= SYMBOL_TRADE_FREEZE_LEVEL
   Buy position            |  Bid               |  TakeProfit-Bid >= SYMBOL_TRADE_FREEZE_LEVEL 
                           |                    |  Bid-StopLoss   >= SYMBOL_TRADE_FREEZE_LEVEL
   Sell position           |  Ask               |  Ask-TakeProfit >= SYMBOL_TRADE_FREEZE_LEVEL
                           |                    |  StopLoss-Ask   >= SYMBOL_TRADE_FREEZE_LEVEL
                           
   Buying is done at the Ask price                 |  Selling is done at the Bid price
   ------------------------------------------------|----------------------------------
   TakeProfit        >= Bid                        |  TakeProfit        <= Ask
   StopLoss          <= Bid                      |  StopLoss          >= Ask
   TakeProfit - Bid  >= SYMBOL_TRADE_STOPS_LEVEL   |  Ask - TakeProfit  >= SYMBOL_TRADE_STOPS_LEVEL
   Bid - StopLoss    >= SYMBOL_TRADE_STOPS_LEVEL   |  StopLoss - Ask    >= SYMBOL_TRADE_STOPS_LEVEL
*/
   if(!RefreshRates() || !m_symbol.Refresh())
      return;
//--- FreezeLevel -> for pending order and modification
   double freeze_level=m_symbol.FreezeLevel()*m_symbol.Point();
   if(freeze_level==0.0)
      freeze_level=(m_symbol.Ask()-m_symbol.Bid())*3.0;
   freeze_level*=1.1;
//--- StopsLevel -> for TakeProfit and StopLoss
   double stop_level=m_symbol.StopsLevel()*m_symbol.Point();
   if(stop_level==0.0)
      stop_level=(m_symbol.Ask()-m_symbol.Bid())*3.0;
   stop_level*=1.1;

   if(freeze_level<=0.0 || stop_level<=0.0)
      return;
//---
   if(pos_type==POSITION_TYPE_BUY)
     {
      double price=m_symbol.Ask();
      double sl=(InpStopLoss==0)?0.0:price-ExtStopLoss;
      double tp=(InpTakeProfit==0)?0.0:price+ExtTakeProfit;
      if(((sl!=0 && ExtStopLoss>=stop_level) || sl==0.0) && ((tp!=0 && ExtTakeProfit>=stop_level) || tp==0.0))
        {
         OpenBuy(sl,tp);
         return;
        }
     }
   if(pos_type==POSITION_TYPE_SELL)
     {
      double price=m_symbol.Bid();
      double sl=(InpStopLoss==0)?0.0:price+ExtStopLoss;
      double tp=(InpTakeProfit==0)?0.0:price-ExtTakeProfit;
      if(((sl!=0 && ExtStopLoss>=stop_level) || sl==0.0) && ((tp!=0 && ExtTakeProfit>=stop_level) || tp==0.0))
        {
         OpenSell(sl,tp);
         return;
        }
     }
  }
//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
void OpenBuy(double sl,double tp)
  {
   sl=m_symbol.NormalizePrice(sl);
   tp=m_symbol.NormalizePrice(tp);

   double long_lot=0.0;
   if(IntLotOrRisk==risk)
     {
      long_lot=m_money.CheckOpenLong(m_symbol.Ask(),sl);
      Print("sl=",DoubleToString(sl,m_symbol.Digits()),
            ", CheckOpenLong: ",DoubleToString(long_lot,2),
            ", Balance: ",    DoubleToString(m_account.Balance(),2),
            ", Equity: ",     DoubleToString(m_account.Equity(),2),
            ", FreeMargin: ", DoubleToString(m_account.FreeMargin(),2));
      if(long_lot==0.0)
        {
         Print(__FUNCTION__,", ERROR: method CheckOpenLong returned the value of \"0.0\"");
         return;
        }
     }
   else if(IntLotOrRisk==lot)
      long_lot=InpVolumeLorOrRisk;
   else
      return;
//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
   double free_margin_check= m_account.FreeMarginCheck(m_symbol.Name(),ORDER_TYPE_BUY,long_lot,m_symbol.Ask());
   double margin_check     = m_account.MarginCheck(m_symbol.Name(),ORDER_TYPE_SELL,long_lot,m_symbol.Bid());
   if(free_margin_check>margin_check)
     {
      if(m_trade.Buy(long_lot,m_symbol.Name(),m_symbol.Ask(),sl,tp,InpTradeComment))
        {
         if(m_trade.ResultDeal()==0)
           {
            //if(m_trade.ResultRetcode()==10009)
            //  {
            //   m_waiting_transaction=true;  // "true" -> it's forbidden to trade, we expect a transaction
            //   m_waiting_order_ticket=m_trade.ResultOrder();
            //  }
            Print("#1 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
                  ", description of result: ",m_trade.ResultRetcodeDescription());
            PrintResultTrade(m_trade,m_symbol);
           }
         else
           {
            //if(m_trade.ResultRetcode()==10009)
            //  {
            //   m_waiting_transaction=true;  // "true" -> it's forbidden to trade, we expect a transaction
            //   m_waiting_order_ticket=m_trade.ResultOrder();
            //  }
            Print("#2 Buy -> true. Result Retcode: ",m_trade.ResultRetcode(),
                  ", description of result: ",m_trade.ResultRetcodeDescription());
            PrintResultTrade(m_trade,m_symbol);
           }
        }
      else
        {
         Print("#3 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
               ", description of result: ",m_trade.ResultRetcodeDescription());
         PrintResultTrade(m_trade,m_symbol);
        }
     }
   else
     {
      Print(__FUNCTION__,", ERROR: method CAccountInfo::FreeMarginCheck returned the value ",DoubleToString(free_margin_check,2));
      return;
     }
//---
  }
//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
void OpenSell(double sl,double tp)
  {
   sl=m_symbol.NormalizePrice(sl);
   tp=m_symbol.NormalizePrice(tp);

   double short_lot=0.0;
   if(IntLotOrRisk==risk)
     {
      short_lot=m_money.CheckOpenShort(m_symbol.Bid(),sl);
      Print("sl=",DoubleToString(sl,m_symbol.Digits()),
            ", CheckOpenLong: ",DoubleToString(short_lot,2),
            ", Balance: ",    DoubleToString(m_account.Balance(),2),
            ", Equity: ",     DoubleToString(m_account.Equity(),2),
            ", FreeMargin: ", DoubleToString(m_account.FreeMargin(),2));
      if(short_lot==0.0)
        {
         Print(__FUNCTION__,", ERROR: method CheckOpenShort returned the value of \"0.0\"");
         return;
        }
     }
   else if(IntLotOrRisk==lot)
      short_lot=InpVolumeLorOrRisk;
   else
      return;
//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
   double free_margin_check= m_account.FreeMarginCheck(m_symbol.Name(),ORDER_TYPE_SELL,short_lot,m_symbol.Bid());
   double margin_check     = m_account.MarginCheck(m_symbol.Name(),ORDER_TYPE_SELL,short_lot,m_symbol.Bid());
   if(free_margin_check>margin_check)
     {
      if(m_trade.Sell(short_lot,m_symbol.Name(),m_symbol.Bid(),sl,tp,InpTradeComment))
        {
         if(m_trade.ResultDeal()==0)
           {
            //if(m_trade.ResultRetcode()==10009)
            //  {
            //   m_waiting_transaction=true;  // "true" -> it's forbidden to trade, we expect a transaction
            //   m_waiting_order_ticket=m_trade.ResultOrder();
            //  }
            Print("#1 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),
                  ", description of result: ",m_trade.ResultRetcodeDescription());
            PrintResultTrade(m_trade,m_symbol);
           }
         else
           {
            //if(m_trade.ResultRetcode()==10009)
            //  {
            //   m_waiting_transaction=true;  // "true" -> it's forbidden to trade, we expect a transaction
            //   m_waiting_order_ticket=m_trade.ResultOrder();
            //  }
            Print("#2 Sell -> true. Result Retcode: ",m_trade.ResultRetcode(),
                  ", description of result: ",m_trade.ResultRetcodeDescription());
            PrintResultTrade(m_trade,m_symbol);
           }
        }
      else
        {
         Print("#3 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),
               ", description of result: ",m_trade.ResultRetcodeDescription());
         PrintResultTrade(m_trade,m_symbol);
        }
     }
   else
     {
      Print(__FUNCTION__,", ERROR: method CAccountInfo::FreeMarginCheck returned the value ",DoubleToString(free_margin_check,2));
      return;
     }
//---
  }
//+------------------------------------------------------------------+
//| Trailing                                                         |
//|   InpTrailingStop: min distance from price to Stop Loss          |
//+------------------------------------------------------------------+
void Trailing(const double stop_level,int &count_buys,int &count_sells)
  {
   count_buys=0;
   count_sells=0;
/*
     Buying is done at the Ask price                 |  Selling is done at the Bid price
   ------------------------------------------------|----------------------------------
   TakeProfit        >= Bid                        |  TakeProfit        <= Ask
   StopLoss          <= Bid                      |  StopLoss          >= Ask
   TakeProfit - Bid  >= SYMBOL_TRADE_STOPS_LEVEL   |  Ask - TakeProfit  >= SYMBOL_TRADE_STOPS_LEVEL
   Bid - StopLoss    >= SYMBOL_TRADE_STOPS_LEVEL   |  StopLoss - Ask    >= SYMBOL_TRADE_STOPS_LEVEL
*/
//if(InpTrailingStop==0)
//   return;
   for(int i=PositionsTotal()-1;i>=0;i--) // returns the number of open positions
      if(m_position.SelectByIndex(i))
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==m_magic)
           {
            if(m_position.PositionType()==POSITION_TYPE_BUY)
              {
               count_buys++;
               if(m_position.PriceCurrent()-m_position.PriceOpen()>ExtTrailingStop+ExtTrailingStep)
                  if(m_position.StopLoss()<m_position.PriceCurrent()-(ExtTrailingStop+ExtTrailingStep))
                     if(ExtTrailingStop>=stop_level)
                       {
                        if(!m_trade.PositionModify(m_position.Ticket(),
                           m_symbol.NormalizePrice(m_position.PriceCurrent()-ExtTrailingStop),
                           m_position.TakeProfit()))
                           Print("Modify ",m_position.Ticket(),
                                 " Position -> false. Result Retcode: ",m_trade.ResultRetcode(),
                                 ", description of result: ",m_trade.ResultRetcodeDescription());
                        RefreshRates();
                        m_position.SelectByIndex(i);
                        PrintResultModify(m_trade,m_symbol,m_position);
                        continue;
                       }
              }
            else
              {
               count_sells++;
               if(m_position.PriceOpen()-m_position.PriceCurrent()>ExtTrailingStop+ExtTrailingStep)
                  if((m_position.StopLoss()>(m_position.PriceCurrent()+(ExtTrailingStop+ExtTrailingStep))) || 
                     (m_position.StopLoss()==0))
                     if(ExtTrailingStop>=stop_level)
                       {
                        if(!m_trade.PositionModify(m_position.Ticket(),
                           m_symbol.NormalizePrice(m_position.PriceCurrent()+ExtTrailingStop),
                           m_position.TakeProfit()))
                           Print("Modify ",m_position.Ticket(),
                                 " Position -> false. Result Retcode: ",m_trade.ResultRetcode(),
                                 ", description of result: ",m_trade.ResultRetcodeDescription());
                        RefreshRates();
                        m_position.SelectByIndex(i);
                        PrintResultModify(m_trade,m_symbol,m_position);
                       }
              }

           }
  }
//+------------------------------------------------------------------+
//| Print CTrade result                                              |
//+------------------------------------------------------------------+
void PrintResultTrade(CTrade &trade,CSymbolInfo &symbol)
  {
   Print("File: ",__FILE__,", symbol: ",m_symbol.Name());
   Print("Code of request result: "+IntegerToString(trade.ResultRetcode()));
   Print("code of request result as a string: "+trade.ResultRetcodeDescription());
   Print("Deal ticket: "+IntegerToString(trade.ResultDeal()));
   Print("Order ticket: "+IntegerToString(trade.ResultOrder()));
   Print("Volume of deal or order: "+DoubleToString(trade.ResultVolume(),2));
   Print("Price, confirmed by broker: "+DoubleToString(trade.ResultPrice(),symbol.Digits()));
   Print("Current bid price: "+DoubleToString(symbol.Bid(),symbol.Digits())+" (the requote): "+DoubleToString(trade.ResultBid(),symbol.Digits()));
   Print("Current ask price: "+DoubleToString(symbol.Ask(),symbol.Digits())+" (the requote): "+DoubleToString(trade.ResultAsk(),symbol.Digits()));
   Print("Broker comment: "+trade.ResultComment());
   Print("Freeze Level: "+DoubleToString(m_symbol.FreezeLevel(),2));
   Print("Stops Level: "+DoubleToString(m_symbol.StopsLevel(),2));
  }
//+------------------------------------------------------------------+
//| Print CTrade result                                              |
//+------------------------------------------------------------------+
void PrintResultModify(CTrade &trade,CSymbolInfo &symbol,CPositionInfo &position)
  {
   Print("File: ",__FILE__,", symbol: ",m_symbol.Name());
   Print("Code of request result: "+IntegerToString(trade.ResultRetcode()));
   Print("code of request result as a string: "+trade.ResultRetcodeDescription());
   Print("Deal ticket: "+IntegerToString(trade.ResultDeal()));
   Print("Order ticket: "+IntegerToString(trade.ResultOrder()));
   Print("Volume of deal or order: "+DoubleToString(trade.ResultVolume(),2));
   Print("Price, confirmed by broker: "+DoubleToString(trade.ResultPrice(),symbol.Digits()));
   Print("Current bid price: "+DoubleToString(symbol.Bid(),symbol.Digits())+" (the requote): "+DoubleToString(trade.ResultBid(),symbol.Digits()));
   Print("Current ask price: "+DoubleToString(symbol.Ask(),symbol.Digits())+" (the requote): "+DoubleToString(trade.ResultAsk(),symbol.Digits()));
   Print("Broker comment: "+trade.ResultComment());
   Print("Freeze Level: "+DoubleToString(m_symbol.FreezeLevel(),2));
   Print("Stops Level: "+DoubleToString(m_symbol.StopsLevel(),2));
   Print("Price of position opening: "+DoubleToString(position.PriceOpen(),symbol.Digits()));
   Print("Price of position's Stop Loss: "+DoubleToString(position.StopLoss(),symbol.Digits()));
   Print("Price of position's Take Profit: "+DoubleToString(position.TakeProfit(),symbol.Digits()));
   Print("Current price by position: "+DoubleToString(position.PriceCurrent(),symbol.Digits()));
  }
//+------------------------------------------------------------------+
//| TimeControl                                                      |
//+------------------------------------------------------------------+
bool TimeControl(void)
  {
   if(!InpTimeControl)
      return(true);
   MqlDateTime STimeCurrent;
   datetime time_current=TimeCurrent();
   if(time_current==D'1970.01.01 00:00')
      return(false);
   TimeToStruct(time_current,STimeCurrent);
   if(InpStartHour<InpEndHour) // intraday time interval
     {
/*
Example:
input uchar    InpStartHour      = 5;        // Start hour
input uchar    InpEndHour        = 10;       // End hour
0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15
_  _  _  _  _  +  +  +  +  +  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  +  +  +  +  +  _  _  _  _  _  _
*/
      if(STimeCurrent.hour>=InpStartHour && STimeCurrent.hour<InpEndHour)
         return(true);
     }
   else if(InpStartHour>InpEndHour) // time interval with the transition in a day
     {
/*
Example:
input uchar    InpStartHour      = 10;       // Start hour
input uchar    InpEndHour        = 5;        // End hour
0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15
_  _  _  _  _  _  _  _  _  _  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  +  _  _  _  _  _  +  +  +  +  +  +
*/
      if(STimeCurrent.hour>=InpStartHour || STimeCurrent.hour<InpEndHour)
         return(true);
     }
   else
      return(false);
//---
   return(false);
  }
//+------------------------------------------------------------------+
