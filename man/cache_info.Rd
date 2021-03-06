% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/local_path_helpers.R
\name{cache_info}
\alias{cache_info}
\title{Get local file cache info}
\usage{
cache_info()
}
\value{
Returns a data.frame that has the columns \code{file, type, size.MB}.
}
\description{
Returns info on all locally cached files stored at the current cache.
By default, prints a summary of cache info including total size.
}
\examples{
\dontshow{cache_set_dir(temppath=TRUE)}
cache_info()

}
