Aussen.SuedOst.Lichtsensor:CURRENT_ILLUMINATION:.*|OG.Balkon.Wetterstation:ILLUMINATION:.*|System.Sonnenstand:elevation:.* {

# Berechne relative Helligkeit je nach Sonnenstand (für wetterabhängige Gewichtung)
# Wenn Elevation zu niedrig, wird mit festen Grenzwerten gearbeitet

# Setze Zustand (0 = Nacht, 1 = Wolkig, 2 = Sonnig) basierend auf Schwellenwerten und Wechselbedingungen
# Verwende Hysterese, um zu vermeiden, dass Zustand zu häufig wechselt

# Aktualisiere lesbaren Zustand für GUI/Visualisierung


    # 📡 Gerätekonfiguration für Helligkeitssensoren einlesen
	my $vHellSensor1Dev = AttrVal($SELF, "HelligkeitSensor1Dev","Aussen.SuedOst.Lichtsensor");
	my $vHellSensor1Read = AttrVal($SELF, "HelligkeitSensor1Read","CURRENT_ILLUMINATION");
	my $vHellSensor2Dev = AttrVal($SELF, "HelligkeitSensor2Dev","OG.Balkon.Wetterstation");
	my $vHellSensor2Read = AttrVal($SELF, "HelligkeitSensor2Read","ILLUMINATION");
	
	# 🔆 Referenzwerte für Sonne und Wolken
	my $vHelligkeitSonne1  = AttrVal($SELF, "HelligkeitSonne1","30000");
	my $vHelligkeitWolke1  = AttrVal($SELF, "HelligkeitWolke1","15000");
	my $vHelligkeitSonne2  = AttrVal($SELF, "HelligkeitSonne2","8000");
	my $vHelligkeitWolke2  = AttrVal($SELF, "HelligkeitWolke2","3000");
	
	# 🔄 Aktuelle Zustandswerte abrufen
	my $vZustand  = ReadingsVal($SELF, "Zustand",0);
	my $vWechselZuWolken  = ReadingsVal($SELF, "WechselZuWolken",0);
	my $vWechselZuSonne  = ReadingsVal($SELF, "WechselZuSonne",0);
	
	# ☀️ Sonnenstandkonfiguration für Helligkeitsgewichtung
    my $vSonnenstandDev = AttrVal($SELF, "SonnenstandDev","System.Sonnenstand");
	my $vSonnenstandReadAzi = AttrVal($SELF, "SonnenstandReadAzi","azimuth");
	my $vSonnenstandReadElev = AttrVal($SELF, "SonnenstandReadElev","elevation");
	my $vZeitunterschiedZuSonne = AttrVal($SELF, "MindZeitunterschiedWechselSonne",5);	
	my $vZeitunterschiedZuWolken = AttrVal($SELF, "MindZeitunterschiedWechselWolken",40);	
	
	# 📥 Sensorwerte und Sonnenstand auslesen
	my $vHelligkeit1 = ReadingsVal($vHellSensor1Dev,$vHellSensor1Read, "0");
	my $vHelligkeit2 = ReadingsVal($vHellSensor2Dev,$vHellSensor2Read, "0");
	my $vAzimuth = ReadingsVal($vSonnenstandDev,$vSonnenstandReadAzi, "0");
	my $vElevation = ReadingsVal($vSonnenstandDev,$vSonnenstandReadElev, "0");
	
	# 🕒 Letzte Umschaltzeit abrufen (zur Hysterese-Berechnung)
	my $vUhrStundeLast = ReadingsVal($SELF, "UhrStundeLast", 0);
	my $vUhrMinuteLast = ReadingsVal($SELF, "UhrMinuteLast", 0);
	my $vUhrzeitStunde = POSIX::strftime("%H", localtime);
	my $vUhrzeitMinute = POSIX::strftime("%M", localtime);

	my $vElevationMax = 65;
	my $vHelligkeitSonne1Berech = 0;
	my $vHelligkeitSonne2Berech = 0;
	my $vHelligkeitWolke1Berech = 0;
	my $vHelligkeitWolke2Berech = 0;

	my $vZeitunterschied = 0;
	# ⏱ Zeitunterschied zum letzten Zustandswechsel berechnen (nur bei aktivem Wechsel)
	if ($vWechselZuSonne == 1 || $vWechselZuWolken == 1 ){
		# Zeitunterschied ist nur relevant wenn auch ein Wechsel an steht
		if (($vUhrzeitStunde - $vUhrStundeLast) >= 0) 
		{
			$vZeitunterschied = ($vUhrzeitStunde - $vUhrStundeLast) * 60 + ($vUhrzeitMinute - $vUhrMinuteLast);
		}
		else
		{
			$vZeitunterschied = ($vUhrzeitStunde - $vUhrStundeLast + 24) * 60 + ($vUhrzeitMinute - $vUhrMinuteLast);
		}
	}
	
	# 🧪 Debug-Werte zur Analyse setzen
	fhem("setreading $SELF Helligkeit1 $vHelligkeit1");
	fhem("setreading $SELF Helligkeit2 $vHelligkeit2");
	fhem("setreading $SELF ZeitunterschiedMinute $vZeitunterschied");

	# ☀️ Relative Helligkeit je nach Sonnenhöhe berechnen (lineare Gewichtung)
	if ($vElevation >= 2)
	{
		$vHelligkeitSonne1Berech = sprintf("%.1f",$vHelligkeitSonne1 * $vElevation / $vElevationMax);
		$vHelligkeitSonne2Berech = sprintf("%.1f",$vHelligkeitSonne2 * $vElevation / $vElevationMax);
		$vHelligkeitWolke1Berech = sprintf("%.1f",$vHelligkeitWolke1 * $vElevation / $vElevationMax);
		$vHelligkeitWolke2Berech = sprintf("%.1f",$vHelligkeitWolke2 * $vElevation / $vElevationMax);	
	}
	else
	{
		$vHelligkeitSonne1Berech = $vHelligkeitSonne1;
		$vHelligkeitSonne2Berech = $vHelligkeitSonne2;
		$vHelligkeitWolke1Berech = $vHelligkeitWolke1;
		$vHelligkeitWolke2Berech = $vHelligkeitWolke2;	
	}
	
	# 🧾 Berechnete Referenzwerte ins Reading schreiben
	fhem("setreading $SELF HelligkeitSonne1Berechnet $vHelligkeitSonne1Berech");
	fhem("setreading $SELF HelligkeitSonne2Berechnet $vHelligkeitSonne2Berech");
	fhem("setreading $SELF HelligkeitWolke1Berechnet $vHelligkeitWolke1Berech");
	fhem("setreading $SELF HelligkeitWolke2Berechnet $vHelligkeitWolke2Berech");
	
	my $LichtStatus = 99; # Unbestimmt
	
	# 💡 Helligkeit bewerten → 0 = Nacht, 1 = Wolkig, 2 = Sonnig, 99 = unklar
	if (($vHelligkeit1 < 10) && ($vHelligkeit2 < 5)) {
		$LichtStatus = 0;  # Nacht
	}
	elsif (($vHelligkeit1 > 100) && ($vHelligkeit2 > 50) && ($vElevation >= 2)) {
		if (($vHelligkeit1 > $vHelligkeitSonne1Berech) || ($vHelligkeit2 > $vHelligkeitSonne2Berech)) {
			$LichtStatus = 2;  # Sonnig
		}
		elsif (($vHelligkeit1 < $vHelligkeitWolke1Berech) && ($vHelligkeit2 < $vHelligkeitWolke2Berech)) {
			$LichtStatus = 1;  # Wolkig
		}
	}	
	
	# 🎛 Zustandswechsel mit Hysterese-Logik verarbeiten
	# Ziel: Wechsel nur nach definierter Zeitspanne → reduziert Flackern durch schwankende Werte
	if ($LichtStatus == 0) {
		$vZustand = 0;
	}
	elsif ($LichtStatus == 1) { #Wolken - Helligkeitswerte für Wolken erreicht
		if ($vZustand == 2 && $vWechselZuWolken == 0) {
			$vWechselZuWolken = 1; # Wechselstatus setzen
			$vWechselZuSonne = 0; # Wechselstatus zurücksetzten
			$vZeitunterschied = 0; # Zeit unterschied zurücksetzten
			fhem("setreading $SELF UhrStundeLast $vUhrzeitStunde"); # Neue Zeit speichern
			fhem("setreading $SELF UhrMinuteLast $vUhrzeitMinute");
		}
		if ($vZeitunterschied > $vZeitunterschiedZuWolken && $vWechselZuWolken == 1) {
			# Status auf Sonne setzen
			$vWechselZuWolken = 0; # Wechselstatus zurücksetzten
			$vWechselZuSonne = 0; # Wechselstatus zurücksetzten
			$vZustand = 1;
		}
	}
		elsif ($LichtStatus == 2) { # Sonne - Helligkeits werte für Sonne erreicht
		if ($vZustand == 1 && $vWechselZuSonne == 0) {
			$vWechselZuWolken = 0; # Wechselstatus zurücksetzten
			$vWechselZuSonne = 1; # Wechselstatus setzen
			$vZeitunterschied = 0; # Zeit unterschied zurücksetzten
			fhem("setreading $SELF UhrStundeLast $vUhrzeitStunde"); # Neue Zeit speichern
			fhem("setreading $SELF UhrMinuteLast $vUhrzeitMinute");	
		}
		if ((($vZeitunterschied > $vZeitunterschiedZuSonne) && ($vWechselZuSonne == 1)) || ($vZustand == 0)) {
			$vWechselZuWolken = 0; # Wechselstatus zurücksetzten
			$vWechselZuSonne = 0; # Wechselstatus zurücksetzten
			$vZustand = 2;
		}
	} else {
		# Lichtverhältnisse sind unklar - Wechsel status zurücksetzten, letzten Zustand beibehalten
		$vWechselZuWolken = 0;
		$vWechselZuSonne = 0;
	}
	
	# 📄 Lesbaren Zustand zur besseren Interpretation setzen
	my $vState = "Nicht Init";
	if ($vZustand == 0) {
		$vState = "Nacht";
	}
	elsif ($vZustand == 1) {
		$vState = "Wolkig";
	}
	elsif ($vZustand == 2) {
		$vState = "Sonnig";
	}
	else {
		$vState = "Unbekannt";
	}
	
	# 📤 Zustandswerte ins System schreiben
	fhem("setreading $SELF state $vState");	
	fhem("setreading $SELF LichtStatus $LichtStatus");
	fhem("setreading $SELF Zustand $vZustand");
	fhem("setreading $SELF WechselZuWolken $vWechselZuWolken");
	fhem("setreading $SELF WechselZuSonne $vWechselZuSonne");
}