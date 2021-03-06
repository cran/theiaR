#' A tile from Theia
#'
#' Generate and manage a tile from Theia (download, check, load).
#'
#' @name TheiaTile
#'
#' @section Usage:
#' \preformatted{
#'    t <- TheiaTile$new(file.path,
#'                       url,
#'                       file.hash,
#'                       check = TRUE,
#'                       quiet = TRUE)
#'
#'    t$download(overwrite = FALSE, check = TRUE, quiet = TRUE)
#'    t$check()
#'    t$extract(overwrite = FALSE, dest.dir = NULL)
#'    t$read(bands)
#' }
#'
#' @section Arguments:
#'
#' \describe{
#'    \item{t:}{A \code{TheiaTile} object}
#'    \item{file.path:}{The path to the zip file containing the tile}
#'    \item{url:}{The url to download the tile}
#'    \item{file.hash:}{The md5sum used to check the zip file}
#'    \item{check:}{Whether or not to check existing files on tile's creation}
#'    \item{quiet:}{Control verbose output}
#'    \item{auth:}{A character string giving the file path to Theia credentials.
#'    Or a \code{\link{TheiaAuth}} object}
#'    \item{overwrite:}{Overwrite existing tiles (default to `FALSE`)}
#'    \item{bands:}{A character vector of bands to load from tiles}
#'  }
#'
#' @section Details:
#'    \code{TheiaTile$new(file.path, url, file.hash, check)} Create a new instance of
#'    the class
#'
#'    \code{t$download(auth, overwrite = FALSE, check = TRUE)} Download the
#'    tiles of the collection and check the resulting files
#'
#'    \code{t$check()} Check the tiles of the collection
#'
#'    \code{t$extract(overwrite = FALSE, dest.dir = NULL)} Extract archive to
#'    dest.dir if supplied, or to the same directory as the archive otherwise
#'
#'    \code{t$read(bands)} Read requested bands, apply corrections on values
#'    (as specified in Theia's product information), and return a RasterStack
#'
#'    \code{t$bands} List bands available in the tile
#'
#'
NULL


#' @export

TheiaTile <-
  R6Class("TheiaTile",
          # public -------------------------------------------------------------
          public =
            list(file.path      = NA,
                 file.hash      = NA,
                 url            = NA,
                 tile.name      = NA,
                 path.extracted = NA,
                 md             = NULL,
                 collection     = NA,
                 status         = list(exists    = FALSE,
                                       checked   = FALSE,
                                       correct   = FALSE,
                                       extracted = FALSE),

                 initialize = function(file.path, url, tile.name, file.hash, collection = NULL, check = TRUE, quiet = TRUE)
                 {
                   if (quiet == TRUE) {
                     suppressMessages({
                       .TheiaTile_initialize(self, file.path, url, tile.name, file.hash, collection, check)
                     })
                   } else {
                     .TheiaTile_initialize(self, file.path, url, tile.name, file.hash, collection, check)
                   }
                 },

                 print = function(...)
                 {
                   .TheiaTile_print(self)
                 },

                 check = function(check = TRUE)
                 {
                   .TheiaTile_check(self, check)
                 },

                 download = function(auth, overwrite = FALSE, check = TRUE, quiet = TRUE)
                 {
                   if (quiet == TRUE) {
                     suppressMessages({
                       .TheiaTile_download(self, auth, overwrite, check)
                     })
                   } else {
                     .TheiaTile_download(self, auth, overwrite, check)
                   }
                 },
                  
                 read = function(bands)
                 {
                   .TheiaTile_read(self, bands)
                 },

                 extract = function(overwrite = FALSE, dest.dir = NULL)
                 {
                   .TheiaTile_extract(self, overwrite, dest.dir)
                 }),

          active =
            list(meta.data = function()
                 {
                   if (is.null(self$md)) {
                     return(.TheiaTile_read_md(self))
                   }

                   return(self$md)
                 },

                 bands = function()
                 {
                   .TheiaTile_get_bands(self)
                 })
          )


