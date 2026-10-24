/// <summary>
/// Example for the blog: PrepareData groups by ONE field only. To forecast per item AND location,
/// build the Time Series Buffer yourself and hand it over with SetPreparedData.
/// Group ID is Code[50], so "ITEM|LOCATION" fits. Fill every period, also the empty ones (0).
/// For many items, replace the CalcSums loop with a Query object.
/// </summary>
codeunit 50501 "Location Series Example"
{
    procedure ForecastItemPerLocation(ItemNo: Code[20]; HistoryMonths: Integer; HorizonMonths: Integer; var TempTimeSeriesForecast: Record "Time Series Forecast" temporary)
    var
        TempTimeSeriesBuffer: Record "Time Series Buffer" temporary;
        DateRec: Record Date;
        TimeSeriesManagement: Codeunit "Time Series Management";
        NoKey: SecretText;
        ForecastStart: Date;
    begin
        ForecastStart := CalcDate('<-CM>', WorkDate());
        BuildSeriesPerLocation(ItemNo, ForecastStart, HistoryMonths, TempTimeSeriesBuffer);

        TimeSeriesManagement.Initialize('', NoKey, 0, true);
        TimeSeriesManagement.SetPreparedData(TempTimeSeriesBuffer, DateRec."Period Type"::Month, ForecastStart, HistoryMonths);
        TimeSeriesManagement.Forecast(HorizonMonths, 80, 0); // 0 = ARIMA
        TimeSeriesManagement.GetForecast(TempTimeSeriesForecast);
        // TempTimeSeriesForecast."Group ID" is again 'ITEM|LOCATION': split it and write
        // demand forecast entries with "Location Code", and turn on Use Forecast on Locations.
    end;

    local procedure BuildSeriesPerLocation(ItemNo: Code[20]; ForecastStart: Date; HistoryMonths: Integer; var TempTimeSeriesBuffer: Record "Time Series Buffer" temporary)
    var
        Location: Record Location;
        ItemLedgerEntry: Record "Item Ledger Entry";
        PeriodStart: Date;
        PeriodNo: Integer;
        MonthsBackTok: Label '<-%1M>', Locked = true;
    begin
        Location.SetRange("Use As In-Transit", false);
        if not Location.FindSet() then
            exit;
        repeat
            for PeriodNo := 1 to HistoryMonths do begin
                // Period 1 is the oldest month, period HistoryMonths the month before ForecastStart.
                PeriodStart := CalcDate(StrSubstNo(MonthsBackTok, HistoryMonths - PeriodNo + 1), ForecastStart);

                ItemLedgerEntry.SetRange("Item No.", ItemNo);
                ItemLedgerEntry.SetRange("Location Code", Location.Code);
                ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Sale);
                ItemLedgerEntry.SetRange("Posting Date", PeriodStart, CalcDate('<CM>', PeriodStart));
                ItemLedgerEntry.CalcSums(Quantity);

                TempTimeSeriesBuffer.Init();
                TempTimeSeriesBuffer."Group ID" := CopyStr(ItemNo + '|' + Location.Code, 1, MaxStrLen(TempTimeSeriesBuffer."Group ID"));
                TempTimeSeriesBuffer."Period No." := PeriodNo;
                TempTimeSeriesBuffer."Period Start Date" := PeriodStart;
                TempTimeSeriesBuffer.Value := -ItemLedgerEntry.Quantity; // sales are negative in the ledger
                TempTimeSeriesBuffer.Insert();
            end;
        until Location.Next() = 0;
    end;
}
