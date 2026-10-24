/// <summary>
/// Creates a demand forecast from item ledger history with the Business Central time series
/// service. Search for "Create Time Series Demand Forecast". Filter the items, choose the history,
/// the horizon and the model, then open the forecast in Demand Forecasts and run planning.
/// </summary>
report 50500 "Create Time Series Forecast"
{
    Caption = 'Create Time Series Demand Forecast';
    ProcessingOnly = true;
    UsageCategory = Tasks;
    ApplicationArea = All;

    dataset
    {
        dataitem(Item; Item)
        {
            RequestFilterFields = "No.", "Item Category Code", "Vendor No.", "Replenishment System";
            DataItemTableView = sorting("No.") where(Type = const(Inventory), Blocked = const(false));

            trigger OnPreDataItem()
            begin
                Builder.SetParameters(ForecastName, DemandSource, PeriodType, HistoryPeriods, HorizonPeriods, Model, ConfidencePct, MaxDeltaPct);
                Builder.ForecastItems(Item);
                if MakeCurrent then
                    Builder.SetAsCurrentDemandForecast();
                CurrReport.Break();
            end;
        }
    }

    requestpage
    {
        SaveValues = true;

        layout
        {
            area(Content)
            {
                group(Forecast)
                {
                    Caption = 'Forecast';

                    field(ForecastNameField; ForecastName)
                    {
                        ApplicationArea = All;
                        Caption = 'Demand Forecast Name';
                        ToolTip = 'Specifies the demand forecast to write to. It is created when it does not exist. A new run replaces the future entries of the same items.';
                        TableRelation = "Production Forecast Name";
                    }
                    field(DemandSourceField; DemandSource)
                    {
                        ApplicationArea = All;
                        Caption = 'Demand Source';
                        ToolTip = 'Specifies the history to forecast from. Sales gives a sales item forecast for MPS. Consumption gives a component forecast for MRP.';
                    }
                    field(MakeCurrentField; MakeCurrent)
                    {
                        ApplicationArea = All;
                        Caption = 'Set as Current Demand Forecast';
                        ToolTip = 'Specifies if the forecast becomes the Current Demand Forecast in Inventory Setup, so planning uses it by default.';
                    }
                }
                group(TimeSeries)
                {
                    Caption = 'Time Series';

                    field(PeriodTypeField; PeriodType)
                    {
                        ApplicationArea = All;
                        Caption = 'Period';
                        ToolTip = 'Specifies the length of one data point. Use Month for most items, Week for fast movers.';
                    }
                    field(HistoryPeriodsField; HistoryPeriods)
                    {
                        ApplicationArea = All;
                        Caption = 'History Periods';
                        MinValue = 6;
                        ToolTip = 'Specifies how many past periods are sent, counted back from the start of the current period. 24 months is a good start; STL needs more than two years.';
                    }
                    field(HorizonPeriodsField; HorizonPeriods)
                    {
                        ApplicationArea = All;
                        Caption = 'Forecast Periods';
                        MinValue = 1;
                        ToolTip = 'Specifies how many future periods to forecast. A long horizon lowers the quality.';
                    }
                    field(ModelField; Model)
                    {
                        ApplicationArea = All;
                        Caption = 'Model';
                        ToolTip = 'Specifies the time series model. ARIMA is a good default. All runs every model and keeps the one with the lowest error, but costs more processing time.';
                    }
                    field(ConfidencePctField; ConfidencePct)
                    {
                        ApplicationArea = All;
                        Caption = 'Confidence Level %';
                        MinValue = 0;
                        MaxValue = 99;
                        ToolTip = 'Specifies the confidence level of the forecast range (Delta). 80 is common.';
                    }
                    field(MaxDeltaPctField; MaxDeltaPct)
                    {
                        ApplicationArea = All;
                        Caption = 'Skip Lines Above Delta %';
                        MinValue = 0;
                        ToolTip = 'Specifies a limit for the uncertainty of a forecast line. Lines with a wider range are not written. 0 writes every line.';
                    }
                }
            }
        }

        trigger OnOpenPage()
        begin
            if ForecastName = '' then
                ForecastName := 'TS-FCST';
            if HistoryPeriods = 0 then
                HistoryPeriods := 24;
            if HorizonPeriods = 0 then
                HorizonPeriods := 6;
            if ConfidencePct = 0 then
                ConfidencePct := 80;
        end;
    }

    trigger OnPostReport()
    var
        ItemsForecast: Integer;
        EntriesWritten: Integer;
        LinesSkipped: Integer;
        BatchesFailed: Integer;
        LastError: Text;
    begin
        Builder.GetResult(ItemsForecast, EntriesWritten, LinesSkipped, BatchesFailed, LastError);
        if BatchesFailed = 0 then
            Message(DoneMsg, ItemsForecast, EntriesWritten, ForecastName, LinesSkipped)
        else
            Message(DoneWithErrorsMsg, ItemsForecast, EntriesWritten, ForecastName, LinesSkipped, BatchesFailed, LastError);
    end;

    var
        Builder: Codeunit "Demand Forecast Builder";
        ForecastName: Code[10];
        DemandSource: Enum "Forecast Demand Source";
        PeriodType: Enum "Forecast Period";
        Model: Enum "Time Series Model";
        HistoryPeriods: Integer;
        HorizonPeriods: Integer;
        ConfidencePct: Integer;
        MaxDeltaPct: Decimal;
        MakeCurrent: Boolean;
        DoneMsg: Label '%1 items forecast, %2 entries written to demand forecast %3.\%4 lines skipped because the range was too wide.', Comment = '%1 = items, %2 = entries, %3 = forecast name, %4 = skipped lines';
        DoneWithErrorsMsg: Label '%1 items forecast, %2 entries written to demand forecast %3.\%4 lines skipped because the range was too wide.\%5 batches failed. Last error: %6', Comment = '%1 = items, %2 = entries, %3 = forecast name, %4 = skipped lines, %5 = failed batches, %6 = error text';
}