# Functions definitions --------------------------------------------------------

.TheiaTile_print <- function(self)
{
  # Special method to print
  cat("An Tile from Theia\n\n")

  cat("Collection:", self$collection, "\n\n")

  cat("Status:\n")
  cat("   downloaded :", self$status$exists, "\n")
  cat("   checked    :", self$status$checked, "\n")
  cat("   correct    :", self$status$correct, "\n")

  return(invisible(self))
}


.TheiaTile_initialize <- function(self, file.path, url, tile.name, file.hash, collection = NULL, check)
{
  # Fill fields of the object
  self$file.path  <- file.path
  self$url        <- url
  self$tile.name  <- gsub("\\.tar\\.gz$|\\.zip$", "", tile.name)
  self$file.hash  <- file.hash

  if (is.null(collection)) {
    # try to guess the collection based on the file name (should be used only if
    # the collection has been created from a cart file)
    self$collection <- gsub("(.*)(/[^/]*$)", "\\2", self$file.path)
    self$collection <- gsub("(^/)([[:alnum:]]*)(_.*$)", "\\2", self$collection)
    self$collection <- gsub("([[:alnum:]]*)([[:alnum:]]{1}$)", "\\1", self$collection)
  } else {
    self$collection <- collection
  }

  # check the tile
  self$check(check)

  return(invisible(self))
}


.TheiaTile_check <- function(self, check)
{
  # check the tile
  if (file.exists(self$file.path)) {
    # if the file exists, check it

    if (check == FALSE) {
      message("Assuming file is correctly downloaded. Set 'check=TRUE' to check file's hash")

      self$status$exists  <- TRUE
      self$status$checked <- FALSE
      self$status$correct <- TRUE

      return(invisible(self))
    }

    message("Checking downloaded file...")

    self$status$exists  <- TRUE
    self$status$checked <- TRUE

    if (is.na(self$file.hash)) {
      # if no hash is provided, assume the file is correct
      self$status$correct <- TRUE

      return(invisible(self))
    }

    # compute the md5 sum and compare it to the hash
    if (tools::md5sum(self$file.path) == self$file.hash) {
      self$status$correct <- TRUE
    } else {
      self$status$correct <- FALSE
      warning(self$file.path, "incorrectly downloaded")
    }
  }

  return(invisible(self))
}


.TheiaTile_download <- function(self, auth, overwrite, check)
{
  if (is.character(auth)) {
    # create authentification system if not supplied
    auth <- TheiaAuth$new(auth.file = auth)
  }

  if (!(self$status$correct) | overwrite == TRUE ) {
    # file does not exist, is not correct, or overwrite is TRUE

    # build the URL for the request: remove token if link has been created from
    # a cart file and add needed part
    url <- gsub("\\?_tk=.*$", "", self$url)
    url <- paste0(url, "/?issuerId=theia")

    # HTTP request
    req <- httr::GET(url,
                     httr::add_headers(Authorization = paste("Bearer", auth$token)),
                     httr::write_disk(self$file.path, overwrite = TRUE),
                     httr::progress())

    httr::stop_for_status(req, task = paste0("download tile: ", self$file.path))

    # test if file is text
    if (!(grepl("zip", httr::http_type(req)))) {
      stop("Downloaded product is a text file, it should not be... Response:\n\n",
           httr::content(req, as = "text"))
    }

  } else {
    # The file already exists
    message("File ",
            self$file.path,
            " already exists. Use 'overwrite=TRUE' to ovewrite.")
  }

  if (check == TRUE) {
    # check the tile
    self$check()
  } else {
    # do not check file
    message("Assuming file is correctly downloaded. Set 'check=TRUE' to check file's hash")

    self$status$exists  <- TRUE
    self$status$checked <- FALSE
    self$status$correct <- TRUE
  }

  return(invisible(self))
}


