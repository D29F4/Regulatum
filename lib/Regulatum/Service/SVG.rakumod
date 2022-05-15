# SPDX-License-Identifier: Artistic-2.0
##===========================================================================
##  Module : SVG
##
##  Render SVG enclosure and tiles as SVG elements.
##===========================================================================
use Regulatum::Type::Subsets;
use Regulatum::Type::Tile;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
unit module Regulatum::SVG;



#============================================================================
#  svg-start
#
#  The main SVG enclosure element.
#
#  (We don't have a means of producing SVG structures with more than two
#  dimensions....)
#----------------------------------------------------------------------------
sub svg-start(
  Int           @dimensions,
  Spacing_Ratio $spacing_ratio
  --> Str
) is export
{
  my Int @dims = @dimensions.map(-> $num_cells
  {
    $spacing_ratio == 0
      ?? $num_cells
      !! ($num_cells * $spacing_ratio) + ($num_cells - 1);
  });

  return sprintf
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s">',
    @dims[0], @dims[1];
}
#____________________________________________________________________________



#============================================================================
#  svg-end
#
#  End SVG enclosure element.
#----------------------------------------------------------------------------
sub svg-end(--> Str) is export
{
  return '</svg>';
}
#____________________________________________________________________________



#============================================================================
#  determine_tile_coordinates
#--------------------------------------------------------------------------
sub determine_tile_coordinates(
  Spacing_Ratio $spacing_ratio,
  Int           @positions
  --> Seq
)
{
  return @positions.keys.map(
  {
    (@positions[$_] * $spacing_ratio) + @positions[$_];
  });
}
#__________________________________________________________________________



#============================================================================
#  determine_tile_dimensions
#--------------------------------------------------------------------------
sub determine_tile_dimensions(
  Spacing_Ratio $spacing_ratio,
  @positions,
  Tile $tile
  --> Seq
)
{
  return $tile.extensions.map(-> $extension
  {
    $spacing_ratio == 0
      #  If there is to be no intertile spacing
      ?? $extension + 1
      #  If positive intertile spacing
      !! (($extension + 1) * $spacing_ratio) + ($extension);
  });
}
#__________________________________________________________________________



#============================================================================
#  generate_tile_element
#
#  Produce text for a single tile element.
#--------------------------------------------------------------------------
sub generate_tile_element(
  Spacing_Ratio $spacing_ratio,
  @positions,
  Tile $tile,
  Color $tile_color
  --> Str
) is export
{
  my $coordinates = determine_tile_coordinates($spacing_ratio, @positions);
  my $dims = determine_tile_dimensions($spacing_ratio, @positions, $tile);

  return sprintf
    '<rect x="%s" y="%s" width="%s" height="%s" fill="%s"></rect>',
    $coordinates[0], $coordinates[1], $dims[0], $dims[1], $tile_color;
}
#____________________________________________________________________________



## EOF
