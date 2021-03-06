#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use Getopt::Long;
use File::Slurp;
use JSON;
use XML::Simple;
use 5.010.000;

## -----
## Global variables
## -----
my $DATETIME = localtime;
my $SCRIPT = basename $0;
my $OUT_SEP = "\t";
my $NA_CHAR = "NA";

my $SSHT_LOC = 'SampleSheet.csv';
my $RXML_LOC = 'RunInfo.xml';
my $JSON_LOC = 'Data/Intensities/BaseCalls/Stats/Stats.json';
my $LANE_KEY = 'ConversionResults';
my $SMPL_KEY = 'DemuxResults';
my $READ_KEY = 'ReadMetrics';
my $BARC_KEY = 'IndexMetrics';
my @OUT_FIELDS = qw( flowcell yld q30 pf yld_p mm0 mm1 id name submission description );
my @SUM_FIELDS = qw( submission id name yld q30 description );

my $YIELD_FACTOR = 1e6;
my $ROUND_DECIMALS = 0;
my %QC_LIMITS = (
    'lane_yld' => undef,
    'lane_q30' => undef,
    'samp_yld' => undef,
    'samp_q30' => undef,
    'max_undt' => undef
);

my $RUN_PATH;
my $JSON_PATH;
my $RXML_PATH;
my $SSHT_PATH;

my $HELP =<<HELP;

  Description
    Parses conversion output json and prints table with
    flowcell/lane/sample/read metrics
    
  Usage
    $SCRIPT -run \${run-path} -samplesheet \${samplesheet-path}
    $SCRIPT -json \${json-path}
    
  Options
    -sep <s>               Output sep (default = <TAB>)
    -max_undet_perc <i>    Percentage
    -min_lane_q30 <i>      Percentage
    -min_sample_q30 <i>    Percentage
    -min_lane_yield <i>    Bases
    -min_sample_yield <i>  Bases
    -yield_factor <i>      Factor to divide all yields with ($YIELD_FACTOR)
    -round_decimals <i>    Factor to divide all yields with ($ROUND_DECIMALS)
    -samplesheet <s>       Path to SampleSheet.csv file
    -run_info_xml <s>      Path to RunInfo.xml file
    -no_qc                 Skip QC checks
    -summary               Prints extra sample summary table
    -debug                 Prints complete datastructure
    
HELP
print $HELP and exit(0) if scalar @ARGV == 0;

## -----
## Gather input
## -----
my %opt = ();
GetOptions (
  "run_dir=s"          => \$RUN_PATH,
  "json_path=s"        => \$JSON_PATH,
  "samplesheet=s"      => \$SSHT_PATH,
  "run_info_xml=s"     => \$RXML_PATH,
  "sep=s"              => \$OUT_SEP,
  "max_undet_perc=i"   => \$QC_LIMITS{ 'max_undt' },
  "min_sample_yield=i" => \$QC_LIMITS{ 'samp_yld' },
  "min_lane_yield=i"   => \$QC_LIMITS{ 'lane_yld' },
  "min_sample_q30=i"   => \$QC_LIMITS{ 'samp_q30' },
  "min_lane_q30=i"     => \$QC_LIMITS{ 'samp_q30' },
  "yield_factor=i"     => \$YIELD_FACTOR,
  "round_decimals=i"   => \$ROUND_DECIMALS,
  "no_qc"              => \$opt{ no_qc },
  "summary"            => \$opt{ print_summary },
  "debug"              => \$opt{ debug },
  "help|h"             => \$opt{ help },
) or die "[ERROR] Issue in command line arguments\n";
print $HELP and exit(0) if $opt{ help };
die "[ERROR] Provide either run-dir or json-path not both\n" if (defined $RUN_PATH and defined $JSON_PATH);
die "[ERROR] Provide either run-dir or json-path, see -h\n" unless (defined $RUN_PATH or defined $JSON_PATH);
die "[ERROR] Provided run dir does not exist ($RUN_PATH)\n" if defined $RUN_PATH and not -d $RUN_PATH;
die "[ERROR] Provided json does not exist ($JSON_PATH)\n" if defined $JSON_PATH and not -f $JSON_PATH;
die "[ERROR] Provided xml does not exist ($RXML_PATH)\n" if defined $RXML_PATH and not -f $RXML_PATH;

