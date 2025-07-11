package XLSX2SIMA;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(xlsx2sima trim);
@EXPORT_OK = qw(xlsx_lesen);

use strict;
use warnings;
use Encode;
use lib '.';

use XLSX qw(XLSX_ErrorHandling XLSX_SetColumns);

use Win32::OLE;
use Win32::OLE::Const 'Microsoft Excel';
use Win32::OLE::Variant;

my %rx_signale;
my %tx_signale;
my %rx_vars;
my %tx_vars;
my %mappings;
my %pdu_mapping;
my %bus_mapping;
my %col; # for Excel columns

# initialization procedure
sub init_XLSX2SIMA
{
	my ($hrCol) = @_;
	# set columns
	%col = %$hrCol;	
}

# xlsx2sima
# wandelt Excel-Dokument in datamodel.xml
# Rückgabewert: String ne "" falls Datei nicht geöffnet werden konnte
sub xlsx2sima
{
	(my $input_file, my $output_file, my $datamodel, my $log, my $nicht_gemappte_entfernen, my $auto_system_signals, my $version) = @_;
	
	%rx_signale = ();
	%tx_signale = ();
	%rx_vars = ();
	%tx_vars = ();
	%mappings = ();
	%pdu_mapping = ();
	%bus_mapping = ();
	
	my $s = xlsx_lesen($input_file, $version, \%rx_signale, \%tx_signale, \%rx_vars, \%tx_vars, \%mappings, \%pdu_mapping, \%bus_mapping, $log);
	if($s ne "") { return $s; }
	if ($auto_system_signals == 0)
	{
		$s = datamodel_schreiben($output_file, $datamodel, $log, $nicht_gemappte_entfernen);
	}
	else
	{
		$s = create_datamodel_from_template($output_file, $datamodel, $log);
	}
	
	return $s;
}


