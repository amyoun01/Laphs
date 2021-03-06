# Calculating UTM locations for NEON Woody Vegetation structure data 
#
#
# This script calculates UTM (easting, northing) coordinates for individual 
# plants using the NEON Woody Vegetation Structure (NEON.DP1.10098) data 
# product. 
# 
# Victoria Scholl
# victoria.scholl@colorado.edu
# July 13, 2018 
# Capstone project for team LaPHS, 2018 NEON Data Institute 


# install geoNEON for the woody veg location calculation
library(devtools)
#install_github('NEONScience/NEON-geolocation/geoNEON', dependencies=TRUE)
library(geoNEON)

# install neon utilities for the stackByTable function
#install_github("NEONScience/NEON-utilities/neonDataStackR", dependencies=TRUE)
library (neonDataStackR)

# load other required libraries 
library(dplyr)
library(raster)
library(sp)
library(rgdal)



# set working directory to use relative paths 
setwd("~/github/Laphs/")

# define the path to the CHM to get the geographic extent and CRS 
chm_filename = './data/NEON_D01_HARV_DP3_732000_4713000_CHM.tif'

# define the path to the zipped woody veg data
woody_veg_filename = './data/NEON_struct-woody-plant.zip'

neonDataStackR::stackByTable(dpID = 'DP1.10098.001',
             filepath = woody_veg_filename,
             savepath = './data/stackedFiles/')


# calculate absolute locations of individual stems

# read the mappingandtagging data
woody_mapping_and_tagging = read.csv('./data/NEON_struct-woody-plant/stackedFiles/vst_mappingandtagging.csv')

# check how many trees there are in the input mapping_and_tagging file 
print(paste0('There are ', as.character(length(unique(woody_mapping_and_tagging$uid))), 
             ' trees in the mapping_and_tagging file'))


# keep only the entries with stemDistance and stemAzimuth information
woody_mapping_and_tagging <- woody_mapping_and_tagging[complete.cases(woody_mapping_and_tagging$stemAzimuth) & 
                                                       complete.cases(woody_mapping_and_tagging$stemDistance),]

# check how many trees there are with location information (stem distance and azimuth)
print(paste0('There are ', as.character(length(unique(woody_mapping_and_tagging$uid))), 
             ' trees with location information'))


# use the geoNEON R package to pull geolocation data from the NEON API for each reference point. 
# concatenate fields for namedLocation and pointID into new column called "namedLocationPointID"
woody_mapping_and_tagging$namedLocationPointID <- paste(woody_mapping_and_tagging$namedLocation, 
                                                        woody_mapping_and_tagging$pointID, sep=".")

# get coordinates of the reference points for each tree measurement from the API
woody_utm <- geoNEON::def.extr.geo.os(woody_mapping_and_tagging, 'namedLocationPointID')

# get easting/northing of reference point ID
ref_east <- as.numeric(woody_utm$api.easting)
ref_north <- as.numeric(woody_utm$api.northing)
theta <- (woody_utm$stemAzimuth * pi) / 180

# calculate easting and northing for each plant
# add new columns to the woody_utm veg data frame 
woody_utm$easting <- ref_east + 
  woody_utm$stemDistance * sin(theta)
woody_utm$northing <- ref_north + 
  woody_utm$stemDistance * cos(theta)

# get rid of any entries with NA values in the easting/northing columns 
woody_utm_complete <- woody_utm[complete.cases(woody_utm$easting) & 
                                complete.cases(woody_utm$stemDistance),]

# write the woody veg data with UTM (easting, northing) coordinates eo .csv 
write.csv(woody_utm_complete,
          './output/woody_veg_locations.csv')



# get the geographic extent of the tile we will use 
chm_raster <- raster::raster(chm_filename)
chm_extent <- chm_raster@extent
chm_crs <- chm_raster@crs

# write a shapefile with the woody veg locations and other columns of interest 
stem_locations <- woody_utm_complete %>%
  dplyr::select(individualID, scientificName, taxonID, easting, northing)

# assign spatial coordinates to each entry, and coordinate reference system
sp::coordinates(stem_locations) <- ~easting+northing
sp::proj4string(stem_locations) <- chm_crs

# write shapefile 
suppressWarnings(
  rgdal::writeOGR(stem_locations, 
           './output/',
           'woody_veg_location_species', 
           driver="ESRI Shapefile", 
           overwrite_layer = TRUE))

# filter the trees to keep only the ones within in the current CHM tile extent
stem_locations_in <- raster::crop(stem_locations,
                                  chm_extent)

# count how many trees are left
print(paste0(as.character(nrow(stem_locations_in)), 
             " trees are within the current CHM extent"))

# crop the CHM to the area containing stems.
# add a 5m buffer to the edges. 
chm_cropped <- raster::crop(chm_raster,
                            extent(stem_locations_in) + 5)

# plot the CHM and add the tree locations as points 
plot(chm_cropped, legend=TRUE,
     xlab = 'Easting (m)', ylab = 'Northing (m)',
     legend.args=list(text='Height (m)', cex=0.75))
points(stem_locations_in, pch = 20, cex = 0.25)

# Extract height values from the CHM 

