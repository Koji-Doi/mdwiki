#!/usr/bin/env perl

# This should be run in the directory where mdwiki.html exists.

use strict;
use warnings;
use File::stat;
use Time::Piece;
use File::Copy;
use File::Path;
use utf8;
use Data::Dumper;
use URI::Escape;
use JSON;
no warnings;
*Data::Dumper::qquote = sub {return shift};
$Data::Dumper::Useperl = 1;
use warnings;

binmode STDERR, ':utf8';
binmode STDOUT, ':utf8';

my %CFG;
my $HTMLFILE = '';
my $MAINHTML  = 'mdwiki.html';
my @mainhtml0 = ('index.html', <*.html>);
until(-f $MAINHTML){
  $MAINHTML = shift(@mainhtml0);
}
(-f $MAINHTML) or die "No html file found";

my $LANG = (defined $CFG{lang}) || "ja"; # or "en"
my %MONTHNAME=(ja=>[map {"${_}tsuki"} 0..12], en=>[qw/x January February March April May June July August September October November December/]);
my @LOGLIST;
my @TOPIC;

# read config file
sub read_config{
  my($htmlfile) = @_;
  my @configfiles  = ('config.json', $htmlfile);
  $configfiles[-1]=~s/\.html/\.json/;

  foreach my $configfile (@configfiles){
    if(-f $configfile){
      print STDERR "Read $configfile\n";
      open(my $fhi, '<:utf8', $configfile);
      my $json = from_json(join('', <$fhi>));
      foreach my $key (keys %$json){
        $CFG{$key} = $json->{$key};
      }
    }
  }
}

=test
if(-f "mdwiki.cfg"){
  open(my $fhi, '<:utf8', "mdwiki.cfg");
  while(<$fhi>){
    s/[\n\r]*$//;
    my($k,$v) = /(\w+)\s*:\s*(.*)/;
    $CFG{$k}  = $v;
  }
}
=cut

sub makefilename{
  my($filename, $n)=@_; # test_{}.txt or test_*.txt
  my $filename_wildcard = $filename;
  $filename_wildcard=~s/{}/\*/;
  #$filename=~s/({}|\*)/@{[<${filename_wildcard}>]}/e;
  (defined $n) or $n=3;
  my $outfile;
  for(my $i=1; $i<10**$n; $i++){
    $outfile = $filename_wildcard;
    $outfile=~s/\*/sprintf("%0*d", $n, $i)/e;
    (-f $outfile) or return($outfile);
  }
  return($outfile);
}

sub makeloglist{
  my %year_month;
  # check logfile dirs, update @LOGLIST
  undef @LOGLIST;
  foreach my $dir_year (sort grep {/^\d{4}$/ and -d $_} <*>) {
    foreach my $dir_month (sort grep {/^\d/ and -d $_} <${dir_year}/*>) {
      open(my $fho, '>:utf8', "${dir_month}/index.md");
      print {$fho} "記事一覧 （${dir_month}）\n\n";

      foreach my $file (sort {my $aa=stat($a); my $bb=stat($b); $aa->mtime <=> $bb->mtime } grep {/\d{8}_\d{6}(?:_.*)?\.md$/} <${dir_month}/*.md>) { # only 2020/*.md are targets
        my($year,$month,$mday,$hour,$min,$sec,$x) = $file =~m{(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})_(.*)\.md};
        ($year) or next;
        my $fstat = stat($file);
        my $logdata = {file=>$file, mtime=>$fstat->mtime, year=>$year, month=>$month, day=>$mday, hour=>$hour, min=>$min, sec=>$sec};
        open(my $fhi, '<:utf8', $file) or die "missed $file";
        while(<$fhi>){
          s/[\n\r]*$//;
          $logdata->{title} = $logdata->{title} || $_;
          if(/<!-- @@@ (topic|data) start -->/ .. /<!-- @@@ (topic|data) end -->/){
            if(my($topic) = m{\(.*#!topic/(.*)\)}){
              $topic=~s!/(index\.md)?$!!;
              $topic=~s/%20/ /g;
              #$topic = url_decode($topic);
              $logdata->{topics}{$topic}++;
            }
          }
        }
        close $fhi;
        $logdata->{title}=~s/^[\s#]*//;
        
        push(@LOGLIST, $logdata);
        $year_month{$year}{$month}++;
        my $title1=$logdata->{title};
        $title1=~s/^\s*#\s*//;
        print {$fho} "* [$title1 ($file)](${MAINHTML}#!$file)\n";        
      }
      close $fho;
    }
  }

  # year/month
  my $outfile="_list_year_month.md";
  open(my $fho, '>:utf8', $outfile) or die;
  print {$fho} "# logs sorted by year/month\n\n";
  foreach my $year (sort {$a<=>$b} keys %year_month) {
    print {$fho} "\n\n## $year\n\n";
    foreach my $month (sort {$a<=>$b} keys %{$year_month{$year}}) {
      my $outfile2="_list_${year}_${month}.md";
      open(my $fho2, '>:utf8', $outfile2) or die;
      my $n        = $year_month{$year}{$month} || '0';
      my $year_mon = ($LANG eq 'ja')?"$year nen $month":"month $year";
      print {$fho}  "* ${year_mon} ($n logs)\n";
      print {$fho2} "# ${year_mon}\n\n";
      foreach my $log (@LOGLIST) {
        if ($log->{year}==$year and $log->{month}==$month) {
          print {$fho2} "* $log->{file}\n";
        }
      }
      close $fho2;              # list by each month
      print STDERR "Modified: $outfile2\n";
    }
  }
  close $fho;
  print STDERR "Modified: $outfile\n";

  $outfile="_list_newest.md";
  open($fho, '>:utf8', $outfile) or die;
  print {$fho} "# Newest 3 log\n\n";
  foreach my $log ((reverse @LOGLIST)[0..2]) { # newest
    (defined $log) or next;
    print {$fho} "* $log->{file}\n";
  }
  close $fho;
  print STDERR "Modified: $outfile\n";
} # sub makelogfile

