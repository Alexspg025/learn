;
; agglo-rank.scm
;
; Loop over all words, merging them into grammatical categories.
; Agglomerative clustering.
;
; Copyright (c) 2021 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; This file manages the top-most loop for traversing over all words,
; and assigning them to grammatical clusters. This file does not
; provide tools for judging similarity, nor does it provide the
; low-level merge code.  It only manages the top loop.
;
; This is basically the general concept of "agglomerative clustering",
; which is what is (in effect) implemented in this file.
;
; There are other styles of doing agglomerative clustering, implemented
; in `agglo-loops.scm`. They work but are more complicated and don't
; work as well.  (I think they don't work as well, but this has not
; been double-checked experimentally.)
;
; Agglomerative clustering
; ------------------------
; This file implements a form of ranked clustering. It assumes that
; there is a pair-ranking function that will report the next pair to
; be merged together. That pair may be a  pair of words, a word and
; an existing cluster, or a pair of clusters.
;
; This is basic, the `cliques/democratic voting` thing is next, but its
; more complicated, so we do this first.
;
; Assumptions:
; * This assumes that shapes are being used. This is a fundamental
;   requirement for performing connector merges, so we are not going
;   to try to pretend to support anything else.
; * This assumes that support marginals have been computed, and have
;   been loaded into RAM. it will keep support marginals updated, as
;   words are merged.
;
; Notes:
; * make sure WordClassNodes and the MemberLinks are loaded
; ---------------------------------------------------------------------

(use-modules (srfi srfi-1))
(use-modules (opencog) (opencog matrix) (opencog persist))

; Where the simiarity scores will be stored
(define SIM-ID "shape-mi")

; ---------------------------------------------------------------

