# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##  Module : Colors
##
##  Provide functionality related to colors.
##===========================================================================
use Regulatum::Type::Subsets;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit module Regulatum::Colors;



#============================================================================
#  generate_color
#
#  Generate an SVG-compatible/Web color.
#----------------------------------------------------------------------------
sub generate_color(Bool $truncated = True --> Color) is export
{
  return '#'
    #  Obtain a Seq of color values
    ~ ((0..15).roll($truncated ?? 3 !! 6)
    #  Translate all to hex and combine
    .map({ .trans([10..15] => ['a'..'f']) }).join);
}
#____________________________________________________________________________



## EOF
