//
// MetaTrader structure HISTORY_BAR_401
//
// HistoryFile Barformat v401 (ab Build 510), entspricht dem MetaQuotes-Struct MqlRates
//
//
// @see  Definition in MT4Expander::Expander.h
//

template    "MT4 History Data v401 [3]"
description "Files '*.hst'"

applies_to   file
fixed_start  148
requires    -148 "91 01"              // Version = 401
multiple

begin
   { endsection
      UnixDateTime "Time"
      move         4
      double       "Open"
      double       "High"
      double       "Low"
      double       "Close"
      int64        "Ticks"
      int32        "Spread"
      int64        "Volume"
   }[3]
end
