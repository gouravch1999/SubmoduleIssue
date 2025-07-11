package XLSX2GRL;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(xlsx2grl);

use strict;
use warnings;
use Fcntl qw(:seek);

use XLSX2SIMA qw(xlsx_lesen);
use XLSX qw(XLSX_ErrorHandling XLSX_SetColumns);

my %col; # for Excel columns

# initialization procedure
sub init_XLSX2GRL
{
	my ($hrCol) = @_;
	# set columns
	%col = %$hrCol;	
}

sub xlsx2grl
{
	my ($input_file, $output_file, $old_grl, $old_conv, $version, $tx2grl, $rx2decldef, $log) = @_;
	
	my %rx_signale;
	my %tx_signale;
	my %rx_vars;
	my %tx_vars;
	my %mappings;
	my %conversions;
	my %pdu_mapping;
	my %bus_mapping;
	
	open(OUTPUT, ">".$output_file) or return "Error on opening $output_file";
	open(OLD_GRL, $old_grl) or die "Error on opening $old_grl";
	
	# Einlesen des Excel-Dokuments mit der Funktion xlsx_lesen aus XLSX2SIMA.pm
	my $fehler = xlsx_lesen($input_file, $version, \%rx_signale, \%tx_signale, \%rx_vars, \%tx_vars, \%mappings, \%pdu_mapping, \%bus_mapping, $log);
	if($fehler ne "")
	{
		return $fehler;
	}
	
	# Mapping Variabe -> Signal erstellen, für Variablenkommentar
	my %rev_mappings;
	foreach my $s (keys(%mappings))
	{
		if($mappings{$s}->{var})
		{
			$rev_mappings{$mappings{$s}->{var}} = $s;
		}
	}
	
	my @vars = keys(%rx_vars);
	
	if ($tx2grl)
	{ # use also tx signals
		my @txvars = keys(%tx_vars);
		push(@vars, @txvars);
	}
	
					
	# Altes com.grl lesen und die dort definierten TX-Variablen zusätzlich zu den RX-Variablen in die Liste der zu generierenden aufnehmen, falls noch in XLSX definiert
	while(<OLD_GRL>)
	{
		if(/online\s+(\w+)/)
		{
			if(defined($tx_vars{$1}))
			{
				push(@vars, $1);
			}
		}
	}
	
	# Altes com.grl zum Anfang zurückspulen
	seek(OLD_GRL, 0, SEEK_SET);
	
	# Altes com.grl lesen, alles außer online-Definitionen in neues grl ausgeben, neue online-Definitionen schreiben
	my $online = 0;
	my $ausg = 1;
	while(<OLD_GRL>)
	{
		if(/online\s+\w+/)
		{
			# neue online-Definitionen schreiben
			if($ausg)
			{
				foreach my $v (sort(@vars))
				{
					if(defined($rx_vars{$v}))
					{
						variable_schreiben($v, $rx_vars{$v}, $rev_mappings{$v}, 0, $rx2decldef, \%conversions);
					}
					elsif(defined($tx_vars{$v}))
					{
						variable_schreiben($v, $tx_vars{$v}, $rev_mappings{$v}, 1, $rx2decldef, \%conversions);
					}
				}
				$ausg = 0;
			}
			$online = 1;
		}
		elsif($online && /^}/)
		{
			# wenn nächste Zeile Leerzeile, diese auch entfernen
			my $pos = tell(OLD_GRL);
			my $l = <OLD_GRL>;
			if(!($l =~ /^\s*$/))
			{
				seek(OLD_GRL, $pos, SEEK_SET);
			}
			$online = 0;
		}
		elsif(!$online)
		{
			# Zeile nicht ausgeben, wenn in alter online-Definition
			print OUTPUT $_;
		}
	}
	
	close(OLD_GRL);
	close(OUTPUT);
	
	# Prüfen, ob alle Conversions definiert sind
	conv_pruefen(\%conversions, $old_conv, $output_file);
}


