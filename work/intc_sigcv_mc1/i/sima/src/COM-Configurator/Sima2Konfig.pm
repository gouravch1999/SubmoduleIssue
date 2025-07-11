package Sima2Konfig;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(sima2konfig);

use strict;
use warnings;
use Encode;
use lib '.';

use XLSX2SIMA qw(trim);
use XLSX qw(XLSX_ErrorHandling XLSX_SetColumns);

use Win32::OLE;
use Win32::OLE::Const 'Microsoft Excel';
use Win32::OLE::Variant;

my %bus_signale;
my %sys_signale;
my %mappings;
my %pdu_mapping;
my %bus_mapping;
my %pdu_secured;
my %col; # for Excel columns
	
my %bus_signale2mapping;

# sima2konfig
# wandelt datamodel.xml in Excel-Dokument um
# Aufruf: sima2konfig("datamodel.xml", "signalmapping.xlsx", $nicht_gemappte_ausgeben, $versionsstring);
# $nicht_gemappte_ausgeben: Signale / Variablen, die nicht mit Variablen / Signalen gemappt sind, werden am Ende durch Leerzeilen getrennt ausgegeben
# $versionsstring: String in der Form "2014_06_03", um zu prüfen, dass das Excel-Dokument nur mit der Version des COM-Configurators gelesen wird, mit der es geschrieben wurde
# Rückgabewert bei Erfolg: "", sonst ein String, der eine Fehlermeldung enthält
sub sima2konfig
{
	(my $input_file, my $output_file, my $nicht_gemappte_ausgeben, my $version) = @_;
	
	open(INPUT, $input_file) or return "Could not open $input_file: $!";

	# globale Datenstrukturen leeren
	%bus_signale = ();
	%sys_signale = ();
	%mappings = ();
	%pdu_mapping = ();
	%bus_mapping = ();
	%pdu_secured = ();

	# hash reference to Excel columns (Column name -> Excel column; e.g. "Signal" -> "A")
	my $hrCol = XLSX_SetColumns();
	%col = %$hrCol;
	
	# Handle für Excel erzeugen
	my $handle = Win32::OLE->new('Excel.Application');
	# Excel nicht anzeigen
	$handle->{Visible} = 0;	
	# Leeres Dokument anlegen
	my $book = $handle->Workbooks->Add();

	# Arbeitsblätter anlegen
	$book->Worksheets(1)->{Name} = "Signalmapping";
	if(!$book->Worksheets(2))
	{
		$book->Worksheets->Add( { after => $book->Worksheets("Signalmapping") } );
	}
	$book->Worksheets(2)->{Name} = "Bus mapping";
	if(!$book->Worksheets(3))
	{
		$book->Worksheets->Add( { after => $book->Worksheets("Bus mapping") } );
	}
	$book->Worksheets(3)->{Name} = "Version information";

	# Excel-Fehler prüfen
	my $msg = XLSX_ErrorHandling($handle, $book, "Error on creating $output_file");
	if($msg ne "")
	{
		return $msg;
	}
	
	# Überflüssige Seiten löschen
	while($book->Worksheets(4))
	{
		$book->Worksheets(4)->Delete();
	}
	
	# Versionsinformation schreiben
	my $wsVersion = $book->Worksheets("Version information");
	$wsVersion->Range("A1")->{Value} = "Created with COM-Configurator version:";
	$wsVersion->Range("A2")->{NumberFormat} = "\@";
	$wsVersion->Range("A2")->{Value} = $version;

	# datamodel.xml lesen
	while(<INPUT>)
	{
		chomp;
	
		if(/<BUS_SIGNAL>/)
		{
			read_bus_sig();
		}
		elsif(/<SYS_SIGNAL>/)
		{
			read_sys_sig();
		}
		elsif(/<MAPPING ID="(.*)">/)
		{
			read_mapping($1);
			# Mapping als nicht in Variant referenziert initialisieren
			$mappings{$1}->{ref} = 0;
		}
		elsif(/<MAPPING_REF>(\w+)<\/MAPPING_REF>/)
		{
			# Mapping wird in Variant referenziert
			$mappings{$1}->{ref} = 1;
		}
		elsif(/<PDU>/)
		{
			# Signal-zu-PDU-Mapping lesen
			read_pdu_mapping();
		}
		elsif(/<BUSREF>/)
		{
			# PDU-zu-Bus-Mapping lesen
			read_busref();
		}
	}
	close(INPUT);

	# Signalmapping schreiben
	my %gemappte_signale;
	my %gemappte_variablen;
	
	my $wsSignalMap = $book->Worksheets("Signalmapping");
	$wsSignalMap->Activate();

	# Titelzeile
	foreach my $key ( keys %col )
	{
		$wsSignalMap->Range($col{$key}."1")->{Value}=$key;
	}
	
	#$wsSignalMap->Range("A1:AF1")->{Value} = [
	#	"Signal", 							# COL_A -> column_Signal
	#	"Dir",									# COL_B -> column_Dir
	#	"Type (Bus)",						# COL_C -> column_TypeBus
	#	"Init value (Bus)",			# COL_D -> column_InitValueBus
	#	"Invalid value (Bus)",	# COL_E -> column_InvalidValueBus
	#	"Description",					# COL_F -> column_Description
	#	"Resolution (Bus)",			# COL_G -> column_ResolutionBus
	#	"Offset (Bus)",					# COL_H -> column_OffsetBus
	#	"Phy. Min. (Bus)",			# COL_I -> column_PhyMinBus
	#	"Phy. Max. (Bus)",			# COL_J -> column_PhyMaxBus
	#	"Unit (Bus)",						# COL_K -> column_UnitBus
	#	"Logical values (Bus)",	# COL_L -> column_LogicalValuesBus
	#	"Variable",							# COL_M -> column_Variable
	#	"Type (int)",						# COL_N -> column_TypeInt
	#	"Init value (int)",			# COL_O -> column_InitValueInt
	#	"Description",					# COL_P -> column_Description
	#	"Resolution (int)",			# COL_Q -> column_ResolutionInt
	#	"Offset (int)",					# COL_R -> column_OffsetInt
	#	"Phy. Min. (int)",			# COL_S -> column_PhyMinInt
	#	"Phy. Max. (int)",			# COL_T -> column_PhyMaxInt
	#	"Unit",									# COL_U -> column_Unit
	#	"Logical values (int)",	# COL_V -> column_LogicalValuesInt
	#	"Processing",						# COL_W -> column_Processing
	#	"Oor",									# COL_X -> column_Oor
	#	"External conversion",	# COL_Y -> column_ExternalConversion
	#	"Text mappings",				# COL_Z -> column_TextMappings
	#	"Pre conv. callout",		# COL_AA -> column_PreConvCallout
	#	"Post conv. callout",		# COL_AB -> column_PostConvCallout
	#	"Init handling",				# COL_AC -> column_InitHandling
	#	"Invalid handling",			# COL_AD -> column_InvalidHandling
	#	"PDU",									# COL_AE -> column_PDU
	#	"unhandled values"			# COL_AF -> column_UnhandledValues
	#];
	
	# gemappte und in Variant referenzierte Signale ausgeben
	my $i = 2;
	foreach my $bus (sort(keys(%bus_signale2mapping)))
	{
		my $m = $bus_signale2mapping{$bus};
		if($mappings{$m}->{ref})
		{
			my $sys = $mappings{$m}->{sys_signal};
			
			$gemappte_signale{$bus} = 1;
			$gemappte_variablen{$sys} = 1;
			
			bussignal_schreiben($bus, $wsSignalMap, $i);
			variable_schreiben($sys, $wsSignalMap, $i);
			mapping_schreiben($m, $wsSignalMap, $i);
			
			# Signal-zu-PDU-Mapping ausgeben
			$wsSignalMap->Range($col{'PDU'} . $i)->{Value} = $pdu_mapping{$bus}->{pdu};
			
			nicht_gemappte_werte_schreiben($bus, $sys, $m, $wsSignalMap, $i);

			$i++;
		}
	}

	# Nicht in Variant referenzierte Signale ausgeben (entspricht obigem foreach, bis auf if(!$mappings{$m}->{ref}))
	my $erstes = 1;
	foreach my $bus (sort(keys(%bus_signale2mapping)))
	{
		my $m = $bus_signale2mapping{$bus};
		if(!$mappings{$m}->{ref})
		{
			if($erstes)
			{
				$i += 2;
				$wsSignalMap->Range($col{'Signal'} . $i)->{Value} = "Mappings not referenced in variant";
				$erstes = 0;
				$i++;
			}
			
			my $sys = $mappings{$m}->{sys_signal};
			
			$gemappte_signale{$bus} = 1;
			$gemappte_variablen{$sys} = 1;
			
			bussignal_schreiben($bus, $wsSignalMap, $i);
			variable_schreiben($sys, $wsSignalMap, $i);
			mapping_schreiben($m, $wsSignalMap, $i);
			nicht_gemappte_werte_schreiben($bus, $sys, $m, $wsSignalMap, $i);
			
			$i++;
		}
	}

	# Nicht gemappte Signale ausgeben
	if($nicht_gemappte_ausgeben)
	{
		$i += 2;
		$wsSignalMap->Range($col{'Signal'} . $i)->{Value} = "Not mapped signals";
		$i++; # next line
		my $j = $i; # remember start of not mapped bus signals
		foreach my $bus (sort(keys(%bus_signale)))
		{
			if(!defined($gemappte_signale{$bus}))
			{
				bussignal_schreiben($bus, $wsSignalMap, $i);
				
				$i++;
			}
		}
		foreach my $sys (sort(keys(%sys_signale)))
		{
			if(!defined($gemappte_variablen{$sys}))
			{
				variable_schreiben($sys, $wsSignalMap, $i);
				
				$i++;
			}
		}
		
		# Special function to generate variable name on base of bus signal
		$i = $j; # go back to line of not mapped bus signals
		foreach my $bus (sort(keys(%bus_signale)))
		{
			if(!defined($gemappte_signale{$bus}))
			{
				my $value;
				if (!defined($value = $wsSignalMap->Range($col{'Variable'} . $i)->{Value}) or ($value eq ""))
				{
					# generate variable name but only if variable name is not already set
					my $var_name = lc($bus_signale{$bus}->{typ}). $bus; # concatenate lower case of type with signal name
					$var_name =~ s/([A-Z])([A-Z]+)/$1\L$2/g; # take care for correct camel case (no two upper case letters in succession)
					$var_name =~ s/(_+|\s+)([A-Za-z0-9]{1,1})/\U$2/g; # e.g. replace _A by A or _b by B
					$var_name =~ s/^flag/b/; # replace flag by b
					$wsSignalMap->Range($col{'Variable'} . $i)->{Value} = $var_name;
				}
				$i++;
			}
		}
	}
	# Spaltenbreite für Signal und Variable automatisch anpassen
	$wsSignalMap->Range($col{'Signal'} . "1:" . $col{'Signal'} . $i)->Columns->AutoFit;
	$wsSignalMap->Range($col{'Variable'} . "1:" . $col{'Variable'} . $i)->Columns->AutoFit;
	
	# Spaltenbreite für Callouts auf 20 festsetzen und Blocksatz wählen (damit läuft der längere Text nicht in die nächste Spalte über)
	$wsSignalMap->Range($col{'Processing'} . "1:" . $col{'Processing'} . $i)->{ColumnWidth} = 20; # Processing
	$wsSignalMap->Range($col{'Processing'} . "1:" . $col{'Processing'} . $i)->{HorizontalAlignment} = xlJustify; 
	$wsSignalMap->Range($col{'Oor'} . "1:" . $col{'Oor'} . $i)->{ColumnWidth} = 20; # Oor
	$wsSignalMap->Range($col{'Oor'} . "1:" . $col{'Oor'} . $i)->{HorizontalAlignment} = xlJustify;
	$wsSignalMap->Range($col{'External conversion'} . "1:" . $col{'External conversion'} . $i)->{ColumnWidth} = 20; # External conversion
	$wsSignalMap->Range($col{'External conversion'} . "1:" . $col{'External conversion'} . $i)->{HorizontalAlignment} = xlJustify;
	$wsSignalMap->Range($col{'Pre conv. callout'} . "1:" . $col{'Pre conv. callout'} . $i)->{ColumnWidth} = 20; # Pre conv. callout
	$wsSignalMap->Range($col{'Pre conv. callout'} . "1:" . $col{'Pre conv. callout'} . $i)->{HorizontalAlignment} = xlJustify;
	$wsSignalMap->Range($col{'Post conv. callout'} . "1:" . $col{'Post conv. callout'} . $i)->{ColumnWidth} = 20; # Post conv. callout
	$wsSignalMap->Range($col{'Post conv. callout'} . "1:" . $col{'Post conv. callout'} . $i)->{HorizontalAlignment} = xlJustify;
	$wsSignalMap->Range($col{'Init handling'} . "1:" . $col{'Init handling'} . $i)->{ColumnWidth} = 20; # Init handling
	$wsSignalMap->Range($col{'Init handling'} . "1:" . $col{'Init handling'}. $i)->{HorizontalAlignment} = xlJustify;
	$wsSignalMap->Range($col{'Invalid handling'} . "1:" . $col{'Invalid handling'} . $i)->{ColumnWidth} = 20; # Invalid handling
	$wsSignalMap->Range($col{'Invalid handling'} . "1:" . $col{'Invalid handling'} . $i)->{HorizontalAlignment} = xlJustify;

	for(my $j = 2; $j < $i; $j++)
	{
		$wsSignalMap->Rows($j)->{RowHeight} = 15;

		# Zeilenumbruch für Beschreibung, Einheit, Logische Werte einschalten
		foreach my $c ($col{'Description (Bus)'}, $col{'Unit (Bus)'}, $col{'Logical values (Bus)'} , $col{'Description (int)'}, $col{'Unit (int)'}, $col{'Logical values (int)'}, $col{'Text mappings'})
		{
			$wsSignalMap->Range($c . $j)->{WrapText} = 1;
		}
		
		# Korrekte Darstellung von Kommazahlen für Auflösung, Offset, Min- und Max-Wert einstellen
		foreach my $c ($col{'Resolution (Bus)'}, $col{'Offset (Bus)'}, $col{'Phy. Min. (Bus)'}, $col{'Phy. Max. (Bus)'}, $col{'Resolution (int)'}, $col{'Offset (int)'}, $col{'Phy. Min. (int)'}, $col{'Phy. Max. (int)'})
		{
			if(defined($wsSignalMap->Range($c . $j)->{Value}) && ($wsSignalMap->Range($c . $j)->{Value} =~ /\./))
			{
				$wsSignalMap->Range($c . $j)->{NumberFormat} = "0,#############################";
			}
			else
			{
				#$wsSignalMap->Range($c . $j)->{NumberFormat} = "\@";
			}
		}
	}

	# Bus-mapping schreiben
	my $wsBusMap = $book->Worksheets("Bus mapping");
	$wsBusMap->Activate();
	
	# Titelzeile
	$wsBusMap->Range("A1:C1")->{Value} = [ "Bus", "PDU", "secured" ];
	
	$i = 2;
	foreach my $bus (sort(keys(%bus_mapping)))
	{
		foreach my $pdu (sort(@{$bus_mapping{$bus}}))
		{
			$wsBusMap->Range("A" . $i)->{Value} = $bus;
			$wsBusMap->Range("B" . $i)->{Value} = $pdu;
			$wsBusMap->Range("C" . $i)->{Value} = $pdu_secured{$pdu};
			$i++;
		}
	}

	# Signalmapping-Blatt wählen
	$wsSignalMap->Activate();

	# Excel sichtbar machen und Dokument speichern
	$handle->{Visible} = 1;	
	$book->SaveAs($output_file);

	return "";
}


