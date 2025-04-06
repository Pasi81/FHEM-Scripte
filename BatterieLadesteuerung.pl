*00:04:00 {

	fhem ("deletereading $SELF .*");
	
	# Lese eigene Attribute
	# Lese Vorhersage-Attribute
	my $ForecastDev	= AttrVal($SELF, "ForecastDev","UG.PVAnlage.SolarForecast");
	my $ForecastProdRead = AttrVal($SELF, "ForecastProdRead","RestOfDayPVforecast");
	my $ForecastCosumRead = AttrVal($SELF, "ForecastCosumRead","RestOfDayConsumptionForecast");

	# Lese Batterie-Attribute
	my $PVBatterieDev  = AttrVal($SELF, "PVBatterieDev","UG.Keller.PVAnlage.Gen24");
	my $PVBatReseRead = AttrVal($SELF, "PVBatReseRead","BatConfigReserve");
	my $PVBatSOCRead = AttrVal($SELF, "PVBatSOCRead","BatteryChargePercent");
	my $PVBatCapaRead = AttrVal($SELF, "PVBatCapaRead","BatteryCapacity");
	my $PVBatConfigMaxEnabledRead = AttrVal($SELF, "PVBatConfigMaxEnabledRead","BatConfigMaxEnabled");
	my $PVBatConfigMaxDischargeWattRead = AttrVal($SELF, "PVBatConfigMaxDischargeWattRead","BatConfigMaxDischargeWatt");
	
	# Lese sonst Attribute
	my $EndHourCheapPower = AttrVal($SELF, "EndHourCheapPower","5");
	my $PVBatReserveSOC = AttrVal($SELF, "PVBatReserveSOC","7");
	my $PVMaxPower = AttrVal($SELF, "PVMaxPower","9000");
	
	# Lese Werte
	my $ForecastProd = ReadingsVal($ForecastDev,$ForecastProdRead, "0");
	my $ForecastCosum = ReadingsVal($ForecastDev,$ForecastCosumRead, "0");
	
	my $PVBatSOC = ReadingsVal($PVBatterieDev,$PVBatSOCRead, "10");
	my $PVBatRese = ReadingsVal($PVBatterieDev,$PVBatReseRead, "10");
	my $PVBatCapa = ReadingsVal($PVBatterieDev,$PVBatCapaRead, "10");
	   
	my $ForecastCosum1 = 0; 
	my $ForecastProdCalc = 0;
	
	# Lese die Zeit für Sonnenaufgang und Sonnenuntergang
	my $sunrise = ReadingsVal($ForecastDev, "Today_SunRise", "06:00");
	my $sunset = ReadingsVal($ForecastDev, "Today_SunSet", "18:00");

	# Konvertiere die Zeiten in Stunden
	my ($sunrise_hour) = $sunrise =~ /^(\d+):/;
	my ($sunset_hour) = $sunset =~ /^(\d+):/;

	my $FoCaCosumDurCheapPower = 0; # Vorhersage Stromverbrauch während der Günstig Strom phase
	
	# Lese stündliche Vorhersagewerte für Verbrauch in das Array
	# Initialisiere das Array @hourlyForecastConsumption mit 24 Nullen
	my @hourlyForecastConsumption = (0) x 24;
	for (my $i = 1; $i <= 24; $i++) {
		my $readingName = "special_todayConsumptionForecast_" . sprintf("%02d", $i);
		my $value = ReadingsVal($ForecastDev, $readingName, "0");
		
		# Extrahiere den numerischen Teil
		if ($value =~ /(\d+)/) {
			$value = $1;
		} else {
			$value = 0;	 # Fallback, falls kein numerischer Wert gefunden wird
		}

		$hourlyForecastConsumption[$i-1] = $value;	# Setze den Wert im Array
		$ForecastCosum1 = $ForecastCosum1 + $value;
		if ($i >= 1 && $i <= ($EndHourCheapPower) ){
			$FoCaCosumDurCheapPower = $FoCaCosumDurCheapPower + $value;
		}
	}
	
	# Initialisiere das Array @hourlyForecastProduction mit 24 Nullen (oder entsprechend der Anzahl der Stunden von Sonnenaufgang bis Sonnenuntergang)
	my @hourlyForecastProduction = (0) x 24;
	# Lese stündliche Vorhersagewerte für PV-Produktion in das Array
	for (my $i = 1; $i <= 24; $i++) {
		if ($i>=$sunrise_hour && $i<= $sunset_hour){
			my $readingName = "Today_Hour" . sprintf("%02d", $i) . "_PVforecast";
			my $value = ReadingsVal($ForecastDev, $readingName, "0");
			
			# Extrahiere den numerischen Teil
			if ($value =~ /(\d+)/) {
				$value = $1;
			} else {
				$value = 0;	 # Fallback, falls kein numerischer Wert gefunden wird
			}
			# Wenn mehr als die maximale Lestung der PV Analge pro Stunde vorhergesagt wird stimmt das nicht.
			# Die Anlage kann nicht mehr Energie pro Stunde liefern als ihre maximale Leistung (E = P*t).
			if ( $value < $PVMaxPower){
				$hourlyForecastProduction[$i-1] = $value;  # Setze den Wert im Array
				$ForecastProdCalc = $ForecastProdCalc + $value;
			}
			else{
				$hourlyForecastProduction[$i-1] = $PVMaxPower;  # Setze den Wert im Array
				$ForecastProdCalc = $ForecastProdCalc + $PVMaxPower;
			}
		}else{
			$hourlyForecastProduction[$i-1] = 0;  # Setze den Wert im Array auf 0
		}
	}

	# Berechne die verbleibenden Stunden von Sonnenaufgang an bis die Produktion den Verbrauch übersteigt.
	my $remainingTime = 0;
	
	fhem ("setreading $SELF sunrise_hour $sunrise_hour");	
	fhem ("setreading $SELF sunset_hour $sunset_hour"); 
	for (my $i = $sunrise_hour; $i <= $sunset_hour; $i++) {
		my $Num = sprintf("%02d", $i);
		if ($hourlyForecastProduction[$i-1] > $hourlyForecastConsumption[$i-1]) {
			$remainingTime = $i - $sunrise_hour;
			last;
		}
	}
	fhem ("setreading $SELF RemainingTime $remainingTime");
	# Ist der Sonnenaufgang nach 5 Uhr addiere die Stunden zwischen 5 Uhr und Sonnenaufgang dazu
	if ($sunrise_hour > $EndHourCheapPower){
		$remainingTime += ($sunrise_hour - $EndHourCheapPower);
	}elsif($sunrise_hour < $EndHourCheapPower){
		$remainingTime -= ($EndHourCheapPower - $sunrise_hour);
	}
	$remainingTime += 1; # Um 1h korrigieren (Sicherheit)
	
	# Berechne nutzbare verbleibende Energie der Batterie
	my $BattUseRemaEner = ($PVBatSOC - $PVBatReserveSOC) / 100 * $PVBatCapa;
	
	# Berechne erforderliche Energie + 20% Reserve
	my $RequEnergieToday = ($ForecastCosum1 - $FoCaCosumDurCheapPower) * 1.2 ;
	#Berechne wieviel Energie geladen werden muss
	my $RequEnergieToCharge = ($RequEnergieToday - $ForecastProdCalc) - $BattUseRemaEner;

	my $EnergieToCharge = 0;
	
	# Readings ausgeben
	fhem ("setreading $SELF ForecastProd $ForecastProd");
	fhem ("setreading $SELF ForecastProdCalc $ForecastProdCalc"); 
	fhem ("setreading $SELF RemainingTime $remainingTime");		
	fhem ("setreading $SELF ForecastCosum $ForecastCosum");
	fhem ("setreading $SELF ForecastCosumCalc $ForecastCosum1");
	fhem ("setreading $SELF FoCaCosumDurCheapPower $FoCaCosumDurCheapPower");
	fhem ("setreading $SELF PVBatSOC $PVBatSOC");
	fhem ("setreading $SELF PVBatRese $PVBatRese");
	fhem ("setreading $SELF PVBatCapa $PVBatCapa");
	fhem ("setreading $SELF BattUseRemaEner $BattUseRemaEner");
	fhem ("setreading $SELF RequEnergieToday $RequEnergieToday");
	fhem ("setreading $SELF RequEnergieToCharge $RequEnergieToCharge");

	my $NewBatResvSOC = $PVBatReserveSOC;

	# Reicht die Energie für den Tag?
	if ($RequEnergieToCharge > 0)
	{
	#############################################################################################
	# Die Vorhersage sagt voraus, dass die Energie nicht ausreicht
	#############################################################################################

		# Wenn die zu ladende Energie mehr ist als die Batterie aufnehmen kann, den Wert auf das Maximum begrenzen
		if ($RequEnergieToCharge > ($PVBatCapa - $BattUseRemaEner) ){
			
			$EnergieToCharge = ($PVBatCapa - $BattUseRemaEner);
		}
		else
		{
			$EnergieToCharge = $RequEnergieToCharge;
		}
	}
	else{
	#############################################################################################
	# Die Vorhersage sagt mehr Energie voraus bzw. mit der rest Akku Energie ist mehr Energie verfügbar als während des Tages benötigt wird
	#############################################################################################
		
		# Berechne die benötigte Energie bis zur ausreichenden PV-Leistung
		my $requiredEnergyUntilSufficient = 0;

		for (my $i = $EndHourCheapPower; $i < ($EndHourCheapPower + $remainingTime); $i++) {
			if ($i < ($EndHourCheapPower + $remainingTime - 1)){
				$requiredEnergyUntilSufficient += ($hourlyForecastConsumption[$i - 1] - $hourlyForecastProduction[$i - 1]);
			}
			else{
				# Für die letzte Stunden wird die Produktion nicht abgezogen
				$requiredEnergyUntilSufficient += ($hourlyForecastConsumption[$i - 1]);
			}
			my $Num = sprintf("%02d", $i);
			fhem ("setreading $SELF hourlyForecastProduction$Num $hourlyForecastProduction[$i-1]"); 
			fhem ("setreading $SELF hourlyForecastConsumption$Num $hourlyForecastConsumption[$i-1]");
			
		}

		# Berechne die Differenz zwischen der verfügbaren Batteriekapazität und der benötigten Energie
		my $energyDeficit = $requiredEnergyUntilSufficient - $BattUseRemaEner;
		
		# Setze Reading für die Energiedefizit
		fhem ("setreading $SELF EnergyDeficit $energyDeficit");
			
		# Lade die Batterie, falls sie nicht genug Energie liefert
		if ($energyDeficit > 0) {
			$EnergieToCharge = $energyDeficit;
		} 
		else{
			# Die Batterie hat noch genügend Energie von 5 bis die PV-Leistung ausreicht. Aber reicht die Energie auch bis dahin?
			my $requiredEnergyUntilSufficient2 = 0;

			for (my $i = 1; $i < $EndHourCheapPower + $remainingTime; $i++) {
				if ($i < ($EndHourCheapPower + $remainingTime - 1)){
					$requiredEnergyUntilSufficient2 += ($hourlyForecastConsumption[$i - 1] - $hourlyForecastProduction[$i - 1]);
				}
				else{
					# Für die letzte Stunden wird die Produktion nicht abgezogen
					$requiredEnergyUntilSufficient2 += ($hourlyForecastConsumption[$i - 1]);
				}
				my $Num = sprintf("%02d", $i);
				fhem ("setreading $SELF hourlyForecastProduction$Num $hourlyForecastProduction[$i-1]"); 
				fhem ("setreading $SELF hourlyForecastConsumption$Num $hourlyForecastConsumption[$i-1]");
			
			}
			# Setze Reading für die benötigte Energie von jetzt bis zur ausreichenden PV-Leistung
			fhem ("setreading $SELF RequiredEnergyUntilSufficient2 $requiredEnergyUntilSufficient2");
		 
			# Berechne die Differenz zwischen der verfügbaren Batteriekapazität und der benötigten Energie
			my $energyDeficit2 = $requiredEnergyUntilSufficient2 - $BattUseRemaEner;
			
			# Setze Reading für die Energiedefizit
			fhem ("setreading $SELF EnergyDeficit2 $energyDeficit2");

			# Gibt es ein Energiedefizit, das Entladen der Batterie stoppen
			if ($energyDeficit2 > 0) {
				# Errechne wieviel Energie noch verbraucht werden kann
				my $UseableBattEnergie = $BattUseRemaEner - $requiredEnergyUntilSufficient;
				fhem ("setreading $SELF UseableBattEnergie $UseableBattEnergie");
				#Errechne neue Batterie Entladestand
				$NewBatResvSOC =  (100/$PVBatCapa*$UseableBattEnergie) + $PVBatReserveSOC;	
			} 
		}
	}

	$NewBatResvSOC = round($NewBatResvSOC, 0);	

	# Berechne die Laderate für die Batterie. Verwende eine fixe Dauer von 4,25 Stunden
	my $BattChargRate = $EnergieToCharge / 4.25;
	my $BattDisChargRate = $BattChargRate * (-1);

	fhem ("setreading $SELF EnergieToCharge $EnergieToCharge");
	fhem ("setreading $SELF BattChargRate $BattChargRate");
	fhem ("setreading $SELF BattDisChargRate $BattDisChargRate");
	fhem ("setreading $SELF NewBatResvSOC $NewBatResvSOC");
	
	# Setze die neue Batteriereserve falls notwendig
	if ($PVBatRese != $NewBatResvSOC){
		fhem ("set $PVBatterieDev $PVBatReseRead $NewBatResvSOC"); 
	}

	# Wenn die Laderate größer als 0 ist, starte das Laden der Batterie
	if ($BattChargRate > 0)
	{
		fhem ("set $PVBatterieDev $PVBatConfigMaxEnabledRead dischrMax"); 
		fhem ("set $PVBatterieDev $PVBatConfigMaxDischargeWattRead $BattDisChargRate"); 
	}
	
}