$JSON_PATH = "$RUN_PATH/$JSON_LOC" if defined $RUN_PATH;
$RXML_PATH = "$RUN_PATH/$RXML_LOC" if defined $RUN_PATH;
$SSHT_PATH = "$RUN_PATH/$SSHT_LOC" if (defined $RUN_PATH and not defined $SSHT_PATH);

## -----
## MAIN
## -----

my $seq_run = basename $RUN_PATH;
my $ssht_info = readSampleSheet( $SSHT_PATH );
my $json_info = readJson( $JSON_PATH );
my $rxml_info = readXml( $RXML_PATH );
my $parsed_info = parseJsonInfo( $json_info, $rxml_info );

addSamplesheetInfo( $parsed_info, $ssht_info, $seq_run );
performQC( $parsed_info ) unless $opt{ no_qc };

if ( $opt{ print_summary } ){
    printSummaryTable( $parsed_info, \@SUM_FIELDS );
}
else{
    printTable( $parsed_info, \@OUT_FIELDS );
}

if ( $opt{ debug } ){
    say "[DEBUG] Samplesheet data structure";
    print Dumper $ssht_info;
    say "[DEBUG] Complete final data structure";
    print Dumper $parsed_info;
}

## -----
## /MAIN
## -----

sub addSamplesheetInfo{
    my ($json_info, $ssht_info, $seq_run) = @_;
    
    ## add run name: eg X17-0001
    $json_info->{ 'stats' }{ 'seq_runname' } = $seq_run;
    $json_info->{ 'stats' }{ 'hmf_runname' } = $ssht_info->{'runname'};
    $json_info->{ 'stats' }{ 'platform' } = $ssht_info->{'platform'};
    
    ## add sample metadata
    my $samples = $json_info->{ 'samp' };
    foreach my $sample_id ( keys %$samples ){
        my $sample = $samples->{ $sample_id };
        
        my $submission = $NA_CHAR;
        $submission = $ssht_info->{'samples'}{$sample_id}{ 'Sample_Project' } if defined $ssht_info->{'samples'}{$sample_id}{ 'Sample_Project' };
        $sample->{ 'submission_print' } = $submission;
        
        my $description = $NA_CHAR;
        $description = $ssht_info->{'samples'}{$sample_id}{ 'Description' } if defined $ssht_info->{'samples'}{$sample_id}{ 'Description' };
        $sample->{ 'description_print' } = $description;
    }
}

sub readXml{
    my ($file) = @_;
    my $obj = XMLin( $file );
    return($obj);
}

sub readJson{
    my ($json_file) = @_;
    my $json_txt = read_file( $json_file );
    my $json_obj = decode_json( $json_txt );
    return( $json_obj );
}

