#!/usr/bin/perl
# use CGI::Carp qw(fatalsToBrowser);
# use Data::Dumper;

if ($ENV{'REQUEST_METHOD'} eq "GET") {
    $buffer = $ENV{'QUERY_STRING'};

    # Split information into name/value pairs
    
    @pairs = split(/&/, $buffer);
    foreach $pair (@pairs)
    {
	($name, $value) = split(/=/, $pair);
	$value =~ tr/+/ /;
	$value =~ s/%(..)/pack("C", hex($1))/eg;
	$GET{$name} = $value;
    }

    if ($GET{'act'} eq "") {
	print "Content-type: text/html\n\n";
	open (FILE,"templates/index.html");
	@data = <FILE>;
	foreach $line (@data) {
	    print "$line";
	}
	close (FILE);
    } else {
	print "Content-type: text/plain\n\n";

	my @acts = split(/[;\+]/, $GET{'act'});
	my $result = "failed";
	my $hostname = $GET{'host'};
	$ENV{DEST_HOSTNAME} = $hostname;
	my $content = "";
	
	foreach my $act (@acts) {
	    my($target, $action) = split(/ /, $act, 2);
	    my $cliutil = "";

	    if ($target eq "beep") {
		$duration = int($action)*25;
		for($i = 0; $i < int($action); $i++) {
		    system("/psp/utils/beep -f2600 -s -l5");
		}
		$result = "{'result': 'meep'}\n";

	    } elsif ($target eq "muck") {
		$duration = int($action)*25;
		for($i = 0; $i < int($action); $i++) {
		    system("/psp/utils/beep -f50 -s -l5");
		}
		$result = "{'result': 'meep'}\n";
		
	    } elsif ($target eq "screen") {
		if ($action eq "dim") {
		    system("echo 5 > /sys/devices/platform/stmp3xxx-bl/backlight/stmp3xxx-bl/brightness");
		} else {
		    system("echo 70 > /sys/devices/platform/stmp3xxx-bl/backlight/stmp3xxx-bl/brightness");
		}
		$result = "{'result': 'done'}\n";
	    } elsif ($target eq "diag") {
		if ($action eq "ip") {
		    $interface="wlan0";
		    # path to ifconfig
		    $ifconfig="/sbin/ifconfig";
		    @lines=qx|$ifconfig $interface| or die("Can't get info from ifconfig: ".$!);
		    foreach(@lines){
			    if(/inet addr:([\d.]+)/){
				    $result = "{'result': '$1'}";
			    }
		    }
		} else {
		    # Your code here
		}
	    } elsif ($target eq "temp") {
		$result=`/mnt/storage/bin/pcsensor -c`;
	    } else {
		$cmdresult = `$cliutil $action`;
		$result = "{'result': '$cmdresult'}";
	    }
	    #@args = ($cliutil, $action);
	    #system(@args);
	}

	if ($GET{'jsoncallback'} eq "") {
	    print $result;
	} else {
	    print "$GET{'jsoncallback'}($result)";
	}
    }
}

