package main;

use strict;
use warnings;

sub RolladenAutomatik_Initialize {
  my ($hash) = @_;
  
  $hash->{DefFn}    = \&RolladenAutomatik_Define;
  $hash->{NotifyFn} = \&RolladenAutomatik_Notify;
  $hash->{AttrList} =
    "ZustSonneDev ZustSonneRead SonnenStandDev SonnenStandReadAzi SonnenStandReadElv "
  . "SonnenStandAziStart SonnenStandAziEnd SonnenStandElvStart SonnenStandElvEnd FenstPosEinbWink "
  . "RollladenDev PosBeschattung PosOffen PosZu "
  . "TempAussenDev TempAussenRead TempAussenMin "
  . "TempVorherDev TempVorherRead TempVorherMin "
  . "MaxFahrtenProTag:1,2,3,4,5,6,7,8,9,10,11,12,13,14 NachtsFahren:0,1 "
  . $main::readingFnAttributes;
}

sub RolladenAutomatik_Define {
  my ($hash, $def) = @_;
  my @args = split("[ \t]+", $def);
  return "Usage: define <name> RolladenAutomatik" if @args < 2;

  $hash->{NAME} = $args[0];
  $hash->{TYPE} = "RolladenAutomatik";
  return undef;
}

sub RolladenAutomatik_Notify {
  my ($hash, $dev) = @_;
  my $name    = $hash->{NAME};
  my $devName = $dev->{NAME}; # auslösendes Device

  return "" if (IsDisabled($name));                  # Modul deaktiviert
  return "" if ($hash->{TYPE} eq $dev->{TYPE});       # Endlosschleifen vermeiden

  # Attribute laden
  my $get = sub { my ($attr, $def) = @_; AttrVal($name, $attr, $def) };

  my $zustSonneDev   = $get->("ZustSonneDev", "System.Sonnenschein");
  my $zustSonneRead  = $get->("ZustSonneRead", "Zustand");
  my $sonnenDev      = $get->("SonnenStandDev", "System.Sonnenstand");
  my $aziRead        = $get->("SonnenStandReadAzi", "azimuth");
  my $elvRead        = $get->("SonnenStandReadElv", "elevation");
  my $aziStart       = $get->("SonnenStandAziStart", 90);
  my $aziEnd         = $get->("SonnenStandAziEnd", 300);
  my $elvStart       = $get->("SonnenStandElvStart", 0);
  my $elvEnd         = $get->("SonnenStandElvEnd", 90);
  my $einbauWinkel   = $get->("FenstPosEinbWink", 45);
  my $rolloDev       = $get->("RollladenDev", "");
  my $posBeschattung = $get->("PosBeschattung", 5);
  my $posOffen       = $get->("PosOffen", 100);
  my $posZu          = $get->("PosZu", 0);
  my $tempAussDev    = $get->("TempAussenDev", "OG.Balkon.Wetterstation");
  my $tempAussRead   = $get->("TempAussenRead", "ACTUAL_TEMPERATURE");
  my $tempAussMin    = $get->("TempAussenMin", 18);
  my $tempVorhDev    = $get->("TempVorherDev", "WetterProplanta");
  my $tempVorhRead   = $get->("TempVorherRead", "fc0_tempMax");
  my $tempVorhMin    = $get->("TempVorherMin", 18);
  my $maxFahrten     = $get->("MaxFahrtenProTag", 10);
  my $nachtsFahren   = $get->("NachtsFahren", 1);

  # --- Matches-Prüfung neu ---
  my $events  = $dev->{CHANGED} // [];
  my $changes = ref($events) eq 'ARRAY' ? join(", ", @$events) : "<keine CHANGED-Werte>";
  Log3 $name, 4, "RolladenAutomatik [$name]: Notify von '$devName' mit Änderungen: $changes";

  return undef if (ref($events) ne 'ARRAY' || !@$events);

  my $hasReading = sub {
    my ($reading) = @_;
    my $q = quotemeta($reading);
    return scalar grep { $_ =~ /^$q(?:[:\s]|$)/ } @$events;
  };

  my $matches = 0;
  $matches ||= ($devName eq $zustSonneDev && $hasReading->($zustSonneRead));
  $matches ||= ($devName eq $sonnenDev    && ($hasReading->($aziRead) || $hasReading->($elvRead)));
  $matches ||= ($devName eq $tempAussDev  && $hasReading->($tempAussRead));
  $matches ||= ($devName eq $tempVorhDev  && $hasReading->($tempVorhRead));

  Log3 $name, 4, "RolladenAutomatik [$name]: Matches=$matches";
  return undef unless $matches;
  # --- Ende Matches-Prüfung ---

  # Werte holen
  my $zustand        = ReadingsVal($name, "Zustand", 0);
  my $fahrtenZaehler = ReadingsVal($name, "FahrtenZaehler", 0);
  my $sonnenZust     = ReadingsVal($zustSonneDev, $zustSonneRead, 0); # 0=Nacht, 1=Wolkig, 2=Sonnig
  my $azi            = ReadingsVal($sonnenDev, $aziRead, 0);
  my $elv            = ReadingsVal($sonnenDev, $elvRead, 0);
  my $tempAussen     = ReadingsVal($tempAussDev, $tempAussRead, 0);
  my $tempVorh       = ReadingsVal($tempVorhDev, $tempVorhRead, 0);
  my $actRollPos     = ReadingsVal($rolloDev, "pct", 0);

  # Info-Readings schreiben
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "ZustandSonne", $sonnenZust);
  readingsBulkUpdate($hash, "Sonnenstand_Azimut", $azi);
  readingsBulkUpdate($hash, "Sonnenstand_Elevation", $elv);
  readingsBulkUpdate($hash, "Temperatur_Aussen", $tempAussen);
  readingsBulkUpdate($hash, "Temperatur_Vorhersage", $tempVorh);
  readingsBulkUpdate($hash, "Temperatur_Aussen_Min", $tempAussMin);
  readingsBulkUpdate($hash, "Temperatur_Vorhersage_Min", $tempVorhMin);
  readingsBulkUpdate($hash, "Aktuelle_Position_Rollo", $actRollPos);

  # Hauptlogik
  if ($zustand == 1) {
    if ($sonnenZust > 0) {
      fhem("set $rolloDev pct $posOffen") if $nachtsFahren;
      readingsBulkUpdate($hash, "Zustand", 2);
      readingsBulkUpdate($hash, "FahrtenZaehler", 0);
    }
  }
  elsif ($zustand == 2) {
    if ($sonnenZust == 0) {
      fhem("set $rolloDev pct $posZu") if $nachtsFahren;
      readingsBulkUpdate($hash, "Zustand", 1);
    }
    elsif ($sonnenZust == 2
      && ((($azi >= $aziStart && $azi < $aziEnd) && ($elv >= $elvStart && $elv < $elvEnd))
          || ($elv >= $einbauWinkel))
      && $tempAussen >= $tempAussMin
      && $tempVorh >= $tempVorhMin) {
      if ($actRollPos > $posBeschattung) {
        fhem("set $rolloDev pct $posBeschattung");
      }
      readingsBulkUpdate($hash, "Zustand", 3);
      readingsBulkUpdate($hash, "state", "Beschattung");
      $fahrtenZaehler++;
      readingsBulkUpdate($hash, "FahrtenZaehler", $fahrtenZaehler);
    }
  }
  elsif ($zustand == 3) {
    if ((($sonnenZust == 1 && $fahrtenZaehler < $maxFahrten)
         || ($azi < $aziStart || $azi > $aziEnd || $elv < $elvStart || $elv > $elvEnd)
            && $elv < $einbauWinkel)) {
      if ($actRollPos == $posBeschattung) {
        fhem("set $rolloDev pct $posOffen");
      }
      readingsBulkUpdate($hash, "Zustand", 2);
      readingsBulkUpdate($hash, "state", "Offen");
    }
    elsif ($sonnenZust == 0) {
      fhem("set $rolloDev pct $posZu") if $nachtsFahren;
      readingsBulkUpdate($hash, "Zustand", 1);
      readingsBulkUpdate($hash, "state", "Nacht");
    }
  }
  else {
    readingsBulkUpdate($hash, "Zustand", 1);
    readingsBulkUpdate($hash, "state", "Nacht");
  }

  readingsEndUpdate($hash, 1);
  return undef;
}

sub RolladenAutomatik_AttrFn {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  if ($cmd eq "set") {
    if ($attrName eq "MaxFahrtenProTag") {
      return "Ungültiger Wert für MaxFahrtenProTag (erlaubt: 1–14)"
        unless ($attrVal =~ /^(?:1[0-4]?|[2-9]|1)$/);
    }
    if ($attrName eq "NachtsFahren") {
      return "Ungültiger Wert für NachtsFahren (erlaubt: 0 oder 1)"
        unless ($attrVal eq "0" || $attrVal eq "1");
    }
  }

  return undef;
}

1;