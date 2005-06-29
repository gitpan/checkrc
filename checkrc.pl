#!/usr/bin/perl -w
#---------------------------------------------------------------------------#
# $Id: checkrc.pl 271 2005-06-29 19:46:55Z helmut $

use strict;
#SKIP use Logging::Debug;
use Getopt::Long;

my $VERSION = 0.1;


=head1 NAME

checkrc.pl - analyzes Visual Studio 6.0 resource files (*.rc)


=head1 DESCRIPTION

checkrc.pl analyzes Visual Studio resource files (*.rc) and prints a
list of languages or compares sections for two given languages.


=head1 README

checkrc.pl analyzes Visual Studio resource files (*.rc) and ...

a) ... lists languages present; 

b) ... compares elements of two language sections:

- detects difference in types e.g. PUSHBUTTON vs. DEFPUSHBUTTON,

- detects dialogs, menus or strings present in only one section,

- outputs result in XHTML tables side by side with colours and links next/prev.


=head1 LIMITATIONS

- include directive is not interpreted

- XHTML output uses constant encoding ISO-8859-1

- (numeric) string constants in 'IDD_xx DLGINIT...' are not handled

- the script detects only a fix set of languages (see %LANG_MAP)


=head1 PREREQUISITES

This script requires the C<strict> module.


=head1 COREQUISITES

