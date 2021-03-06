### The constrained ordination methods cca, rda, capscale & dbrda are
### very similar. Their main difference is the init of dependent
### matrix and after that the partializing, constraining and residual
### steps are very similar to each other. This file provides functions
### that can analyse any classic method, the only difference being the
### attributes of the dependet variable.

### In this file we use convention modelfunction(Y, X, Z) where Y is
### the dependent data set (community), X is the model matrix of
### constraints, and Z is the model matrix of conditions to be
### partialled out. The common outline of the function is:
###
### initX(Y)
### pCCA <- ordPartial(Y, Z)
### CCA <- ordConstrain(Y, X, Z)
### CA <- ordResid(Y)
###
### The init step sets up the dependent data Y and sets up its
### attributes that control how it will be handled at later
### stage. Each of the later stages modifies Y and returns results of
### its analysis. The handling of the function is mainly similar, but
### there is some variation depending on the attributes of Y.

### THE USAGE

### Function prototype is ordConstrained(Y, X=NULL, Z=NULL, method),
### where Y is the dependent community data set, X is the model matrix
### of constraints, Z the model matrix of conditions, method is "cca",
### "rda", "capscale" or "dbrda" (the last two may not work, and
### "capscale" may not work in the way you assume). The function
### returns a large subset of correspoding constrained ordination
### method. For instance, with method = "dbrda", the result is mainly
### correct, but it differs so much from the current dbrda that it
### cannot be printed cleanly.

### THE INIT METHODS

### The init methods transform the dependent data specifically to the
### particular method and set up attributes that will control further
### processing of Y. The process critical attributes are set up in
### UPPER CASE to make the if-statements stand out in later analysis.

`initPCA` <-
    function(Y, scale = FALSE)
{
    Y <- as.matrix(Y)
    Y <- scale(Y, scale = scale)
    ## we want variance based model when scale = FALSE -- this will
    ## break Xbar where we want to have back the original scaling
    if (!scale)
        Y <- Y / sqrt(nrow(Y) - 1)
    attr(Y, "METHOD") <- "PCA"
    Y
}

`initCA` <-
    function(Y)
{
    Y <- as.matrix(Y)
    Y <- Y/sum(Y)
    rw <- rowSums(Y)
    cw <- colSums(Y)
    rc <- outer(rw, cw)
    Y <- (Y - rc)/sqrt(rc)
    attr(Y, "RW") <- rw
    attr(Y, "CW") <- cw
    attr(Y, "METHOD") <- "CA"
    Y
}

`initDBRDA` <-
    function(Y)
{
    ## check
    Y <- as.matrix(Y)
    dims <- dim(Y)
    if (dims[1] != dims[2] || !isSymmetric(unname(Y)))
        stop("input Y must be distances or a symmetric square matrix")
    ## transform
    Y <- -0.5 * GowerDblcen(Y^2)
    attr(Y, "METHOD") <- "DISTBASED"
    Y
}

### COMMON HEADER INFORMATION FOR ORDINATION MODELS

`ordHead`<- function(Y)
{
    totvar <- sum(Y^2)
    head <- list("tot.chi" = totvar)
    head
}

### THE PARTIAL MODEL

`ordPartial` <-
    function(Y, Z)
{
    ## attributes
    DISTBASED <- attr(Y, "METHOD") == "DISTBASED"
    RW <- attr(Y, "RW")
    ## centre Z
    if (!is.null(RW)) {
        envcentre <- apply(Z, 2, weighted.mean, w = RW)
        Z <- scale(Z, center = envcentre, scale = FALSE)
        Z <- sweep(Z, 1, sqrt(RW), "*")
    } else {
        envcentre <- colMeans(Z)
        Z <- scale(Z, center = envcentre, scale = FALSE)
    }
    ## QR decomposition
    Q <- qr(Z)
    ## partialled out variation as a trace of Yfit
    Yfit <- qr.fitted(Q, Y)
    if (DISTBASED)
        totvar <- sum(diag(Yfit))
    else
        totvar <- sum(Yfit^2)
    ## residuals of Y
    Y <- qr.resid(Q, Y)
    if (DISTBASED)
        Y <- qr.resid(Q, t(Y))
    ## result object like in current cca, rda
    result <- list(
        rank = Q$rank,
        tot.chi = totvar,
        QR = Q,
        Fit = Yfit,
        envcentre = envcentre)
    list(Y = Y, result = result)
}

### THE CONSTRAINTS

