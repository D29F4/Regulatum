# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##  Class : Tile
##
##  Uniquely-defined by dimensions.
##===========================================================================
use Regulatum::Type::Subsets;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit class Regulatum::Type::Tile is export;



#----------------------------------------------------------------------------
#  The spatial extensions (lengths) of this tile in each dimension.  Each
#  value corresponds to the respective dimensional element in
#  Parameters.dimensions.
#----------------------------------------------------------------------------
has Extension @.extensions
  is required;

#----------------------------------------------------------------------------
#  The probability (as a percentile) of this tile's placement.
#
#  This is a sort of attribute of the tile though it may not be directly
#  referenced as probabilities may be aggregated in other data structures.
#----------------------------------------------------------------------------
has Int_Pos $.probability;

#----------------------------------------------------------------------------
#  An HTML-compatible representation of the tile color.
#
#  A writable property because the coloring method may overwrite any
#  prescribed value.
#----------------------------------------------------------------------------
has Color $.color
  is rw
  = Color;
#____________________________________________________________________________



## EOF