# bussignal_schreiben
# schreibt den ersten Teil der Zeile im Excel-Dokument, der die Informationen über das Bussignal enthält
# bestimmt Werte für Auflösung, Offset, Min-, Max- und Logische-Werte aus den Informationen in datamodel.xml
# Aufruf: bussignal_schreiben("Signalname", $worksheet, $zeile);
sub bussignal_schreiben
{
	(my $bus, my $worksheet, my $zeile) = @_;
	
	#print "Signal:".$bus."\n";
	
	my $desc = Encode::encode('latin1', $bus_signale{$bus}->{desc});
	#$worksheet->Range("A" . $zeile . ":F" . $zeile)->{Value} = [ $bus, $bus_signale{$bus}->{dir}, $bus_signale{$bus}->{typ}, $bus_signale{$bus}->{init}, $bus_signale{$bus}->{invalid}, $desc ];
	$worksheet->Range($col{'Signal'} . $zeile)->{Value} = $bus;
	$worksheet->Range($col{'Dir'} . $zeile)->{Value} = $bus_signale{$bus}->{dir};
	$worksheet->Range($col{'Type (Bus)'} . $zeile)->{Value} = $bus_signale{$bus}->{typ};
	$worksheet->Range($col{'Init value (Bus)'} . $zeile)->{Value} = $bus_signale{$bus}->{init};
	$worksheet->Range($col{'Invalid value (Bus)'} . $zeile)->{Value} = $bus_signale{$bus}->{invalid};
	$worksheet->Range($col{'Description (Bus)'} . $zeile)->{Value} = $desc;
	$worksheet->Range($col{'Interface Type (Bus)'} . $zeile)->{Value} = $bus_signale{$bus}->{interface_type};
	
	# Format für Phys. Min- und Max-Wert auf Text stellen,
	# da Excel lange Zahlen mit vielen Nachkommastellen (z.B. -80216064,0168961865940992) nicht speichern kann und deshalb abschneidet.
	# Als Text gespeichert funktioniert das.
	$worksheet->Range($col{'Phy. Min. (Bus)'} . $zeile)->{NumberFormat} = "\@";
	$worksheet->Range($col{'Phy. Max. (Bus)'} . $zeile)->{NumberFormat} = "\@";
		
	# Numerische Umrechnung
	if(defined($bus_signale{$bus}->{num}))
	{
		my $skalierung_bus;
		my $offset_bus;
		my $err_div = 0;
		
		if($bus_signale{$bus}->{typ} =~ /^S/)
		{
			if (hex($bus_signale{$bus}->{num}->{code_max}) + hex($bus_signale{$bus}->{num}->{code_min}) != 0)
			{
				$skalierung_bus = ($bus_signale{$bus}->{num}->{phy_max} - $bus_signale{$bus}->{num}->{phy_min}) / (hex($bus_signale{$bus}->{num}->{code_max}) + hex($bus_signale{$bus}->{num}->{code_min}));
			}
			else
			{
				$err_div = 1;
				print "Error: (Maximum + Minimum) results to zero!\n";
				$skalierung_bus = 1;
			}
			$offset_bus = 0;
		}
		else
		{
			if (hex($bus_signale{$bus}->{num}->{code_max}) - hex($bus_signale{$bus}->{num}->{code_min}) != 0)
			{
				$skalierung_bus = ($bus_signale{$bus}->{num}->{phy_max} - $bus_signale{$bus}->{num}->{phy_min}) / (hex($bus_signale{$bus}->{num}->{code_max}) - hex($bus_signale{$bus}->{num}->{code_min}));
			}
			else
			{
				$err_div = 1;
				print "Error: (Maximum - Minimum) results to zero!\n";
				$skalierung_bus = 1;
			}
			$offset_bus = $bus_signale{$bus}->{num}->{phy_min} - (hex($bus_signale{$bus}->{num}->{code_min}) * $skalierung_bus);
		}
		if ($err_div)
		{
			printf("%-5s = %8s\n", "bus", $bus);
			printf("%-5s = %8s (%d)\n", "max", $bus_signale{$bus}->{num}->{code_max}, hex($bus_signale{$bus}->{num}->{code_max}));
			printf("%-5s = %8s (%d)\n", "min", $bus_signale{$bus}->{num}->{code_min}, hex($bus_signale{$bus}->{num}->{code_min}));
		}
				
		my $unit = Encode::encode('latin1', $bus_signale{$bus}->{num}->{unit});
		
		my $phy_min_bus = $bus_signale{$bus}->{num}->{phy_min};
		$phy_min_bus =~ s/\./,/g;
		my $phy_max_bus = $bus_signale{$bus}->{num}->{phy_max};
		$phy_max_bus =~ s/\./,/g;
		#$worksheet->Range("G" . $zeile . ":K" . $zeile)->{Value} = [ $skalierung_bus, $offset_bus, "$phy_min_bus", "$phy_max_bus", $unit ];	# "" um $phy_max_bus sind notwendig, da sonst 4294967295 (0xFFFF) als -1 dargestellt wird
		$worksheet->Range($col{'Resolution (Bus)'} . $zeile)->{Value} = $skalierung_bus;
		$worksheet->Range($col{'Offset (Bus)'} . $zeile)->{Value} = $offset_bus;
		$worksheet->Range($col{'Phy. Min. (Bus)'} . $zeile)->{Value} = "$phy_min_bus";		# "" um $phy_min_bus sind notwendig, da sonst 4294967295 (0xFFFF) als -1 dargestellt wird
		$worksheet->Range($col{'Phy. Max. (Bus)'} . $zeile)->{Value} = "$phy_max_bus";		# "" um $phy_max_bus sind notwendig, da sonst 4294967295 (0xFFFF) als -1 dargestellt wird
		$worksheet->Range($col{'Unit (Bus)'} . $zeile)->{Value} = $unit;
	}
	
	# Logische Werte
	if(defined($bus_signale{$bus}->{text}))
	{
		my $log_werte = "";
		my $value;
		
		# allways sorted
		my @logical_values = sort {   $a->{code_min} cmp $b->{code_min}  
                               or $a->{code_max} cmp $b->{code_max}
														 # or $a->{value} <=> $b->{value}
		                          } @{$bus_signale{$bus}->{text}};
		
		for(my $i = 0; $i < @logical_values; $i++)
		{
			#print $bus_signale{$bus}->{text}->[$i]->{value}."\n";
			$value = "$logical_values[$i]->{value}: $logical_values[$i]->{code_min}";
			$log_werte .= $value;
			if(hex($logical_values[$i]->{code_min}) != hex($logical_values[$i]->{code_max}))
			{
				$log_werte .= " ... $logical_values[$i]->{code_max}";
			}
			if($i != scalar @logical_values - 1)
			{
				$log_werte .= "\n";
			}

			# Special case of init, invalid and SNA values in the logical value part
			# Such values are taken to fill empty init, invalid cells
			if ($value =~ /init value[^:]*:(.+)/)
			{
				my $v;
				if (!defined($v = $worksheet->Range($col{'Init value (Bus)'}.$zeile)->{Value}) or ($v eq ""))
				{
					$worksheet->Range($col{'Init value (Bus)'}.$zeile)->{Value} = trim($1);
				}
				#print "INIT:".$1."\n";
			}
			elsif ($value =~ /(Invalid|SNA)[^:]*:(.+)/)
			{
				my $v;
				if (!defined($v = $worksheet->Range($col{'Invalid value (Bus)'}.$zeile)->{Value}) or ($v eq ""))
				{
					$worksheet->Range($col{'Invalid value (Bus)'}.$zeile)->{Value} = trim($2);
				}
				#print "SNA:".$2."\n";
			}
		}
		#print $log_werte."\n";
		$log_werte = Encode::encode('latin1', $log_werte);
		$worksheet->Range($col{'Logical values (Bus)'}  . $zeile)->{Value} = $log_werte;
	}
}


