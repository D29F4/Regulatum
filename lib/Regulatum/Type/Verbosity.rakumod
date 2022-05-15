# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##  Class : Verbosity
##
##  Attributes necessary for and functions available to the verbosity option.
##===========================================================================
use Regulatum::Type::Subsets;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit class Regulatum::Type::Verbosity is export;



#----------------------------------------------------------------------------
#  Verbosity level
#----------------------------------------------------------------------------
subset Verbosity_Level of Int where * ~~ 0..2;
#____________________________________________________________________________



#----------------------------------------------------------------------------
#  Verbosity level
#----------------------------------------------------------------------------
has Verbosity_Level $.level
  is rw
  = 0;

#----------------------------------------------------------------------------
#  The filehandle for output
#----------------------------------------------------------------------------
has IO::Handle $.fh-out
  is rw
  = $*OUT;

#----------------------------------------------------------------------------
#  Commented output
#
#  True if messages should be printed as comments in the output context.
#----------------------------------------------------------------------------
has Bool $.as_comment
  = False;
#____________________________________________________________________________



#============================================================================
#  print
#
#  Print message (possibly with necessary formatting).
#----------------------------------------------------------------------------
method print(Str $text is copy, Str $format = 'svg' --> Nil)
{
  #  Apply comment content if necessary
  if $!as_comment
  {
    given $format
    {
      when 'svg' | 'html'
      {
        #  Disable any strings which would close the comment
        $text ~~ s/'-->'/->/;
        $text = sprintf '<!-- %s -->', $text;
      }
      default
      {
        $text = '# ' ~ $text;
      }
    }
  }

  #  Print text
  $!fh-out.put: $text;

  return;
}
#____________________________________________________________________________



## EOF