(define (rank-words LLOBJ)
"
  rank-words LLOBJ -- Return a list of all words, ranked by count.
  If counts are equal, then rank by support. This may take half-a-
  minute to run.  Assumes that supports have been computed and are
  available.
"
	(define sup (add-support-api LLOBJ))

	; nobs == number of observations
	(define (nobs WRD) (sup 'right-count WRD))
	(define (nsup WRD) (sup 'right-support WRD))

	(define wrds (LLOBJ 'left-basis))
	(sort wrds
		(lambda (ATOM-A ATOM-B)
			(define na (nobs ATOM-A))
			(define nb (nobs ATOM-B))
			(if (equal? na nb)
				(> (nsup ATOM-A) (nsup ATOM-B))
				(> na nb))))
)

(define (compute-diag-mi-sims LLOBJ WORDLI START-RANK DEPTH)
"
  compute-diag-mi-sims LLOBJ WORDLI START-RANK DEPTH - compute MI.

  This will compute the MI similarity of words lying around a diagonal.
  The width of the diagonal is DEPTH. The diagonal is defined by the
  the ranked words. Computations start at START-RANK and proceed to
  DEPTH.  If the Similarity has already been recorded, it will not
  be recomputed.

  Think of a tri-diagonal matrix, but instead of three, its N-diagonal
  with N given by DEPTH.

  WORDLI is a list of word, presumed sorted by rank.

  Examples: If START-RANK is 0 and DEPTH is 200, then the 200x200
  block matrix of similarities will be computed. Since similarities
  are symmetric, this is a symmetric matrix, and so 200 x 201 / 2
  grand total similarities are computed.

  If START-RANK is 300 and DEPTH is 200, then computations start at
  the 300'th ranked word. This results in a total of 200x200
  similarities, as 200 rows are computed, out to 200 places away from
  the diagonal.

"
	(define sap (add-similarity-api LLOBJ #f SIM-ID))
	(define smi (add-symmetric-mi-compute LLOBJ))

	(define ol2 (/ 1.0 (log 2.0)))
	(define (log2 x) (if (< 0 x) (* (log x) ol2) -inf.0))

	(define mmt-q (smi 'mmt-q))

	; Compute ans save both the fmi and the ranked-MI.
	; The marginal is sum_d P(w,d)P(*,d) / sum_d P(*,d)P(*,d)
	; The mmt-q is sum_d P(*,d)P(*,d) =
	;              sum_d N(*,d)N(*,d) / [ sum_d N(*,d) ]^2
	(define (compute-sim WA WB)
		(define fmi (smi 'mmt-fmi WA WB))
		(define mwa (smi 'mmt-marginal WA))
		(define mwb (smi 'mmt-marginal WB))
		(define rmi (+ fmi (* 0.5 (log2 (* mwa mwb))) mmt-q))

		; Print something, so user has something to look at.
		(if (< 4 fmi)
			(format #t "\tMI(`~A`, `~A`) = ~6F  rank-MI = ~6F\n"
				(cog-name WA) (cog-name WB) fmi rmi))
		(store-atom
			(sap 'set-pair-similarity
				(sap 'make-pair WA WB)
				(FloatValue fmi rmi))))

	; Perform similarity computations for one row.
	(define (batch-simlist ITEM ITEM-LIST)
		(for-each
			(lambda (item) (compute-sim ITEM item))
			ITEM-LIST))

	; Take the word list and trim it down.
	(define nwords (length WORDLI))
	(define start (min START-RANK nwords))   ; avoid overflow
	(define depth (min DEPTH (- nwords start)))  ; avoid overflow
	(define row-range (take (drop WORDLI start) depth)) ; list of words to do
	(define (col-start off) (max 0 (- (+ start off) depth))) ;  column start
	(define (col-end off) (min (+ start off) depth)) ;  column end
	(define (col-range off)   ; reverse, so we go from diagonal outwards
		(reverse (take (drop WORDLI (col-start off)) (col-end off))))

	(define (do-one-row off)
		(batch-simlist (list-ref row-range off) (col-range (+ 1 off))))

	; Perform the similarity calculations, looping over the fat diagonal.
	(for-each (lambda (n) (do-one-row n)) (iota depth))
)

; ---------------------------------------------------------------

(define (do stuff LLOBJ)
	; Start by getting the ranked words.  Note that this may include
	; WordClass nodes as well as words.
	(define ranked-words (rank-words LLOBJ))

	; Create sims for the initial set.
	(define NRANK 200)
	(compute-diag-mi-sims LLOBJ ranked-words 0 NRANK)

	; General setup of things we need
	(define trp (add-transpose-api LLOBJ))
	(define sap (add-similarity-api LLOBJ #f SIM-ID))
	(define sms (add-pair-stars sap))

	(define logtot-mmt (log2 (trp 'total-mmt-count)))

	; The MI similarity of two words
	(define (mi-sim WA WB)
		(define fmi (sap 'pair-count WA WB))
		(if fmi (cog-value-ref fmi 0) -inf.0))


	; Get all the similarities
	(define all-sim-pairs (sms 'get-all-elts))

	; Get rid of all MI-similarity scores below this cutoff.
	; This is set quite low; a later loop will use a higher cutoff.
	; This cuts down on the total work to be done.
	(define MI-CUTOFF 2.0)

	; Exclude self-similar pairs too.
	(define good-sims
		(filter
			(lambda (SIM)
				(define WA (gar SIM))
				(define WB (gdr SIM))
				(and (< MI-CUTOFF (mi-sim WA WB)) (not (equal? WA WB))))
			all-sim-pairs))

)

; ---------------------------------------------------------------
#! ========
;
; Example usage

(define pca (make-pseudo-cset-api))
(define pcs (add-pair-stars pca))
(define sha (add-covering-sections pcs))
(sha 'fetch-pairs)
(sha 'explode-sections)

; If this hasn't been done, then it needs to be!
(define bat (batch-transpose sha))
(bat 'mmt-marginals)

(define sap (add-similarity-api sha #f "shape-mi"))
(define asm (add-symmetric-mi-compute sha))

==== !#