# variable_schreiben
# schreibt den zweiten Teil der Zeile im Excel-Dokument, der die Informationen über die Variable enthält
# bestimmt Werte für Auflösung, Offset, Min-, Max- und Logische-Werte aus den Informationen in datamodel.xml
# Aufruf: variable_schreiben("Signalname", $worksheet, $zeile);
sub variable_schreiben
{
	(my $sys, my $worksheet, my $zeile) = @_;
	
	if($sys ne "")
	{
		my $sys = $_[0];
		
		#print "Signal:".$sys;
		
		my $desc = Encode::encode('latin1', $sys_signale{$sys}->{desc});
		#$worksheet->Range("M" . $zeile . ":P" . $zeile)->{Value} = [ $sys, $sys_signale{$sys}->{typ}, $sys_signale{$sys}->{init}, $desc ];
		$worksheet->Range($col{'Variable'} . $zeile)->{Value} = $sys;
		$worksheet->Range($col{'Type (int)'} . $zeile)->{Value} = $sys_signale{$sys}->{typ};
		$worksheet->Range($col{'Init value (int)'} . $zeile)->{Value} = $sys_signale{$sys}->{init};
		$worksheet->Range($col{'Description (int)'} . $zeile)->{Value} = $desc;

		# Format für Phys. Min- und Max-Wert auf Text stellen,
		# da Excel lange Zahlen mit vielen Nachkommastellen (z.B. -80216064,0168961865940992) nicht speichern kann und deshalb abschneidet.
		# Als Text gespeichert funktioniert das.
		$worksheet->Range($col{'Phy. Min. (int)'} . $zeile)->{NumberFormat} = "\@";
		$worksheet->Range($col{'Phy. Max. (int)'} . $zeile)->{NumberFormat} = "\@";
		
		# Numerische Umrechnung
		if(defined($sys_signale{$sys}->{num}))
		{
			my $skalierung_sys;
			my $offset_sys;
			if($sys_signale{$sys}->{typ} =~ /^S/)
			{
				$skalierung_sys = ($sys_signale{$sys}->{num}->{phy_max} - $sys_signale{$sys}->{num}->{phy_min}) / (hex($sys_signale{$sys}->{num}->{code_max}) + hex($sys_signale{$sys}->{num}->{code_min}));
				$offset_sys = 0;
			}
			else
			{
				$skalierung_sys = ($sys_signale{$sys}->{num}->{phy_max} - $sys_signale{$sys}->{num}->{phy_min}) / (hex($sys_signale{$sys}->{num}->{code_max}) - hex($sys_signale{$sys}->{num}->{code_min}));
				$offset_sys = $sys_signale{$sys}->{num}->{phy_min} - (hex($sys_signale{$sys}->{num}->{code_min}) * $skalierung_sys);
			}
			my $unit = Encode::encode('latin1', $sys_signale{$sys}->{num}->{unit});
			if(substr($unit, 0, 1) eq "'")
			{
				$unit = "'$unit";
			}
			my $phys_min = $sys_signale{$sys}->{num}->{phy_min};
			$phys_min =~ s/\./,/g;
			my $phys_max = $sys_signale{$sys}->{num}->{phy_max};
			$phys_max =~ s/\./,/g;
			$worksheet->Range($col{'Resolution (int)'} . $zeile . ":U" . $zeile)->{Value} = [ $skalierung_sys, $offset_sys, "$phys_min", "$phys_max", "$unit" ];
		}
		
		# Logische Werte
		if(defined($sys_signale{$sys}->{text}))
		{
			my $log_werte = "";
			for(my $i = 0; $i < @{$sys_signale{$sys}->{text}}; $i++)
			{
				$log_werte .= "$sys_signale{$sys}->{text}->[$i]->{value}: $sys_signale{$sys}->{text}->[$i]->{code_min}";
				if(hex($sys_signale{$sys}->{text}->[$i]->{code_min}) != hex($sys_signale{$sys}->{text}->[$i]->{code_max}))
				{
					$log_werte .= " ... $sys_signale{$sys}->{text}->[$i]->{code_max}";
				}
				if($i != @{$sys_signale{$sys}->{text}} - 1)
				{
					$log_werte .= "\n";
				}
				#print $log_werte;
			}
			$log_werte = Encode::encode('latin1', $log_werte);
			$worksheet->Range($col{'Logical values (int)'} . $zeile)->{Value} = $log_werte; 
		}
	}
}


