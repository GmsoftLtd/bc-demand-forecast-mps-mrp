/// <summary>
/// Builds a Business Central demand forecast from item ledger history with the standard
/// time series service: codeunit 2000 "Time Series Management" (namespace System.AI).
///
/// Flow per batch of items:
///   Initialize -> PrepareData (item ledger -> Time Series Buffer) -> Forecast -> GetForecast
///   -> write Production Forecast Entry ("Demand Forecast Entries" in the UI).
///
/// Sales history gives a sales item forecast (independent demand, used by MPS).
/// Consumption history gives a component forecast (dependent demand, used by MRP).
/// The forecast is written without location and variant, at item level.
/// </summary>
codeunit 50500 "Demand Forecast Builder"
{
    Permissions = tabledata "Production Forecast Name" = ri,
                  tabledata "Production Forecast Entry" = rid,
                  tabledata "Inventory Setup" = rm;

    var
        ForecastName: Code[10];
        DemandSource: Enum "Forecast Demand Source";
        Model: Enum "Time Series Model";
        PeriodType: Enum "Forecast Period";
        HistoryPeriods: Integer;
        HorizonPeriods: Integer;
        ConfidencePct: Integer;
        MaxDeltaPct: Decimal;
        BatchSize: Integer;
        ForecastStart: Date;
        ItemsForecast: Integer;
        EntriesWritten: Integer;
        LinesSkippedUncertain: Integer;
        BatchesFailed: Integer;
        LastServiceError: Text;
        ForecastDescriptionTok: Label 'Time series forecast (%1)', Comment = '%1 = model, for example ARIMA';
        NoForecastNameErr: Label 'Enter the name of the demand forecast to write to.';
        TooFewPeriodsErr: Label 'Use at least %1 periods of history. The time series service cannot forecast reliably on less.', Comment = '%1 = minimum number of periods';
        MinHistoryPeriods: Integer;

    /// <summary>
    /// Sets the run parameters. Call before ForecastItems.
    /// </summary>
    /// <param name="NewForecastName">Demand forecast (Production Forecast Name) to write to. Created when missing.</param>
    /// <param name="NewDemandSource">Sales for MPS (sales item forecast) or Consumption for MRP (component forecast).</param>
    /// <param name="NewPeriodType">Month or Week buckets.</param>
    /// <param name="NewHistoryPeriods">How many past periods to send, for example 24 months.</param>
    /// <param name="NewHorizonPeriods">How many future periods to forecast, for example 6 months.</param>
    /// <param name="NewModel">Time series model; ARIMA is a good default.</param>
    /// <param name="NewConfidencePct">Confidence level for the Delta (range), for example 80. 0 = service default.</param>
    /// <param name="NewMaxDeltaPct">Skip forecast lines whose Delta % is above this value. 0 = keep all.</param>
    procedure SetParameters(NewForecastName: Code[10]; NewDemandSource: Enum "Forecast Demand Source"; NewPeriodType: Enum "Forecast Period"; NewHistoryPeriods: Integer; NewHorizonPeriods: Integer; NewModel: Enum "Time Series Model"; NewConfidencePct: Integer; NewMaxDeltaPct: Decimal)
    begin
        MinHistoryPeriods := 6;
        if NewForecastName = '' then
            Error(NoForecastNameErr);
        if NewHistoryPeriods < MinHistoryPeriods then
            Error(TooFewPeriodsErr, MinHistoryPeriods);

        ForecastName := NewForecastName;
        DemandSource := NewDemandSource;
        PeriodType := NewPeriodType;
        HistoryPeriods := NewHistoryPeriods;
        HorizonPeriods := NewHorizonPeriods;
        Model := NewModel;
        ConfidencePct := NewConfidencePct;
        MaxDeltaPct := NewMaxDeltaPct;
        if BatchSize = 0 then
            BatchSize := 50;
        ForecastStart := GetPeriodStart(WorkDate());
    end;

    /// <summary>
    /// Number of items sent to the service in one call. Smaller batches avoid service time-outs.
    /// </summary>
    procedure SetBatchSize(NewBatchSize: Integer)
    begin
        if NewBatchSize > 0 then
            BatchSize := NewBatchSize;
    end;

    /// <summary>
    /// Forecasts every item in the filtered Item record and writes demand forecast entries.
    /// Items are sent in batches; a failed batch is counted and the run continues.
    /// </summary>
    procedure ForecastItems(var Item: Record Item)
    var
        BatchItem: Record Item;
        SelectionFilterManagement: Codeunit SelectionFilterManagement;
        ItemsInBatch: Integer;
    begin
        EnsureForecastName();
        Item.SetLoadFields("No.");
        if not Item.FindSet() then
            exit;
        repeat
            BatchItem := Item;
            BatchItem.Mark(true);
            ItemsInBatch += 1;
            if ItemsInBatch >= BatchSize then begin
                BatchItem.MarkedOnly(true);
                ForecastBatch(SelectionFilterManagement.GetSelectionFilterForItem(BatchItem));
                BatchItem.ClearMarks();
                BatchItem.MarkedOnly(false);
                ItemsInBatch := 0;
            end;
        until Item.Next() = 0;

        if ItemsInBatch > 0 then begin
            BatchItem.MarkedOnly(true);
            ForecastBatch(SelectionFilterManagement.GetSelectionFilterForItem(BatchItem));
        end;
    end;

    /// <summary>
    /// Makes the forecast the one that planning uses (Inventory Setup, Current Demand Forecast).
    /// The Calculate Plan request page can still pick another forecast in Use Forecast.
    /// </summary>
    procedure SetAsCurrentDemandForecast()
    var
        InventorySetup: Record "Inventory Setup";
    begin
        InventorySetup.Get();
        InventorySetup.Validate("Current Demand Forecast", ForecastName);
        InventorySetup.Modify(true);
    end;

    procedure GetResult(var NewItemsForecast: Integer; var NewEntriesWritten: Integer; var NewLinesSkippedUncertain: Integer; var NewBatchesFailed: Integer; var NewLastServiceError: Text)
    begin
        NewItemsForecast := ItemsForecast;
        NewEntriesWritten := EntriesWritten;
        NewLinesSkippedUncertain := LinesSkippedUncertain;
        NewBatchesFailed := BatchesFailed;
        NewLastServiceError := LastServiceError;
    end;

    local procedure ForecastBatch(ItemFilter: Text)
    var
        TempTimeSeriesForecast: Record "Time Series Forecast" temporary;
    begin
        if ItemFilter = '' then
            exit;

        ClearLastError();
        if not TryForecast(ItemFilter, TempTimeSeriesForecast) then begin
            BatchesFailed += 1;
            LastServiceError := GetLastErrorText();
            exit;
        end;

        WriteForecast(TempTimeSeriesForecast);
    end;

    /// <summary>
    /// The four calls to codeunit 2000. It only talks to the service and reads data,
    /// so it is safe as a TryFunction. Nothing is written to the database here.
    /// </summary>
    [TryFunction]
    local procedure TryForecast(ItemFilter: Text; var TempTimeSeriesForecast: Record "Time Series Forecast" temporary)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        TimeSeriesManagement: Codeunit "Time Series Management";
        NoKey: SecretText;
    begin
        // Business Central online: empty URI and key + standard credentials = the Microsoft-hosted
        // service, counted against the tenant's Azure AI usage. On-premises: pass your own
        // Azure ML endpoint and key instead (keep the key in isolated storage, never in a table).
        TimeSeriesManagement.Initialize('', NoKey, 0, true);

        // History: posted sales or consumption, before the first forecast period.
        ItemLedgerEntry.SetCurrentKey("Item No.", "Entry Type", "Variant Code", "Drop Shipment", "Location Code", "Posting Date");
        ItemLedgerEntry.SetFilter("Item No.", ItemFilter);
        ItemLedgerEntry.SetRange("Entry Type", GetEntryType());
        ItemLedgerEntry.SetFilter("Posting Date", '<%1', ForecastStart);

        // One series per item, one value per period. Periods without entries are sent as 0.
        TimeSeriesManagement.PrepareData(
            ItemLedgerEntry,
            ItemLedgerEntry.FieldNo("Item No."),      // group: one series per item
            ItemLedgerEntry.FieldNo("Posting Date"),  // date of each entry
            ItemLedgerEntry.FieldNo(Quantity),        // value to sum per period
            GetDatePeriodType(),                      // Date."Period Type": Week or Month
            ForecastStart,                            // history runs back from this date
            HistoryPeriods);                          // number of past periods

        TimeSeriesManagement.Forecast(HorizonPeriods, ConfidencePct, Model.AsInteger());
        TimeSeriesManagement.GetForecast(TempTimeSeriesForecast);
    end;

    local procedure WriteForecast(var TempTimeSeriesForecast: Record "Time Series Forecast" temporary)
    var
        LastItemNo: Code[20];
        ForecastQty: Decimal;
    begin
        LastItemNo := '';
        TempTimeSeriesForecast.SetCurrentKey("Group ID", "Period No.");
        if not TempTimeSeriesForecast.FindSet() then
            exit;

        repeat
            if TempTimeSeriesForecast."Group ID" <> LastItemNo then begin
                LastItemNo := CopyStr(TempTimeSeriesForecast."Group ID", 1, MaxStrLen(LastItemNo));
                DeleteFutureEntries(LastItemNo);
                ItemsForecast += 1;
            end;

            // Sales and consumption are negative in the item ledger, so the forecast is negative too.
            ForecastQty := Round(-TempTimeSeriesForecast.Value, 0.00001);

            if (MaxDeltaPct > 0) and (Abs(TempTimeSeriesForecast."Delta %") > MaxDeltaPct) then
                LinesSkippedUncertain += 1
            else
                if ForecastQty > 0 then
                    InsertEntry(LastItemNo, TempTimeSeriesForecast."Period Start Date", ForecastQty);
        until TempTimeSeriesForecast.Next() = 0;
    end;

    local procedure InsertEntry(ItemNo: Code[20]; ForecastDate: Date; ForecastQty: Decimal)
    var
        Item: Record Item;
        ProductionForecastEntry: Record "Production Forecast Entry";
    begin
        Item.SetLoadFields("Base Unit of Measure");
        if not Item.Get(ItemNo) then
            exit;

        ProductionForecastEntry.Init();
        ProductionForecastEntry."Entry No." := 0;
        ProductionForecastEntry."Production Forecast Name" := ForecastName;
        ProductionForecastEntry."Item No." := ItemNo;
        ProductionForecastEntry."Forecast Date" := ForecastDate;
        ProductionForecastEntry."Unit of Measure Code" := Item."Base Unit of Measure";
        ProductionForecastEntry."Qty. per Unit of Measure" := 1;
        ProductionForecastEntry."Forecast Quantity" := ForecastQty;
        ProductionForecastEntry."Forecast Quantity (Base)" := ForecastQty;
        ProductionForecastEntry."Component Forecast" := IsComponentForecast();
        ProductionForecastEntry.Description := CopyStr(StrSubstNo(ForecastDescriptionTok, Model), 1, MaxStrLen(ProductionForecastEntry.Description));
        ProductionForecastEntry.Insert(true);
        EntriesWritten += 1;
    end;

    /// <summary>
    /// A new run replaces this app's future entries for the item, so forecasts never pile up.
    /// Entries before the forecast start (history) and the other forecast type are kept.
    /// </summary>
    local procedure DeleteFutureEntries(ItemNo: Code[20])
    var
        ProductionForecastEntry: Record "Production Forecast Entry";
    begin
        ProductionForecastEntry.SetRange("Production Forecast Name", ForecastName);
        ProductionForecastEntry.SetRange("Item No.", ItemNo);
        ProductionForecastEntry.SetRange("Location Code", '');
        ProductionForecastEntry.SetRange("Variant Code", '');
        ProductionForecastEntry.SetRange("Component Forecast", IsComponentForecast());
        ProductionForecastEntry.SetFilter("Forecast Date", '>=%1', ForecastStart);
        if not ProductionForecastEntry.IsEmpty() then
            ProductionForecastEntry.DeleteAll(true);
    end;

    local procedure EnsureForecastName()
    var
        ProductionForecastName: Record "Production Forecast Name";
    begin
        if ProductionForecastName.Get(ForecastName) then
            exit;
        ProductionForecastName.Init();
        ProductionForecastName.Name := ForecastName;
        ProductionForecastName.Description := 'Time series forecast (codeunit 2000)';
        if IsComponentForecast() then
            ProductionForecastName."Forecast Type" := "Demand Forecast Type"::Component
        else
            ProductionForecastName."Forecast Type" := "Demand Forecast Type"::"Sales Item";
        ProductionForecastName.Insert(true);
    end;

    local procedure GetEntryType(): Enum "Item Ledger Entry Type"
    begin
        if DemandSource = DemandSource::Consumption then
            exit("Item Ledger Entry Type"::Consumption);
        exit("Item Ledger Entry Type"::Sale);
    end;

    local procedure IsComponentForecast(): Boolean
    begin
        exit(DemandSource = DemandSource::Consumption);
    end;

    local procedure GetDatePeriodType(): Integer
    var
        DateRec: Record Date;
    begin
        if PeriodType = PeriodType::Week then
            exit(DateRec."Period Type"::Week);
        exit(DateRec."Period Type"::Month);
    end;

    local procedure GetPeriodStart(FromDate: Date): Date
    begin
        if PeriodType = PeriodType::Week then
            exit(CalcDate('<-CW>', FromDate));
        exit(CalcDate('<-CM>', FromDate));
    end;
}