# gibt eine Variablendefinition aus
sub variable_schreiben
{
	my ($name, $var, $signal, $tx, $rx2decldef, $conversions) = @_;
	
	printf "%d:%s\n", $tx, $name;
	
	my $typ;
	my $len;
	if($var->{typ} eq "FLAG") { $typ = "boolean"; $len = 1; }
	elsif($var->{typ} eq "U8") { $typ = "uint8"; $len = 8; }
	elsif($var->{typ} eq "U16") { $typ = "uint16"; $len = 16; }
	elsif($var->{typ} eq "U32") { $typ = "uint32"; $len = 32; }
	elsif($var->{typ} eq "S8") { $typ = "sint8"; $len = 8; }
	elsif($var->{typ} eq "S16") { $typ = "sint16"; $len = 16; }
	elsif($var->{typ} eq "S32") { $typ = "sint32"; $len = 32; }
	
	print OUTPUT "online $name {\n";
	if(($tx) or ($rx2decldef))
	{
		print OUTPUT "	declFile = cFile 'com_data.h';\n";
		print OUTPUT "	defFile = cFile 'com_data.c';\n";
	}
	print OUTPUT "	memoryRegion = memRegion INT_RAM;\n";
	print OUTPUT "	elemType = numberType $typ;\n";
	print OUTPUT "	update = onlineUpdate '10ms';\n";
	my $einheit;
	if($var->{einheit})
	{
		if(($var->{einheit} =~ /^\w*$/) || ($var->{einheit} =~ /^'.*'$/))
		{
			$einheit = $var->{einheit};
		}
		else
		{
			$einheit = "'$var->{einheit}'";
		}
	}
	if($typ eq "boolean")
	{
		print OUTPUT "	numFormat = numFormat '%s';\n";
		if($var->{einheit}) { print OUTPUT "	physUnit = physUnit $einheit;\n"; }
		print OUTPUT "	sourceSection = \n";
		print OUTPUT "		sourceSectionRef {\n";
		print OUTPUT "			declFile = sourceSection MEM_DATA_PUBLIC_FLAG_H;\n";
		print OUTPUT "			defFile = sourceSection MEM_DATA_PUBLIC_FLAG;\n";
		print OUTPUT "		}\n";

		print OUTPUT "	conversion = conversion 'RANGE     [0, 0H, 0H] [1, 1H, 1H]';\n";
	}
	else
	{
		print OUTPUT "	numFormat = numFormat '%10.6f';\n";
		if($var->{einheit}) { print OUTPUT "	physUnit = physUnit $einheit;\n"; }
		print OUTPUT "	sourceSection = \n";
		print OUTPUT "		sourceSectionRef {\n";
		print OUTPUT "			declFile = sourceSection MEM_DATA_PUBLIC_${len}_H;\n";
		print OUTPUT "			defFile = sourceSection MEM_DATA_PUBLIC_${len};\n";
		print OUTPUT "		}\n";

		my $phys_min;
		my $phys_max;
		my $code_min_num;
		my $code_max_num;
		if($var->{skalierung})
		{
			if(substr($typ, 0, 1) eq "s")
			{
				$code_min_num = 2 ** ($len - 1);
				$code_max_num = 2 ** ($len - 1) - 1;
			}
			else
			{
				$code_min_num = 0;  #($var->{min} - $var->{offset}) / $var->{skalierung};
				$code_max_num = (2**$len) - 1;  #($var->{max} - $var->{offset} + ($var->{skalierung} / 2)) / $var->{skalierung};
			}
			$phys_min = ((-1 * $code_min_num) * $var->{skalierung}) + $var->{offset};
			$phys_max = ($code_max_num * $var->{skalierung}) + $var->{offset};
		}
		else
		{
			$phys_min = 0;
			$phys_max = (2**$len) - 1;
			$code_min_num = 0;
			$code_max_num = (2**$len) - 1;
		}
		my $conv = sprintf("LINEAR     [%.6f, %XH] [%.6f, %XH]", $phys_min, $code_min_num, $phys_max, $code_max_num);
		print OUTPUT "	conversion = conversion '$conv';\n";
		$conversions->{$conv} = { min => $phys_min, max => $phys_max, min_hex => $code_min_num, max_hex => $code_max_num };
	}
	print OUTPUT "	mappingScheme = mappingSchemeOnline '20';\n";
	print OUTPUT "	calFunction = calFunction COM;\n";
	print OUTPUT "	description = \n";
	print OUTPUT "		mlString {\n";
	if(!$tx)
	{
		print OUTPUT "			value = \"received value for signal $signal\";\n";
	}
	else
	{
		print OUTPUT "			value = \"value to send for signal $signal\";\n";
	}
	print OUTPUT "			language = language en;\n";
	print OUTPUT "		}\n";
	print OUTPUT "}\n\n";
}

# @conversions.grl einlesen und nicht definierte Conversions in Datei mit dem Namen der generierten GRL-Datei mit angehängtem _conv.grl ausgeben.
# Rückgabewert: leerer String, wenn kein Fehler, sonst String mit Fehlerursache (oder Hinweis auf in @conversions.grl nicht vorhandene Conversions)
sub conv_pruefen
{
	(my $conversions, my $old_conv, my $grl) = @_;
	
	my $ret = "";
	
	$grl =~ /(^.*\/?[^\/]+)\.grl/;
	my $new_conv = $1 . "_conv.grl";

	if(($old_conv ne "") && open(OLD_CONV, $old_conv))
	{
		# Altes @conversions.grl lesen und darin definierte Conversions in $conversions löschen
		while(<OLD_CONV>)
		{
			if(/conversion\s+'(.*)'/)
			{
				delete($conversions->{$1});
			}
		}
		close(OLD_CONV);
	}
	else
	{
		$ret = "No old \@conversions.grl given. Check if all conversions in $new_conv are defined.";
	}
	
	# Die verbleibenden in Datei mit dem selben Namen wie generierte com.grl, mit Endung _conv.grl aufgeben
	if(keys(%{$conversions}) > 0)
	{
		open(NEW_CONV, ">$new_conv") or return "Error on opening $new_conv";
		if($ret eq "")
		{
			$ret = "Some conversions are missing in \@conversions.grl. See $new_conv";
		}

		foreach my $c (sort(keys(%{$conversions})))
		{
			print NEW_CONV "conversion '$c' {\n";
			print NEW_CONV "	intRealTable = (\n";
			print NEW_CONV "		intRealItem {\n";
			print NEW_CONV "			real = $conversions->{$c}->{min};\n";
			print NEW_CONV "			int = $conversions->{$c}->{min_hex};\n";
			print NEW_CONV "		}\n";
			print NEW_CONV "		intRealItem {\n";
			print NEW_CONV "			real = $conversions->{$c}->{max};\n";
			print NEW_CONV "			int = $conversions->{$c}->{max_hex};\n";
			print NEW_CONV "		}\n";
			print NEW_CONV "		)\n";
			print NEW_CONV "	kind = conversionKind interpolationTable;\n";
			print NEW_CONV "}\n\n";
		}
		close(NEW_CONV);
	}
	
	return $ret;
}


1;