# mapping_schreiben
# schreibt dritten Teil der Zeile im Excel-Dokument, der die Informationen über das Mapping enthält
# Aufruf: mapping_schreiben("Mapping-ID", $worksheet, $zeile);
sub mapping_schreiben
{
	(my $m, my $worksheet, my $zeile) = @_;

	# Processing-Type
	# ist bei uns entweder UNCONDITIONAL (normales Mapping) oder STUB (Stub value = Initwert) oder CONDITIONAL (für TX-Initwerte)
	if($mappings{$m}->{processing} ne "UNCONDITIONAL")
	{
		if($mappings{$m}->{processing} eq "CONDITIONAL")
		{
			(my $base_name) = $mappings{$m}->{sys_signal} =~ /^[usb]\d+(\w+)$/;
			my $dft_condition = "Get_u8StateSig$base_name() != 1";
			
			if($mappings{$m}->{processing_cond} eq $dft_condition)
			{
				$worksheet->Range($col{'Processing'} . $zeile)->{Value} = "qualifier";
			}
			else
			{
				$worksheet->Range($col{'Processing'} . $zeile)->{Value} = "$mappings{$m}->{processing_cond}";
			}
		}
		else
		{
			$worksheet->Range($col{'Processing'} . $zeile)->{Value} = "$mappings{$m}->{processing}";
		}
	}

	# Out-of-range-Handling
	# mögliche Werte: CANCEL oder CALLOUT
	if($mappings{$m}->{oor} ne "CANCEL")
	{
		$worksheet->Range($col{'Oor'} . $zeile)->{Value} = "$mappings{$m}->{oor_callout}";
	}
	
	# Conversion-Callout
	# mögliche Werte: DISABLED oder CALLOUT
	if($mappings{$m}->{ext_conv} ne "DISABLED")
	{
		$worksheet->Range($col{'External conversion'} . $zeile)->{Value} = "$mappings{$m}->{ext_conv_callout}";
	}
	
	# Textmappings (Logische Werte)
	if(defined($mappings{$m}->{text_map}))
	{
		my $text_map = "";
		for(my $i = 0; $i < @{$mappings{$m}->{text_map}}; $i++)
		{
			$text_map .= "$mappings{$m}->{text_map}->[$i]->{src}: $mappings{$m}->{text_map}->[$i]->{dst}\n";
		}
		$text_map = Encode::encode('latin1', $text_map);
		$worksheet->Range($col{'Text mappings'} . $zeile)->{Value} =  $text_map;
	}

	# Pre-Conversion-Callout
	# mögliche Werte: DISABLED oder CALLOUT
	if($mappings{$m}->{pre_cvt} ne  "DISABLED")
	{
		$worksheet->Range($col{'Pre conv. callout'} . $zeile)->{Value} = "$mappings{$m}->{pre_cvt_callout}";
	}

	# Post-Conversion-Callout
	# mögliche Werte: DISABLED oder CALLOUT
	if($mappings{$m}->{post_cvt} ne  "DISABLED")
	{
		$worksheet->Range($col{'Post conv. callout'} . $zeile)->{Value} = "$mappings{$m}->{post_cvt_callout}";
	}

	# Inithandling	
	# mögliche Werte: DISABLED, AUTO oder CALLOUT
	if($mappings{$m}->{initialisation} eq "CALLOUT")
	{
		$worksheet->Range($col{'Init handling'} . $zeile)->{Value} = "$mappings{$m}->{initialisation_callout}";
	}
	elsif($mappings{$m}->{initialisation} ne "DISABLED")
	{
		$worksheet->Range($col{'Init handling'} . $zeile)->{Value} = "$mappings{$m}->{initialisation}";
	}
	
	# Invalidhandling
	# mögliche Werte: DISABLED, AUTO oder CALLOUT
	if($mappings{$m}->{invalidation} eq "CALLOUT")
	{
		$worksheet->Range($col{'Invalid handling'} . $zeile)->{Value} = "$mappings{$m}->{invalidation_callout}";		
	}
	elsif($mappings{$m}->{invalidation} ne "DISABLED")
	{
		$worksheet->Range($col{'Invalid handling'} . $zeile)->{Value} = "$mappings{$m}->{invalidation}";
	}
}


