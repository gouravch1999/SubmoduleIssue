use warnings;
use strict;
use Tk;
use Tk::DialogBox;
use Tk::BrowseEntry;
use utf8;

use Win32::File;

use lib '.';
use Sima2Konfig;
use XLSX2SIMA;
use XLSX2GRL;

# XLSX-Format-Version
my $version = "2015-12-09";

# Liste der zuletzt verwendeten Verzeichnisse
my @dirs; # = ("D:\\", "D:\\p\\au\\", "D:\\p\\au\\h0\\", "D:\\p\\au\\h2\\", "D:\\p\\au\\h0\\501\\", "D:\\p\\au\\h0\\502\\", "D:\\p\\au\\h2\200\\", "D:\\p\\au\\h2\\300\\");

# Liste der aktuell angezeigen Eingabefelder; wird benötigt, um die Auswahlliste zu aktualisieren
my @browse_entries;

# Zuletzt verwendete Verzeichnisse laden
if(open(INI, "D:\\COM-Configurator.ini"))
{
	while(<INI>)
	{
		chomp;
		if(/dir\s*=\s*(.*)/)
		{
			push(@dirs, $1);
		}
	}
	close(INI);
}

my $main = MainWindow->new (-title => "COM configurator");

my $button_frame = $main->Frame;
$button_frame->Button(-width => 25, -text => "Convert SiMa config to XLSX", -command => sub {sima2xlsx_handler()})->pack(-side => 'top');
$button_frame->Button(-width => 25, -text => "Convert XLSX to SiMa", -command => sub {xlsx2sima_handler()})->pack(-side => 'top');
$button_frame->Button(-width => 25, -text => "Convert XLSX to GRL", -command => sub {xlsx2grl_handler()})->pack(-side => 'top');
$button_frame->pack(-side => 'top');

MainLoop;

# Zuletzt verwendete Verzeichnisse speichern
if(-f "D:\\COM-Configurator.ini")
{
	# INI-Datei sichtbar machen
	Win32::File::GetAttributes ("D:\\COM-Configurator.ini", my $attr); 
	Win32::File::SetAttributes("D:\\COM-Configurator.ini", $attr & ~HIDDEN); 
}
if(open(INI, ">D:\\COM-Configurator.ini"))
{
	foreach my $d (@dirs)
	{
		print INI "dir=$d\n";
	}
	close(INI);

	# INI-Datei verstecken
	Win32::File::GetAttributes ("D:\\COM-Configurator.ini", my $attr); 
	Win32::File::SetAttributes("D:\\COM-Configurator.ini", $attr | HIDDEN); 
}

# öffnet Dialog zur Dateiauswahl um Sima-Konfig in Excel-Datei zu konvertieren
sub sima2xlsx_handler
{
	my $sima_config;
	my $xlsx;
	my $nicht_gemappte_ausgeben = 0;
	
	my $dg = $main->DialogBox(-title => "Convert SiMa to XLSX", -buttons => ["OK", "Cancel"]);

	# Select Sima config to convert
	my @sima_types = (['Sima config', ['.xml']], ['Sima config', ['.xml']]); # two times because of bug
	eingabefeld_erstellen($dg, "SiMa:", \$sima_config, "datamodel.xml", \@sima_types, "Select old SiMa config", 0);

	# Select XLSX to save
	my @xlsx_types = (['XLSX', ['.xlsx']], ['XLS', ['.xls']]); # two times because of bug
	eingabefeld_erstellen($dg, "XLSX:", \$xlsx, "signalConfig_Requirements.xlsx", \@xlsx_types, "Select XLSX to save", 1);

	# Output unmapped signals?
	my $cb_frame = $dg->add("Frame")->pack(-side => "top");
	$cb_frame->Checkbutton(-text => "Output unmapped signals and variables", -variable => \$nicht_gemappte_ausgeben, -width => 80)->pack(-side => "left");
	

	my $ret = $dg->Show();
	
	if($ret eq "Cancel")
	{
		return;
	}

	if(defined($sima_config) && $sima_config ne "")
	{
		utf8::decode($sima_config);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting SiMa config", -type => "OK");
		return;
	}

	if(defined($xlsx) && $xlsx ne "")
	{
		$xlsx =~ s/\//\\/g;		# Diese Ersetzung muss vor utf8::decode() stehen!!!
		utf8::decode($xlsx);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting XLSX file", -type => "OK");
		return;
	}

	my $s = sima2konfig($sima_config, $xlsx, $nicht_gemappte_ausgeben, $version);
	if($s ne "")
	{
		$main->messageBox(-title => "Error", -message => "$s", -type => "OK");
	}
	else
	{
		$main->messageBox(-title => "Info", -message => "Finished converting $sima_config to $xlsx.", -type => "OK");
	}

	# BrowseEntries dieses Handlers aus Liste entfernen
	@browse_entries = ();
}


