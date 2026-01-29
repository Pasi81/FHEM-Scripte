*00:04:00 {

    ###############################################################
    # Grund-Setup & Attribute
    ###############################################################

    fhem("deletereading $SELF .*");

    # Vorhersage-Device & Readings
    my $ForecastDev              = AttrVal($SELF, "ForecastDev",              "UG.PVAnlage.SolarForecast");
    my $ForecastProdRead         = AttrVal($SELF, "ForecastProdRead",         "RestOfDayPVforecast");
    my $ForecastCosumRead        = AttrVal($SELF, "ForecastCosumRead",        "RestOfDayConsumptionForecast");

    # Batterie-Device & Readings
    my $PVBatterieDev                    = AttrVal($SELF, "PVBatterieDev",                    "UG.Keller.PVAnlage.Gen24");
    my $PVBatReseRead                    = AttrVal($SELF, "PVBatReseRead",                    "BatConfigReserve");
    my $PVBatSOCRead                     = AttrVal($SELF, "PVBatSOCRead",                     "BatteryChargePercent");
    my $PVBatCapaRead                    = AttrVal($SELF, "PVBatCapaRead",                    "BatteryCapacity");
    my $PVBatConfigMaxEnabledRead        = AttrVal($SELF, "PVBatConfigMaxEnabledRead",        "BatConfigMaxEnabled");
    my $PVBatConfigMaxDischargeWattRead  = AttrVal($SELF, "PVBatConfigMaxDischargeWattRead",  "BatConfigMaxDischargeWatt");

    # Sonstige Attribute
    my $EndHourCheapPower        = AttrVal($SELF, "EndHourCheapPower",        "5");   # Ende der günstigen Stromphase (Stunde)
    my $PVBatReserveSOC          = AttrVal($SELF, "PVBatReserveSOC",          "7");   # Reserve-SOC in %
    my $PVBatMinSOCAtEndCheap    = AttrVal($SELF, "PVBatMinSOCAtEndCheap",    "20");  # Minimaler SOC am Ende der Billigphase
    my $PVMaxPower               = AttrVal($SELF, "PVMaxPower",               "9000");
    my $TargetSOC                = AttrVal($SELF, "TargetSOC",                "80");  # Ziel-SOC in %

    ###############################################################
    # Aktuelle Werte lesen
    ###############################################################

    my $ForecastProd   = ReadingsVal($ForecastDev, $ForecastProdRead,  "0");
    my $ForecastCosum  = ReadingsVal($ForecastDev, $ForecastCosumRead, "0");

    my $PVBatSOC       = ReadingsVal($PVBatterieDev, $PVBatSOCRead,    "10");
    my $PVBatRese      = ReadingsVal($PVBatterieDev, $PVBatReseRead,   "10");
    my $PVBatCapa      = ReadingsVal($PVBatterieDev, $PVBatCapaRead,   "10");

    ###############################################################
    # Sonnenaufgang / Sonnenuntergang
    ###############################################################

    my $sunrise = ReadingsVal($ForecastDev, "Today_SunRise", "06:00");
    my $sunset  = ReadingsVal($ForecastDev, "Today_SunSet",  "18:00");

    my ($sunrise_hour) = $sunrise =~ /^(\d+):/;
    my ($sunset_hour)  = $sunset  =~ /^(\d+):/;

    fhem("setreading $SELF sunrise_hour $sunrise_hour");
    fhem("setreading $SELF sunset_hour $sunset_hour");

    ###############################################################
    # Stündliche Vorhersage: Verbrauch
    ###############################################################

    my @hourlyForecastConsumption = (0) x 24;
    my $ForecastCosumCalc         = 0;
    my $FoCaCosumDurCheapPower    = 0;

    for (my $i = 1; $i <= 24; $i++) {
        my $readingName = "special_todayConsumptionForecast_" . sprintf("%02d", $i);
        my $value       = ReadingsVal($ForecastDev, $readingName, "0");

        if ($value =~ /(\d+)/) {
            $value = $1;
        } else {
            $value = 0;
        }

        $hourlyForecastConsumption[$i-1] = $value;
        $ForecastCosumCalc += $value;

        if ($i >= 1 && $i <= $EndHourCheapPower) {
            $FoCaCosumDurCheapPower += $value;
        }
    }

    ###############################################################
    # Stündliche Vorhersage: PV-Produktion
    ###############################################################

    my @hourlyForecastProduction = (0) x 24;
    my $ForecastProdCalc         = 0;

    for (my $i = 1; $i <= 24; $i++) {
        if ($i >= $sunrise_hour && $i <= $sunset_hour) {
            my $readingName = "Today_Hour" . sprintf("%02d", $i) . "_PVforecast";
            my $value       = ReadingsVal($ForecastDev, $readingName, "0");

            if ($value =~ /(\d+)/) {
                $value = $1;
            } else {
                $value = 0;
            }

            if ($value < $PVMaxPower) {
                $hourlyForecastProduction[$i-1] = $value;
                $ForecastProdCalc += $value;
            } else {
                $hourlyForecastProduction[$i-1] = $PVMaxPower;
                $ForecastProdCalc += $PVMaxPower;
            }
        } else {
            $hourlyForecastProduction[$i-1] = 0;
        }
    }

    ###############################################################
    # Zeit bis ausreichender PV-Leistung (RemainingTime)
    ###############################################################

    my $remainingTime = 0;
	my $hourMoreProdThenCon = 24;

    for (my $i = $sunrise_hour; $i <= $sunset_hour; $i++) {
        if ($hourlyForecastProduction[$i-1] > $hourlyForecastConsumption[$i-1]) {
            $remainingTime = $i - $sunrise_hour;
			$hourMoreProdThenCon = $i;
            last;
        }
    }

    fhem("setreading $SELF RemainingTime_raw $remainingTime");

    if ($sunrise_hour > $EndHourCheapPower) {
        $remainingTime += ($sunrise_hour - $EndHourCheapPower);
    } elsif ($sunrise_hour < $EndHourCheapPower) {
        $remainingTime -= ($EndHourCheapPower - $sunrise_hour);
    }
    $remainingTime += 1; # Sicherheitsstunde

    fhem("setreading $SELF RemainingTime $remainingTime");

    ###############################################################
    # Batterie-Energie / Restenergie
    ###############################################################

    my $BattUseRemaEner = ($PVBatSOC - $PVBatReserveSOC) / 100 * $PVBatCapa;

    my $RequEnergieToday    = ($ForecastCosumCalc - $FoCaCosumDurCheapPower) * 1.1;
    my $RequEnergieToCharge = ($RequEnergieToday - $ForecastProdCalc) - $BattUseRemaEner;

    ###############################################################
    # Alte Logik: EnergieToCharge & Reserve-SOC
    ###############################################################

    my $EnergieToCharge = 0;
    my $PVBatNewResvSOC = $PVBatReserveSOC;

    if ($RequEnergieToCharge > 0) {

        # Vorhersage sagt: Energie reicht nicht
        if ($RequEnergieToCharge > ($PVBatCapa - $BattUseRemaEner)) {
            $EnergieToCharge += ($PVBatCapa - $BattUseRemaEner);
        } else {
            $EnergieToCharge += $RequEnergieToCharge;
        }

    } else {

        # Vorhersage sagt: genug oder zu viel Energie
        my $requiredEnergyUntilSufficient = 0;

        for (my $i = $EndHourCheapPower; $i < ($EndHourCheapPower + $remainingTime); $i++) {
            if ($i < ($EndHourCheapPower + $remainingTime - 1)) {
                $requiredEnergyUntilSufficient += ($hourlyForecastConsumption[$i-1] - $hourlyForecastProduction[$i-1]);
            } else {
                $requiredEnergyUntilSufficient += $hourlyForecastConsumption[$i-1];
            }
            my $Num = sprintf("%02d", $i);
            fhem("setreading $SELF hourlyForecastProduction$Num $hourlyForecastProduction[$i-1]");
            fhem("setreading $SELF hourlyForecastConsumption$Num $hourlyForecastConsumption[$i-1]");
        }

        my $energyDeficit = $requiredEnergyUntilSufficient - $BattUseRemaEner;
        fhem("setreading $SELF EnergyDeficit $energyDeficit");

        if ($energyDeficit > 0) {
            $EnergieToCharge += $energyDeficit;
        } else {

            my $requiredEnergyUntilSufficient2 = 0;

            for (my $i = 1; $i < $EndHourCheapPower + $remainingTime; $i++) {
                if ($i < ($EndHourCheapPower + $remainingTime - 1)) {
                    $requiredEnergyUntilSufficient2 += ($hourlyForecastConsumption[$i-1] - $hourlyForecastProduction[$i-1]);
                } else {
                    $requiredEnergyUntilSufficient2 += $hourlyForecastConsumption[$i-1];
                }
                my $Num = sprintf("%02d", $i);
                fhem("setreading $SELF hourlyForecastProduction$Num $hourlyForecastProduction[$i-1]");
                fhem("setreading $SELF hourlyForecastConsumption$Num $hourlyForecastConsumption[$i-1]");
            }

            fhem("setreading $SELF RequiredEnergyUntilSufficient2 $requiredEnergyUntilSufficient2");

            my $energyDeficit2 = $requiredEnergyUntilSufficient2 - $BattUseRemaEner;
            fhem("setreading $SELF EnergyDeficit2 $energyDeficit2");

            if ($energyDeficit2 > 0) {
                my $UseableBattEnergie = $BattUseRemaEner - $requiredEnergyUntilSufficient;
                fhem("setreading $SELF UseableBattEnergie $UseableBattEnergie");

                $PVBatNewResvSOC = (100 / $PVBatCapa * $UseableBattEnergie) + $PVBatReserveSOC;
            }
        }
    }

    ###############################################################
    # Nachbearbeitung SOC-Reserve & erste Laderaten
    ###############################################################

    $PVBatNewResvSOC = round($PVBatNewResvSOC, 0);

    if ($PVBatNewResvSOC < $PVBatMinSOCAtEndCheap) {
        $PVBatNewResvSOC = $PVBatMinSOCAtEndCheap;
    }
	# Wenn der neue Reserve SOC mehr Energie erfordert als nach geladen werden sollte dann die nachzuladende Energiemenge anpassen
	if (($PVBatNewResvSOC - $PVBatSOC) > 0){
		my $BattCapGap = ($PVBatNewResvSOC - $PVBatSOC) / 100 * $PVBatCapa;
		fhem("setreading $SELF BattCapGap $BattCapGap"); 
		if ($BattCapGap>$EnergieToCharge){
			$EnergieToCharge = $BattCapGap;
		}
	}
	
	my $hours_to_charge = $EndHourCheapPower;
    if ($hours_to_charge < 1) { $hours_to_charge = 1; }

    # Basis-Laderate (5 Stunden als Basis)
    my $BattChargRate    = $EnergieToCharge / $hours_to_charge;
    my $BattDisChargRate = $BattChargRate * (-1);
	
    fhem("setreading $SELF BattDisChargRate_1 $BattDisChargRate");   
	fhem("setreading $SELF BattChargRate_1 $BattChargRate");
	
    ###############################################################
    # SOC-Simulation NACH alter Logik (inkl. Nachtladung)
    ###############################################################

    my $StartSOCpercent = $PVBatSOC;
    my $StartSOCwh      = ($StartSOCpercent / 100) * $PVBatCapa;

    my @hourlySOC          = (0) x 24;
    my $soc_wh             = $StartSOCwh;
    my $soc_reaches_target = 0;
	my $soc_wh_max 	       = 0;
    for (my $h = 1; $h <= 24; $h++) {

        # 1) Nachtladung berücksichtigen (00:00–EndHourCheapPower)
        if ($h <= $EndHourCheapPower && $BattChargRate > 0) {
            $soc_wh += $BattChargRate;
        }
		else {
			# 2) PV-Produktion + Verbrauch (nur wenn nicht geladen wird)
			my $delta = $hourlyForecastProduction[$h-1] - $hourlyForecastConsumption[$h-1];
			$soc_wh += $delta;
		}
        # 3) Begrenzen auf Batteriegröße und Reserve
        my $min_wh = ($PVBatReserveSOC / 100) * $PVBatCapa;
        if ($soc_wh > $PVBatCapa) { $soc_wh = $PVBatCapa; }
        if ($soc_wh < $min_wh)    { $soc_wh = $min_wh;    }

        # 4) SOC in %
        my $soc_percent = ($soc_wh / $PVBatCapa) * 100;
        $hourlySOC[$h-1] = sprintf("%.1f", $soc_percent);

        # 5) Readings
        my $Num = sprintf("%02d", $h);
        fhem("setreading $SELF hourlySOC_$Num $hourlySOC[$h-1]");

        # 6) Ziel-SOC erreicht?
        if ($soc_percent >= $TargetSOC) {
            $soc_reaches_target = 1;
        }
		if ($h > $hourMoreProdThenCon){
			if ($soc_wh_max < $soc_wh){
				$soc_wh_max = $soc_wh;
			}
		}
    }
	my $soc_max = (($soc_wh_max / $PVBatCapa) * 100);
	$soc_max = sprintf("%.1f", $soc_max);
    fhem("setreading $SELF SOC_Reaches_Target $soc_reaches_target");
	fhem("setreading $SELF SOC_WH_Max $soc_wh_max");
	fhem("setreading $SELF SOC_Max $soc_max");
	fhem("setreading $SELF HourMoreProductionThenConsume $hourMoreProdThenCon");
	

    ###############################################################
    # Offset berechnen, falls Ziel-SOC nicht erreicht wird
    ###############################################################

    if (!$soc_reaches_target) {

        my $target_wh  = ($TargetSOC / 100) * $PVBatCapa;
        my $missing_wh = $target_wh - $soc_wh_max;
        if ($missing_wh < 0) { $missing_wh = 0; }

        fhem("setreading $SELF MissingEnergyAfterSimulation $missing_wh");

        my $offset_rate = $missing_wh / $hours_to_charge;

        fhem("setreading $SELF OffsetChargeRate $offset_rate");

        $BattChargRate    += $offset_rate;
        $BattDisChargRate  = $BattChargRate * (-1);

        fhem("setreading $SELF BattChargRate_Final $BattChargRate");
        fhem("setreading $SELF BattDisChargRate_Final $BattDisChargRate");
    }

    ###############################################################
    # Readings schreiben (Übersicht)
    ###############################################################

    fhem("setreading $SELF ForecastProd $ForecastProd");
    fhem("setreading $SELF ForecastProdCalc $ForecastProdCalc");
    fhem("setreading $SELF ForecastCosum $ForecastCosum");
    fhem("setreading $SELF ForecastCosumCalc $ForecastCosumCalc");
    fhem("setreading $SELF FoCaCosumDurCheapPower $FoCaCosumDurCheapPower");
    fhem("setreading $SELF PVBatSOC $PVBatSOC");
    fhem("setreading $SELF PVBatRese $PVBatRese");
    fhem("setreading $SELF PVBatCapa $PVBatCapa");
    fhem("setreading $SELF BattUseRemaEner $BattUseRemaEner");
    fhem("setreading $SELF RequEnergieToday $RequEnergieToday");
    fhem("setreading $SELF RequEnergieToCharge $RequEnergieToCharge");
    fhem("setreading $SELF EnergieToCharge $EnergieToCharge");
 

    fhem("setreading $SELF PVBatNewResvSOC $PVBatNewResvSOC");

    ###############################################################
    # Batterie-Parameter setzen
    ###############################################################

    if ($PVBatRese != $PVBatNewResvSOC) {
        fhem("set $PVBatterieDev $PVBatReseRead $PVBatNewResvSOC");
    }

    if ($BattChargRate > 0) {
        fhem("set $PVBatterieDev $PVBatConfigMaxEnabledRead dischrMax");
        fhem("set $PVBatterieDev $PVBatConfigMaxDischargeWattRead $BattDisChargRate");
    }

}
