use strict;
use warnings;

#my $input;
my $output;

#($input) = @ARGV;

foreach my $input ("ipl_hook.c", "ipl_hook.h", "ipl_hook_mcr.h" )
{
	$input =~ /(.*).([ch])/;
	$output = $1 . "_conv.$2";
	
	open(INPUT, $input) or die "Could not open $input: $!\n";
	open(OUTPUT, ">$output") or die "Could not open $output: $!\n";
	
	while(<INPUT>)
	{
		if(!/ipl_variant/)
		{
			s/GET_/Get_/;
		}
		s/SET_/Set_/;
		
		print OUTPUT $_;
	}
	
	close(INPUT);
	close(OUTPUT);
}
