System.Sonnenschein:Zustand:.*|System.Sonnenstand:azimuth:.*|System.Sonnenstand:elevation:.* {
    
	#V00.01.04
	
	# Auslesen der eigenen Attribute
	# Sonnenzustands Attribute lesen
	my $vZustSonneDev  = AttrVal($SELF, "ZustSonneDev","System.Sonnenschein");
	my $vZustSonneRead = AttrVal($SELF, "ZustSonneRead","Zustand");
	# Sonnenstand Attribute lesen
	my $vSonnenStandDev  = AttrVal($SELF, "SonnenStandDev","System.Sonnenstand");
	my $vSonnenStandReadAzi = AttrVal($SELF, "SonnenStandReadAzi","azimuth");
	my $vSonnenStandReadElv = AttrVal($SELF, "SonnenStandReadElv","elevation");
	my $SonnenStandAziStart = AttrVal($SELF, "SonnenStandAziStart","90");
	my $SonnenStandAziEnd = AttrVal($SELF, "SonnenStandAziEnd","300");
	my $SonnenStandElvStart = AttrVal($SELF, "SonnenStandElvStart","0");
	my $SonnenStandElvEnd = AttrVal($SELF, "SonnenStandElvEnd","90");
	my $FenstPosEinbWink = AttrVal($SELF, "FenstPosEinbWink","45");
	
	# Rollanden Attribute lesen
	my $vRollladenDev = AttrVal($SELF, "RollladenDev","");
	my $vPosBeschattung  = AttrVal($SELF, "PosBeschattung","5");
	my $vPosOffen  = AttrVal($SELF, "PosOffen","100");  
	my $vPosZu  = AttrVal($SELF, "PosZu","0");
	my $ActPosRoll = ReadingsVal($vRollladenDev, "pct" , "0");
	
	# Aussen Temperatur Attribute lesen 
	my $vTempAussenDev   = AttrVal($SELF, "TempAussenDev","OG.Balkon.Wetterstation");
	my $vTempAussenRead  = AttrVal($SELF, "TempAussenRead","ACTUAL_TEMPERATURE");
	my $vTempAussenMin  = AttrVal($SELF, "TempAussenMin","18");
	# Vorhersage Temperatur Attribute lesen 
	my $vTempVorherDev = AttrVal($SELF, "TempVorherDev ","WetterProplanta");
	my $vTempVorherRead = AttrVal($SELF, "TempVorherRead","fc0_tempMax");
	my $vTempVorherMin = AttrVal($SELF, "TempVorherMin","18");
	# Einstellungen lesen
	my $vMaxFahrtenProTag = AttrVal($SELF, "MaxFahrtenProTag","10");
	my $vNachtsFahren = AttrVal($SELF, "NachtsFahren","1");
	# Lesen des letzten Zustands
	my $vZustand = ReadingsVal($SELF, "Zustand",0);
	my $vFahrtenZaehler = ReadingsVal($SELF, "FahrtenZaehler",0);

	# Auslesen der benötigten Werte
	my $vZustandSonne = ReadingsVal($vZustSonneDev,$vZustSonneRead, "0"); #0=Nacht 1=Wolken 2=Sonne
	my $vSonnenStandAzi = ReadingsVal($vSonnenStandDev,$vSonnenStandReadAzi, "0"); 
	my $vSonnenStandElv = ReadingsVal($vSonnenStandDev,$vSonnenStandReadElv, "0"); 
	my $vTempAussen= ReadingsVal($vTempAussenDev,$vTempAussenRead, "0"); 
	my $vTempVorher = ReadingsVal($vTempVorherDev,$vTempVorherRead, "0"); 
	
	#Info Readings setzten
	fhem("setreading $SELF ZustandSonne $vZustandSonne");
	fhem("setreading $SELF Sonnenstand_Azimut $vSonnenStandAzi");
	fhem("setreading $SELF Sonnenstand_Elevation $vSonnenStandElv");
	fhem("setreading $SELF Temperatur_Aussen $vTempAussen");
	fhem("setreading $SELF Temperatur_Vorhersage $vTempVorher");
	fhem("setreading $SELF Temperatur_Vorhersage_Min $vTempVorherMin");
	fhem("setreading $SELF Temperatur_Aussen_Min $vTempAussenMin");
	fhem("setreading $SELF Aktuelle_Position_Rollo $ActPosRoll");

	if ($vZustand == 1) # Nacht Modus
	{ 	
		# Nacht Modus
		if (($vZustandSonne > 0))
		{
			if ($vNachtsFahren == 1){ fhem ("set $vRollladenDev pct $vPosOffen");}
			fhem ("setreading $SELF Zustand 2");
			fhem ("setreading $SELF FahrtenZaehler 0");
		}
	}
	elsif ($vZustand == 2) # Tag Modus Bewölkt
	{ 
		
	   if ($vZustandSonne == 0)
	   {
		   if ($vNachtsFahren == 1) {fhem ("set $vRollladenDev pct $vPosZu");}
		   fhem ("setreading $SELF Zustand 1");
	   }
	   elsif (
	   ($vZustandSonne == 2) # Prüfe Sonne ob da
	   && ((($vSonnenStandAzi >= $SonnenStandAziStart) && ($vSonnenStandAzi < $SonnenStandAziEnd) # Prüfe Sonnenstand Richtung (azimuth)
	   && ($vSonnenStandElv >= $SonnenStandElvStart) && ($vSonnenStandElv < $SonnenStandElvEnd)) # Prüfe Sonnenstand Höhe (elevation)
	   || ($vSonnenStandElv >= $FenstPosEinbWink))
	   && ($vTempAussen >= $vTempAussenMin) # Prüfe Aussentemperatur
	   && ($vTempVorher >= $vTempVorherMin) # Prüfe Vorhersagetempertur
	   )
	   {
			if ($ActPosRoll>$vPosBeschattung){ # Nur fahren wenn der Rolladen weiter geöffnet ist
				fhem ("set $vRollladenDev pct $vPosBeschattung");
			}
			fhem ("setreading $SELF Zustand 3");
			$vFahrtenZaehler = $vFahrtenZaehler + 1;
			fhem ("setreading $SELF FahrtenZaehler $vFahrtenZaehler");
	   }
	}
	elsif ($vZustand == 3) # Beschattungs Modus
	{
		if 
		(			
		(($vZustandSonne == 1) && ($vFahrtenZaehler < $vMaxFahrtenProTag))	# Sonnen nicht mehr da und maximale anzahl der Fahren pro Tag noch nicht überschritten	
		|| (($vSonnenStandAzi < $SonnenStandAziStart) # Prüfe Sonnenstand Richtung (azimuth)
		|| ($vSonnenStandAzi > $SonnenStandAziEnd)  # Prüfe Sonnenstand Richtung (azimuth)
		|| ($vSonnenStandElv < $SonnenStandElvStart) # Prüfe Sonnenstand Höhe (elevation)
		|| ($vSonnenStandElv > $SonnenStandElvEnd)) # Prüfe Sonnenstand Höhe (elevation)	
		&& ($vSonnenStandElv < $FenstPosEinbWink)		
		)
	   {
			if ($ActPosRoll=$vPosBeschattung){ # Nur öffen wenn der Rolladen noch auf Position ist
				fhem ("set $vRollladenDev pct $vPosOffen");
			}
			fhem ("setreading $SELF Zustand 2");			
	   }
	   elsif ($vZustandSonne == 0) # Direkt in den Nachtmodus
	   { 
		   if ($vNachtsFahren == 1) {fhem ("set $vRollladenDev pct $vPosZu");}
		   fhem ("setreading $SELF Zustand 1");
	   }
	}
	else 
	{
		#Wenn Zustand undefiniert setzte auf 1
		fhem ("setreading $SELF Zustand 1");
	}
	
}