.TheiaTile_read_md <- function(self)
{
  message("Parsing meta data...")

  # create temporary directory
  tmp.dir <- file.path(tempdir(), "/")

  # get file name to extract
  file.name <- extraction_wrapper(self$file.path, args = list(list = TRUE))
  file.name <- file.name[grepl("\\.xml$", file.name)]

  # extract and parse xml file
  extraction_wrapper(self$file.path, args = list(files = file.name, exdir = tmp.dir))
  meta.data <- XML::xmlToList(XML::xmlParse(file.path(tmp.dir, file.name)))

  # remove temporary file
  unlink(file.path(tmp.dir, file.name))

  # store it in object so it we don't have to read again if we need it
  self$md = meta.data

  return(meta.data)
}


.TheiaTile_get_bands <- function(self)
{
  # get bands list from meta data
  if (self$collection == 'Landsat57') {
    # Read the bands from the old format
    bands = data.frame(
      band       = unlist(strsplit(self$meta.data$RADIOMETRY$BANDS, ';')),
      resolution = 'R1'
    )

    return(bands)
  }

  bands <- lapply(self$meta.data$Product_Characteristics$Band_Group_List,
                  function(x) {
                    band.list <- unlist(x$Band_List[-(length(x$Band_List))])
                    band.id   <- unname(x$.attrs)

                    data.frame(band = band.list, resolution = band.id)
                  })

  bands <- do.call(rbind, bands)
  rownames(bands) <- NULL

  return(bands)
}


.TheiaTile_read <- function(self, bands)
{
  if (self$collection == 'Landsat57') {
    stop(
      'This feature is not available for Landsat57 collection. You can read the bands manually with the `raster` library.',
      call. = FALSE
    )
    # file.name <- paste0('/vsitar/', self$file.path, '/', self$meta.data$FILES$ORTHO_SURF_CORR_PENTE)
    # tiles.stack <- raster::stack(file.name)
    # names(tiles.stack) <- avail.bands
    # tiles.stack = tiles.stack[[bands]]

    # return(tiles.stack)
  }

  # check if requested bands are available
  avail.bands <- self$bands

  if (any(!(bands %in% avail.bands$band))) {
    # error if some bands are not available
    bad.bands <- paste(bands[!(bands %in% avail.bands)], collapse = ", ")
    stop("Bands '", bad.bands, "' are not available!")
  }

  # get file names to read from
  files   <- unzip(self$file.path, list = TRUE)$Name
  pattern <- paste(paste0("FRE_", bands, ".tif$"), collapse = "|")
  files   <- files[grepl(pattern, files)]

  # read tiles from zip file and create raster::rasterStack object
  tiles.list <- lapply(files, read_tiff_from_zip, zip.file = self$file.path)

  # correct values
  tiles.stack <- raster::stack(lapply(tiles.list, correct_values))

  # give names to the layers
  bands.names <- gsub("(^.*_)([[:alnum:]]*$)", "\\2", names(tiles.stack))
  names(tiles.stack) <- bands.names

  return(tiles.stack)
}


.TheiaTile_extract <- function(self, overwrite, dest.dir)
{
  if (is.null(dest.dir)) {
    # create destination directory if not supllied
    dest.dir <- gsub(self$tile.name, "", self$file.path)
    dest.dir <- gsub("\\.zip$|\\.tar.\\gz$", "", dest.dir)
  }

  # get extracted archive name
  file.path <- extraction_wrapper(self$file.path, args = list(list = TRUE))[1]
  file.path <- gsub("(^.*/)(.*$)", "\\1", file.path)
  file.path <- file.path(dest.dir, file.path)

  if (!(dir.exists(file.path)) | overwrite == TRUE) {
    # check if it exists
    extraction_wrapper(self$file.path, args = list(exdir = dest.dir))

    self$status$extracted <- TRUE
    self$path.extracted   <- file.path
  } else {
    self$status$extracted <- TRUE
    self$path.extracted   <- file.path

    message(file.path, " already exists. Use 'overwrite=TRUE' to overwrite")
  }

  return(invisible(file.path))
}
