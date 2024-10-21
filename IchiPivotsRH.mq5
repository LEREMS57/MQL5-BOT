//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
input double RiskPerTrade = 1.0; // Risque par transaction en pourcentage du solde du compte
input int StartHour = 9;
input int EndHour = 17;
input int PauseStartHour = 12;
input int PauseStartMinute = 0;
input int PauseEndHour = 13;
input int PauseEndMinute = 0;
input double MaxDailyLoss = 5.0; // Perte maximale quotidienne en pourcentage

double AccountBalanceAtStart;
double DailyLoss = 0;
datetime lastPivotTime = 0;
double pivot, resistance1, resistance2, resistance3, support1, support2, support3;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  AccountBalanceAtStart = AccountInfoDouble(ACCOUNT_BALANCE);
  EventSetTimer(60); // Vérifier les conditions toutes les minutes
  CalculatePivots(); // Calcul initial des pivots
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  EventKillTimer();
}

//+------------------------------------------------------------------+
//| Calcul des heures de trading                                     |
//+------------------------------------------------------------------+
bool IsTradingHour()
{
  int currentHour = TimeHour(TimeCurrent());
  int currentMinute = TimeMinute(TimeCurrent());

  // Vérifier les heures de trading
  if (currentHour < StartHour || currentHour >= EndHour)
    return false;

  // Vérifier la période de pause
  if ((currentHour > PauseStartHour || (currentHour == PauseStartHour && currentMinute >= PauseStartMinute)) &&
      (currentHour < PauseEndHour || (currentHour == PauseEndHour && currentMinute < PauseEndMinute)))
    return false;

  // Vérifier la période de trading interdite
  if (currentHour == 15 && (currentMinute >= 25 && currentMinute < 45))
    return false;

  return true;
}

//+------------------------------------------------------------------+
//| Calcul des points pivots                                         |
//+------------------------------------------------------------------+
void CalculatePivots()
{
  if (TimeHour(TimeCurrent()) != TimeHour(lastPivotTime))
  {
    double high = iHigh(NULL, PERIOD_H1, 1);
    double low = iLow(NULL, PERIOD_H1, 1);
    double close = iClose(NULL, PERIOD_H1, 1);

    pivot = (high + low + close) / 3.0;
    resistance1 = (2 * pivot) - low;
    resistance2 = pivot + (high - low);
    resistance3 = high + 2 * (pivot - low);
    support1 = (2 * pivot) - high;
    support2 = pivot - (high - low);
    support3 = low - 2 * (high - pivot);

    lastPivotTime = TimeCurrent();
  }
}

//+------------------------------------------------------------------+
//| Vérification des pertes journalières                             |
//+------------------------------------------------------------------+
bool CheckDailyLoss()
{
  double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
  DailyLoss = ((AccountBalanceAtStart - currentBalance) / AccountBalanceAtStart) * 100.0;

  if (DailyLoss >= MaxDailyLoss)
  {
    Print("Perte quotidienne maximale atteinte. Arrêt des trades pour aujourd'hui.");
    return true; // Indique que la perte maximale est atteinte
  }

  return false;
}

//+------------------------------------------------------------------+
//| Fonction principale de trading                                   |
//+------------------------------------------------------------------+
void OnTick()
{
  if (!IsTradingHour())
    return;

  CalculatePivots();

  // Vérifier les conditions d'achat et de vente pour chaque symbole
  CheckConditions("GER40.cash");
  CheckConditions("US30.cash");
}

//+------------------------------------------------------------------+
//| Vérification des conditions d'achat et de vente                  |
//+------------------------------------------------------------------+
void CheckConditions(string symbol)
{
  double kijun = iIchimoku(symbol, PERIOD_M1, 9, 26, 52, MODE_KIJUN);
  double closePrice = iClose(symbol, PERIOD_M1, 0);
  double atr = iATR(symbol, PERIOD_M5, 14);

  bool buyCondition = closePrice > kijun && closePrice > pivot && iClose(symbol, PERIOD_M1, 1) <= kijun;
  bool sellCondition = closePrice < kijun && closePrice < pivot && iClose(symbol, PERIOD_M1, 1) >= kijun;

  if (buyCondition)
  {
    EnterTrade(symbol, ORDER_TYPE_BUY, closePrice, atr);
  }
  else if (sellCondition)
  {
    EnterTrade(symbol, ORDER_TYPE_SELL, closePrice, atr);
  }
}

//+------------------------------------------------------------------+
//| Entrée en position                                               |
//+------------------------------------------------------------------+
void EnterTrade(string symbol, int tradeType, double price, double atr)
{
  if (CheckDailyLoss()) // Vérifier la perte journalière avant d'entrer en position
    return;

  double lotSize = CalculateLotSize(atr);
  double stopLoss = tradeType == ORDER_TYPE_BUY ? price - (2 * atr) : price + (2 * atr);

  MqlTradeRequest request;
  MqlTradeResult result;
  ZeroMemory(request);
  ZeroMemory(result);

  request.action = TRADE_ACTION_DEAL;
  request.symbol = symbol;
  request.volume = lotSize;
  request.type = tradeType;
  request.price = price;
  request.sl = stopLoss;
  request.tp = 0;
  request.deviation = 2;
  request.magic = 0;
  request.comment = "IchiPivotsRH Bot";

  if (!OrderSend(request, result))
  {
    Print("Erreur lors de l'envoi de l'ordre: ", GetLastError());
  }
}

//+------------------------------------------------------------------+
//| Calcul de la taille des lots                                     |
//+------------------------------------------------------------------+
double CalculateLotSize(double atr)
{
  double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPerTrade / 100.0);
  double lotSize = riskAmount / (atr * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE));
  lotSize = MathMax(lotSize, 0.01); // Taille minimum
  lotSize = MathMin(lotSize, 3.0); // Taille maximum
  return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Gestion des positions ouvertes                                   |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
  for (int i = OrdersTotal() - 1; i >= 0; i--)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      double closePrice = iClose(OrderSymbol(), PERIOD_M1, 0);

      if (OrderType() == ORDER_TYPE_BUY)
      {
        if (closePrice > resistance3)
        {
          OrderClose(OrderTicket(), OrderLots() * 0.25, OrderClosePrice(), 2, clrNONE);
        }
        else if (closePrice > resistance2)
        {
          OrderClose(OrderTicket(), OrderLots() * 0.25, OrderClosePrice(), 2, clrNONE);
        }
        else if (closePrice > resistance1)
        {
          OrderClose(OrderTicket(), OrderLots() * 0.50, OrderClosePrice(), 2, clrNONE);
        }
      }
      else if (OrderType() == ORDER_TYPE_SELL)
      {
        if (closePrice < support3)
        {
          OrderClose(OrderTicket(), OrderLots() * 0.25, OrderClosePrice(), 2, clrNONE);
        }
        else if (closePrice < support2)
        {
          OrderClose(OrderTicket(), OrderLots() * 0.25, OrderClosePrice(), 2, clrNONE);
        }
        else if (closePrice < support1)
        {
          OrderClose(OrderTicket(), OrderLots() * 0.50, OrderClosePrice(), 2, clrNONE);
        }
      }
    }
  }
}

//+------------------------------------------------------------------+
//| Fonction de gestion du timer                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
  ManageOpenTrades();
  OnTick();
}