sub performQC{
    my ($info) = @_;
   
    my $stats = $info->{'stats'};
    my $samps = $info->{'samp'};
    my $lanes = $info->{'lane'};
    my $fails = 0;
    
    my $identifier = $stats->{'identifier'};
    my $platform = $stats->{'platform'};
    
    ## setup qc limit by platform unless provided by user
    my %platform_qc_limits = (
        'HiSeq' => {
            'lane_yld' => 100e9,
            'lane_q30' => 75,
            'samp_yld' => 1e9,
            'samp_q30' => 75,
            'max_undt' => 8
        },
        'NextSeq' => {
            'lane_yld' => 8e9,
            'lane_q30' => 75,
            'samp_yld' => 1e9,
            'samp_q30' => 75,
            'max_undt' => 8
        },
        'NovaSeq' => {
            'lane_yld' => 100e9,
            'lane_q30' => 75,
            'samp_yld' => 1e9,
            'samp_q30' => 75,
            'max_undt' => 8
        },
        'ISeq' => {
            'lane_yld' => 0,
            'lane_q30' => 75,
            'samp_yld' => 0,
            'samp_q30' => 75,
            'max_undt' => 8
        }
    );
       
    ## determine actual platform in use
    my @possible_platforms = keys %platform_qc_limits;
    my $limit_to_use = ();
    foreach my $platform_name ( @possible_platforms ){
        if ( $platform =~ /$platform_name/ ){
            say "## Setting QC limit for platform $platform_name";
            my $limits = $platform_qc_limits{ $platform_name };
            foreach my $limit_name ( keys %$limits ){
                next if defined $QC_LIMITS{ $limit_name };
                $QC_LIMITS{ $limit_name } = $limits->{ $limit_name };
            }
        }
    }

    ## flowcell checks
    my $undet = $stats->{'undet_perc'};
    my $max_undet = $QC_LIMITS{ 'max_undt' };
    if ( $undet > $max_undet ){
        say "## WARNING Percentage undetermined ($undet) too high (max=$max_undet)";
        $fails += 1;
    }
        
    ## lane and sample checks
    $fails += checkObjectField( $lanes, 'yield', $QC_LIMITS{ 'lane_yld' } );
    $fails += checkObjectField( $lanes, 'q30',   $QC_LIMITS{ 'lane_q30' } );
    $fails += checkObjectField( $samps, 'yield', $QC_LIMITS{ 'samp_yld' } );
    $fails += checkObjectField( $samps, 'q30',   $QC_LIMITS{ 'samp_q30' } );
    
    ## conclusion
    my $flowcell_qc = "NoQcResult";
    if ( $fails == 0 ){
        $flowcell_qc = "PASS";
        say "## FINAL QC RESULT: OK";
    }
    else{
        $flowcell_qc = "FAIL";
        warn "## WARNING Some checks failed, inspect before proceeding (for $identifier)\n";
        say "## FINAL QC RESULT: FAIL (for $identifier)";
    }
    $stats->{'flowcell_qc'} = $flowcell_qc;
}

sub checkObjectField{
    my ($objects, $field, $min) = @_;
    my $fails = 0;
    foreach my $obj_key ( sort { $objects->{$b}{'name'} cmp $objects->{$a}{'name'} } keys %$objects){
        my $obj = $objects->{$obj_key};
        my $name = $obj->{'name'};
        next if $name eq 'UNDETERMINED';
        my $value = 0;
        $value = $obj->{$field} if exists $obj->{$field};
        if ( $value < $min ){
            say "## WARNING $field for $name too low: $value < $min";
            $fails += 1;
        }
    }
    return $fails;
}

