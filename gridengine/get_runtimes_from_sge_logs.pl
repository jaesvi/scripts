#!/usr/bin/perl -w
use strict;

my %data;
my @headers = qw(
qname
hostname
group
owner
job_name
job_number
account
priority
submission_time
start_time
end_time
failed
exit_status
ru_wallclock
ru_utime
ru_stime
ru_maxrss
ru_ixrss
ru_ismrss
ru_idrss
ru_isrss
ru_minflt
ru_majflt
ru_nswap
ru_inblock
ru_oublock
ru_msgsnd
ru_msgrcv
ru_nsignals
ru_nvcsw
ru_nivcsw
project
department
granted_pe
slots
task_number
cpu
mem
io
category
iow
pe_taskid
maxvmem
arid
ar_submission_time
);

my $verbose=1;

my $period_start=0;
my $period_end=0;
my $total_cpu_time;
my $total_wall_clock;
my %jobs;

my $joblist = shift;
open JOB, $joblist or die "cannot open joblist file\n";

while (my $line=<JOB>){ 
    $jobs{$1}++ if $line =~ /Your job (\d+)/;
}

print scalar keys %jobs, " jobs stored from file $joblist ..\n";

if ($verbose==1) {
    print join("\t", qw(jobnumber jobname group owner cpu_time threads wall_clock department  start_time end_time sub_time)),"\n";
}

foreach my $file (@ARGV) {
    print "parsing $file..\n";
    if ($file =~ /.gz$/) {
	open IN, '-|','gzip', '-dc', $file or die "cannot open $file..\n";
    }else{
	open IN, $file or die "cannot open $file..\n";
    }
    
    
    
    while (my $line = <IN>) {
	chomp($line);
	next if $line =~ /^#/;
	my ($slots,$jobname, $jobnumber,$group, $owner, $cpu_time, $wall_clock,$department, $start_time, $end_time, $sub_time) = (split(/\:/,$line))[34,4,5,31,3,36,13,32,9,10,8]; #project is used for group definition
	next if $start_time == 0;
	next unless exists $jobs{$jobnumber};
	
	if ($verbose==1) {
	    
	    print join("\t", $jobnumber, $jobname, $group, $owner, $cpu_time, $slots,$wall_clock,$department, scalar localtime $start_time, scalar localtime $end_time, scalar localtime $sub_time),"\n";
	}
	
	
	
	
	$data{$group}{$department}{$owner}{'cpu_time'} += $cpu_time;
	$total_cpu_time +=  $cpu_time;
	
	$data{$group}{$department}{$owner}{'wall_clock'} += $wall_clock;
	$total_wall_clock +=  $wall_clock;
	
	
	$period_start = $start_time if ( ($start_time < $period_start) or ($period_start ==0) );
	$period_end = $end_time if ( ($end_time > $period_end) or ($period_end ==0) );
    }
    
    close(IN);
}
print "\n\nHPC usage tabel over period: ", scalar localtime $period_start,  " - ", scalar localtime $period_end,"\n";
print "GROUP\tDEPARTMENT\tUSER\tWALL_CLOCK\tCPU_hours\t%cpu_time\n";
foreach my $group (sort keys %data) {
    print $group,"\n";
    foreach my $department (sort keys %{$data{$group}}) {
    print "\t",$department,"\n";
	my $dept_cpu=0;
	my $dept_wall_clock = 0;
	foreach my $owner (sort keys %{$data{$group}{$department}}) {
	    my $owner_cpu = $data{$group}{$department}{$owner}{'cpu_time'};
	    my $owner_wall_clock = $data{$group}{$department}{$owner}{'wall_clock'};
	    $dept_cpu += $owner_cpu;
	    $dept_wall_clock += $owner_wall_clock;
	    print "\t\t$owner\t", int($owner_wall_clock/(60*60)),"\t",int($owner_cpu/(60*60)),"\t", sprintf("%.3f",($owner_cpu*100/$total_cpu_time)),"%\n";
	}
	print "\t\tTOTAL: $group\:$department\t", int($dept_wall_clock/(60*60)),"\t",int($dept_cpu/(60*60)),"\t", sprintf("%.3f",($dept_cpu*100/$total_cpu_time)),"%\n";
    }
}





=head
0	qname
1	hostname
2	group
3	owner
4	job_name
5	job_number
6	account
7	priority
8	submission_time
9	start_time
10	end_time
11	failed
12	exit_status
13	ru_wallclock
14	ru_utime
15	ru_stime
16	ru_maxrss
17	ru_ixrss
18	ru_ismrss
19	ru_idrss
20	ru_isrss
21	ru_minflt
22	ru_majflt
23	ru_nswap
24	ru_inblock
25	ru_oublock
26	ru_msgsnd
27	ru_msgrcv
28	ru_nsignals
29	ru_nvcsw
30	ru_nivcsw
31	project
32	department
33	granted_pe
34	slots
35	task_number
36	cpu
37	mem
38	io
39	category
40	iow
41	pe_taskid
42	maxvmem
43	arid
44	ar_submission_time
=cut