# nicht_gemappte_werte_schreiben
# bestimmt nicht gemappte Werte und gibt diese in der letzten Spalte aus; funktioniert nicht für negative Werte
# Aufruf: nicht_gemappte_werte_schreiben("Signal", "Variable", "Mapping-Id", $worksheet, $zeile");
sub nicht_gemappte_werte_schreiben
{
	(my $bus, my $sys, my $m, my $worksheet, my $zeile) = @_;
	
	my $unhandled = "";
	
	if($sys ne "") {
		# Nicht gemappte Werte
		my %bus_werte;
		my %sys_werte;
		if($bus_signale{$bus}->{init} ne "")
		{
			my $init = hex($bus_signale{$bus}->{init});
			$sys_werte{$init} = "Init";	# Wenn Logischer Wert "Init" als Init value des Bussignals konfiguriert ist, ist ein Textmapping nicht nötig
		}
		# Bussignal-Fehlerwert soll nicht gemappt werden
		
		if(defined($bus_signale{$bus}->{text}))
		{
			for(my $i = 0; $i < @{$bus_signale{$bus}->{text}}; $i++)
			{
				my $val = hex($bus_signale{$bus}->{text}->[$i]->{code_min});
				$bus_werte{$val} = $bus_signale{$bus}->{text}->[$i]->{value};
			}
		}
	
		if(defined($sys_signale{$sys}->{text}))
		{
			for(my $i = 0; $i < @{$sys_signale{$sys}->{text}}; $i++)
			{
				my $val = hex($sys_signale{$sys}->{text}->[$i]->{code_min});
				$sys_werte{$val} = $sys_signale{$sys}->{text}->[$i]->{value};
			}
		}
	
		# Nicht gemappte Werte im Bereich der numerischen Konvertierung
		my @nicht_gemappt;
		if(defined($bus_signale{$bus}->{num}))
		{
			if(hex($sys_signale{$sys}->{num}->{code_min}) > hex($bus_signale{$bus}->{num}->{code_min}))
			{
				$unhandled .= "$bus_signale{$bus}->{num}->{code_min} ... $sys_signale{$sys}->{num}->{code_min}, ";
			}
	
			if(hex($sys_signale{$sys}->{num}->{code_max}) < hex($bus_signale{$bus}->{num}->{code_max}))
			{
				$unhandled .= "$sys_signale{$sys}->{num}->{code_max} ... $bus_signale{$bus}->{num}->{code_max}, "
			}
		}
		
		# Nicht gemappte Logische Werte
		foreach my $w (sort(keys(%bus_werte)))
		{
			if(!defined($sys_werte{$w}) && ($bus_werte{$w} ne "Fehler") && ($mappings{$m}->{processing} ne "STUB"))
			{
				if(!defined($bus_signale{$bus}->{num}) || ($w < hex($bus_signale{$bus}->{num}->{code_min})) || ($w > hex($bus_signale{$bus}->{num}->{code_max})))
				{
					$unhandled .= "$w, ";
				}
			}
		}
		$worksheet->Range($col{'unhandled values'} . $zeile)->{Value} = $unhandled;
	}
}


