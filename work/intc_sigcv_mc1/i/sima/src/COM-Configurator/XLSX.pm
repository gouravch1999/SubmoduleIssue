package XLSX;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(XLSX_ErrorHandling XLSX_SetColumns);

use strict;
use warnings;

use Win32::OLE;
use Win32::OLE::Const 'Microsoft Excel';
use Win32::OLE::Variant;


# Excel-Fehler prüfen
sub XLSX_ErrorHandling
{
	(my $handle, my $book, my $msg) = @_;
	
	if(Win32::OLE->LastError() != 0)
	{
		my $err = Win32::OLE->LastError();
		if(defined($book))
		{
			$book->Close( { SaveChanges => 0 } );
		}
		if(defined($handle))
		{
			$handle->Quit();
		}
		return "$msg: $err.";
	}
	else
	{
		return "";
	}
}

# Creates a hash with all required Excel columns of the Signal Mapping sheet
# Returns the reference for the just created hash
sub XLSX_SetColumns
{
	my %col;
	
	$col{'Signal'} = 'A';
	$col{'Dir'} = 'B';
	$col{'Type (Bus)'} = 'C';
	$col{'Init value (Bus)'} = 'D';
	$col{'Invalid value (Bus)'} = 'E';
	$col{'Description (Bus)'} = 'F';
	$col{'Resolution (Bus)'} = 'G';
	$col{'Offset (Bus)'} = 'H';
	$col{'Phy. Min. (Bus)'} = 'I';
	$col{'Phy. Max. (Bus)'} = 'J';
	$col{'Unit (Bus)'} = 'K';
	$col{'Logical values (Bus)'} = 'L';
	$col{'Interface Type (Bus)'} = 'M';	
	$col{'Variable'} = 'N';
	$col{'Type (int)'} = 'O';
	$col{'Init value (int)'} = 'P';
	$col{'Description (int)'} = 'Q';
	$col{'Resolution (int)'} = 'R';
	$col{'Offset (int)'} = 'S';
	$col{'Phy. Min. (int)'} = 'T';
	$col{'Phy. Max. (int)'} = 'U';
	$col{'Unit (int)'} = 'V';
	$col{'Logical values (int)'} = 'W';
	$col{'Interface Type (int)'} = 'X';	
	$col{'Processing'} = 'Y';
	$col{'Oor'} = 'Z';
	$col{'External conversion'} = 'AA';
	$col{'Text mappings'} = 'AB';
	$col{'Pre conv. callout'} = 'AC';
	$col{'Post conv. callout'} = 'AD';
	$col{'Init handling'} = 'AE';
	$col{'Invalid handling'} = 'AF';
	$col{'PDU'} = 'AG';
	$col{'unhandled values'} = 'AH';

	return \%col;
}

1;