When you drop "#SKIP", the script uses my module Logging::Debug
(see http://www.jsteeb.de/software - which does not yet have an installation package).


=head1 OSNAMES

any


=head1 SCRIPT CATEGORIES

Win32/Utilities


=head1 AUTHOR

  Helmut Steeb
  mailto: helmut_steeb(AT)losung.de
  http://www.jsteeb.de/

=head1 COPYRIGHT

Copyright (c) 2005 by Helmut Steeb. All rights reserved.

This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut


# $STRING_PATTERN
# NOTE - Visual Studio stores double quotes within a string
# not escaped with backslash but as two consective double quotes.
my $STRING_PATTERN = 
    "\""                 # leading double-quote
    # content char or doubled double-quote, content stored via (), 
    # do use minimal match (otherwise search would stop at embedded double quote!)
    . "((?:[^\"]|\"\")*)"
    . "\"";              # trailing double-quote

my %LANG_MAP = (
    "af" => "Unknown language: 0x36, 0x1",
    "de" => "German (Germany)",
    "en" => "English (U.S.)",
    "es" => "Spanish (Modern)",
    "fr" => "French (France)",
    "it" => "Italian (Italy)",
    "nl" => "Dutch (Netherlands)",
    "no" => "Norwegian (Nynorsk)",
    "ro" => "Romanian",
    "ru" => "Russian",
  );
my %REVERSE_LANG_MAP = reverse %LANG_MAP;

my $errLinkNumber = 0;

sub usage {
  my $msg = shift;

  if ($msg) { print STDERR "$msg\n"; }
#SKIP logfile <filename>      sets output filename for logging
#SKIP verbose (0|1|2)         sets messages level (errors only | info | debug) (default: 1)
  print STDERR <<EOUSAGE;
Usage: checkrc.pl [options]

  cmd      (compare|list|List)
    compare requires lang1 and lang2, outputs HTML comparison of the languages to STDOUT
    list    lists ISO codes of languages from resource to STDOUT
    List    lists ISO codes + Windows names of languages from resource to STDOUT
  resource  resource filename
  lang1    language (ISO code, e.g. 'de')
  lang2    language (ISO code, e.g. 'en')
  help                    displays this text

Analyzes Visual Studio resource file (*.rc):
- walks through sections for two languages in parallel,
- detects differences in types of controls (e.g. LTEXT vs. EDITTEXT),
- detects dialogs, menus or strings present in one language only.
Version: $VERSION.
EOUSAGE
  exit;
}


sub ReadFile($)
{
  my $filename = shift or die;
  if (!-r $filename || !open(FILE, $filename)) {
    #SKIP MsgError("ReadFile: cannot read file $filename");
    return 0;
  }
  my $old = $/;
  undef $/;
  my $text = <FILE>;
  close(FILE);
  $/ = $old;
  #SKIP MsgDebug("  done.");
  return $text;
}


sub ReadResFile($)
{
  my $filename = shift or die;
  my $text = ReadFile($filename) or return 0;
  # TODO process includes - but include is only used for *.h, not for *.rc?
  return $text;
}


sub WinLang2IsoLang($)
{
  my $winLang = shift or die;
  my $isoLang = $REVERSE_LANG_MAP{$winLang};
  if (!$isoLang) {
    #SKIP MsgError("WinLang2IsoLang: no iso language for Win language '$winLang'");
    return 0;
  }  
  return $isoLang;
}

sub IsoLang2WinLang($)
{
  my $isoLang = shift or die;
  my $winLang = $LANG_MAP{$isoLang};
  if (!$winLang) {
    #SKIP MsgError("IsoLang2WinLang: no win language for ISO language '$isoLang'");
    return 0;
  }  
  return $winLang;
}


# ExtractLanguages($resFileString)
# 
# Extracts and returns an array of languages from $resFileString.
# Skips language names that contain "Neutral".
# 
sub ExtractLanguages($)
{
  my $resFileString = shift or die;

  # extract
  my @LANGUAGES = ($resFileString =~ m@\n//\s*(\w+.*?)\s+resources@g);
  @LANGUAGES =  grep { $_ !~ m/Neutral/ } @LANGUAGES;
  if (!@LANGUAGES) {
    #SKIP MsgError("ExtractLanguages: no data from resource file");
    return 0;
  }
  return @LANGUAGES;
}

sub ExtractLangData($$)
{
  my $resFile = shift or die;
  my $isoLang = shift or die;
  my $winLang = IsoLang2WinLang($isoLang) or return 0;

  # protect Perl meta characters
  $winLang =~ s@([()])@\\$1@g;
  $winLang =~ s@[ ]@\\s+@g;

  # extract
  my $langData = ($resFile =~ m@//\s*$winLang(.*?)\#endif\s+//\s*$winLang@s)[0];
  if (!$langData) {
    #SKIP MsgError("ExtractLangData: no data from resource file for isoLang='$isoLang', winLang='$winLang'");
    return 0;
  }
  return $langData;
}

sub ExtractControls($$)
{
  my $name = shift or die;
  my $content = shift;

  if (!$content) {
    #SKIP MsgDebug("Warning: empty content for control '$name'");
    return [];
  }

  # Format assumed:

  #                       240,60
  #       LTEXT           "&Year",IDC_STATIC,20,20,80,8
  #       CONTROL         "",IDC_YEAR1,"Button",BS_AUTORADIOBUTTON | WS_GROUP,100,
  #                       20,50,10
  #       LTEXT           "(Watchwords for %d will be available not before October %d)",
  #                       IDC_YEAR_HINT,150,20,90,30
  #       EDITTEXT        IDC_CURRDOCLANG,100,50,140,14,ES_AUTOHSCROLL | 
  #                       ES_READONLY
  #       DEFPUSHBUTTON   "&Download",IDOK,260,13,60,14
  #       PUSHBUTTON      "&Cancel",IDCANCEL,260,30,60,14
  #   END
  #
  # Result:
  #
  #   my %CONTROL;
  #   $CONTROL{"TYPE"} = "GROUPBOX" | ...;
  #   $CONTROL{"STRING"} = "...";
  #
  my @CONTROLS;
  while ($content =~ m@\s+(GROUPBOX|LTEXT|CONTROL|(?:DEF)?PUSHBUTTON)\s+$STRING_PATTERN@sg) {
    my ($type, $string) = ($1, $2);
    # print STDERR "$type <$string>\n";
    push @CONTROLS, {"TYPE" => $type, "STRING" => $string};
  }
  return \@CONTROLS;
}

sub ExtractDialogs($)
{
  my $langData = shift or die;
  # Format assumed:
  #   IDD_LANGPACK DIALOG DISCARDABLE  0, 0, 332, 81
  #   STYLE DS_MODALFRAME | WS_POPUP | WS_CAPTION | WS_SYSMENU
  #   CAPTION "Actualize watchwords"
  #   FONT 8, "MS Sans Serif"
  #   ... content see ExtractControls
  #
  # Result:
  #
  #   my %DIALOGS;
  #   $DIALOGS($name) = \%DIALOG;
  #
  #   my %DIALOG;
  #   $DIALOG{"NAME"} = $name;
  #   $DIALOG{"CAPTION"} = $caption;
  #   $DIALOG{"CONTROLS"} = [\%CONTROL, ...];
  #
  #   %CONTROL see ExtractControls.
  # 
  #SKIP MsgDebug("ExtractDialogs...");
  my @DIALOGS = ($langData =~ m@\n(\w+\s+DIALOG(?:EX)?\s+.*?\nBEGIN.*?)\nEND@sg);
  my %DIALOGS;
  foreach my $dialog (@DIALOGS) {
    my ($name, $caption, $content) = ($dialog =~ m@
      (\w+) .*?
      (?:CAPTION \s+ $STRING_PATTERN)?    # contains () for string content, maybe empty!
      .*? \n BEGIN
      (.*)
      @xsg);
    if (!$name) {
      #SKIP MsgError("Empty name in dialog " . substr($dialog, 0, 40));
      die "Empty name in\n<$dialog>\n";
    }
    my $Controls = ExtractControls($name, $content) or return 0; 
    $DIALOGS{$name} = { "NAME" => $name, "CAPTION" => $caption, "CONTROLS" => $Controls};
  }
  #SKIP MsgDebug("  done.");
  return \%DIALOGS;
}

sub ExtractStrings($)
{
  my $langData = shift or die;

  # Format assumed:
  #   STRINGTABLE PRELOAD DISCARDABLE 
  #   BEGIN
  #       IDR_MAINFRAME           "appName\..."
  #   END
  # 
  # Result:
  # 
  #   my %STRINGS;
  #   $STRINGS{$name} = $content
  # 

  #SKIP MsgDebug("ExtractStrings...");
  my @STRINGTABLES = ($langData =~ m@STRINGTABLE.*?\nBEGIN(.*?)\nEND@sg);
  my %STRINGS;
  foreach my $stringTable (@STRINGTABLES) {
    #print STDERR "<$stringTable>\n";
    while ($stringTable =~ m@(\w+)\s+$STRING_PATTERN@osg) {
      my ($name, $content) = ($1, $2);
      # print STDERR "<$name>\t->" . substr($content, 0, 20) . "\n";
      $STRINGS{$name} = $content;
    }
  }
  #SKIP MsgDebug("  done.");
  return \%STRINGS;
}

sub ExtractMenuItems($$); # for prototype checking
sub ExtractMenuItems($$)
{
  my $name = shift or die;
  my $content = shift or die;
  # Format assumed:
  #   POPUP "&Datei"
  #   BEGIN
  #       MENUITEM "Losungstext &aktualisieren...\tCtrl+A", ID_FILE_ACTUALIZE
  #       MENUITEM SEPARATOR
  #       MENUITEM "&Beenden",                    ID_APP_EXIT
  #   END
  # - on top-level either "POPUP" or "MENUITEM"
  # - after "POPUP", "BEGIN" and "END" with same indentation
  # - "MENUITEM" followed by string followed by ", " and ID
  #
  # Result:
  #
  #   my @MENUITEMS;
  #   $MENUITEMS{$i} = (\%POPUP | \%MENUITEM);
  #   my %POPUP;
  #     $POPUP->{"TYPE"} = "POPUP";
  #     $POPUP->{"NAME"} = $name;      // e.g. "&Datei"
  #     $POPUP->{"SUB"} = \@SUB_MENUITEMS;
  #   my %MENUITEM;
  #     $MENUITEM->{"TYPE"} = "MENUITEM";
  #     $MENUITEM->{"NAME"} = $name;   // e.g. "Losungstext &aktualisieren...\tCtrl+A"
  #     $MENUITEM->{"ID"} = $ID;   // e.g. "ID_FILE_ACTUALIZE"

  # trim MENUITEM onto single line
  # Format assumed:
  #   MENUITEM \s+ "..." \s , \s ID_bla
  #   (with double-quote masked by backslash in string "...", e.g. "This is double-quote: \"")
  $content =~ s@
      (MENUITEM) \s+ 
      $STRING_PATTERN
      \s* , \s* (\w+) # ID
    @$1 "$2", $3@xg;
  #print STDERR "<<$content>>\n";

  # drop SEPARATOR
  # (keep trailing \s for indentation detection in front of "POPUP")
  $content =~ s@MENUITEM\s+SEPARATOR@@g;
  #print STDERR "<<$content>>\n";

  my @MENUITEMS;
  while ($content =~ m@
     \n ([ ]*)          # leading blanks, used to detect "BEGIN" and "END" of "POPUP"
     (?:
       # either "POPUP"
       (POPUP) \s+ $STRING_PATTERN [^\n]* \n
       \1 BEGIN
       (.*?)\n         # popup data (recursion)
       \1 END
       |
       # or "MENUITEM" (on single line)
       # pattern see above
       (MENUITEM) \s+ $STRING_PATTERN \s* , \s* (\w+) # ID
     )
     @oxsg) {
    my ($blanks, $popup, $popupName, $popupContent, $menuItem, $menuItemContent, $menuItemID) = ($1, $2, $3, $4, $5, $6, $7);
    #print STDERR "\nB=<$blanks>\nP=<$popup>\nPN=<$popupName>\nPC=<$popupContent>\nM=<$menuItem>\nMC=<$menuItemContent>\nID=<$menuItemID>\n";
    if ($popup) {
      my $SubMenu = ExtractMenuItems($popupName, $popupContent) or return 0; 
      push @MENUITEMS, {"TYPE" => "POPUP", "NAME" => $popupName, "SUB" => $SubMenu};
    }
    elsif ($menuItem) {
      push @MENUITEMS, {"TYPE" => "MENUITEM", "NAME" => $menuItemContent, "ID" => $menuItemID};
    }
    else {
      #SKIP MsgError("ExtractMenuItems: neither 'POPUP' or 'MENUITEM' detected in <$content>");
      return 0;
    }
  }
  return \@MENUITEMS;
}

sub ExtractMenus($)
{
  my $langData = shift or die;
  # Format assumed:
  #   IDR_MAINFRAME MENU PRELOAD DISCARDABLE 
  # - name at line start (stored in $name)
  # - space, "MENU"
  # - skipping until...
  # - "BEGIN" at start of line
  # - data (stored in $content)
  # - "END" at start of line (assuming nested "END" for submenus is indented!)
  #
  # Result:
  #
  #   $MENUS{$name} = $MenuItems
  #
  #SKIP MsgDebug("ExtractMenus...");
  my @MENUS = ($langData =~ m@\n(\w+\s+MENU.*?BEGIN.*?\nEND)@s);
  my %MENUS;
  foreach my $menu (@MENUS) {
    my ($name, $content) = ($menu =~ m@\A(\w+)\s+MENU.*?BEGIN(.*?)\nEND@s);
    #  print $name . "->" . $content;
    my $MenuItems = ExtractMenuItems($name, $content) or return 0;
    $MENUS{$name} = $MenuItems;
  }
  #SKIP MsgDebug("  done.");
  return \%MENUS;
}

sub SplitLangData($)
{
  my $langData = shift or die;

  my %RES;
  $RES{"DIALOGS"} = ExtractDialogs($langData) or return 0;
  $RES{"STRINGS"} = ExtractStrings($langData) or return 0;
  $RES{"MENUS"} = ExtractMenus($langData) or return 0;
  return \%RES;
}

# SetKeys($KeysHash, $SourceHash, $bit)
# 
# For each key in $SourceHash, sets the bit(s) of $bit in the value of
# the same key in $KeysHash.
# 
# TODO: put into utility class, with access methods...
# 

sub SetKeys($$$)
{
  my $KeysHash = shift or die;
  my $SourceHash = shift or die;
  my $bit = shift or die;

  foreach my $key (keys %$SourceHash) {
    $KeysHash->{$key} |= $bit;
  } 
}

# $anchor = MakeAnchor($number)
# 
# Creates an XHTML <a name... id...> anchor for argument $number, to be referenced by
# MakeLink($number).
# 

sub MakeAnchor
{
  my $number = shift or die;
  return "<a name='err$number' id='err$number'></a>";
}

# $link = MakeLink($number, $isForward)
# 
# Creates an XHTML <a href...> reference to an anchor for argument $number. The
# anchor should be created by MakeAnchor($number).
# 
# If $isForward, uses text ">>", otherwise uses "<<".
# 

sub MakeLink
{
  my $number = shift or die;
  my $isForward = shift;
  return "<a href='#err$number'>[" . ($isForward ? "&gt;&gt;" : "&lt;&lt;") . "]</a>";
}

# $links = MakeLinks()
# 
# Creates a sequence of XHTML <a> elements using the global
# $errLinkNumber: one link "back" (if $errLinkNumber > 0), one link to
# '#_top', one link "forward".
# 
# For the last MakeLinks() call, the "forward" link points to nothing,
# this will be removed by DropLastLink() (TODO less hacky solution).
# 

sub MakeLinks
{
  ++$errLinkNumber;
  my $res;
  if ($errLinkNumber > 1) {
    $res .= MakeLink($errLinkNumber-1, 0);
  }
  $res .= MakeAnchor($errLinkNumber) . "<a href='#_top'>(top)</a>" . MakeLink($errLinkNumber+1, 1);
  return $res;
}

# DropLastLink($string)
# 
# If an error occured ($errLinkNumber non-0), drops all links to
# $errLinkNumber+1 from the first parameter (modified in place).
# 
# Returns the first parameter.
# 

sub DropLastLink
{
  if ($errLinkNumber) {
    my $link = MakeLink($errLinkNumber+1, 1);
    # protect [] in regular expression
    $link =~ s@\[@\\\[@g;
    $link =~ s@\]@\\\]@g;
    $_[0] =~ s@$link@@g;
  }
  return $_[0];
}

# $res = FormatString([$string[, $errNoRef[, $maybeEmpty]]])
# 
# Returns HTML cell (<td>) with data put into it.
# 
# If $string not given, returns empty cell (if !$maybeEmpty, empty cell has class 'miss').
# Otherwise, puts $string into the cell. If $type given additionally, prefixes it to $string.
# 

sub FormatString(;$$$)
{
  my $string = shift;
  my $errNoRef = shift;
  my $maybeEmpty = shift;
  my $res;
  if (!defined($string)) {
    if ($maybeEmpty) {
      $res .= "<td>&nbsp;</td>\n";
    }
    else {
      ++$$errNoRef if $errNoRef;
     $res .= "<td class='miss'>" . MakeLinks() . "</td>\n";
    }
  }
  else {
    # protect some XML meta characters (missing: comments, "]]")
    $string =~ s@&@&amp;@g;
    $string =~ s@<@&lt;@g;
    $string =~ s@>@&gt;@g;
    $res .= "<td>$string</td>\n";
  }
  return $res;
}

sub FormatStringComparison($$$$)
{
  my $name = shift or die;
  my $string1 = shift;
  my $string2 = shift;
  my $errNoRef = shift or die;

  my $res;
  $res = "<tr><td>$name</td>\n";
  my $maybeEmpty = !$string1 && !$string2;
  $res .= FormatString($string1, $errNoRef, $maybeEmpty);
  $res .= FormatString($string2, $errNoRef, $maybeEmpty);
  $res .= "</tr>\n";
  return $res;
}

sub FormatDialogComparison($$$)
{
  my $Dialog1 = shift or die;
  my $Dialog2 = shift or die;
  my $errNoRef = shift or die;
  #   my %DIALOG;
  #   $DIALOG{"NAME"} = $name;
  #   $DIALOG{"CAPTION"} = $caption;
  #   $DIALOG{"CONTROLS"} = [\%CONTROL, ...];
  #
  #   my %CONTROL;
  #   $CONTROL{"TYPE"} = "GROUPBOX" | ...;
  #   $CONTROL{"STRING"} = "...";

  my $res;
  $res .= "<h3>Dialog " . $Dialog1->{"NAME"} . "</h3>\n";
  $res .= "<table width='100%' border='1' cellpadding='5' style='border-collapse:collapse'>\n";
  $res .= FormatStringComparison("CAPTION", $Dialog1->{"CAPTION"}, $Dialog2->{"CAPTION"}, $errNoRef);
  my @CONTROLS1 = @{$Dialog1->{"CONTROLS"}};
  my @CONTROLS2 = @{$Dialog2->{"CONTROLS"}};
  my $errNo = 0;
  my $maxNum = (@CONTROLS1 > @CONTROLS2) ? @CONTROLS1 : @CONTROLS2;
  for (my $i = 0; $i < $maxNum; ++$i) {
    my $Control1 = $CONTROLS1[$i];
    my $Control2 = $CONTROLS2[$i];

    my $type1 = defined($Control1) ? $Control1->{"TYPE"} : "";
    my $type2 = defined($Control2) ? $Control2->{"TYPE"} : "";
    my $typeString = ($type1 eq $type2) ? $type1 : "$type1 &lt;-&gt; $type2";

    my $lineStyle = "";
    my $links = "";
    if ($type1 eq $type2 && $Control1->{"STRING"} eq $Control2->{"STRING"}) {
      # give equality prio over previous difference
      $lineStyle = " class='equal'";
    }
    elsif ($type1 ne $type2) {
      ++$errNo;
      $lineStyle = " class='miss'";
      $links = MakeLinks();
    }
    elsif ($errNo) {
      # this line is equal, but there was a difference before -> highlight, but do not link
      $lineStyle = " class='consecutive'";
    }
    $res .= "<tr$lineStyle>\n<td>$typeString$links</td>\n";

    # Control1
    my $style = "";
    if (defined($Control1) && defined($Control2) && $Control1->{"STRING"} eq $Control2->{"STRING"}) {
      $style = " class='equal'";
    }
    if (!defined($Control1)) {
      ++$errNo;
      $res .= "<td class='miss'>" . MakeLinks() . "</td>\n";
    }
    else {
      $res .= FormatString($Control1->{"STRING"});
    }

    # Control2
    if (!defined($Control2)) {
      ++$errNo;
      $res .= "<td class='miss'>" . MakeLinks() . "</td>\n";
    }
    else {
      $res .= FormatString($Control2->{"STRING"});
    }

    $res .= "</tr>\n";
  }
  $res .= "</table>\n";
  $$errNoRef += $errNo;  
  return $res;
}

sub FormatDialogsComparison($$$)
{
  my $Dialogs1 = shift;
  my $Dialogs2 = shift;
  my $errNoRef = shift or die;

  #   my %DIALOGS;
  #   $DIALOGS($name) = \%DIALOG;

  my $res = "";
  $res = "<h2><a name='dialogs' id='dialogs'>Dialogs</a></h2>\n";  
  $res .= <<EODIALOGCONV;
<div class='convention'>
<p>Convention: dialog items of both resources are listed in parallel in the order defined in the resource file.
If types are different, <em>all</em> following items are highlighted (no smart diff!).</p>
</div>
EODIALOGCONV

  #$res .= "<p>1:<br />" . join(" ", (keys %$Dialogs) . "</p>\n";
  #$res .= "<p>2:<br />" . join(" ", (keys %$Dialogs) . "</p>\n";
  # compute usage of dialog names in resRef1/resRef2
  my %NAMES;
  SetKeys(\%NAMES, $Dialogs1, 1);
  SetKeys(\%NAMES, $Dialogs2, 2);

  # process
  foreach my $name (sort keys %NAMES) {
    if ($NAMES{$name} == 3) {
      my $Dialog1 = $Dialogs1->{$name};
      my $Dialog2 = $Dialogs2->{$name};
      $res .= FormatDialogComparison($Dialog1, $Dialog2, $errNoRef);
    }
    else {
      $res .= "<p class='miss'>Dialog $name only in language " . $NAMES{$name} . " " . MakeLinks() . "</p>\n";
      ++$$errNoRef;
    }
    $res .= "<p><a href='#_top'>(top)</a></p><hr />\n";
  }

  return $res;
}

sub FormatStringsComparison($$$)
{
  my $Strings1 = shift or die;
  my $Strings2 = shift or die;
  my $errNoRef = shift or die;

  #   my %STRINGS;
  #   $STRINGS{$name} = $content

  my %NAMES;
  SetKeys(\%NAMES, $Strings1, 1);
  SetKeys(\%NAMES, $Strings2, 2);

  my $res = "";
  $res .= "<h2><a name='strings' id='strings'>String tables</a></h2>\n";
  $res .= <<EOMENUSTRINGS;
<div class='convention'>
<p>Convention: all string table entries of both resources are listed in parallel, sorted by the symbolic resourceID.</p>
</div>
EOMENUSTRINGS

  $res .= "<table width='100%' border='1' cellpadding='5' style='border-collapse:collapse'>\n";

  # process
  foreach my $name (sort keys %NAMES) {
    my $lineStyle = "";
    if (defined($Strings1->{$name}) && defined($Strings2->{$name}) && $Strings1->{$name} eq $Strings2->{$name}) {
      $lineStyle = " class='equal'";
    }
    $res .= "<tr$lineStyle><td>$name</td>\n";
    $res .= FormatString($Strings1->{$name}, $errNoRef);
    $res .= "\n";
    $res .= FormatString($Strings2->{$name}, $errNoRef);
    $res .= "</tr>\n";
  }
  $res .= "</table>\n";
  $res .= "<p><a href='#_top'>(top)</a></p><hr />\n";
  return $res;
}


sub FormatMenuItem($)
{
  my $MenuItem = shift or die;
  return $MenuItem->{"TYPE"} . " " . $MenuItem->{"NAME"};
}

sub FormatMenuComparisonRec($$$$);
sub FormatMenuComparisonRec($$$$)
{
  my @MENUITEMS1 = @{shift()};
  my @MENUITEMS2 = @{shift()};
  my $level = shift;
  my $errNoRef = shift or die;

  #   my @MENUITEMS;
  #   $MENUITEMS{$i} = (\%POPUP | \%MENUITEM);
  #   my %POPUP;
  #     $POPUP->{"TYPE"} = "POPUP";
  #     $POPUP->{"NAME"} = $name;      // e.g. "&Datei"
  #     $POPUP->{"SUB"} = \@SUB_MENUITEMS;
  #   my %MENUITEM;
  #     $MENUITEM->{"TYPE"} = "MENUITEM";
  #     $MENUITEM->{"NAME"} = $name;   // e.g. "Losungstext &aktualisieren...\tCtrl+A"
  #     $MENUITEM->{"ID"} = $ID;   // e.g. "ID_FILE_ACTUALIZE"

  my $maxNum = (@MENUITEMS1 > @MENUITEMS2) ? @MENUITEMS1 : @MENUITEMS2;
  my $res = "";
  my $errNo = 0; # local counter (but recursive)
  for (my $i = 0; $i < $maxNum; ++$i) {
    my $MenuItem1 = $MENUITEMS1[$i];
    my $MenuItem2 = $MENUITEMS2[$i];

    # Concept: highlight all lines starting from the first difference (i.e. $errNo > 0)
    my $lineStyle = "";
    my $links = "";
    my $typesMatch = (defined($MenuItem1) && defined($MenuItem2) && $MenuItem1->{"TYPE"} eq $MenuItem2->{"TYPE"});
    my $valuesMatch = $typesMatch && ($MenuItem1->{"NAME"} eq $MenuItem2->{"NAME"});
    if ($typesMatch && $valuesMatch) {
      $lineStyle = " class='equal'";
    }
    elsif (!$typesMatch) {
      ++$errNo;
      $lineStyle = " class='miss'";
      $links = MakeLinks();
    }
    elsif ($errNo) {
      $lineStyle = " class='consecutive'";
    }
    my $prettyLevel = ("&nbsp;" x (4*($level-1))) . "+" || "&nbsp";
    $res .= "<tr$lineStyle>\n<td>$prettyLevel$links</td>\n";

    # NOTE: each case must terminate the table row (because recursion adds lines)!
    if (defined($MenuItem1) && defined($MenuItem2)) {
      # both exist, type may differ
      if ($MenuItem1->{"TYPE"} eq $MenuItem2->{"TYPE"}) {
        # both exist, type equal
        $res .= FormatString($MenuItem1->{"NAME"});
        $res .= FormatString($MenuItem2->{"NAME"});
        $res .= "</tr>\n";
        if ($MenuItem1->{"TYPE"} eq "POPUP") {
          # both exist, type equal -> recurse if submenu
          # recursion may add lines!
          my $subErrNo = 0;
          $res .= FormatMenuComparisonRec($MenuItem1->{"SUB"}, $MenuItem2->{"SUB"}, $level+1, \$subErrNo);
          $errNo += $subErrNo;
        }
      }
      else {
        # both exist, type differs
        ++$errNo;
        $res .= "<td colspan='2'>MenuItem $i has different types: " 
         . FormatMenuItem($MenuItem1)
         . " / " 
         . FormatMenuItem($MenuItem2)
         . " " . MakeLinks()
         . "</td>\n";
        $res .= "</tr>\n";
      }
    }
    else {
      # only one exists
      ++$errNo;
      my $langIndex = (defined($MenuItem1) ? 1 : 2);
      my $MenuItem  = $MenuItem1 || $MenuItem2;
      $res .= "<td colspan='2'>MenuItem $i only in language $langIndex: " . FormatMenuItem($MenuItem) . " " . MakeLinks() . "</td>\n";
      $res .= "</tr>\n";
    }
  }
  $$errNoRef += $errNo;
  return $res;
}

sub FormatMenuComparison($$$$)
{
  my $Menu1 = shift or die;
  my $Menu2 = shift or die;
  my $name = shift or die;
  my $errNoRef = shift or die;

  my $res = "";
  $res .= "<h3>Menu $name</h3>\n";
  $res .= "<table width='100%' border='1' cellpadding='5' style='border-collapse:collapse'>\n";
  my $initialLevel = 1;
  $res .= FormatMenuComparisonRec($Menu1, $Menu2, $initialLevel, $errNoRef) or return 0;
  $res .= "</table>\n";
  return $res;
}

sub FormatMenusComparison($$$)
{
  my $Menus1 = shift;
  my $Menus2 = shift;
  my $errNoRef = shift or die;

  #   $MENUS{$name} = $MenuItems

  my $res = "";
  $res = "<h2><a name='menus' id='menus'>Menus</a></h2>\n";  
  $res .= <<EOMENUCONV;
<div class='convention'>
<p>Convention: menus items of both resources are listed in parallel in the order defined in the resource file,
with recursion into popup menus. If types (POPUP/MENUITEM) are different, <em>all</em> following items in the same menu
are highlighted (no smart diff!).</p>
<p>Items of type SEPARATOR are completely ignored.</p>
</div>
EOMENUCONV

  # compute usage of menu names in Menus1/2
  my %NAMES;
  SetKeys(\%NAMES, $Menus1, 1); # number identifies language in message below!
  SetKeys(\%NAMES, $Menus2, 2);

  # process
  foreach my $name (sort keys %NAMES) {
    if ($NAMES{$name} == 3) {
      my $Menu1 = $Menus1->{$name};
      my $Menu2 = $Menus2->{$name};
      $res .= FormatMenuComparison($Menu1, $Menu2, $name, $errNoRef);
    }
    else {
      ++$$errNoRef;
      $res .= "<p class='miss'>Menu $name only in language " . $NAMES{$name} . " " . MakeLinks() . "</p>\n";
    }
    $res .= "<p><a href='#_top'>(top)</a></p><hr />\n";
  }

  return $res;
}

sub FormatComparison($$$)
{
  my $resourceFilename = shift or die;
  my $resRef1 = shift or die;
  my $resRef2 = shift or die;

  my $errNo = 0;

  #SKIP MsgDebug("FormatComparison...");
  # compute (for having summary)
  my $tables = FormatDialogsComparison($resRef1->{"DIALOGS"}, $resRef2->{"DIALOGS"}, \$errNo);
  $tables .= FormatStringsComparison($resRef1->{"STRINGS"}, $resRef2->{"STRINGS"}, \$errNo);
  $tables .= FormatMenusComparison($resRef1->{"MENUS"}, $resRef2->{"MENUS"}, \$errNo);

  # TODO: encoding, [xml:]lang
  my $encoding ="ISO-8859-1";
  my $firstLink = "";
  if ($errLinkNumber) {
    $firstLink = " <a href='#err1'>[>>]</a>";
  }
  my $filenameOnly = $resourceFilename;
  $filenameOnly =~ s@.*[\\/]@@;


  my $res = <<EOHEAD;
<?xml version="1.0" encoding="$encoding"?>
<!DOCTYPE html 
     PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=$encoding" />
<title>$filenameOnly</title>
<style type="text/css">
.equal { background-color:\#CCFFCC;}
.miss { background-color:\#FFCCCC;}
.consecutive { background-color:\#FFEEFF;}
.convention { font-size:10pt;}
.indent {text-indent:50pt;}
body { background-color:\#FFFFBD}
h1   { font-size:24pt; font-weight:bold}
h2   { font-size:16pt; font-weight:bold; background-color:\#FFFF66}
h3   { font-size:14pt; background-color:\#FFFF99; color:maroon; font-weight:bold; }
</style>
</head>
<body>
<h1><a name='_top' id='_top'>$filenameOnly - Resource file comparison</a></h1>
<table border='1' cellpadding='5' style='border-collapse:collapse'>
<tr><th>Resource file</th><td>$resourceFilename</td></tr>
<tr><th>Language 1</th><td>$resRef1->{"__LANG"}</td></tr>
<tr><th>Language 2</th><td>$resRef2->{"__LANG"}</td></tr>
<tr><th class='miss'>\# differences</th><td>$errNo$firstLink</td></tr>
</table>
<h2>Meaning of colours</h2>
<p class='indent'><span class='equal'>Equal strings</span></p>
<p class='indent'><span class='miss'>Different types or missing string</span></p>
<p class='indent'><span class='consecutive'>Suspicious data (lines after different types or missing string)</span></p>
<h2>Contents:</h2>
<table class='indent'>
<tr><td><a href='#dialogs'>Dialogs</a></td></tr>
<tr><td><a href='#strings'>String tables</a></td></tr>
<tr><td><a href='#menus'>Menus</a></td></tr>
</table>
EOHEAD

  DropLastLink($tables);
  $res .= $tables;
  $res .= <<EOFOOT;
</body>
</html>
EOFOOT
  #SKIP MsgDebug("  done.");
  return $res;
}

sub List($)
{
  my $optRef = shift or die;
  my $cmd = $optRef->{"cmd"};
  my $wantLongList = $cmd ne "list";
  my $resource = $optRef->{"resource"};

  usage("resource missing") unless $resource;
  MsgInfo("Listing languages in $resource");

  my $resFile = ReadResFile($resource) or return 0;
  my @LANGUAGES = ExtractLanguages($resFile) or return 0;
  print map { 
    my $lang = $_;
    my $res = WinLang2IsoLang($_);
    $res .= ";" . $_ if $wantLongList;
    $res .= "\n";
    $res;
  } @LANGUAGES;
  return 1;
}



sub Compare($)
{
  my $optRef = shift or die;
  my $lang1 = $optRef->{"lang1"};
  my $lang2 = $optRef->{"lang2"};
  my $resource = $optRef->{"resource"};

  usage("lang1 missing") unless $optRef->{"lang1"};
  usage("lang2 missing") unless $optRef->{"lang2"};
  usage("lang1/lang2 must be different: $lang1") if $lang1 eq $lang2;
  usage("resource missing") unless $resource;

  #SKIP MsgInfo("Comparing $lang1 - $lang2 in $resource");

  my $resFile = ReadResFile($resource) or return 0;

  my $resRef1;
  {
    my $langData = ExtractLangData($resFile, $lang1) or return 0;
    #SKIP MsgDebug("Processing language $lang1...");
    $resRef1 = SplitLangData($langData) or return 0;
    $resRef1->{"__LANG"} = $lang1;
  }
  my $resRef2;
  {
    my $langData = ExtractLangData($resFile, $lang2) or return 0;
    #SKIP MsgDebug("Processing language $lang2...");
    $resRef2 = SplitLangData($langData) or return 0;
    $resRef2->{"__LANG"} = $lang2;
  }
  print FormatComparison($resource, $resRef1, $resRef2);
  # HS 2004-12-23 TODO:
  # print STDERR "TODO: (numeric) string constants in 'IDD_xx DLGINIT...' not handled!\n";
  return 1;
}



sub main
{
  my @options = (
    "cmd=s",
    "resource=s",
    "lang1=s",
    "lang2=s",
    "help",
    #SKIP "logfile:s",
    #SKIP "verbose:i",
  );

  my %opt = ();
  &GetOptions(\%opt, @options) or usage();
  my $resource = $opt{"resource"};
  usage() if $opt{"help"};

  #SKIP SetDebug($opt{"verbose"}) if defined($opt{"verbose"});
  #SKIP if (!defined($opt{"logfile"})) {
  #SKIP   $opt{"logfile"} = "checkrc.log";
  #SKIP }
  my $cmd = $opt{"cmd"};
  usage("cmd missing") unless $cmd;

  # Use for setting defaults:
  # $opt{"resource"} = "appName.rc" unless $opt{"resource"};
  # $opt{"lang1"}    = "de" unless $opt{"lang1"};
  # $opt{"lang2"}    = "en" unless $opt{"lang2"};
  # print STDERR "HACK: using " . $opt{"lang1"} . ", " . $opt{"lang2"} . ",  ". $opt{"resource"} . "\n";

  #SKIP SetLogfile($opt{"logfile"}, truncate=>1);
  #SKIP SetStdErrListener();


  # cmd switching

  if ($cmd eq "compare") {
    Compare(\%opt);
  }
  elsif ($cmd =~ m/list/i) {
    List(\%opt);
  }
  else {
    usage("Unknown cmd $cmd");
  }
}

&main();
