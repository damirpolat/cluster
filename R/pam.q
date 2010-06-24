#### PAM : Partitioning Around Medoids
#### --- $Id: pam.q 5592 2010-06-19 16:37:03Z maechler $
pam <- function(x, k, diss = inherits(x, "dist"),
		metric = "euclidean", medoids = NULL,
                stand = FALSE, cluster.only = FALSE, do.swap = TRUE,
                keep.diss = !diss && !cluster.only && n < 100,
                keep.data = !diss && !cluster.only, trace.lev = 0)
{
    if((diss <- as.logical(diss))) {
	## check type of input vector
	if(any(is.na(x))) stop(..msg$error["NAdiss"])
	if(data.class(x) != "dissimilarity") { # try to convert to
	    if(!is.null(dim(x))) {
		x <- as.dist(x) # or give an error
	    } else {
		## possibly convert input *vector*
		if(!is.numeric(x) || is.na(n <- sizeDiss(x)))
		    stop(..msg$error["non.diss"])
		attr(x, "Size") <- n
	    }
	    class(x) <- dissiCl
	    if(is.null(attr(x,"Metric"))) attr(x, "Metric") <- "unspecified"
	}
	## adapt S dissimilarities to Fortran:
	## convert upper matrix, read by rows, to lower matrix, read by rows.
	n <- attr(x, "Size")
	dv <- x[lower.to.upper.tri.inds(n)]
	## prepare arguments for the Fortran call
	dv <- c(0, dv) ## <- internally needed {FIXME! memory hog!}
	jp <- 1
	mdata <- FALSE
	ndyst <- 0
	x2 <- double(n)
    }
    else {
	## check input matrix and standardize, if necessary
	x <- data.matrix(x)
	if(!is.numeric(x)) stop("x is not a numeric dataframe or matrix.")
	x2 <- if(stand) scale(x, scale = apply(x, 2, meanabsdev)) else x
	## put info about metric, size and NAs in arguments for the Fortran call
	ndyst <- if(metric == "manhattan") 2 else 1
	n <- nrow(x2)
	jp <- ncol(x2)
	if((mdata <- any(inax <- is.na(x2)))) { # TRUE if x[] has any NAs
	    jtmd <- as.integer(ifelse(apply(inax, 2, any), -1, 1))
	    ## VALue for MISsing DATa
	    valmisdat <- 1.1* max(abs(range(x2, na.rm=TRUE)))
	    x2[inax] <- valmisdat
	    valmd <- rep(valmisdat, jp)
	}
	dv <- double(1 + (n * (n - 1))/2)
    }
    if((k <- as.integer(k)) < 1 || k >= n)
	stop("Number of clusters `k' must be in {1,2, .., n-1}; hence n >= 2")
    if(is.null(medoids))# default: using "build & swap" to determine medoids"
        medID <- integer(k)# all 0 -> will be used as `code' in C
    else {
        ## 'fixme': consider  sort(medoids) {and rely on it in ../src/pam.c }
	if(length(medID <- as.integer(medoids)) != k ||
	   any(medID < 1) || any(medID > n) || any(duplicated(medID)))
	    stop("'medoids' must be NULL or vector of ",
		 k, " distinct indices in {1,2, .., n}, n=", n)
        ## use observation numbers  'medID' as starting medoids for 'swap' only
    }
    nisol <- integer(if(cluster.only) 1 else k)
    if(do.swap) nisol[1] <- 1L
    stopifnot(length(cluster.only) == 1,
	      length(trace.lev) == 1)
    ## call Fortran routine
    storage.mode(dv) <- "double"
    storage.mode(x2) <- "double"
    res <- .C(cl_pam,
	      as.integer(n),
	      as.integer(jp),
	      k,
	      x = x2,
	      dys = dv,
	      jdyss = as.integer(diss),
	      if(mdata)valmd else double(1),
	      if(mdata) jtmd else integer(jp),
	      as.integer(ndyst),
	      integer(n),		# nsend[]
	      logical(n),		# nrepr[]
	      integer(if(cluster.only) 1 else n), # nelem[]
	      double(n),		# radus[]
	      double(n),		# damer[]
	      avsil = double(n),	# `ttd'
	      double(n),		# separ[]
	      ttsil = as.double(0),
	      obj = as.double(c(cluster.only, trace.lev)),# in & out!
	      med = medID,# in & out(if !cluster.only)
	      clu = integer(n),
	      clusinf = if(cluster.only) 0. else matrix(0., k, 5),
	      silinf  = if(cluster.only) 0. else matrix(0., n, 4),
	      isol = nisol,
	      DUP = FALSE) # care!!

    xLab <- if(diss) attr(x, "Labels") else dimnames(x)[[1]]
    if(length(xLab) > 0)
        names(res$clu) <- xLab
    if(cluster.only)
        return(res$clu)

    ## Else, usually
    medID <- res$med
    if(any(medID <= 0))
	stop("error from .C(cl_pam, *): invalid medID's")
    sildim <- res$silinf[, 4]
    if(diss) {
	if(keep.diss) disv <- x
	## add labels to Fortran output
	if(length(xLab) > 0) {
	    sildim <- xLab[sildim]
	    res$med <- xLab[medID]
	}
    }
    else {
	## give warning if some dissimilarities are missing.
	if(res$jdyss == -1)
	    stop("No clustering performed, NAs in the computed dissimilarity matrix.")
        if(keep.diss) {
            ## adapt Fortran output to S:
            ## convert lower matrix, read by rows, to upper matrix, read by rows.
            disv <- res$dys[-1]
            disv[disv == -1] <- NA
            disv <- disv[upper.to.lower.tri.inds(n)]
            class(disv) <- dissiCl
            attr(disv, "Size") <- nrow(x)
            attr(disv, "Metric") <- metric
            attr(disv, "Labels") <- dimnames(x)[[1]]
        }
	## add labels to Fortran output
	res$med <- x[medID,  , drop =FALSE]
	if(length(xLab) > 0)
	    sildim <- xLab[sildim]
    }
    ## add dimnames to Fortran output
    names(res$obj) <- c("build", "swap")
    res$isol <- factor(res$isol, levels = 0:2, labels = c("no", "L", "L*"))
    names(res$isol) <- 1:k
    dimnames(res$clusinf) <- list(NULL, c("size", "max_diss", "av_diss",
					  "diameter", "separation"))
    ## construct S object
    r <-
	list(medoids = res$med, id.med = medID, clustering = res$clu,
	     objective = res$obj, isolation = res$isol,
	     clusinfo = res$clusinf,
	     silinfo = if(k != 1) {
		 dimnames(res$silinf) <-
		     list(sildim, c("cluster", "neighbor", "sil_width", ""))
		 list(widths = res$silinf[, -4],
		      clus.avg.widths = res$avsil[1:k],
		      avg.width = res$ttsil)
	     },
	     diss = if(keep.diss)disv,
	     call = match.call())
    if(keep.data && !diss) {
	if(mdata) x2[x2 == valmisdat] <- NA
	r$data <- x2
    }
    class(r) <- c("pam", "partition")
    r
}

