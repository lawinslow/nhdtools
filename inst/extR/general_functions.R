library(dplyr)
library(dbplyr) #this is an implicit dependency of dplyr when using sqlite DB 
library(sf)
library(foreign)
library(tools)
library(RCurl)

# args is a named vector with 3 columns: shape path, output layer name, bounding box entry file name
project_and_get_bb = function(args){
  shape_path = args["shape_path"]
  layer = args["layer"]
  output_name = args["output_name"]
  shape = st_read(shape_path)
  shape = st_transform(shape, st_crs("+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=23 +lon_0=-96 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs"))
  shape = st_zm(shape)
  centroids = st_centroid(shape)
  shape$centroid.x = st_coordinates(centroids)[,"X"]
  shape$centroid.y = st_coordinates(centroids)[,"Y"]
  colnames(shape) = tolower(colnames(shape))
  st_write(shape, dsn = shape_path, layer = layer, driver = "ESRI Shapefile", update=TRUE)
  ret = st_sf(file = output_name,
              geometry=st_as_sfc(st_bbox(shape), crs=nhd_projected_proj), stringsAsFactors = FALSE)
  return(ret)
}

build_id_table = function(bbdf, layer, file_name, index_columns, shape_locations = NULL){
  ids = list()
  index_columns = tolower(index_columns)
  for(i in 1:nrow(bbdf)){
    shape = NULL
    if(is.null(shape_locations)){
      shape = st_read(file.path(bbdf$file[i], layer), stringsAsFactors = FALSE)
    }else{
      shape = st_read(file.path(shape_locations[i], layer), stringsAsFactors = FALSE)
    }
    st_geometry(shape) = NULL
    colnames(shape) = tolower(colnames(shape))
    shape = shape[,index_columns]
    shape$file = bbdf$file[i]
    ids[[i]] = shape
  }
  id_lookup = bind_rows(ids)
  db = src_sqlite(file_name, create = TRUE)
  copy_to(db, id_lookup, overwrite = TRUE, temporary = FALSE, indexes = list(index_columns, "file"))
}

format_flowtable = function(raw_tables, shape_directories, wbarea_column, from_column, to_column, id_column, output_name){
  changes = list()
  
  for(i in 1:length(shape_directories)){
    file = shape_directories[i]
    flowline = st_read(file.path(shape_directories[i], "NHDFlowline_projected.shp"))
    waterbody = st_read(file.path(shape_directories[i], "NHDWaterbody_projected.shp"))
    st_geometry(flowline) = NULL
    st_geometry(waterbody) = NULL
    colnames(flowline) = toupper(colnames(flowline))
    colnames(waterbody) = toupper(colnames(waterbody))
    flowline = flowline[!is.na(flowline[,wbarea_column]),]
    flowline = flowline[flowline[,wbarea_column] %in% waterbody[,id_column],]
    change = data.frame(flowline[,id_column], flowline[,wbarea_column], stringsAsFactors = FALSE)
    colnames(change) = c("id_column", "wbarea_column")
    change$id_column = as.character(change$id_column)
    change$wbarea_column = as.character(change$wbarea_column)
    changes[[i]] = change
  }
  
  tables = list()
  
  for(i in 1:length(raw_tables)){
    table = read.dbf(raw_tables[i], as.is = TRUE)
    
    colnames(table) = toupper(colnames(table))
    
    #changes_from = changes[[i]][changes[[i]][,"id_column"] %in% tables[[i]][,from_column], ]
    #changes_to = changes[[i]][changes[[i]][,"id_column"] %in% tables[[i]][,to_column], ]
    change = changes[[i]]
    
    table = merge(table, change, by.x = from_column, by.y = "id_column", all.x = TRUE)
    table[!is.na(table$wbarea_column), from_column] = table$wbarea_column[!is.na(table$wbarea_column)]
    table$wbarea_column = NULL
    
    table = merge(table, change, by.x = to_column, by.y = "id_column", all.x = TRUE)
    table[!is.na(table$wbarea_column), to_column] = table$wbarea_column[!is.na(table$wbarea_column)]
    table$wbarea_column = NULL
    
    tables[[i]] = table
    
  }
  #tables = lapply(tables, function(x){x = sapply(x, as.character)})
  flowtable = do.call(rbind, tables)
  flowtable = as.data.frame(flowtable)
  save(flowtable, file = paste0(output_name, "_complete.Rdata"))
  flowtable = flowtable[,c(from_column, to_column)]
  
  distances = list()
  
  for(i in 1:length(shape_directories)){
    flowline = st_read(file.path(shape_directories[i], "NHDFlowline_projected.shp"))
    st_geometry(flowline) = NULL
    colnames(flowline) = toupper(colnames(flowline))
    distances[[i]] = data.frame(flowline[,id_column], flowline$LENGTHKM)
  }
  
  distances = bind_rows(distances)
  colnames(distances) = c(from_column, "LENGTHKM")
  distances[,from_column] = as.character(distances[,from_column])
  flowtable = merge(flowtable, distances, by = from_column, all.x = TRUE)
  flowtable = flowtable[-which(flowtable[,from_column] == flowtable[, to_column]), ] # remove links to self
  ids_db = src_sqlite(paste0(output_name, ".sqlite3"), create = TRUE)
  copy_to(ids_db, flowtable, overwrite = TRUE, temporary = FALSE, indexes = list(from_column, to_column))
  rm(ids_db)
  gc()
}


gen_upload_file = function(files, remote_path){
  hash = md5sum(files)
  #conf = read.csv(conf_file)
  # for(i in 1:length(files)){
  #   result = ftpUpload(files[i], paste0("ftp://", conf$username, ":", conf$password, "@", conf$hostname, "/", remote_path, "/", basename(files[i])))
  #   if(result != 0){
  #     stop("upload failed!")
  #   }
  # }
  urls = file.path(remote_path, basename(files))
  #files = basename(files)
  result = data.frame(filename = basename(files), url = urls, md5 = hash)
  rownames(result) = c(1:nrow(result))
  return(result)
}