`ordConstrain` <- function(Y, X, Z)
{
    ## attributes & constants
    DISTBASED <- attr(Y, "METHOD") == "DISTBASED"
    RW <- attr(Y, "RW")
    CW <- attr(Y, "CW")
    ZERO <- 1e-5
    ## combine conditions and constraints if necessary
    if (!is.null(Z)) {
        X <- cbind(Z, X)
        zcol <- ncol(Z)
    } else {
        zcol <- 0
    }
    ## centre
    if (!is.null(RW)) {
        envcentre <- apply(X, 2, weighted.mean, w = RW)
        X <- scale(X, center = envcentre, scale = FALSE)
        X <- sweep(X, 1, sqrt(RW), "*")
    } else {
        envcentre <- colMeans(X)
        X <- scale(X, center = envcentre, scale = FALSE)
    }
    ## QR
    Q <- qr(X)
    ## we need to see how much rank grows over rank of conditions
    rank <- sum(Q$pivot[seq_len(Q$rank)] > zcol)
    ## check for aliased terms
    if (length(Q$pivot) > Q$rank)
        alias <- colnames(Q$qr)[-seq_len(Q$rank)]
    else
        alias <- NULL
    ## kept constraints
    kept <- seq_along(Q$pivot) <= Q$rank & Q$pivot > zcol
    ## eigen solution
    Yfit <- qr.fitted(Q, Y)
    if (DISTBASED) {
        Yfit <- qr.fitted(Q, t(Yfit))
        sol <- eigen(Yfit, symmetric = TRUE)
        lambda <- sol$values
        u <- sol$vectors
        v <- NULL
    } else {
        sol <- svd(Yfit)
        lambda <- sol$d^2
        u <- sol$u
        v <- sol$v
    }
    ## handle zero  eigenvalues ... negative eigenvalues not yet implemented
    zeroev <- abs(lambda) < ZERO * lambda[1]
    if (any(zeroev)) {
        lambda <- lambda[!zeroev]
        u <- u[, !zeroev]
        if (!is.null(v))
            v <- v[, !zeroev]
    }
    ## wa scores
    if (DISTBASED) { # not yet implemented
        wa <- NA
    } else {
        wa <- Y %*% v %*% diag(1/sqrt(lambda), length(lambda))
    }
    ## biplot scores
    bp <- cor(X[, Q$pivot[kept], drop = FALSE], u)
    ## de-weight
    if (!is.null(RW)) {
        u <- sweep(u, 1, sqrt(RW), "/")
        if (all(!is.na(wa)))
            wa <- sweep(wa, 1, sqrt(RW), "/")
    }
    if (!is.null(CW) && !is.null(v)) {
        v <- sweep(v, 1, sqrt(CW), "/")
    }

    ## out
    result <- list(
        eig = lambda,
        u = u,
        v = v,
        wa = wa,
        alias = alias,
        biplot = bp,
        rank = rank,
        qrank = Q$rank,
        tot.chi = sum(lambda),
        QR = Q,
        envcentre = envcentre,
        Xbar = Y)
    ## residual of Y
    Y <- qr.resid(Q, Y)
    if (DISTBASED)
        Y <- qr.resid(Q, t(Y))
    ## out
    list(Y = Y, result = result)
}

### THE RESIDUAL METHOD

### Finds the unconstrained ordination after (optionally) removing the
### variation that could be explained by partial and constrained
### models.

`ordResid` <-
    function(Y)
{
    ## get attributes
    DISTBASED <- attr(Y, "METHOD") == "DISTBASED"
    RW <- attr(Y, "RW")
    CW <- attr(Y, "CW")
    ## Ordination
    ZERO <- 1e-5
    if (DISTBASED) {
        sol <- eigen(Y, symmetric = TRUE)
        lambda <- sol$values
        u <- sol$vectors
        v <- NULL
    } else {
        sol <- svd(Y)
        lambda <- sol$d^2
        u <- sol$u
        v <- sol$v
    }
    ## handle zero  eigenvalues ... negative eigenvalues not yet implemented
    zeroev <- abs(lambda) < ZERO * lambda[1]
    if (any(zeroev)) {
        lambda <- lambda[!zeroev]
        u <- u[, !zeroev]
        if (!is.null(v))
            v <- v[, !zeroev]
    }

    ## de-weight
    if (!is.null(RW)) {
        u <- sweep(u, 1, sqrt(RW), "/")
    }
    if (!is.null(CW) && !is.null(v)) {
        v <- sweep(v, 1, sqrt(CW), "/")
    }
    ## out
    out <- list(
        "eig" = lambda,
        "u" = u,
        "v" = v,
        "rank" = length(lambda),
        "tot.chi" = sum(lambda),
        "Xbar" = Y)
    out
}

## The actual function that calls all previous and returns the fitted
## ordination model

`ordConstrained` <-
    function(Y, X = NULL, Z = NULL,
             method = c("cca", "rda", "capscale", "dbrda"),
             scale = FALSE)
{
    method = match.arg(method)
    partial <- constraint <- resid <- NULL
    ## init
    Y <- switch(method,
                "cca" = initCA(Y),
                "rda" = initPCA(Y, scale = scale),
                "capscale" = initPCA(Y, scale = FALSE),
                "dbrda" = initDBRDA(Y))
    ## header info for the model
    head <- ordHead(Y)
    ## Partial
    if (!is.null(Z)) {
        out <- ordPartial(Y, Z)
        Y <- out$Y
        partial <- out$result
    }
    ## Constraints
    if (!is.null(X)) {
        out <- ordConstrain(Y, X, Z)
        Y <- out$Y
        constraint <- out$result
    }
    ## Residuals
    resid <- ordResid(Y)
    ## return a CCA object
    out <- c(head,
             list("pCCA" = partial, "CCA" = constraint, "CA" = resid))
    class(out) <- switch(method,
                         "cca" = "cca",
                         "rda" = c("rda", "cca"),
                         "capscale" = c("capscale", "rda", "cca"),
                         "dbrda" = c("dbrda", "rda", "cca"))
    out
}