# Füllt %bus_signale mit folgenden Feldern ($name ist Signalname):
# $bus_signale{$name}->{dir}
# $bus_signale{$name}->{num}->{phy_min}	(opt)
# $bus_signale{$name}->{num}->{phy_max}	(opt)
# $bus_signale{$name}->{num}->{code_min}	(opt)
# $bus_signale{$name}->{num}->{code_max}	(opt)
# $bus_signale{$name}->{text}->[$text_map_num]->{value}	(opt)
# $bus_signale{$name}->{text}->[$text_map_num]->{code_min}	(opt)
# $bus_signale{$name}->{text}->[$text_map_num]->{code_max}	(opt)
# $bus_signale{$name}->{typ} // Variablentyp
# $bus_signale{$name}->{init}	(opt)
# $bus_signale{$name}->{invalid}	(opt)
sub read_bus_sig
{
	my $text_map_num = 0;
	my $name;
	
	while(<INPUT>)
	{
		if(/<NAME>(.*)<\/NAME>/)
		{
			$name = $1;
		}
		elsif(/<DIR>(.*)<\/DIR>/)
		{
			$bus_signale{$name}->{dir} = $1;
		}
		elsif(/<DESC>(.*)/)
		{
			my $desc = "";
			my $l = "$1\n";
			while(!($l =~ /(.*)<\/DESC>/))
			{
				$desc .= $l;
				$l = <INPUT>;
			}
			if($l =~ /(.*)<\/DESC>/)
			{
				$desc .= $1;
			}
				
			$bus_signale{$name}->{desc} = Encode::decode("utf-8", $desc);
		}
		elsif(/<NUM>/)
		{
			read_num(\%{$bus_signale{$name}->{num}});
			# TODO
		}
		elsif(/<TEXT>/)
		{
			my $array_ref = $bus_signale{$name}->{text};

			my @ret = read_text();
			$bus_signale{$name}->{text}->[$text_map_num]->{value} = $ret[0];
			$bus_signale{$name}->{text}->[$text_map_num]->{code_min} = $ret[1];
			$bus_signale{$name}->{text}->[$text_map_num]->{code_max} = $ret[2];
			
			$text_map_num++;
			# TODO
		}
		elsif(/<COD_DTYPE>(.*)<\/COD_DTYPE>/)
		{
			$bus_signale{$name}->{typ} = $1;
		}
		elsif(/<COD_INIT>(.*)<\/COD_INIT>/)
		{
			$bus_signale{$name}->{init} = $1;
		}
		elsif(/<COD_INVALID>(.*)<\/COD_INVALID>/)
		{
			$bus_signale{$name}->{invalid} = $1;
		}
		elsif(/<INTERFACE_TYPE>(.*)<\/INTERFACE_TYPE>/)
		{
			$bus_signale{$name}->{interface_type} = $1;
		}
		elsif(/<\/BUS_SIGNAL>/)
		{
			$text_map_num = 0;
			last;
		}
	}
}