# öffnet Dialog zur Dateiauswahl um Excel-Datei in SiMa-Konfig zu konvertieren
sub xlsx2sima_handler
{
	my $xlsx;
	my $old_sima_config;
	my $new_sima_config;
	my $nicht_gemappte_entfernen = 1;
	my $auto_system_signals = 0;
	
	my $dg = $main->DialogBox(-title => "Convert XLSX to SiMa", -buttons => ["OK", "Cancel"]);

	# Select XLSX to convert
	my @xlsx_types = (['XLSX', ['.xlsx']], ['XLS', ['.xls']]); # two times because of bug
	eingabefeld_erstellen($dg, "XLSX:", \$xlsx, "signalConfig_Requirements.xlsx", \@xlsx_types, "Select XLSX to convert", 0);

	# Select old SiMa config
	my @sima_types = (['Sima config', ['.xml']], ['Sima config', ['.xml']]); # two times because of bug
	eingabefeld_erstellen($dg, "Old SiMa/Template:", \$old_sima_config, "datamodel.xml", \@sima_types, "Select old SiMa config or template", 0);

	# Select new SiMa config to save
	my $new_sima_frame = $dg->add("Frame")->pack(-side => "top");
	eingabefeld_erstellen($dg, "New SiMa:", \$new_sima_config, "datamodel.xml", \@sima_types, "Select new SiMa config to save", 1);

	# Remove unmapped signals?
	my $cb_frame1 = $dg->add("Frame")->pack(-side => "top");
	$cb_frame1->Checkbutton(-text => "Remove unmapped signals and variables from SiMa config", -variable => \$nicht_gemappte_entfernen)->pack(-side => "left");

	# Remove unmapped signals?
	my $cb_frame2 = $dg->add("Frame")->pack(-side => "top");
	$cb_frame2->Checkbutton(-width => 100, -text => "Ignore old SiMa config but create system signal from variables and map them", -variable => \$auto_system_signals)->pack(-side => "left");

	my $ret = $dg->Show();
	
	if($ret eq "Cancel")
	{
		return;
	}

	if(defined($xlsx) && $xlsx ne "")
	{
		utf8::decode($xlsx);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting XLSX file", -type => "OK");
		return;
	}

	if(defined($old_sima_config) && $old_sima_config ne "")
	{
		utf8::decode($old_sima_config);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting old SiMa config or template", -type => "OK");
		return;
	}

	if(defined($new_sima_config) && $new_sima_config ne "")
	{
		utf8::decode($new_sima_config);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting new SiMa config", -type => "OK");
		return;
	}

	open(my $log, ">${new_sima_config}_log.txt");
	my $s = xlsx2sima($xlsx, $new_sima_config, $old_sima_config, $log, $nicht_gemappte_entfernen, $auto_system_signals, $version);
	close($log);
	if($s ne "")
	{
		$main->messageBox(-title => "Error", -message => "$s", -type => "OK");
	}
	else
	{
		$main->messageBox(-title => "Info", -message => "Finished converting $xlsx to $new_sima_config.\nSee ${new_sima_config}_log.txt for errors or warnings.", -type => "OK");
	}

	# BrowseEntries dieses Handlers aus Liste entfernen
	@browse_entries = ();
}


# öffnet Dialog zur Dateiauswahl um Excel-Datei in GRL-Datei zu konvertieren
sub xlsx2grl_handler
{
	my $xlsx;
	my $old_grl;
	my $new_grl;
	my $old_conv;
	my $tx2grl = 1;
	my $rx2decldef = 1;
	
	my $dg = $main->DialogBox(-title => "Convert XLSX to GRL", -buttons => ["OK", "Cancel"]);

	# Select XLSX to convert
	my @xlsx_types = (['XLSX', ['.xlsx']], ['XLS', ['.xls']]); # two times because of bug
	eingabefeld_erstellen($dg, "XLSX:", \$xlsx, "signalConfig_Requirements.xlsx", \@xlsx_types, "Select XLSX to convert", 0);

	# Select old GRL
	my @grl_types = (['DDS file', ['.grl']], ['DDS file', ['.grl']]); # two times because of bug
	eingabefeld_erstellen($dg, "Old GRL:", \$old_grl, "com.grl", \@grl_types, "Select old GRL file", 0);

	# Select new GRL
	eingabefeld_erstellen($dg, "New GRL:", \$new_grl, "com.grl", \@grl_types, "Select new GRL file", 1);

	# Select old @conversions.grl
	eingabefeld_erstellen($dg, "Old conversions:", \$old_conv, "\@conversions.grl", \@grl_types, "Select old conversions file", 0);

	# Add tx signals?
	my $cb_frame1 = $dg->add("Frame")->pack(-side => "top");
	$cb_frame1->Checkbutton(-text => "Add also tx bus signals to GRL file", -variable => \$tx2grl)->pack(-side => "left");

	# Add rx signals to file?
	my $cb_frame2 = $dg->add("Frame")->pack(-side => "top");
	$cb_frame2->Checkbutton(-width => 100, -text => "Add also rx bus signals to declFile and defFile", -variable => \$rx2decldef)->pack(-side => "left");

	my $ret = $dg->Show();
	
	if($ret eq "Cancel")
	{
		return;
	}

	if($xlsx)
	{
		utf8::decode($xlsx);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting XLSX file", -type => "OK");
		return;
	}

	if($old_grl)
	{
		utf8::decode($old_grl);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting old GRL file", -type => "OK");
		return;
	}

	if($new_grl)
	{
		utf8::decode($new_grl);
	}
	else
	{
		$main->messageBox(-title => "Warning", -message => "Error selecting new GRL file", -type => "OK");
		return;
	}

	if($old_conv)
	{
		utf8::decode($old_conv);
	}
	else
	{
		$old_conv = "";
	}

	open(my $log, ">${new_grl}_log.txt");
	my $s = xlsx2grl($xlsx, $new_grl, $old_grl, $old_conv, $version, $tx2grl, $rx2decldef, $log);
	close($log);
	if($s ne "")
	{
		$main->messageBox(-title => "Error", -message => "$s", -type => "OK");
	}
	else
	{
		$main->messageBox(-title => "Info", -message => "Finished converting $xlsx to $new_grl.", -type => "OK");
	}
	
	# BrowseEntries dieses Handlers aus Liste entfernen
	@browse_entries = ();
}


