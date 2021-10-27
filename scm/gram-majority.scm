;
; gram-majority.scm
;
; Merge N vectors at a time into a new cluster. Merge basis elements by
; majority democratic vote.
;
; Copyright (c) 2021 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; See `gram-classification.scm` and `gram-projective.scm` for an overview.
;
; Given N vectors that have been selected to form a cluster, one can
; determine what basis elements should be a part of that cluster by
; looking to see what all the vectors have in common. If the majority
; of the vectors share a particular basis element, then all of them
; should contribute that element to the cluster.
;
; This is termed "democratic voting" since a majority concept is used,
; and each vector gets one vote. (Future extensions might consider
; proportional votes?) This idea really only works if N>2 as voting
; between two contributors does not make really make sense.
;
; TODO:
; * Reintroduce FRAC for those disjuncts not shared by the majority.
; * Maybe reintroduce NOISE for minimum counts, if this cannot be
;   handled in other ways.
;
; make-merge-majority
; -------------------
; Merge N items into a brand new cluster.  See also `make-merge-pair`
; (not in this file) which merges two items at a time, possibly into
; existing clusters.
;
; ---------------------------------------------------------------------

(use-modules (srfi srfi-1))
(use-modules (opencog) (opencog matrix) (opencog persist))

; ---------------------------------------------------------------------

; TODO: we can very easily re-introduce FRAC here, and thus
; provide compatibility with the older merge methods. Just
; modify `clique` below to do this.
;
; TODO: maybe reintroduce NOISE as well.

(define-public (make-count-majority-shared LLOBJ QUORUM)
"
prototype
"
	; WLIST is a list of WordNodes and/or WordClassNodes that are
	; being proposed for merger. This will count how many disjuncts
	; these share in common.
	(define (count WLIST)

		; The minimum number of sections that must exist for
		; a given disjunct. For a list of length two, both
		; must share that disjunct (thus giving the traditional
		; overlap merge).
		(define wlen (length WLIST))
		(define vote-thresh
			(if (equal? wlen 2) 2
				(inexact->exact (round (* QUORUM wlen)))))

		; Return #t if the DJ is shared by the majority of the
		; sections. Does the count exceed the threshold?
		(define (vote-to-accept? DJ)
			(<= vote-thresh
				(fold
					(lambda (WRD CNT)
						(if (nil? (LLOBJ 'get-pair WRD DJ)) CNT (+ 1 CNT)))
					0
					WLIST)))

		; Put all of the connector-sets on all of the words int a bag.
		(define set-of-all-djs (make-atom-set))
		(for-each
			(lambda (WRD)
				(for-each
					(lambda (DJ) (set-of-all-djs DJ))
					(LLOBJ 'right-basis WRD)))
			WLIST)

		(define list-of-all-djs (set-of-all-djs #f))

		; Count the particular DJ, if it is shared by the majority.
		(fold
			(lambda (DJ CNT)
				(if (vote-to-accept? DJ) (+ 1 CNT) CNT))
			list-of-all-djs)


	)

	; Return the above function
	count
)

(define-public (make-merge-majority LLOBJ QUORUM MRG-CON)
"
  make-merger-majority LLOBJ QUORUM MRG-CON --
  Return a function that will merge a list of words into one class.
  The disjuncts that are selected to be merged are those shared by
  the majority of the given words, where `majority` is defined as
  a fraction that is greater or equal to QUORUM.

  LLOBJ is the object holding the disjuncts. For example, it could
  be (add-dynamic-stars (make-pseudo-cset-api))

  QUORUM is a floating point number indicating the fraction of
  sections that must share a given disjunct, before that disjunct is
  merged into the cluster.

  MRG-CON is #t if Connectors should also be merged.  This requires
  that the LLOBJ object have shapes on it.
"
	; WLIST is a list of WordNodes and/or WordClassNodes that will be
	; merged into one WordClass.
	; Return a WordClassNode that is the result of the merge.
	(define (merge WLIST)
		(for-each
			(lambda (WRD)
				(if (equal? (cog-type WRD) 'WordClassNode)
					(throw 'not-implemented 'make-merge-majority
						"Not done yet")))
			WLIST)

		; The minimum number of sections that must exist for
		; a given disjunct. For a list of length two, both
		; must share that disjunct (thus giving the traditional
		; overlap merge).
		(define wlen (length WLIST))
		(define vote-thresh
			(if (equal? wlen 2) 2
				(inexact->exact (round (* QUORUM wlen)))))

		; Return #t if the DJ is shared by the majority of the
		; sections. Does the count exceed the threshold?
		(define (vote-to-accept? DJ)
			(<= vote-thresh
				(fold
					(lambda (WRD CNT)
						(if (nil? (LLOBJ 'get-pair WRD DJ)) CNT (+ 1 CNT)))
					0
					WLIST)))

		; Merge the particular DJ, if it is shared by the majority.
		; CLUST is identical to cls, defined below. Return zero if
		; there is no merge.
		(define (clique LLOBJ CLUST SECT ACC-FUN)
			(define DJ (LLOBJ 'right-element SECT))

			(if (vote-to-accept? DJ)
				(ACC-FUN LLOBJ (LLOBJ 'make-pair CLUST DJ) SECT 1.0)
				0))

		; We are going to control the name we give it. We could also
		; delegate this to `add-gram-class-api`, but for now, we're
		; going to punt and do it here. Some day, in a generic framework,
		; this will need to be cleaned up.
		(define cls-name (string-join (map cog-name WLIST)))
		(define cls-type (LLOBJ 'cluster-type))
		(define cls-typname
			(if (cog-atom? cls-type) (cog-name cls-type) cls-type))
		(define cls (cog-new-node cls-typname cls-name))

		(for-each
			(lambda (WRD) (assign-to-cluster LLOBJ cls WRD clique))
			WLIST)

		(when MRG-CON
			(for-each
				(lambda (WRD) (merge-connectors LLOBJ cls WRD clique))
				WLIST)
		)

		; Cleanup after merging.
		; The LLOBJ is assumed to be just a stars object, and so the
		; intent of this clobber is to force it to recompute it's left
		; and right basis.
		(define e (make-elapsed-secs))
		(LLOBJ 'clobber)
		(for-each
			(lambda (WRD) (remove-empty-sections LLOBJ WRD))
			WLIST)
		(remove-empty-sections LLOBJ cls)

		; Clobber the left and right caches; the cog-delete! changed things.
		(LLOBJ 'clobber)

		(format #t "------ merge-majority: Cleanup `~A` in ~A secs\n"
			(cog-name cls) (e))

		cls
	)

	; Return the above function
	merge
)

; ---------------------------------------------------------------
; Example usage  (none)