# xlsx_lesen
# liest Excel-Dokument und befüllt globale Variablen
sub xlsx_lesen
{
	(my $input_file, my $version, my $rx_signale, my $tx_signale, my $rx_vars, my $tx_vars, my $mappings, my $pdu_mapping, my $bus_mapping, my $log) = @_;
	
	my $i;
	
	Win32::OLE->Option(Variant => 1);	# TODO: was ist das?

	# Handle für Excel erstellen
	my $handle = Win32::OLE->new('Excel.Application');
	# Excel nicht anzeigen
	$handle->{Visible} = 0;	
	# Excel-Dokument öffnen
	my $book = $handle->Workbooks->Open($input_file);

	# Excel-Fehler prüfen
	my $msg = XLSX_ErrorHandling($handle, $book, "Error on opening file $input_file");
	if($msg ne "")
	{
		return $msg;
	}
	
	# Versionsinformation prüfen
	my $wsVersion = $book->Worksheets("Version information");
	
	# Excel-Fehler prüfen
	$msg = XLSX_ErrorHandling($handle, $book, "Error on opening sheet \"Version information\"");
	if($msg ne "")
	{
		return $msg;
	}
	
	if(trim($wsVersion->Range("A2")->{Value}) ne $version)
	{
		my $xlsx_version = trim($wsVersion->Range("A2")->{Value});
		if(!$xlsx_version)
		{
			$xlsx_version = "<undefined>";
		}
		$handle->Workbooks->Close();
		$handle->Quit();

		return "$input_file was created with COM-Configurator version $xlsx_version." .
		       "Currently running version is $version. The same version must be used for generation of XLSX and datamodel.xml. Aborting.";
	}

	# Signalmapping-Blatt auswählen
	my $wsSignalMap = $book->Worksheets("Signalmapping");
	
	# hash reference to Excel columns (Column name -> Excel column; e.g. "Signal" -> "A")
	my $hrCol = XLSX_SetColumns();
	%col = %$hrCol;
	
	# Excel-Fehler prüfen
	$msg = XLSX_ErrorHandling($handle, $book, "Error on opening sheet \"Signalmapping\"");
	if($msg ne "")
	{
		return $msg;
	}
		
	$i = 2;
	my $value;
	while(defined($value = $wsSignalMap->Range($col{'Signal'} . $i)->{Value}) and ($value ne ""))
	{
		#printf "[%02d]%s\n", $i, $value;
		# define parameters and initialize it with default values
		my $beschr_bus = "";
		my $beschr_int = "";
		my $dir = "";
		my $interface_type_bus = "";
		my $interface_type_int = "";
		my $log_werte_bus = "";
		my $log_werte_int = "";
		my $max_bus = "";
		my $max_int = "";
		my $min_bus = "";
		my $min_int = "";
		my $offset_bus = "";
		my $offset_int = "";
		my $signal = "";
		my $skalierung_bus = "";
		my $skalierung_int = "";
		my $text_mappings = "";
		my $variable = "";
	
		# Signal;Dir;Type (Bus);Init value (Bus);Invalid value (Bus);Resolution (Bus);Offset (Bus);Phy. Min. (Bus);Phy. Max. (Bus);Logical values (Bus);
		# Variable;Type (int);Init value (int);Resolution (int);Offset (int);Phy. Min. (int);Phy. Max. (int);Logical values (int);
		# Processing;Oor;ext_conv;Text Mappings;Pre conv. callout;Post conv. callout
		
		$signal = trim($wsSignalMap->Range($col{'Signal'} . $i)->{Value});
		$variable = trim($wsSignalMap->Range($col{'Variable'} . $i)->{Value});

		# Mapping-Informationen lesen
		$mappings->{$signal} = {
			var => $variable,
			processing => trim($wsSignalMap->Range($col{'Processing'} . $i)->{Value}),
			oor => trim($wsSignalMap->Range($col{'Oor'} . $i)->{Value}),
			ext_conv => trim($wsSignalMap->Range($col{'External conversion'} . $i)->{Value}),
			pre_conv => trim($wsSignalMap->Range($col{'Pre conv. callout'} . $i)->{Value}),
			post_conv => trim($wsSignalMap->Range($col{'Post conv. callout'} . $i)->{Value}),
			init => trim($wsSignalMap->Range($col{'Init handling'} . $i)->{Value}),
			invalid => trim($wsSignalMap->Range($col{'Invalid handling'} . $i)->{Value})
		};
		# Signalinformationen lesen
		$beschr_bus = trim($wsSignalMap->Range($col{'Description (Bus)'} . $i)->{Value});
		$beschr_bus =~ s/^\"//;
		$beschr_bus =~ s/\"$//;
		$skalierung_bus = trim($wsSignalMap->Range($col{'Resolution (Bus)'} . $i)->{Value});
		$skalierung_bus =~ tr/,/\./;
		$offset_bus = trim($wsSignalMap->Range($col{'Offset (Bus)'} . $i)->{Value});
		$offset_bus =~ tr/,/\./;
		$min_bus = trim($wsSignalMap->Range($col{'Phy. Min. (Bus)'} . $i)->{Value});
		$min_bus =~ tr/,/\./;
		$max_bus = trim($wsSignalMap->Range($col{'Phy. Max. (Bus)'} . $i)->{Value});
		$max_bus =~ tr/,/\./;
		$log_werte_bus = trim($wsSignalMap->Range($col{'Logical values (Bus)'} . $i)->{Value});
		$interface_type_bus = trim($wsSignalMap->Range($col{'Interface Type (Bus)'} . $i)->{Value});
		# Variableninformationen lesen
		$beschr_int = trim($wsSignalMap->Range($col{'Description (int)'} . $i)->{Value});
		$beschr_int =~ s/^\"//;
		$beschr_int =~ s/\"$//;
		$skalierung_int = trim($wsSignalMap->Range($col{'Resolution (int)'} . $i)->{Value});
		$skalierung_int =~ tr/,/\./;
		$offset_int = trim($wsSignalMap->Range($col{'Offset (int)'} . $i)->{Value});
		$offset_int =~ tr/,/\./;
		$min_int = trim($wsSignalMap->Range($col{'Phy. Min. (int)'} . $i)->{Value});
		$min_int =~ tr/,/\./;
		$max_int = trim($wsSignalMap->Range($col{'Phy. Max. (int)'} . $i)->{Value});
		$max_int =~ tr/,/\./;
		$log_werte_int = trim($wsSignalMap->Range($col{'Logical values (int)'} . $i)->{Value});
		$interface_type_int = trim($wsSignalMap->Range($col{'Interface Type (int)'} . $i)->{Value});
		$text_mappings = trim($wsSignalMap->Range($col{'Text mappings'} . $i)->{Value});
		
		# Informationen abhängig von der Signalrichtung in Datenstrukturen schreiben
		$dir = trim($wsSignalMap->Range($col{'Dir'}  . $i)->{Value});
		if($dir eq "RX")
		{
			# RX-Signale
			$rx_signale->{$signal} = {
				typ => trim($wsSignalMap->Range($col{'Type (Bus)'} . $i)->{Value}),
				init => trim($wsSignalMap->Range($col{'Init value (Bus)'} . $i)->{Value}),
				invalid => trim($wsSignalMap->Range($col{'Invalid value (Bus)'} . $i)->{Value}),
				skalierung => $skalierung_bus,
				offset => $offset_bus,
				min => $min_bus,
				max => $max_bus,
				einheit => trim($wsSignalMap->Range($col{'Unit (Bus)'} . $i)->{Value}),
				beschr => $beschr_bus,
				interface => $interface_type_bus
			};
			$rx_vars->{$variable} = {
				typ => trim($wsSignalMap->Range($col{'Type (int)'} . $i)->{Value}),
				init => trim($wsSignalMap->Range($col{'Init value (int)'} . $i)->{Value}),
				skalierung => $skalierung_int,
				offset => $offset_int,
				min => $min_int,
				max => $max_int,
				einheit => trim($wsSignalMap->Range($col{'Unit (int)'} . $i)->{Value}),
				beschr => $beschr_int,
				interface => $interface_type_int
			};
			
			# Definition logischer Werte (0: Log_Wert) am ":" trennen und an @{$xxx{$yyy}->{werte}} zuweisen
			log_werte_trennen($log_werte_bus, $rx_signale->{$signal});
			log_werte_trennen($log_werte_int, $rx_vars->{$variable});

			# Signal-zu-PDU-Mapping lesen
			my $pdu = trim($wsSignalMap->Range($col{'PDU'} . $i)->{Value});
			$pdu_mapping->{$pdu}->{signale}->{$signal} = "RX";
		}
		else
		{
			# TX-Signale
			$tx_signale->{$signal} = {
				typ => trim($wsSignalMap->Range($col{'Type (Bus)'} . $i)->{Value}),
				init => trim($wsSignalMap->Range($col{'Init value (Bus)'} . $i)->{Value}),
				invalid => trim($wsSignalMap->Range($col{'Invalid value (Bus)'} . $i)->{Value}),
				skalierung => $skalierung_bus,
				offset => $offset_bus,
				min => $min_bus,
				max => $max_bus,
				einheit => trim($wsSignalMap->Range($col{'Unit (Bus)'} . $i)->{Value}),
				beschr => $beschr_bus,
				interface => $interface_type_bus
			};
			$tx_vars->{$variable} = {
				typ => trim($wsSignalMap->Range($col{'Type (int)'} . $i)->{Value}),
				init => trim($wsSignalMap->Range($col{'Init value (int)'} . $i)->{Value}),
				skalierung => $skalierung_int,
				offset => $offset_int,
				min => $min_int,
				max => $max_int,
				einheit => trim($wsSignalMap->Range($col{'Unit (int)'} . $i)->{Value}),
				beschr => $beschr_int,
				interface => $interface_type_int
			};

			# Definition logischer Werte (0: Log_Wert) am ":" trennen und an @{$xxx{$yyy}->{werte}} zuweisen
			log_werte_trennen($log_werte_bus, $tx_signale->{$signal});
			log_werte_trennen($log_werte_int, $tx_vars->{$variable});
			
			# Signal-zu-PDU-Mapping lesen
			my $pdu = trim($wsSignalMap->Range($col{'PDU'} . $i)->{Value});
			$pdu_mapping->{$pdu}->{signale}->{$signal} = "TX";
		}
		# Text-Mappings
		if (defined($text_mappings))
		{
			my @mappings = ($text_mappings =~ /[^:\"\n]+\s*:\s*[^:\"\n]+/g);
			foreach my $m (@mappings)
			{
				$m =~ /([^:]+?)\s*:\s*([^\n]+)/;
				my $src = $1;
				my $dst = $2;
				$dst =~ s/\xD//g;	# "Halbe Zeilenwechsel" (0x0D) entfernen
				$dst =~ s/\s*(.*\w)\s*$/$1/;
				$mappings->{$signal}->{text_mappings}->{$src} = $dst;
			}
		}
		
		# Konsistenz prüfen
		my $var;
		my $sig;
		if($dir eq "RX")
		{
			signal_pruefen($rx_signale->{$signal}, $rx_vars->{$variable}, $mappings->{$signal}, $signal, $variable, $dir, $log);
		}
		else
		{
			signal_pruefen($tx_signale->{$signal}, $tx_vars->{$variable}, $mappings->{$signal}, $signal, $variable, $dir, $log);
		}
		
		$i++;
	}
	
	# Busmapping-Blatt auswählen
	my $wsBusMap = $book->Worksheets("Bus mapping");
	
	# Excel-Fehler prüfen
	$msg = XLSX_ErrorHandling($handle, $book, "Error on opening sheet \"Bus mapping\"");
	if($msg ne "")
	{
		return $msg;
	}
	
	# PDU-zu-Bus-Mapping lesen
	$i = 2;
	while(defined($value = $wsBusMap->Range('A' . $i)->{Value}) and ($value ne ""))
	{
		my $bus = trim($wsBusMap->Range('A' . $i)->{Value});
		my $pdu = trim($wsBusMap->Range('B' . $i)->{Value});
		my $secured = trim($wsBusMap->Range('C' . $i)->{Value});
		$bus_mapping->{$bus}->{$pdu} = 1;
		$pdu_mapping->{$pdu}->{secured} = $secured;
		$i++;
	}

	# Excel schließen
	$handle->Workbooks->Close();
	$handle->Quit();

	return "";
}


# datamodel_schreiben
# liest Original datamodel.xml und ändert Daten im generierten datamodel.xml entsprechend der Informationen aus dem Excel-Dokument
sub datamodel_schreiben
{
	my ($output_file, $datamodel, $log, $nicht_gemappte_entfernen) = @_;
	
	open(INPUT, $datamodel) or return "Could not open $datamodel: $!\n";
	open(OUTPUT, ">${output_file}") or return "Could not open $output_file: $!";
	
	my %def_signale;
	my %def_vars;
	my %mapped_signale;
	my %def_mappings;
	my %mapping_refs;
	
	# Warnung ausgeben, wenn PDU auf einen Bus gemappt ist, die in keinem Signalmapping verwendet wird
	my %pm_check = %pdu_mapping;
	foreach my $b (keys(%bus_mapping))
	{
		foreach my $p (keys(%{$bus_mapping{$b}}))
		{
			if(!defined($pm_check{$p}->{signale}))
			{
				print $log "ERROR: PDU $p mapped to bus $b is not used in any signal mapping\n";
			}
			delete($pm_check{$p});
		}
	}
	
	# Warnung ausgeben, wenn PDU nicht auf einen Bus gemappt ist
	foreach my $p (keys(%pm_check))
	{
		if($p)
		{
			print $log "ERROR: PDU $p is not mapped to a bus\n";
		}
	}
	
	# datamodel.xml ändern
	while(<INPUT>)
	{
		my $line = $_;
		if(/<BUS_SIGNAL>/)
		{
			my $l = <INPUT>;
			if($l =~ /<NAME>(.*)<\/NAME>/)
			{
				if(defined($rx_signale{$1}))
				{
					if(!$def_signale{$1})
					{
						bussignal_schreiben($rx_signale{$1}, $1, "RX");
						$def_signale{$1} = 1;
						$l = <INPUT>;
						while(!($l =~ /<\/BUS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
					else
					{
						print $log "INFO: Bus signal $1 was defined more than once. Redundant instances removed.\n";
					}
				}
				elsif(defined($tx_signale{$1}))
				{
					if(!$def_signale{$1})
					{
						bussignal_schreiben($tx_signale{$1}, $1, "TX");
						$def_signale{$1} = 1;
						$l = <INPUT>;
						while(!($l =~ /<\/BUS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
					else
					{
						print $log "INFO: Bus signal $1 was defined more than once. Redundant instances removed.\n";
						$l = <INPUT>;
						while(!($l =~ /<\/BUS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
				}
				else
				{
					#print $log "INFO: signal $1 from old datamodel not found in configuration\n";
					if($nicht_gemappte_entfernen)
					{
						$l = <INPUT>;
						while(!($l =~ /<\/BUS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
					else
					{
						print OUTPUT "$_$l";
					}
				}
			}
			else
			{
				print $log "ERROR: name of bussignal missing in old datamodel\n";
			}
		}
		elsif(/<SYS_SIGNAL>/)
		{
			my $l = <INPUT>;
			if($l =~ /<NAME>(.*)<\/NAME>/)
			{
				if(defined($rx_vars{$1}))
				{
					if(!$def_vars{$1})
					{
						var_schreiben($rx_vars{$1}, $1, "TX");	# Syssignalrichtung entgegengesetzt zu Bussignalrichtung
						$def_vars{$1} = 1;
						$l = <INPUT>;
						while(!($l =~ /<\/SYS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
					else
					{
						print $log "INFO: System signal $1 was defined more than once. Redundant instances removed.\n";
					}
				}
				elsif(defined($tx_vars{$1}))
				{
					if(!$def_vars{$1})
					{
						var_schreiben($tx_vars{$1}, $1, "RX");	# Syssignalrichtung entgegengesetzt zu Bussignalrichtung
						$def_vars{$1} = 1;
						$l = <INPUT>;
						while(!($l =~ /<\/SYS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
					else
					{
						print $log "INFO: System signal $1 was defined more than once. Redundant instances removed.\n";
						$l = <INPUT>;
						while(!($l =~ /<\/SYS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
				}
				else
				{
					#print $log "INFO: variable $1 from old datamodel not found in configuration\n";
					if($nicht_gemappte_entfernen)
					{
						$l = <INPUT>;
						while(!($l =~ /<\/SYS_SIGNAL>/))
						{
							$l = <INPUT>;
						}
					}
					else
					{
						print OUTPUT "$_$l";
					}
				}
			}
			else
			{
				print $log "ERROR: name of variable missing in old datamodel\n";
			}
		}
		elsif(/<MAPPING ID="([^\"]*)">/)
		{
			my $id = $1;
			my $l = <INPUT>;
			
			if($l =~ /<BUS_SIGNAL_REF>(.*)<\/BUS_SIGNAL_REF>/)
			{
				if(defined($mappings{$1}))
				{
					mapping_schreiben($mappings{$1}, $1, $id);
					$mapped_signale{$1} = 1;
					$def_mappings{$id} = 1;
					$l = <INPUT>;
					while(!($l =~ /<\/MAPPING>/))
					{
						$l = <INPUT>;
					}
				}
				else
				{
					#print $log "INFO: mapping $1 from old datamodel not found in configuration\n";
					if($nicht_gemappte_entfernen)
					{
						$l = <INPUT>;
						while(!($l =~ /<\/MAPPING>/))
						{
							$l = <INPUT>;
						}
					}
					else
					{
						print OUTPUT "$_$l";
					}
				}
			}
			else
			{
				print $log "ERROR: name of bussignal for mapping $id missing in old datamodel\n";
			}
		}
		elsif(/<\/BUS_SIGNALS>/)
		{
			# fehlende Bussignale schreiben
			foreach my $s (sort(keys(%rx_signale)))
			{
				if(($s ne "") && (!defined($def_signale{$s})))
				{
					bussignal_schreiben($rx_signale{$s}, $s, "RX");
				}
			}
			foreach my $s (sort(keys(%tx_signale)))
			{
				if(($s ne "") && (!defined($def_signale{$s})))
				{
					bussignal_schreiben($tx_signale{$s}, $s, "TX");
				}
			}
			print OUTPUT $_;
		}
		elsif(/<\/SYS_SIGNALS>/)
		{
			# fehlende Syssignale schreiben
			foreach my $v (sort(keys(%rx_vars)))
			{
				if(($v ne "") && (!defined($def_vars{$v})))
				{
					var_schreiben($rx_vars{$v}, $v, "TX");	# Syssignalrichtung entgegengesetzt zu Bussignalrichtung
				}
			}
			foreach my $v (sort(keys(%tx_vars)))
			{
				if(($v ne "") && (!defined($def_vars{$v})))
				{
					var_schreiben($tx_vars{$v}, $v, "RX");	# Syssignalrichtung entgegengesetzt zu Bussignalrichtung
				}
			}
			print OUTPUT $_;
		}
		elsif(/<\/MAPPINGS>/)
		{
			# fehlende Mappings schreiben
			foreach my $s (sort(keys(%rx_signale)))
			{
				if(($s ne "") && (!defined($mapped_signale{$s})))
				{
					mapping_schreiben($mappings{$s}, $s, "Mapping_$s");
					$def_mappings{"Mapping_$s"} = 1;
				}
			}
			foreach my $s (sort(keys(%tx_signale)))
			{
				if(!defined($mapped_signale{$s}))
				{
					mapping_schreiben($mappings{$s}, $s, "Mapping_$s");
					$def_mappings{"Mapping_$s"} = 1;
				}
			}
			print OUTPUT $_;
		}
		elsif(/<MAPPING_REF>(.*)<\/MAPPING_REF>/)
		{
			$mapping_refs{$1} = 1;
			if(defined($def_mappings{$1}))
			{
							print OUTPUT $_;
			}
			else
			{
				#print $log "INFO: referenced mapping $1 from old datamodel not found in configuration\n";
				if(!$nicht_gemappte_entfernen)
				{
					print OUTPUT $_;
					#$mapping_refs{$1} = 1;
				}
			}
		}
		elsif(/<\/VARIANT>/)
		{
			# fehlende Mapping-Ref schreiben
			foreach my $m (sort(keys(%def_mappings)))
			{
				if(!defined($mapping_refs{$m}))
				{
					print OUTPUT "      <MAPPING_REF>$m</MAPPING_REF>\n";
				}
			}
			print OUTPUT "    </VARIANT>\n";
		}
		elsif(/<PDUS>/)
		{
			# Signal-zu-PDU-Mapping schreiben
			print OUTPUT $_;
			
			my $pdu = "";
			my $ende = 0;
			while(<INPUT>)
			{
				if(/<PDU>/ || /<SECURED>/)
				{
					# ignorieren
					#print OUTPUT $_;
				}
				elsif(/<NAME>(\w+)<\/NAME>/)
				{
					if(defined($pdu_mapping{$1}))
					{
						$pdu = $1;
						print OUTPUT "    <PDU>\n";
						print OUTPUT "      <NAME>$pdu</NAME>\n";
						print OUTPUT "      <SECURED>$pdu_mapping{$pdu}->{secured}</SECURED>\n";
					}
					else
					{
						# PDU ist nicht mehr konfiguriert
					}
				}
				elsif($pdu ne "" && /<BUS_SIGNAL_REF>(\w+)<\/BUS_SIGNAL_REF>/)
				{
					if(defined($pdu_mapping{$pdu}->{signale}->{$1}))
					{
						print OUTPUT $_;
						delete($pdu_mapping{$pdu}->{signale}->{$1});
					}
					else
					{
						# Signal nicht mehr konfiguriert
					}
				}
				elsif($pdu ne "" && /<\/PDU>/)
				{
					# in altem datamodel.xml nicht gemappte Signale ausgeben
					foreach my $s (sort(keys(%{$pdu_mapping{$pdu}->{signale}})))
					{
						print OUTPUT "      <BUS_SIGNAL_REF>$s</BUS_SIGNAL_REF>\n";
					}
					print OUTPUT "    </PDU>\n";
					delete($pdu_mapping{$pdu});
					$pdu = "";
				}
				elsif(/<\/PDUS>/)
				{
					# in altem datamodel.xml nicht gemappte PDUs und Signale ausgeben
					foreach $pdu (sort(keys(%pdu_mapping)))
					{
						if($pdu)
						{
							print OUTPUT "    <PDU>\n";
							print OUTPUT "      <NAME>$pdu</NAME>\n";
							print OUTPUT "      <SECURED>$pdu_mapping{$pdu}->{secured}</SECURED>\n";
							foreach my $s (sort(keys(%{$pdu_mapping{$pdu}->{signale}})))
							{
								print OUTPUT "      <BUS_SIGNAL_REF>$s</BUS_SIGNAL_REF>\n";
							}
							print OUTPUT "    </PDU>\n";
						}
						else
						{
							# Warnung für Signale ohne PDU-Mapping ausgeben
							foreach my $s (sort(keys(%{$pdu_mapping{$pdu}->{signale}})))
							{
								print $log "WARNING: no PDU mapping defined for signal $s\n";
							}
						}
					}
					print OUTPUT "  </PDUS>\n";
					$ende = 1;
					# while-Schleife abbrechen, wenn Signal-PDU-Mappings fertig ausgegeben
					last;
				}
				else
				{
					# Zeilen entfernter PDUs
				}
			}
		}
		elsif(/<BUSREFS>/)
		{
			# PDU-zu-Bus-Mapping schreiben
			print OUTPUT $_;
			
			my $bus = "";
			my $ende = 0;
			while(<INPUT>)
			{
				if(/<BUSREF>/)
				{
					# ignorieren
				}
				elsif(/<BUSREF_NAME>(\w+)<\/BUSREF_NAME>/)
				{
					if(defined($bus_mapping{$1}))
					{
						$bus = $1;
						print OUTPUT "    <BUSREF>\n";
						print OUTPUT "      <BUSREF_NAME>$bus</BUSREF_NAME>\n";
					}
					else
					{
						# Bus ist nicht mehr konfiguriert
					}
				}
				elsif($bus ne "" && /<PDU_REF>(\w+)<\/PDU_REF>/)
				{
					if(defined($bus_mapping{$bus}->{$1}))
					{
						print OUTPUT $_;
						delete($bus_mapping{$bus}->{$1});
					}
					else
					{
						# PDU ist nicht mehr konfiguriert
					}
				}
				elsif($bus ne "" && /<\/BUSREF>/)
				{
					# in altem datamodel.xml nicht gemappte PDUs ausgeben
					foreach my $pdu (sort(keys(%{$bus_mapping{$bus}})))
					{
						print OUTPUT "      <PDU_REF>$pdu</PDU_REF>\n";
					}
					print OUTPUT "    </BUSREF>\n";
					delete($bus_mapping{$bus});
					$bus = "";
				}
				elsif(/<\/BUSREFS>/)
				{
					# in altem datamodel.xml nicht gemappte Busse und PDUs ausgeben
					foreach $bus (sort(keys(%bus_mapping)))
					{
						print OUTPUT "    <BUSREF>\n";
						print OUTPUT "      <BUSREF_NAME>$bus</BUSREF_NAME>\n";
						
						foreach my $pdu (sort(keys(%{$bus_mapping{$bus}})))
						{
							print OUTPUT "      <PDU_REF>$pdu</PDU_REF>\n";
						}
						
						print OUTPUT "    </BUSREF>\n";
					}
					print OUTPUT "  </BUSREFS>\n";
					$ende = 1;
					# while-Schleife abbrechen, wenn PDU-Bus-Mappings fertig ausgegeben
					last;
				}
			}
		}
		else
		{
			print OUTPUT $_;
		}
	}
	
	close(INPUT);
	close(OUTPUT);
	return "";
}

# This procedure creates a new datamodel based on the given template and available bus and sys signals
# It also creates associated mappings
sub create_datamodel_from_template
{
	my ($output_file, $datamodel, $log) = @_;
	
	open(INPUT, $datamodel) or return "Could not open $datamodel: $!\n";
	open(OUTPUT, ">${output_file}") or return "Could not open $output_file: $!";
	
	my %def_signale;
	my %def_vars;
	my %mapped_signale;
	my %def_mappings;
	my %mapping_refs;
	
	
	# read templae.xml
	while(<INPUT>)
	{
		my $line = $_;
		if(/<BUS_SIGNALS>/)
		{
			print OUTPUT $_; # write tag
			
			# write all bus signals
			foreach my $busSig (sort(keys(%rx_signale)))
			{
				if($busSig ne "")
				{
					bussignal_schreiben($rx_signale{$busSig}, $busSig, "RX");
				}
			}
			foreach my $busSig (sort(keys(%tx_signale)))
			{
				if($busSig ne "")
				{
					bussignal_schreiben($tx_signale{$busSig}, $busSig, "TX");
				}
			}
			#print OUTPUT $_;
		}
		elsif(/<SYS_SIGNALS>/)
		{
			print OUTPUT $_; # write tag
						
			# write all sys signals
			foreach my $sysSig (sort(keys(%rx_vars)))
			{
				if($sysSig ne "")
				{
					var_schreiben($rx_vars{$sysSig}, $sysSig, "TX");	# Syssignalrichtung entgegengesetzt zu Bussignalrichtung
				}
			}
			foreach my $sysSig (sort(keys(%tx_vars)))
			{
				if($sysSig ne "")
				{
					var_schreiben($tx_vars{$sysSig}, $sysSig, "RX");	# Syssignalrichtung entgegengesetzt zu Bussignalrichtung
				}
			}
			#print OUTPUT $_;
		}
		elsif(/<MAPPINGS>/)
		{
			print OUTPUT $_; # write tag
						
			# create asscociated mappings
			foreach my $sysSig (sort(keys(%rx_signale)))
			{
				if(($sysSig ne "") && (!defined($mapped_signale{$sysSig})))
				{
					mapping_schreiben($mappings{$sysSig}, $sysSig, "Mapping_$sysSig");
					$def_mappings{"Mapping_$sysSig"} = 1;
				}
			}
			foreach my $sysSig (sort(keys(%tx_signale)))
			{
				if(!defined($mapped_signale{$sysSig}))
				{
					mapping_schreiben($mappings{$sysSig}, $sysSig, "Mapping_$sysSig");
					$def_mappings{"Mapping_$sysSig"} = 1;
				}
			}
			#print OUTPUT $_;
		}
		elsif(/<VARIANT>/)
		{
			print OUTPUT $_; # write tag
						
			# write all mapping refs of the variant
			foreach my $m (sort(keys(%def_mappings)))
			{
				print OUTPUT "      <MAPPING_REF>$m</MAPPING_REF>\n";
			}
		}
		elsif(/<PDUS>/)
		{
			# Signal-zu-PDU-Mapping schreiben
			print OUTPUT $_; # write tag
			
			foreach my $pdu (sort(keys(%pdu_mapping)))
			{
				pdu_write($pdu_mapping{$pdu}, $pdu);
			}
		}
		else
		{
			print OUTPUT $_;
		}
	}
	
	close(INPUT);
	close(OUTPUT);
	return "";
}

# bussignal_schreiben
# schreibt alle nötigen Informationen für ein Bussignal in neues datamodel.xml
sub bussignal_schreiben
{
	my $signal = $_[0];
	my $name = $_[1];
	my $dir = $_[2];
	
	# Kategorie (numerisch, Text oder mixed)
	my $cat = "";
	if($signal->{skalierung} ne "")
	{
		$cat = "NUM";
	}
	if(defined($signal->{werte}))
	{
		if($cat eq "NUM")
		{
			$cat = "MIX";
		}
		else
		{
			$cat = "TEXT"
		}
	}
	# Wenn ein numerisches Signal Init- oder Fehler-Werte hat, muss es auch mixed sein, da Sima sonst keinen Link zum Signaldiagnose-AUX erzeugt
	# Init- und / oder Fehlerwert muss dann auch als logischer Wert definiert werden
	if(($cat eq "NUM") && (($mappings{$name}->{init} ne "") || ($mappings{$name}->{invalid} ne "")))
	{
		$cat = "MIX";
		
		if($signal->{init} ne "")
		{
			my $init = hex($signal->{init});
			if(!defined($signal->{werte}->{$init}))
			{
				$signal->{werte}->{$init} = "Init"
			}
		}
		if($signal->{invalid} ne "")
		{
			my $invalid = hex($signal->{invalid});
			if(!defined($signal->{werte}->{$invalid}))
			{
				$signal->{werte}->{$invalid} = "Fehler"
			}
		}
	}
	
	# Signalname, Richtung, Kategorie und Beschreibung ausgeben
	my $beschr = Encode::encode("utf-8", $signal->{beschr});
	print OUTPUT "    <BUS_SIGNAL>
      <NAME>$name</NAME>
      <DIR>$dir</DIR>
      <CATEGORY>$cat</CATEGORY>
      <DESC>$beschr</DESC>\n";
  
  # Physikalische Umrechnung ausgeben, falls numerisches oder mixed Signal
  if($cat eq "NUM" || $cat eq "MIX")
  {
  	my $einheit = Encode::encode("utf-8", $signal->{einheit});
  	my $code_min_num = ($signal->{min} - $signal->{offset}) / $signal->{skalierung};
		if($code_min_num < 0)
		{
			$code_min_num *= -1;
		}
		my $code_min = sprintf("0x%X", int($code_min_num + 0.5));
		my $code_max_num = ($signal->{max} - $signal->{offset} + ($signal->{skalierung} / 2)) / $signal->{skalierung};
		my $code_max = sprintf("0x%X", int($code_max_num));
  	print OUTPUT "      <NUM>
        <PHY_UNIT>$einheit</PHY_UNIT>
        <PHY_MIN>$signal->{min}</PHY_MIN>
        <PHY_MAX>$signal->{max}</PHY_MAX>
        <COD_LOWER_LIMIT>$code_min</COD_LOWER_LIMIT>
        <COD_UPPER_LIMIT>$code_max</COD_UPPER_LIMIT>
      </NUM>\n";
  }
  
  # Mapping der logischen Werte ausgeben, falls Text- oder mixed Signal
  if($cat eq "TEXT" || $cat eq "MIX")
  {
  	if($cat eq "TEXT")
  	{
  		print OUTPUT "      <NUM xsi:nil=\"true\"/>\n";
  	}

  	foreach my $l (sort{$a <=> $b}(keys(%{$signal->{werte}})))
  	{
  		my $t = Encode::encode("utf-8", $signal->{werte}->{$l});
  		my $v = sprintf("0x%X", $l);
  		print OUTPUT "      <TEXT>
        <VALUE>$t</VALUE>
        <COD_LOWER_LIMIT>$v</COD_LOWER_LIMIT>
        <COD_UPPER_LIMIT>$v</COD_UPPER_LIMIT>
      </TEXT>\n"
    }
  }
  
  # Länge (Variablentyp), Init- / Fehlerwert ausgeben
	$signal->{init} = "0x0" if (defined($signal->{init}) and ($signal->{init} eq "0")); # fix! somehow the function signal_pruefen does not work correctly
	$signal->{invalid} = "0x0" if (defined($signal->{invalid}) and ($signal->{invalid} eq "0")); # fix! somehow the function signal_pruefen does not work correctly
  print OUTPUT "      <COD_DTYPE>$signal->{typ}</COD_DTYPE>
      <COD_INIT>$signal->{init}</COD_INIT>
      <COD_INVALID>$signal->{invalid}</COD_INVALID>
      <INTERFACE_TYPE>$signal->{interface}</INTERFACE_TYPE>
    </BUS_SIGNAL>\n";
}


# var_schreiben
# schreibt alle Informationen für eine Variable (Systemsignal) in neues datamodel.xml
sub var_schreiben
{
	my $signal = $_[0];
	my $name = $_[1];
	my $dir = $_[2];
	
	my $cat = "";
	if($signal->{skalierung} ne "")
	{
		$cat = "NUM";
	}
	if(defined($signal->{werte}))
	{
		if($cat eq "NUM")
		{
			$cat = "MIX";
		}
		else
		{
			$cat = "TEXT"
		}
	}
	
	my $beschr = Encode::encode("utf-8", $signal->{beschr});
	print OUTPUT "    <SYS_SIGNAL>
      <NAME>$name</NAME>
      <DIR>$dir</DIR>
      <CATEGORY>$cat</CATEGORY>
      <DESC>$beschr</DESC>\n";
  
  if($cat eq "NUM" || $cat eq "MIX")
  {
  	my $einheit = Encode::encode("utf-8", $signal->{einheit});
  	my $code_min_num = ($signal->{min} - $signal->{offset}) / $signal->{skalierung};
		if($code_min_num < 0)
		{
			$code_min_num *= -1;
		}
		my $code_min = sprintf("0x%X", int($code_min_num + 0.5));

		my $code_max_num = ($signal->{max} - $signal->{offset} + ($signal->{skalierung} / 2)) / $signal->{skalierung};
		my $code_max = sprintf("0x%X", int($code_max_num));
  	print OUTPUT "      <NUM>
        <PHY_UNIT>$einheit</PHY_UNIT>
        <PHY_MIN>$signal->{min}</PHY_MIN>
        <PHY_MAX>$signal->{max}</PHY_MAX>
        <COD_LOWER_LIMIT>$code_min</COD_LOWER_LIMIT>
        <COD_UPPER_LIMIT>$code_max</COD_UPPER_LIMIT>
      </NUM>\n";
  }
  if($cat eq "TEXT" || $cat eq "MIX")
  {
  	foreach my $l (sort{$a <=> $b}(keys(%{$signal->{werte}})))
  	{
  		my $t = Encode::encode("utf-8", $signal->{werte}->{$l});
  		my $v = sprintf("0x%X", $l);
  		print OUTPUT "      <TEXT>
        <VALUE>$t</VALUE>
        <COD_LOWER_LIMIT>$v</COD_LOWER_LIMIT>
        <COD_UPPER_LIMIT>$v</COD_UPPER_LIMIT>
      </TEXT>\n"
    }
  }
  
  my $mem = "WRONG_TYPE";
  if($signal->{typ} =~ /[SU](\d+)/)
  {
  	$mem = "${1}BIT";
  }
  elsif($signal->{typ} eq "FLAG")
  {
  	$mem = "BOOLEAN";
  }
  	
	$signal->{init} = '0x0' if (defined($signal->{init}) and ($signal->{init} eq '0')); # fix! somehow the function signal_pruefen does not work correctly
	print OUTPUT "      <COD_DTYPE>$signal->{typ}</COD_DTYPE>
      <COD_INIT>$signal->{init}</COD_INIT>
      <COD_INVALID>$signal->{init}</COD_INVALID>
      <INTERFACE_TYPE>$signal->{interface}</INTERFACE_TYPE>
      <COD_NAME>$name</COD_NAME>
      <VAR_TYPE>variable</VAR_TYPE>
      <VAR_MEM_LOC_DEF>#define  IOPT_MEMMAP_DATA           MEMMAP_DATA($mem, ASIL_A, LOCAL, COM)</VAR_MEM_LOC_DEF>
      <VAR_MEM_LOC_DEF_INCLUDE>#include &lt;iopt_memmap.h></VAR_MEM_LOC_DEF_INCLUDE>
    </SYS_SIGNAL>\n";
} # sub var_schreiben


# mapping_schreiben
# schreibt Informationen über ein Mapping in neues datamodel.xml
sub mapping_schreiben
{
	my $mapping = $_[0];
	my $bus_signal = $_[1];
	my $id = $_[2];
	
	my $dir;
	my $signal;
	my $var;
	if(defined($rx_signale{$bus_signal}))
	{
		$dir = "RX";
		$signal = $rx_signale{$bus_signal};
	}
	else
	{
		$dir = "TX";
		$signal = $tx_signale{$bus_signal};
	}
	
	my $processing = "UNCONDITIONAL";
	my $condition = "";
	if($mapping->{processing} eq "STUB")
	{
		$processing = "STUB";
	}
	elsif($mapping->{processing} eq "BYPASS")
	{
		$processing = "BYPASS";
	}
	elsif($mapping->{processing} ne "")
	{
		$processing = "CONDITIONAL";
		if(lc($mapping->{processing}) eq "qualifier")
		{
			(my $base_name) = $mapping->{var} =~ /^[usb]\d+(\w+)$/;
			$condition = "Get_u8StateSig$base_name() != 1";
		}
		else
		{
			$condition = $mapping->{processing};
		}
	}

	# allgemeine Mapping-Konfiguration ausgeben
	print OUTPUT "    <MAPPING ID=\"$id\">
      <BUS_SIGNAL_REF>$bus_signal</BUS_SIGNAL_REF>
      <SYS_SIGNAL_REF>$mapping->{var}</SYS_SIGNAL_REF>
      <PROCESSING>$processing</PROCESSING>\n";
	
	# Konfiguration für Stub-Processing ausgeben (nur für TX-Signale)
	if($processing eq "STUB")
	{
		my $stub_val = "0x00";
		if(defined($signal->{init}) && $signal->{init} ne "")
		{
			$stub_val = $signal->{init};
		}
		print OUTPUT "      <PROCESSING_STUB>USER_VALUE</PROCESSING_STUB>
      <PROCESSING_STUB_USER_VALUE>$stub_val</PROCESSING_STUB_USER_VALUE>\n";
	}

	# Konfiguration für Conditional-Processing ausgeben (TX-Initwerte)
	if($processing eq "CONDITIONAL")
	{
		print OUTPUT "      <PROCESSING_CONDITION>$condition</PROCESSING_CONDITION>
      <PROCESSING_NEG_REACTION>INIT</PROCESSING_NEG_REACTION>\n";
	}
	
	# Konfiguration für Bypass-Processing ausgeben
	if($processing eq "BYPASS")
	{
		print OUTPUT "      <BYPASS_CALLOUT>ByPass_$bus_signal</BYPASS_CALLOUT>\n";
	}
	
  # Text-Mapping
  if((defined($mapping->{text_mappings})) && ($processing ne "STUB"))
  {
		print OUTPUT "      <TEXTTABLE>\n";
		# Nach numerischen Buswert sortiert ausgeben
		my %buswerte;
		foreach my $w (sort{$a <=> $b}(keys(%{$signal->{werte}})))
		{
			if(defined($mapping->{text_mappings}->{$signal->{werte}->{$w}}))
			{
				$buswerte{$signal->{werte}->{$w}} = 1;
	  		my $s = Encode::encode("utf-8", $signal->{werte}->{$w});
	  		my $d = Encode::encode("utf-8", $mapping->{text_mappings}->{$signal->{werte}->{$w}});
				print OUTPUT "        <MAP>
          <SRC>$s</SRC>
          <DST>$d</DST>
        </MAP>\n";
	    }
	  }				

		# Nicht in %buswerte enthaltene Mappings ausgeben (z.B. wenn TX-Signal und int. Bezeichnung abweichend von Busbezeichnung)
		foreach my $w (sort(keys(%{$mapping->{text_mappings}})))
		{
			if(!defined($buswerte{$w}))
			{
	  		my $s = Encode::encode("utf-8", $w);
	  		my $d = Encode::encode("utf-8", $mapping->{text_mappings}->{$w});
				print OUTPUT "        <MAP>
          <SRC>$s</SRC>
          <DST>$d</DST>
        </MAP>\n";
			}
		}
		print OUTPUT "      </TEXTTABLE>\n";
	}
	
	# Pre-Conversion-Callout: mögliche Werte: DISABLED (in XLSX = leer) oder CALLOUT
	if(($mapping->{pre_conv} eq "") || ($processing eq "STUB"))
	{
		print OUTPUT "      <PRE_CVT>DISABLED</PRE_CVT>\n";
	}
	else
	{
		print OUTPUT "      <PRE_CVT>CALLOUT</PRE_CVT>
      <PRE_CVT_CALLOUT>$mapping->{pre_conv}</PRE_CVT_CALLOUT>\n";
	}

	# Initialisation: mögliche Werte: DISABLED (in XLSX = leer), AUTO oder CALLOUT
	if($mapping->{init} eq "AUTO")
	{
		print OUTPUT "      <INITIALIZATION>AUTO</INITIALIZATION>\n";
	}
	elsif(($signal->{init} ne "") && ($dir eq "RX") && ($mapping->{init} ne ""))
	{
		print OUTPUT "      <INITIALIZATION>CALLOUT</INITIALIZATION>
      <INITIALIZATION_CALLOUT>$mapping->{init}</INITIALIZATION_CALLOUT>\n";
	}
	else
	{
		print OUTPUT "      <INITIALIZATION>DISABLED</INITIALIZATION>\n";
	}

	# Invalidation: mögliche Werte: DISABLED (in XLSX = leer), AUTO oder CALLOUT
	if($mapping->{invalid} eq "AUTO")
	{
		print OUTPUT "      <INVALIDATION>AUTO</INVALIDATION>\n";
	}
	elsif($mapping->{invalid} ne "" && $dir eq "RX")
	{
		print OUTPUT "      <INVALIDATION>CALLOUT</INVALIDATION>
      <INVALIDATION_CALLOUT>$mapping->{invalid}</INVALIDATION_CALLOUT>\n";
	}
	else
	{
		print OUTPUT "      <INVALIDATION>DISABLED</INVALIDATION>\n";
	}
	
	# External-Conversion-Callout
	if($mapping->{ext_conv} ne "")
	{
		print OUTPUT "      <EXT_CONVERSION>CALLOUT</EXT_CONVERSION>
      <EXT_CONVERSION_CALLOUT>$mapping->{ext_conv}</EXT_CONVERSION_CALLOUT>\n";
	}
	else
	{
		print OUTPUT "      <EXT_CONVERSION>DISABLED</EXT_CONVERSION>\n";
	}
	
	# Limitation
	print OUTPUT "      <LIMITATION>AUTO</LIMITATION>\n";
	
	# Post-Conversion-Callout
	if($mapping->{post_conv} ne "")
	{
		print OUTPUT "      <POST_CVT>CALLOUT</POST_CVT>
      <POST_CVT_CALLOUT>$mapping->{post_conv}</POST_CVT_CALLOUT>\n";		
	}
	else
	{
		print OUTPUT "      <POST_CVT>DISABLED</POST_CVT>\n";
	}

	# Out-of-Range-Callout
	if($mapping->{oor} ne "")
	{
		print OUTPUT "      <OUT_OFF_RANGE>CALLOUT</OUT_OFF_RANGE>
      <OUT_OFF_RANGE_CALLOUT>$mapping->{oor}</OUT_OFF_RANGE_CALLOUT>\n";
	}
	else
	{
		print OUTPUT "      <OUT_OFF_RANGE>CANCEL</OUT_OFF_RANGE>\n";
	}

	print OUTPUT "    </MAPPING>\n";
}

# writes the PDU mapping 
sub pdu_write
{
	my ($mapping, $pdu) = @_;
	
	#<PDU>
	#	<NAME>Message</NAME>
	#	<SECURED>false</SECURED>
	#	<AUX_TOUT xsi:nil="true"/>
	#	<AUX_PLAUS xsi:nil="true"/>
	#	<BUS_SIGNAL_REF>Signal1</BUS_SIGNAL_REF>
	#	<BUS_SIGNAL_REF>Signal2</BUS_SIGNAL_REF>
	#</PDU>
 
	print OUTPUT "     <PDU>\n";
	print OUTPUT "     	<NAME>$pdu</NAME>\n";
	print OUTPUT "     	<SECURED>false</SECURED>\n" if $mapping->{secured} == 0;
	print OUTPUT "     	<SECURED>true</SECURED>\n" if $mapping->{secured} == 1;
	print OUTPUT "     	<AUX_TOUT xsi:nil=\"true\"/>\n";
	print OUTPUT "     	<AUX_PLAUS xsi:nil=\"true\"/>\n";
	foreach my $sig (keys(%{$mapping->{signale}}))
	{
		print OUTPUT "     		<BUS_SIGNAL_REF>$sig</BUS_SIGNAL_REF>\n";
	}
	print OUTPUT "     </PDU>\n";

}

sub log_werte_trennen
{
	(my $log_werte, my $sig) = @_;

	if (defined($log_werte))
	{
		my @werte = ($log_werte =~ /[^:\"\n]+\s*:\s*[\dA-Fa-fx]+/g);
	
		foreach my $w (@werte)
		{
			$w =~ /([^:]+?)\s*:\s*([\dA-Fa-fx]+)/;
			my $text = $1;
			if ($text !~ /^(invalid|init value|SNA|invalid \/ init value)$/) # special cases of text values which should be not taken
			{
				$sig->{werte}->{hex($2)} = $1;
			}
		}
	}
}

# Prüft Konsistenz der Parameter für Signal, Variable und Mapping
sub signal_pruefen
{
	(my $signal, my $variable, my $mapping, my $sig_name, my $var_name, my $dir, my $log) = @_;
	
	my $bDefaultNumerics = 0;
	my $bWipeNumerics = 0;
	
	# Numerische Parameter prüfen
	if(!(($signal->{skalierung} && (defined($signal->{offset}) && ($signal->{offset} ne "")) && (defined($signal->{max}) && ($signal->{max} ne "")) && (defined($signal->{min}) && ($signal->{min} ne ""))) ||
	     (!$signal->{skalierung} && (!defined($signal->{offset}) || ($signal->{offset} eq "")) && (!defined($signal->{max}) || ($signal->{max} eq "")) && (!defined($signal->{min}) || ($signal->{min} eq "")))
	    )
	  )
	{
		print $log "$sig_name: Error: Either all of Resolution, Offset, Phys. Min and Phys. Max must be defined or none of them!\n";
		$bDefaultNumerics = 1;
	}
	else
	{
		# Wenn numerische Parameter definiert sind, müssen diese dezimal sein
		if(($signal->{skalierung} ne "") &&
		   (!($signal->{skalierung} > 0) ||
				!($signal->{skalierung} =~ /^[-\d\.Ee]+$/) ||
		    !($signal->{offset} =~ /^[-\d\.Ee]+$/) ||
		    !($signal->{max} =~ /^[-\d\.Ee]+$/) ||
		    !($signal->{min} =~ /^[-\d\.Ee]+$/)
		   )
		  )
		{
			print $log "$sig_name: Resolution, Offset, Phys. Min and Phys. Max must be decimal numbers!\n";
			$bDefaultNumerics = 1;
		}
	}
	
	# Prüfen, dass numerische Konvertierung, logische Werte oder beides definiert sind
	if(!$signal->{skalierung} && !$signal->{werte})
	{
		print $log "$sig_name: Error at least one of numerical conversion (Resolution, Offset, Phys. Min and Phys. Max) or logical values must be defined!\n";
   	$bDefaultNumerics = 1;
	}
	
	# Typ prüfen
	if(!$signal->{typ} || !($signal->{typ} =~ /([SU]\d+)|(FLAG)/))
	{
		print $log "$sig_name: Error: Type (Bus) is wrong!\n";
	}
	
	# Wenn Initwert für Signal definiert ist, muss dieser eine Hex-Zahl sein
	if($signal->{init} && (!($signal->{init} =~ /^0x[0-9A-Fa-f]+$/)))
	{
		$signal->{init} = sprintf("0x%x", $signal->{init});
		print $log "$sig_name: Init value must be a hex number (automatically corrected to $signal->{init})\n";
	}
	# Wenn Initwert für Signal definiert ist, muss ein Init-Callout definiert sein.
	# Wenn kein Initwert definiert ist, darf auch kein Init-Callout definiert sein.
	if(($signal->{init} && !$mapping->{init} && ($dir eq "RX")) || 
	   (!$signal->{init} && $mapping->{init})
	  )
	{
		print $log "$sig_name: If an init value is defined for a signal also an init callout must be defined. No callout must be defined if there is no init value\n";
	}

	# Wenn Invalidwert für Signal definiert ist, muss dieser eine Hex-Zahl sein
	if($signal->{invalid} && (!($signal->{invalid} =~ /^0x[0-9A-Fa-f]+$/)))
	{
		$signal->{invalid} = sprintf("0x%x", $signal->{invalid});
		print $log "$sig_name: Invalid value must be a hex number (automatically corrected to $signal->{invalid})\n";
	}
	# Wenn Invalidwert für Signal definiert ist, muss ein Invalid-Callout definiert sein.
	# Wenn kein invalidwert definiert ist, darf auch kein Invalid-Callout definiert sein. 
	if(($signal->{invalid} && !$mapping->{invalid} && ($dir eq "RX")) || 
	   (!$signal->{invalid} && $mapping->{invalid})
	  )
	{
		print $log "$sig_name: If an invalid value is defined for a signal also an invalid callout must be defined. No callout must be defined if there is no invalid value\n";
	}

	# check and clean text values and handle numeric value accordingly
	if (defined($signal->{werte}) and $signal->{werte})
	{
		$bWipeNumerics = CheckTextValue($sig_name, $signal, $log);
	}
	if ($bWipeNumerics)
	{
		ClearNumerics($sig_name, $signal, $log);
	}
	elsif ($bDefaultNumerics)
	{
		SetDefaultNumerics($sig_name, $signal, $log);
	}
	$bWipeNumerics = 0;
	$bDefaultNumerics = 0;
	
	# Variable
	if($var_name)
	{
		# Wenn Signal gestubbt ist, darf keine Variable konfiguriert sein
		if($mapping->{processing} && $mapping->{processing} eq "STUB")
		{
			print $log "$sig_name: Signal is configured as stub but variable $var_name is mapped!\n";
		}
		
		# Numerische Parameter prüfen
		if(!(($variable->{skalierung} && (defined($variable->{offset}) && ($variable->{offset} ne "")) && (defined($variable->{max}) && ($variable->{max} ne "")) && (defined($variable->{min}) && ($variable->{min} ne ""))) ||
		     (!$variable->{skalierung} && (!defined($variable->{offset}) || ($variable->{offset} eq "")) && (!defined($variable->{max}) || ($variable->{max} eq "")) && (!defined($variable->{min}) || ($variable->{min} eq "")))
		    )
		  )
		{
			print $log "$var_name: Error: Either all of Resolution, Offset, Phys. Min and Phys. Max must be defined or none of them!\n";
			$bDefaultNumerics = 1;
		}
		else
		{
			# Wenn numerische Parameter definiert sind, müssen diese dezimal sein
			if(($variable->{skalierung} ne "") &&
			   (!($variable->{skalierung} > 0) ||
				  !($variable->{skalierung} =~ /^[-\d\.Ee]+$/) ||
			    !($variable->{offset} =~ /^[-\d\.Ee]+$/) ||
			    !($variable->{max} =~ /^[-\d\.Ee]+$/) ||
			    !($variable->{min} =~ /^[-\d\.Ee]+$/)
			   )
			  )
			{
				print $log "$var_name: Resolution, Offset, Phys. Min and Phys. Max must be decimal numbers!\n";
				$bDefaultNumerics = 1;
			}
		}
		
		# Prüfen, dass numerische Konvertierung, logische Werte oder beides definiert sind
		if(!$variable->{skalierung} && !$variable->{werte})
		{
			print $log "$var_name: Error at least one of numerical conversion (Resolution, Offset, Phys. Min and Phys. Max) or logical values must be defined!\n";
			$bDefaultNumerics = 1;
		}
		
		# check and clean text values and handle numeric value accordingly
		if (defined($variable->{werte}) and $variable->{werte})
		{
			$bWipeNumerics = CheckTextValue($var_name, $variable, $log);
		}
		if ($bWipeNumerics)
		{
			ClearNumerics($var_name, $variable, $log);
		}
		elsif ($bDefaultNumerics)
		{
			SetDefaultNumerics($var_name, $variable, $log);
		}
	
		# Typ prüfen
		if(!$variable->{typ} || !($variable->{typ} =~ /([SU]\d+)|(FLAG)/))
		{
			print $log "$var_name: Error: Type (Int) is wrong!\n";
		}
		
		# Wenn Initwert für Variable definiert ist, muss dieser eine Hex-Zahl sein
		if($variable->{init} && (!($variable->{init} =~ /^0x[0-9A-Fa-f]+/)))
		{
			$variable->{init} = sprintf("0x%x", $variable->{init});
			print $log "$var_name: Init value must be a hex number (automatically corrected to $variable->{init})\n";
		}

		# Wenn Invalidwert für Variable definiert ist, muss dieser eine Hex-Zahl sein
		if($variable->{invalid} && (!($variable->{invalid} =~ /^0x[0-9A-Fa-f]+/)))
		{
			$variable->{invalid} = sprintf("0x%x", $variable->{invalid});
			print $log "$var_name: Invalid value must be a hex number (automatically corrected to $variable->{invalid})\n";
		}
	}
	elsif($mapping->{processing} ne "STUB")
	{
		print $log "$sig_name: Variable name is missing and signal is not configured as Stub!\n";
	}
	
	# Wenn Initwert für Variable definiert ist, muss dieser eine Hex-Zahl sein
	if($mapping->{init} && ($mapping->{init} !~ /^0x[0-9A-Fa-f]+/) && ($mapping->{init} !~ /AUTO/))
	{
		$mapping->{init} = sprintf("0x%x", $mapping->{init});
		print $log "$sig_name(mapping): Init value must be a hex number (automatically corrected to $mapping->{init})\n";
	}
	# Wenn Invalidwert für Variable definiert ist, muss dieser eine Hex-Zahl sein
	if($mapping->{invalid} && ($mapping->{invalid} !~ /^0x[0-9A-Fa-f]+/) && ($mapping->{invalid} !~ /AUTO/))
	{
		$mapping->{invalid} = sprintf("0x%x", $mapping->{invalid});
		print $log "$sig_name(mapping): Invalid value must be a hex number (automatically corrected to $mapping->{invalid})\n";
	}

	# Wenn Init-, Invalid-, Pre- oder OOR-Callout definiert ist, muss auch ein Post-Callout definiert sein
	if($mapping && ($dir eq "RX") && (($mapping->{init} || $mapping->{invalid} || $mapping->{oor} || $mapping->{pre_conv}) && !$mapping->{post_conv}))
	{
		print $log "$sig_name: If Init, Invalid, OOR or Pre conversion callout are defined, also a Post conversion callout must be defined!\n";
	}
}

# set default values to numerical parameters
sub SetDefaultNumerics
{
	my ($sig_name, $signal, $log) = @_;
	
	if ($signal->{skalierung} == 0)
	{
		$signal->{skalierung} = 1;
	}
	
	if ($signal->{offset} eq "")
	{
		$signal->{offset} = 0;
	}
	
	if ($signal->{min} eq "")
	{
		$signal->{min} = 0;
	}	
	
	if ($signal->{max} eq "")
	{
		if (defined($signal->{invalid}) and ($signal->{invalid} =~ /0x([0-9A-Fa-f]+)/))
		{
			$signal->{max} = hex($1) - 1;
		}
		else
		{
			if ($signal->{typ} eq 'FLAG')
			{
				$signal->{max} = 1;
			}
			elsif ($signal->{typ} eq 'U8')
			{
				$signal->{max} = hex('ff');
			}			
			elsif ($signal->{typ} eq 'U16')
			{
				$signal->{max} = hex('ffff');
			}			
			elsif ($signal->{typ} eq 'U32')
			{
				$signal->{max} = hex('ffffffff');
			}			
		}
	}	
	
	print $log "$sig_name: Info: Set default for Resolution($signal->{skalierung}), Offset($signal->{offset}), Phys. Min($signal->{min}) and Phys. Max($signal->{max}).\n";
}

# set default values to numerical parameters
sub ClearNumerics
{
	my ($sig_name, $signal, $log) = @_;
	
	if (defined($signal))
	{
		$signal->{skalierung} = "";
		$signal->{offset} = "";
		$signal->{min} = "";
		$signal->{max} = "";
		
		if (defined($log) and defined($sig_name))
		{
			print $log "$sig_name: Info: Wipe out Resolution, Offset, Phys. Min and Phys. Max.\n";
		}
	}
}


# check and clean text value
sub CheckTextValue
{
	my ($sig_name, $signal, $log) = @_;
	
	my $textvalue = $signal->{werte};
	return scalar keys %$textvalue; # number of keys	
}

sub trim
{
	my $string = $_[0];
	if (defined($string))
	{
		$string =~ s/^\s+|\s+$//g;
	}
	return $string;
}


1;