# Füllt %sys_signale mit folgenden Feldern ($name ist Variablenname):
# $sys_signale{$name}->{dir}
# $sys_signale{$name}->{num}->{phy_min}	(opt)
# $sys_signale{$name}->{num}->{phy_max}	(opt)
# $sys_signale{$name}->{num}->{code_min}	(opt)
# $sys_signale{$name}->{num}->{code_max}	(opt)
# $sys_signale{$name}->{text}->[$text_map_num]->{value}	(opt)
# $sys_signale{$name}->{text}->[$text_map_num]->{code_min}	(opt)
# $sys_signale{$name}->{text}->[$text_map_num]->{code_max}	(opt)
# $sys_signale{$name}->{typ}
# $sys_signale{$name}->{init}	(opt)
# $sys_signale{$name}->{invalid}	(opt)
sub read_sys_sig
{
	my $text_map_num = 0;
	my $name;

	while(<INPUT>)
	{
		if(/<NAME>(.*)<\/NAME>/)
		{
			$name = $1;
	
			$sys_signale{$name}->{init} = "";
			$sys_signale{$name}->{invalid} = "";
			$sys_signale{$name}->{desc} = "";
		}
		elsif(/<DIR>(.*)<\/DIR>/)
		{
			$sys_signale{$name}->{dir} = $1;
		}
		elsif(/<DESC>(.*)/)
		{
			my $desc = "";
			my $l = "$1\n";
			while(!($l =~ /(.*)<\/DESC>/))
			{
				$desc .= $l;
				$l = <INPUT>;
			}
			if($l =~ /(.*)<\/DESC>/)
			{
				$desc .= $1;
			}
				
			$sys_signale{$name}->{desc} = Encode::decode("utf-8", $desc);
		}
		elsif(/<NUM>/)
		{
			read_num(\%{$sys_signale{$name}->{num}});
		}
		elsif(/<TEXT>/)
		{
			my @ret = read_text();
			$sys_signale{$name}->{text}->[$text_map_num]->{value} = $ret[0];
			$sys_signale{$name}->{text}->[$text_map_num]->{code_min} = $ret[1];
			$sys_signale{$name}->{text}->[$text_map_num]->{code_max} = $ret[2];
			
			$text_map_num++;
		}
		elsif(/<COD_DTYPE>(.*)<\/COD_DTYPE>/)
		{
			$sys_signale{$name}->{typ} = $1;
		}
		elsif(/<COD_INIT>(.*)<\/COD_INIT>/)
		{
			$sys_signale{$name}->{init} = $1;
		}
		elsif(/<COD_INVALID>(.*)<\/COD_INVALID>/)
		{
			$sys_signale{$name}->{invalid} = $1;
		}
		elsif(/<\/SYS_SIGNAL>/)
		{
			$text_map_num = 0;
			last;
		}
	}
}