## non-exported:
.print.pam <- function(x, ...) {
    cat("Medoids:\n");		print(cbind(ID = x$id.med, x$medoids), ...)
    cat("Clustering vector:\n");	print(x$clustering, ...)
    cat("Objective function:\n");	print(x$objective, ...)
}

print.pam <- function(x, ...)
{
    .print.pam(x, ...)
    cat("\nAvailable components:\n")
    print(names(x), ...)
    invisible(x)
}

summary.pam <- function(object, ...)
{
    class(object) <- "summary.pam"
    object
}

print.summary.pam <- function(x, ...)
{
    .print.pam(x, ...)
    cat("\nNumerical information per cluster:\n"); print(x$clusinfo, ...)
    cat("\nIsolated clusters:\n L-clusters: ")
    print(names(x$isolation[x$isolation == "L"]), quote = FALSE, ...)
    cat(" L*-clusters: ")
    print(names(x$isolation[x$isolation == "L*"]), quote = FALSE, ...)
    if(length(x$silinfo) != 0) {
	cat("\nSilhouette plot information:\n")
	print(x$silinfo[[1]], ...)
	cat("Average silhouette width per cluster:\n")
	print(x$silinfo[[2]], ...)
	cat("Average silhouette width of total data set:\n")
	print(x$silinfo[[3]], ...)
    }
    if(!is.null(x$diss)) { ## Dissimilarities:
	cat("\n");			print(summary(x$diss, ...))
    }
    cat("\nAvailable components:\n");	print(names(x), ...)
    invisible(x)
}