# Fügt ein BrowseEntry-Eingabefeld und eine Schaltfläche für die Dateiauswahl zum Frame $dg hinzu
# Aufruf: eingabefeld_erstellen($dg, $label, $file, $inifile, $filetypes, $title, $save);
# $dg: Referenz auf ein Tk::Frame
# $label: Beschriftung des Eingabefelds
# $file: Referenz auf Variable für Inhalt des Eingabefelds
# $inifile: vorgewählter Dateiname für Öffnen- / Speichern-Dialog
# $filetypes: Dateitypen wie von getOpen/SaveFile benötigt für Öffnen- / Speichern-Dialog
# $title: Titel des Öffnen- / Speichern-Dialogs
# $save: 0: Klick auf Schaltfläche öffnet Öffnen-Dialog, 1: Klick auf Schaltfläche öffnet Speichern-Dialog
sub eingabefeld_erstellen
{
	(my $dg, my $label, my $file, my $inifile, my $filetypes, my $title, my $save) = @_;
	
	my $frame = $dg->add("Frame")->pack(-side => "top");
	$frame->Label(-width => 25, -text => $label)->pack(-side => "left");
	my $path_entry = $frame->BrowseEntry(-text => "", -variable => $file, -width => 80, -choices => \@dirs)->pack(-side => "left");
	push(@browse_entries, [$path_entry, $file]);
	$frame->Button(-width => 15, -text => "Select ...", -command => sub { open_save_dialog($dg, $file, $inifile, $filetypes, $title, $save) } )->pack(-side => 'left');
}


# Öffnet einen Dateiauswahldialog zum Öffnen / Speichern von Dateien dar
# Pfad der ausgewählten Datei wird zum Array der zuletzt verwendeten Pfade hinzugefügt
# Aufruf: open_save_dialog($dg, $file, $inifile, $filetypes, $title, $save);
# $dg: Referenz auf ein Tk::Frame
# $file: Referenz auf Variable, die das Startverzeichnis des Dialogs / ausgewählte Datei nach Schließen des Dialogs enthält
# $inifile: vorgewählter Dateiname
# $filetypes: Dateitypen wie von getOpen/SaveFile benötigt
# $title: Titel des Dialogfelds
# $save: 0: getOpenFile wird aufgerufen, 1: getSaveFile wird aufgerufen
sub open_save_dialog
{
	(my $dg, my $file, my $inifile, my $filetypes, my $title, my $save) = @_;
	
	my $inidir = $dirs[0];
	if(${$file})
	{
		$inidir = ${$file};
		$inidir =~ tr/\//\\/;
		
		if($inidir =~ /^(.*\\)[^\\]+\.[^\\]+$/)
		{
			$inidir = $1;
		}
	}
	if(!$save)
	{
		${$file} = $dg->getOpenFile(-initialdir => $inidir, -initialfile => $inifile, -filetypes => $filetypes, -title => $title);
	}
	else
	{
		${$file} = $dg->getSaveFile(-initialdir => $inidir, -initialfile => $inifile, -filetypes => $filetypes, -title => $title);
	}
	
	# Ausgewählten Pfad zu den zuletzt verwendeten hinzufügen
	if(${$file})
	{
		my $seldir = ${$file};
		$seldir =~ tr/\//\\/;
		
		if($seldir =~ /^(.*\\)[^\\]+\.[^\\]+$/)
		{
			$seldir = $1;
		}
		for(my $i = 0; $i < @dirs; $i++)
		{
			if($dirs[$i] eq $seldir)
			{
				splice(@dirs, $i, 1);
				last;
			}
		}
		unshift(@dirs, $seldir);
		if(@dirs > 10)
		{
			pop(@dirs);
		}
	}
	# Pfade für alle Eingabefelder aktualisieren
	foreach my $be (@browse_entries)
	{
		# Aktualisieren der Pfade setzt das Feld auf den ersten Wert der Auswahlliste, deswegen Wert der zugehörigen Variable retten und danach zuweisen
		my $file_tmp = ${@{$be}[1]};
		@{$be}[0]->configure(-choices => \@dirs);
		${@{$be}[1]} = $file_tmp;
	}
}