sub parseJsonInfo{
    my ($raw_json_info, $run_xml_info) = @_;
    my %info = ();

    ## Reading phase
    my @cycle_counts = map( $_->{NumCycles}, @{$run_xml_info->{Run}{Reads}{Read}});
    my $cycle_string = join( "|", @cycle_counts);
    my $fid = $raw_json_info->{ 'Flowcell' };
    $info{ 'flow' }{ $fid }{ 'id' } = $fid;
    $info{ 'flow' }{ $fid }{ 'name' } = $raw_json_info->{ 'RunId' };
    
    my $lanes = $raw_json_info->{ $LANE_KEY };
    foreach my $lane ( @$lanes ){
        my $lid = join( "", "lane", $lane->{ LaneNumber } );
        $info{ 'lane' }{ $lid }{ name } = $lid;
        
        $info{ 'flow' }{ $fid }{ clust_raw } += $lane->{ TotalClustersRaw };
        $info{ 'flow' }{ $fid }{ clust_pf } += $lane->{ TotalClustersPF };
        $info{ 'lane' }{ $lid }{ clust_raw } += $lane->{ TotalClustersRaw };
        $info{ 'lane' }{ $lid }{ clust_pf } += $lane->{ TotalClustersPF };
        
        ## Undetermined info is stored separate from samples in json
        my $undet_id = 'UNDETERMINED';
        my $undet_obj = $lane->{ 'Undetermined' };
        my $undet_reads = $undet_obj->{ $READ_KEY };
        my $undet_info = \%{$info{ 'undt' }{ $undet_id }};
        $undet_info->{ 'name' } = $undet_id;
        foreach my $read ( @$undet_reads ){
            my $rid = join( "", "read", $read->{ ReadNumber } );
            $undet_info->{ 'yield' } += $read->{ Yield };
            $undet_info->{ 'yield_q30' } += $read->{ YieldQ30 };
            $info{ 'flow' }{ $fid }{ 'yield' } += $read->{ Yield };
            $info{ 'flow' }{ $fid }{ 'yield_q30' } += $read->{ YieldQ30 };
            $info{ 'lane' }{ $lid }{ 'yield' } += $read->{ Yield };
            $info{ 'lane' }{ $lid }{ 'yield_q30' } += $read->{ YieldQ30 };
            $info{ 'read' }{ $rid }{ 'yield' } += $read->{ Yield };
            $info{ 'read' }{ $rid }{ 'yield_q30' } += $read->{ YieldQ30 };
        }
        
        ## sample info stored together at SMPL_KEY key
        my $samples = $lane->{ $SMPL_KEY };
        foreach my $sample ( @$samples ){
            
            my $sid = $NA_CHAR;
            
            ## Reset info for all real samples
            $sid = $sample->{ SampleId } if exists $sample->{ SampleId };
            $info{ 'samp' }{ $sid }{ name } = $sample->{ SampleName } if exists $sample->{ SampleName };
            $info{ 'samp' }{ $sid }{ 'seq' } = $sample->{ $BARC_KEY }[0]{ 'IndexSequence' } || $NA_CHAR;
            
            my $reads = $sample->{ $READ_KEY };
            foreach my $read ( @$reads ){
                my $rid = join( "", "read", $read->{ ReadNumber } );
                $info{ 'read' }{ $rid }{ 'name' } = $rid;
                
                $info{ 'flow' }{ $fid }{ 'yield' } += $read->{ Yield };
                $info{ 'lane' }{ $lid }{ 'yield' } += $read->{ Yield };
                $info{ 'samp' }{ $sid }{ 'yield' } += $read->{ Yield };
                $info{ 'read' }{ $rid }{ 'yield' } += $read->{ Yield };
                
                $info{ 'flow' }{ $fid }{ 'yield_q30' } += $read->{ YieldQ30 };
                $info{ 'lane' }{ $lid }{ 'yield_q30' } += $read->{ YieldQ30 };
                $info{ 'samp' }{ $sid }{ 'yield_q30' } += $read->{ YieldQ30 };
                $info{ 'read' }{ $rid }{ 'yield_q30' } += $read->{ YieldQ30 };
            }
            
            my %bc_mismatch_counts = (
                'mm0' => $sample->{ $BARC_KEY }[0]{ 'MismatchCounts' }{ '0' },
                'mm1' => $sample->{ $BARC_KEY }[0]{ 'MismatchCounts' }{ '1' },
            );
            
            my @types = keys %bc_mismatch_counts;
            foreach my $mm ( @types ){
                my $count = 0;
                $count = $bc_mismatch_counts{ $mm } if defined $bc_mismatch_counts{ $mm };
                $info{ 'flow' }{ $fid }{ $mm } += $count;
                $info{ 'lane' }{ $lid }{ $mm } += $count;
                $info{ 'samp' }{ $sid }{ $mm } += $count;
            }
        }
    }

    ## Create the info to print later
    foreach my $type ( keys %info ){
        foreach my $id ( keys %{$info{ $type }} ){
            my $obj = $info{ $type }{ $id };
            my $name = $obj->{ 'name' };
            
            $obj->{ 'q30' } = getPerc( $obj->{ 'yield_q30' }, $obj->{ 'yield' } );
            $obj->{ 'yld_p' } = getPerc( $obj->{ 'yield' }, $info{ 'flow' }{ $fid }{ 'yield' } );
            $obj->{ 'flowcell_print' } = $fid;

            $obj->{ 'q30_print' } = round( $obj->{ 'q30' } );
            $obj->{ 'yld_print' } = round( $obj->{ 'yield' }, $ROUND_DECIMALS, $YIELD_FACTOR );
            $obj->{ 'id_print' } = $id;
            $obj->{ 'name_print' } = $obj->{ 'name' };
            $obj->{ 'yld_p_print' } = round( $obj->{ 'yld_p' } );
            
            ## percentage filtered does not exist for samples
            if ( exists $obj->{ 'clust_pf' } ){
                $obj->{'pf_print'} = round( getPerc( $obj->{'clust_pf'}, $obj->{'clust_raw'} ) );
            }
            
            next if $name =~ /read|UNDETERMINED/;
            $obj->{ 'total_reads' } = $obj->{ 'mm0' } + $obj->{ 'mm1' };
            $obj->{ 'mm0_print' } = 0;
            $obj->{ 'mm1_print' } = 0;
            if ( $obj->{ 'total_reads' } != 0 ){
                $obj->{ 'mm0_print' } = round( getPerc( $obj->{ 'mm0' }, $obj->{ 'total_reads' } ) );
                $obj->{ 'mm1_print' } = round( getPerc( $obj->{ 'mm1' }, $obj->{ 'total_reads' } ) );
            }
            
        }
    }
    
    ## Collect some general stats/info
    my $undet_perc = round( getPerc( $info{'undt'}{'UNDETERMINED'}{'yield'}, $info{'flow'}{$fid}{'yield'}) );
    $info{'stats'}{'run_overview_string'} = sprintf "%s\t%s\t%s\t%s\t%s\t%s", 
      round( $info{'flow'}{$fid}{'yield'}, $ROUND_DECIMALS, $YIELD_FACTOR ), 
      round( $info{'undt'}{'UNDETERMINED'}{'yield'}, $ROUND_DECIMALS, $YIELD_FACTOR ), 
      $info{'flow'}{$fid}{'q30_print'},
      $info{'flow'}{$fid}{'pf_print'},
      $cycle_string,
      $undet_perc . '%';
      
    $info{'stats'}{'undet_perc'} = $undet_perc;
    $info{'stats'}{'lane_count'} = scalar( keys %{$info{'lane'}} );
    $info{'stats'}{'samp_count'} = scalar( keys %{$info{'samp'}} );
    $info{'stats'}{'identifier'} = join( "_", keys %{$info{'flow'}} );
    $info{'stats'}{'cycle_string'} = $cycle_string;

    return \%info;
}