# Füllt %mappings mit folgenden Feldern ($id ist die ID des Mappings):
# $mappings{$id}->{bus_signal}
# $mappings{$id}->{sys_signal}
# $mappings{$id}->{processing}
# (ByPass-Callout wird nicht eingelesen)
# $mappings{$id}->{pre_cvt}
# $mappings{$id}->{pre_cvt_callout}	(opt)
# $mappings{$id}->{initialisation}
# $mappings{$id}->{initialisation_callout}	(opt)
# $mappings{$id}->{invalidation}
# $mappings{$id}->{invalidation_callout}	(opt)
# $mappings{$id}->{ext_conv}
# $mappings{$id}->{ext_conv_callout}	(opt)
# $mappings{$id}->{limit}
# $mappings{$id}->{limit_callout}	(opt)
# $mappings{$id}->{post_cvt}
# $mappings{$id}->{post_cvt_callout}	(opt)
# $mappings{$id}->{oor}
# $mappings{$id}->{oor_callout}	(opt)
# $mappings{$id}->{text_map}->[$text_map_num]->{src}	(opt)
# $mappings{$id}->{text_map}->[$text_map_num]->{dst}	(opt)
sub read_mapping
{
	my $id = $_[0];
	my $text_map_num = 0;
	while(<INPUT>)
	{
		if(/<BUS_SIGNAL_REF>(.*)<\/BUS_SIGNAL_REF>/)
		{
			$mappings{$id}->{bus_signal} = $1;
			$bus_signale2mapping{$1} = $id;
		}
		elsif(/<SYS_SIGNAL_REF>(.*)<\/SYS_SIGNAL_REF>/)
		{
			$mappings{$id}->{sys_signal} = $1;
		}
		elsif(/<PROCESSING>(.*)<\/PROCESSING>/)
		{
			$mappings{$id}->{processing} = $1;
		}
		elsif(/<PROCESSING_CONDITION>(.*)<\/PROCESSING_CONDITION>/)	# <PROCESSING_NEG_REACTION> ist hartcodiert auf INIT, muss nicht in Konfig ausgegeben werden
		{
			$mappings{$id}->{processing_cond} = $1;
		}
		elsif(/<PRE_CVT>(.*)<\/PRE_CVT>/)
		{
			$mappings{$id}->{pre_cvt} = $1;
		}
		elsif(/<PRE_CVT_CALLOUT>(.*)<\/PRE_CVT_CALLOUT>/)
		{
			$mappings{$id}->{pre_cvt_callout} = $1;
		}
		elsif(/<INITIALIZATION>(.*)<\/INITIALIZATION>/)
		{
			$mappings{$id}->{initialisation} = $1;
		}
		elsif(/<INITIALIZATION_CALLOUT>(.*)<\/INITIALIZATION_CALLOUT>/)
		{
			$mappings{$id}->{initialisation_callout} = $1;
		}
		elsif(/<INVALIDATION>(.*)<\/INVALIDATION>/)
		{
			$mappings{$id}->{invalidation} = $1;
		}
		elsif(/<INVALIDATION_CALLOUT>(.*)<\/INVALIDATION_CALLOUT>/)
		{
			$mappings{$id}->{invalidation_callout} = $1;
		}
		elsif(/<EXT_CONVERSION>(.*)<\/EXT_CONVERSION>/)
		{
			$mappings{$id}->{ext_conv} = $1;
		}
		elsif(/<EXT_CONVERSION_CALLOUT>(.*)<\/EXT_CONVERSION_CALLOUT>/)
		{
			$mappings{$id}->{ext_conv_callout} = $1;
		}
		elsif(/<LIMITATION>(.*)<\/LIMITATION>/)
		{
			$mappings{$id}->{limit} = $1;
		}
		elsif(/<LIMITATION_CALLOUT>(.*)<\/LIMITATION_CALLOUT>/)
		{
			$mappings{$id}->{limit_callout} = $1;
		}
		elsif(/<POST_CVT>(.*)<\/POST_CVT>/)
		{
			$mappings{$id}->{post_cvt} = $1;
		}
		elsif(/<POST_CVT_CALLOUT>(.*)<\/POST_CVT_CALLOUT>/)
		{
			$mappings{$id}->{post_cvt_callout} = $1;
		}
		elsif(/<OUT_OFF_RANGE>(.*)<\/OUT_OFF_RANGE>/)
		{
			$mappings{$id}->{oor} = $1;
		}
		elsif(/<OUT_OFF_RANGE_CALLOUT>(.*)<\/OUT_OFF_RANGE_CALLOUT>/)
		{
			$mappings{$id}->{oor_callout} = $1;
		}
		elsif(/<MAP>/)
		{
			my @ret = read_text_map();
			$mappings{$id}->{text_map}->[$text_map_num]->{src} = $ret[0];
			$mappings{$id}->{text_map}->[$text_map_num]->{dst} = $ret[1];
			$text_map_num++;
		}
		elsif(/<\/MAPPING>/)
		{
			last;
		}
	}
}


# Signal-zu-PDU-Mapping
# Füllt %pdus mit folgenden Feldern:
# $pdu_mapping{$signal}->{pdu}
# $pdu_secured{$pdu}
sub read_pdu_mapping
{
	my $name;
	
	while(<INPUT>)
	{
		if(/<NAME>(.*)<\/NAME>/)
		{
			$name = $1;
		}
		elsif(/<SECURED>(\w+)<\/SECURED>/)
		{
			$pdu_secured{$name} = $1;
		}
		elsif(/<BUS_SIGNAL_REF>(\w+)<\/BUS_SIGNAL_REF>/)
		{
			$pdu_mapping{$1}->{pdu} = $name;
		}
		elsif(/<\/PDU>/)
		{
			last;
		}
	}
}


# PDU-zu-Bus-Mapping
# Füllt %bus_mapping mit folgenden Feldern
# @{$bus_mapping{$bus_name}}
sub read_busref
{
	my $bus_name;
	
	while(<INPUT>)
	{
		if(/<BUSREF_NAME>(.*)<\/BUSREF_NAME>/)
		{
			$bus_name = $1;
		}
		elsif(/<PDU_REF>(\w+)<\/PDU_REF>/)
		{
			push(@{$bus_mapping{$bus_name}}, $1);
		}
		elsif(/<\/BUSREF>/)
		{
			last;
		}
	}
}


# read_num
# liest Numerische Wertedefinition für ein Signal oder eine Variable
sub read_num
{
	my $num_map_ref = $_[0];
	
	$num_map_ref->{unit} = "";
	
	while(<INPUT>)
	{
		if(/<PHY_UNIT>(.*)<\/PHY_UNIT>/)
		{
			$num_map_ref->{unit} = Encode::decode("utf-8", $1);
		}
		elsif(/<PHY_MIN>(.*)<\/PHY_MIN>/)
		{
			$num_map_ref->{phy_min} = $1;
		}
		elsif(/<PHY_MAX>(.*)<\/PHY_MAX>/)
		{
			$num_map_ref->{phy_max} = $1;
		}
		elsif(/<COD_LOWER_LIMIT>(.*)<\/COD_LOWER_LIMIT>/)
		{
			$num_map_ref->{code_min} = $1;
		}
		elsif(/<COD_UPPER_LIMIT>(.*)<\/COD_UPPER_LIMIT>/)
		{
			$num_map_ref->{code_max} = $1;
		}
		elsif(/<\/NUM>/)
		{
			last;
		}
	}
}
		

# read_text
# liest einen Logischen Wert für ein Signal oder eine Variable
sub read_text
{
	my @ret;
	while(<INPUT>)
	{
		if(/<VALUE>(.*)<\/VALUE>/)
		{
			$ret[0] = Encode::decode("utf-8", $1);
		}
		elsif(/<COD_LOWER_LIMIT>(.*)<\/COD_LOWER_LIMIT>/)
		{
			$ret[1] = $1;
		}
		elsif(/<COD_UPPER_LIMIT>(.*)<\/COD_UPPER_LIMIT>/)
		{
			$ret[2] = $1;
		}
		elsif(/<\/TEXT>/)
		{
			last;
		}
	}
	return @ret;
}


# read_text_map
# liest ein Mapping logischer Wert ein
sub read_text_map
{
	my @ret;
	while(<INPUT>)
	{
		if(/<SRC>(.*)<\/SRC>/)
		{
			$ret[0] = Encode::decode("utf-8", $1);;
		}
		elsif(/<DST>(.*)<\/DST>/)
		{
			$ret[1] = Encode::decode("utf-8", $1);;
		}
		elsif(/<\/MAP>/)
		{
			last;
		}
	}
	return @ret;
}

1;