sub maketopics{
  my($topicfile) = @_;
  $topicfile or $topicfile="topic.txt";
  @TOPIC =({name=>'topic', parent=>0, dir=>'topic', url=>${MAINHTML}.'#!topic/'});
  my @src;
  my @lasttopic;
  my $ind=0;
  my $i=0;
  my @topics;

  ### check topic structure
  if(-f $topicfile){
    mkpath($TOPIC[0]{dir});
    open(my $fhi, '<:utf8', $topicfile);
    while(<$fhi>){
      s/[\n\r]*$//;
      /\S/ or next;
      push(@topics, $_);
    }
  }else{
    print STDERR "$topicfile not found\n";
    @topics = $CFG{topic};
  }

  open(my $fho_root, '>:utf8', "$TOPIC[0]{dir}/index.md");
  print {$fho_root} << 'EOD';
# Topics

EOD

  foreach (@topics){
    $i++;
    my($ind0, $txt) = /(\s*)(.*)/;
    my $ind=length($ind0);
    my $txt_esc = url_encode($txt); #uri_escape_utf8($txt);

    $lasttopic[$ind] = {n=>$., name=>$txt, esc=>$txt_esc};
    $TOPIC[$i]       = {n=>$., name=>$txt, esc=>$txt_esc, parent=>($ind==0)? 0 : $lasttopic[$ind-1]{n}};
    $TOPIC[$i]{dir}  = "$TOPIC[$TOPIC[$i]{parent}]{dir}/$TOPIC[$i]{name}";
    $TOPIC[$i]{url}  = "$TOPIC[$TOPIC[$i]{parent}]{url}$TOPIC[$i]{esc}/";

    print {$fho_root} ' ' x $ind, "- [$txt]($TOPIC[$i]{url})\n";
  }

  ### topic -> index
  for($i=1; $i<=$#TOPIC; $i++){
    my $dir = $TOPIC[$i]{dir};
    (-d $dir) or mkdir $dir or die "Failed to make $dir";
    my $indexfile = "$dir/index.md";
    my @intext;
#    my @outtext;
    my $tag = '';
    if(-e $indexfile){ # existing file
      copy $indexfile, "$indexfile.bak";
      open(my $fhi, '<:utf8', $indexfile);
      @intext = <$fhi>;
    }else{ # new file
      @intext = template('topic.md', {topicname=>$TOPIC[$i]{name}});
    }
    open(my $fho, '>:utf8', $indexfile) or die "Cannot create $indexfile";
    print STDERR "Modified: $indexfile\n";
    my $outtext = join('', @intext);
    my $loglist='';
    foreach my $logfile (@LOGLIST){
      # check links to topic files from each log file
      my $hir = $TOPIC[$i]{dir};
      $hir=~s{topic/}{};
      if(exists $logfile->{topics}{$hir}){
        $loglist .= sprintf("* [%s (%s)](${MAINHTML}#!%s)\n", $logfile->{title}||'', $logfile->{file}, $logfile->{file});
      }
    }
    $outtext=~s{(<!--\s+@@@\s+log\s+list\s+start\s*-->).*(<!-- @@@\s+log\s+list\s+end\s*-->)}{"$1\n\n$loglist\n$2"}se;    
    print {$fho} $outtext;
  }
} # sub maketopics