sub getPerc {
    my ($value, $total) = @_;
    
    if ( not defined($value) or not defined($total) ) {
        return 0;
    }
    elsif ($value < 0 or $total < 0) {
        die "[ERROR] Cannot calculate percentage if either value ($value) or total ($total) is < 0\n";
    }
    elsif ($value > $total){
        die "[ERROR] value ($value) should never be higher than total ($total)\n";
    }
    elsif ( $total == 0 and $value == 0) {
       return 0;
    }
    else {
        return $value*100/$total;
    }
}

sub printTable {
    my ($info, $fields) = @_;

    say sprintf '## YieldFactor: %s', commify($YIELD_FACTOR);
    say sprintf '## RoundDecimals: %s', commify($ROUND_DECIMALS);
    say sprintf '## Flowcell: %s (%s, %d lanes, %d samples, %s cycles)', 
      $info->{'stats'}{'identifier'}, 
      $info->{'stats'}{'hmf_runname'}, 
      $info->{'stats'}{'lane_count'}, 
      $info->{'stats'}{'samp_count'},
      $info->{'stats'}{'cycle_string'};
    
    say "#".join( $OUT_SEP, "level", @$fields );
    printTableForLevel( $info->{'flow'}, $fields, "RUN" );
    printTableForLevel( $info->{'lane'}, $fields, "LANE" );
    printTableForLevel( $info->{'samp'}, $fields, "SAMPLE" );
    printTableForLevel( $info->{'read'}, $fields, "READ" );
    printTableForLevel( $info->{'undt'}, $fields, "UNDET" );
}