sub makenav{
  (-f "navigation.md") and move "navigation.md", "navigation.md.bak";
  open(my $fho, '>:utf8', "navigation.md") or die;
  printf {$fho} "[gimmick:Theme (inverse: true)](cerulean)\n\n# %s\n\n", $CFG{sitename}||'MDWiki Site';

  my @menubar = (defined $CFG{menubar}) ? @{$CFG{menubar}} : ('month', 'topic');

  foreach my $item (@menubar){
    if($item eq 'month'){
      # year/month
      print  {$fho} "[Year/Month]()\n\n";
      foreach my $year (grep {/^\d{4}$/ and -d $_} <*>){
        print {$fho} "";
        foreach my $ymonth (grep {-d $_} <$year/*>){
          print {$fho} " * [$ymonth](#!${ymonth}/)\n";
        }
      }
    }elsif($item eq 'topic'){
      # topic
      my $lv=0;
      print {$fho} "\n[Topics]()\n\n";
      for(my $i=0; $i<=$#TOPIC; $i++){
        print "$i: $TOPIC[$i]{url}.\n";
        my $url  = $TOPIC[$i]{url};
        my $name = $TOPIC[$i]{name};
        $url=~s{/[^/]*$}{};
        my(@f)  = split('/', $url);
        my $lv0 = scalar @f;
        if($lv0==2){
          ($lv>=2) and print {$fho} "  - - - -\n";
          print {$fho} "  * # &sect;&nbsp;$name\n  * [&bull;&nbsp;$name]($url/)\n";
        }elsif($lv0==3){
          print {$fho} "  * [&emsp;&bull;&nbsp;$name]($url/)\n";
        }elsif($lv0==4){
          print {$fho} "  * [&emsp;&emsp;&bull;&nbsp;$name]($url/)\n";
        }
        $lv = $lv0;
      }
    }else{
    }
  } # foreach @menubar
  close $fho;
}

{
my @data;
sub template{
  my($tag, $opt) = @_;
  (defined $data[0]) or @data = <DATA>;
  my @data1 = @data;
  my @res;
  foreach my $x (@data1){
    if($x=~/^\s*\@\@ $tag/ ... $x=~/^\s*\@\@/){
      $x=~/^\s*\@\@ / and next;
      (scalar @res == 0) and ($x=~/^\s*$/) and next;
      foreach my $k (keys %$opt){
        my $v = $opt->{$k};
        $x=~s/\{\{$k}}/$v/g;
      }
      push(@res, $x);
    }
  }
  return(@res);
}
}

sub url_encode($) {
  my $str = shift;
  $str =~ s/([ \W])/'%'.unpack('H2', $1)/eg;
  #$str =~ tr/ /+/;
  return $str;
}

sub url_decode($) {
  my $str = shift;
  #$str =~ tr/+/ /;
  $str =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/pack('H2', $1)/eg;
  return $str;
}


#
# start
#

if ((not defined $ARGV[0]) or $ARGV[0]=~/help/ or $ARGV[0] eq '-h') {
print <<'EOD';
mdwiki.pl -- a MDwiki helper program ver. 0 rel. 20201125

(C) 2020, Koji Doi

Usage:
perl mdwiki.pl command target_html

Command:
help    -- show this help.
newlog  -- save new markdown template file in the appropriate subdirectory.
build   -- make index files.
loglist -- show logfile list.
EOD

} else{
  $HTMLFILE = $ARGV[1] || $MAINHTML;
  read_config($HTMLFILE);
  
  if ($ARGV[0] eq 'newlog') {
    my $lt  = localtime;
    my $dir = sprintf("%04d/%02d", $lt->year, $lt->mon);
    (-d $dir) or mkpath($dir);
    my $outfile0 = $lt->strftime("$dir/%Y%m%d_%H%M%S_{}.md");
    my $outfile  = makefilename($outfile0);
    open(my $fho, '>:utf8', $outfile) or die "Failed to create $outfile";
    print STDERR "Created new log template file: $outfile\n";
    $lt = localtime;
    my @d = template('log.md', {date=>$lt->ymd()});
    map {print {$fho} $_} @d;
    close $fho;
    my $newest_symlink = "newestlog.md";
    (-f $newest_symlink) and unlink $newest_symlink;
    if($^O eq 'MSWin32'){
      system("mklink ${newest_symlink} $outfile");
    }else{
      system("ln -s $outfile ${newest_symlink}");
    }
  } elsif ($ARGV[0] eq 'loglist'){
    makeloglist();
    foreach my $log (@LOGLIST){
      map { printf "%s: %s\n", $_, $log->{$_}} qw/file title/;
      map { print  "topic: $_\n" } sort keys %{$log->{topics}};
      print "\n";
    }
  } elsif ($ARGV[0] eq 'build') {
    print STDERR "Make topic files, index files etc. for $HTMLFILE\n";
    makeloglist();
    maketopics();
    makenav();
  }
}
no warnings;
$DB::single=1;

__DATA__
@@ log.md
# 新しいログのタイトル

<div style="margin-top: -10em; margin-bottom: 2em; text-align:right;">
<!-- @@@ topic start -->

[topic](#!topic/)
First Edition: {{date}}
Last Modified: {{date}}

<!-- @@@ topic end -->
</div>
<hr>

## 序文

## 本文

## 結語

@@ topic.md
<!-- @@@ title start -->

# Topic {{topicname}}
<!-- @@@ title end -->

<!-- @@@ parent topic start -->
<!-- @@@ parent topic end -->

## 本トピックの説明

工事中

## 本トピックの記事一覧

<!-- @@@ log list start -->

<!-- @@@ log list end -->

@@ end