sub printSummaryTable{
    my ($info, $fields) = @_;
   
    say sprintf '## YieldFactor: %s', commify($YIELD_FACTOR);
    say sprintf '## RoundDecimals: %s', commify($ROUND_DECIMALS);
    say sprintf '## Flowcell: %s (%s, %d lanes, %d samples)', 
      $info->{'stats'}{'hmf_runname'}, 
      $info->{'stats'}{'identifier'}, 
      $info->{'stats'}{'lane_count'}, 
      $info->{'stats'}{'samp_count'};
        
    say sprintf "## RunOverviewInfoLine: %s\t%s\t%s\t%s\t%s", 
      $info->{'stats'}{'hmf_runname'},
      $info->{'stats'}{'seq_runname'},
      $info->{'stats'}{'run_overview_string'},
      $info->{'stats'}{'flowcell_qc'};
      
    say "#".join( $OUT_SEP, @$fields );
    printTableForLevel( $info->{'samp'}, $fields );
}

sub printTableForLevel{
    my ($info, $fields, $level) = @_;
    foreach my $id ( sort { $info->{$b}{'name'} cmp $info->{$a}{'name'} } keys %$info){
        my @output = map( $info->{ $id }{ $_."_print" } || $NA_CHAR, @$fields );
        unshift @output, $level if defined $level;
        say join( $OUT_SEP, @output );
    }
}

sub readSampleSheet{
    my ($csv_file) = @_;
    
    ## SampleSheet file has windows returns
    my $return_str = $/;
    $/ = "\r\n";
    
    my %output;
    $output{ 'samples' } = {};
    $output{ 'runname' } = 'NO_RUNNAME_FROM_SAMPLESHEET';
    $output{ 'platform' } = 'NO_PLATFORM_FROM_SAMPLESHEET';
    my @header;
    
    if ( ! -e $csv_file ){
        say "## WARNING skipping SampleSheet read: file not found ($csv_file)";
        return( \%output );
    }
    
    open FILE, "<", $csv_file or die "Couldn't open file ($csv_file): $!";
    while ( <FILE> ) {
        chomp($_);
        next if $_ =~ /^[\[\,]/;
        next if $_ eq "";
        my @fields = split( ",", $_);
		
        ## get hmf run id from config line
        if ($fields[0] =~ /Experiment(.)*Name/ ){
            my $run_name = $fields[1] || 'NA';
            $output{ 'runname' } = $run_name;
        }
        elsif ($fields[0] =~ /Application/ ){
            my $platform = $fields[1] || 'NA';
            $output{ 'platform' } = $platform;
        }

        ## find header
        elsif ( $_ =~ m/Sample_ID/ ){
            @header = @fields;
        }
        ## read sample line if header seen before
        elsif ( @header ){
            my %tmp = ();
            $tmp{ $_ } = shift @fields foreach @header;

            ## skip "empty" lines (where no sample was defined)
            my $sample_id_column = 'Sample_ID';
            next unless defined $tmp{ $sample_id_column } and $tmp{ $sample_id_column } ne '';

            my $sample_id = $tmp{ $sample_id_column };
            $output{ 'samples' }{ $sample_id } = \%tmp;
        }
    }	
    close FILE;
    
    ## reset return string
    $/ = $return_str;
    
    return( \%output );
}

sub round{
    my ($number, $decimal, $factor) = @_;
    if ( not defined $number ){
        return $NA_CHAR;
    }
    $decimal = 1 unless defined $decimal;
    $factor = 1 unless defined $factor;
    my $rounded = sprintf("%.".$decimal."f", $number/$factor);
    return( $rounded );
}

## input "1000" gives output "1,000"
sub commify {
    local $_ = shift;
    $_ = int($_);
    1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
    return $_;
}
