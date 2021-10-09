;
; gram-projective.scm
;
; Merge words into word-classes by grammatical similarity.
; Projective merge strategies.
;
; Copyright (c) 2017, 2018, 2019, 2021 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; See `gram-classification.scm` for an overview.
;
; This file implements the orthogonal/union/overlap type merging
; described in `gram-classification.scm`. See the `gram-optim.scm` file
; for the entropy-maximizing merge implementation.
;
; Although the code keeps talking about words and word-classes, it is
; (almost) entirely generic, and can merge (cluster) anything. The only
; place(s) where its not generic is in some progress-report printing,
; and in the general discussion of what this code does. Otherwise, what
; to merge, and where to put the merger results are defined by LLOBJ.
;
; TODO: This code implements the "projection merge" strategy, but the
; latest results indicate that this does not improve quality all that
; much, if at all. So the latest merge style `comi` just disables
; the projection merge by setting the union-frac to zero.  Thus, the
; code in this file could be simplified by ripping out all the
; union-merge stuff.  Anyway, the democratic-vote idea will require
; explicit lists of disjuncts to merge, so this needs a rewrite, anyway.
;
; XXX Unless we decide to union-in anything below the noise-threshold
; cutoff, in which case we want to continue doing unions, just to handle
; this particular case.
;
; Orthogonal merging
; ------------------
; In this merge strategy, `w` is decomposed into `s` and `t` by
; orthogonal decomposition, up to a clamping constraint, so as to keep
; all counts non-negative. That is, start by taking `s` as the component
; of `w` that is parallel to `g`, and `t` as the orthogonal complement.
; In general, this will result in `t` having negative components; this
; is clearly not allowed in a probability space. Thus, those counts are
; clamped to zero, and the excess is transferred back to `s` so that the
; total `w = s + t` is preserved.
;
; Note the following properties of this algo:
; a) The combined vector `g_new` has exactly the same support as `g_old`.
;    That is, any disjuncts in `w` that are not in `g_old` are already
;    orthogonal. This may be undesirable, as it prevents the broadening
;    of the support of `g`, i.e. the learning of new, but compatible
;    grammatical usage. See discussion of "broadening" below.
;
; b) The process is not quite linear, as the final `s` is not actually
;    parallel to `g_old`.
;
;
; Union merging
; -------------
; Here, one decomposes `w` into components that are parallel and
; perpendicular to `g + w`, instead of `g` as above.  Otherwise, one
; proceeds as above.
;
; Note that the support of `g + w` is the union of the support of `g`
; and of `w`, whence the name.  This appears to provide a simple
; solution to the broadening problem, mentioned above.  Conversely, by
; taking the union of support, the new support may contain elements
; from `w` that belong to other word-senses, and do NOT belong to `g`
; (do not belong to the word sense associate with `g`).
;
; Initial cluster formation
; -------------------------
; The above described what to do to extend an existing grammatical class
; with a new candidate word.  It does not describe how to form the
; initial grammatical class, out of the merger of two words. Several
; strategies are possible. Given two words `u` and `v`, These are:
;
; * Simple sum: let `g=u+v`. That's it; nothing more.
; * Overlap and union merge, given below.
;
; Overlap merge
; -------------
; A formal (i.e. mathematically dense) description of overlap merging is
; given here. One wishes to compute the intersection of basis elements
; (the intersection of "disjuncts" aka "sections") of the two words, and
; then sum the counts only on this intersected set. Let
;
;   {e_a} = set of basis elements in v_a with non-zero coefficients
;   {e_b} = set of basis elements in v_b with non-zero coefficients
;   {e_overlap} = {e_a} set-intersection {e_b}
;   pi_overlap = unit on diagonal for each e in {e_overlap}
;              == projection matrix onto the subspace {e_overlap}
;   v_a^pi = pi_overlap . v_a == projection of v_a onto {e_overlap}
;   v_b^pi = pi_overlap . v_b == projection of v_b onto {e_overlap}
;
;   v_cluster = v_a^pi + v_b^pi
;   v_a^new = v_a - v_a^pi
;   v_b^new = v_b - v_b^pi
;
; The idea here is that the vector subspace {e_overlap} consists of
; those grammatical usages that are common for both words a and b,
; and thus hopefully correspond to how words a and b are used in a
; common sense. Thus v_cluster is the common word-sense, while v_a^new
; and v_b^new are everything else, everything left-over.  Note that
; v_a^new and v_b^new are orthogonal to v_cluster. Note that v_a^new
; and v_b^new are both exactly zero on {e_overlap} -- the subtraction
; wipes out those coefficients. Note that the total number of counts
; is preserved.  That is,
;
;   ||v_a|| + ||v_b|| = ||v_cluster|| + ||v_a^new|| + ||v_b^new||
;
; where ||v|| == ||v||_1 the l_1 norm aka count aka Manhattan-distance.
;
; If v_a and v_b have several word-senses in common, then so will
; v_cluster.  Since there is no a priori way to force v_a and v_b to
; encode only one common word sense, there needs to be some distinct
; mechanism to split v_cluster into multiple word senses, if that is
; needed.
;
; Union merging can be described using almost the same formulas, except
; that one takes
;
;   {e_union} = {e_a} set-union {e_b}
;
; merge-project
; -------------
; The above merge methods are implemented in the `merge-project`
; function. It takes, as an argument, a fractional weight which is
; used when the disjunct isn't shared between both words. Setting
; the weight to zero gives overlap merging; setting it to one gives
; union merging. Setting it to fractional values provides a merge
; that is intermediate between the two: an overlap, plus a bit more,
; viz some of the union.  A second parameter serves as a cutoff, so
; that any observation counts below the cutoff are always merged.
;
; That is, the merger is given by the vector
;
;   v_merged = v_overlap + FRAC * (v_union - v_overlap)
;
; for those vector components in v_union that have been observed more
; than the minimum cutoff; else all of the small v_union components
; are merged.
;
; If v_a and v_b are both words, then the counts on v_a and v_b are
; adjusted to remove the counts that were added into v_merged. If one
; of the two is already a word-class, then the counts are simply moved
; from the word to the class.
;
; merge-discrim
; -------------
; Built on the merge-project method, the FRAC is a sigmoid function,
; ranging from 0.0 to 1.0, depending on the cosine between the vectors.
; The idea is that, if two words are already extremely similar, we may
; as well assume they really are in the same class, and so do a union
; merge. But if the words are only kind-of similar, but not a lot, then
; assume that the are both linear combinations of several word senses,
; and do only the minimal overlap merge, so as to avoid damaging the
; other senses.
;
; A reasonable strategy would seem to bee to take
;
;   FRAC = (cos - cos_min) / (1.0 - cos_min)
;
; where `cos_min` is the minimum cosine acceptable, for any kind of
; merging to be performed.
; Implemented in the `make-discrim` call.
;
; merge-disinfo
; -------------
; Like `merge-discrim` but using mutual information instead of cosines.
; Implemented in the `make-disinfo` call.
;
; start-cluster, merge-into-cluster
; ---------------------------------
; Implementation of the common parts of the above merge styles,
; using callbacks and parameters to obtain the merge fraction.
; Calls `accumulate-count` to do the column-by-column summing.
;
; make-merger
; -----------
; High-level wrapper for above. Provides a generic API.
;
; Parameter choices
; -----------------
; Gut-sense intuition suggests that `merge-mifuzz` with a min acceptable
; MI of about 5 works best. The union fraction should be set to zero.
;
; Earlier work is summarized in `grammar-report/grammar-report.pdf`.
; Pretty much everything there used a union-merge fraction of 0.3,
; which, in reprospect, may have been much too large. Certainly,
; if the goal is to maximize entropy, then any value greater than zero
; will fail to do that.  Thus, the only reason to usae a union fraction
; greater than zero is if one suspects one is trapped in a local
; maximum, and needs to hop out.  Practical experience shows that this
; can be a bit risky, and easily corrupts clustering.
;
; TODO
; ----
; It might be useful to move the management of the MemberLink's to
; the `add-gram-class-api` object.
;
; ---------------------------------------------------------------------

(use-modules (srfi srfi-1))
(use-modules (opencog) (opencog matrix) (opencog persist))

; ---------------------------------------------------------------------
; Return #t if the count is effectively zero.
; Use an epsilon for rounding errors.
(define (is-zero? cnt) (< cnt 1.0e-10))

(define (accumulate-count LLOBJ ACC PAIR FRAC NOISE)
"
  accumulate-count LLOBJ ACC PAIR FRAC NOISE -- Accumulate count
    from PAIR into ACC.

  ACC and PAIR should be two pairs in the matrix LLOBJ. (Usually,
  they will be in the same row or column, although this code does not
  assume this.)

  The count on PAIR will be transfered to ACC, with some caveats:
  If the count on ACC is non-zero, then *all* of the count on PAIR
  will be transfered (and PAIR will be removed from the database).

  If the count on ACC is zero, and the count on PAIR is greater than
  NOISE (floating-point noise-floor), then only a FRAC of the count
  will get transfered to ACC. If the count is below the noise floor,
  then all of it will be transfered over.

  Both Atoms, with updated counts, are stored to the database.

  The prototypical use-case has ACC and PAIR being two Sections
  of (word, disjunct) pairs, having the same disjunct but two different
  words. The goal is to merge the two words together into a single
  word-class.
"

	; The counts on the accumulator and the pair to merge.
	(define mcnt (LLOBJ 'get-count PAIR))
	(define acnt (LLOBJ 'get-count ACC))

	; If the accumulator count is zero, transfer only a FRAC of
	; the count into the accumulator.
	(define taper-cnt (if
			(and (is-zero? acnt) (< NOISE mcnt))
			(* FRAC mcnt) mcnt))

	; Update the count on the donor pair.
	; If the count is zero or less, delete the donor pair.
	; (Actually, it should never be less than zero!)
	(define (update-donor-count SECT CNT)
		(set-count SECT CNT)
		(unless (is-zero? CNT) (store-atom SECT)))

	; If there is nothing to transfer over, do nothing.
	(if (not (is-zero? taper-cnt))
		(begin

			; The accumulated count
			(set-count ACC (+ acnt taper-cnt))
			(store-atom ACC) ; save to the database.

			; Decrement the equivalent amount from the donor pair.
			(update-donor-count PAIR (- mcnt taper-cnt))
		))

	; Return how much was transfered over.
	taper-cnt
)

; ---------------------------------------------------------------------

(define-public (start-cluster LLOBJ CLS WA WB FRAC-FN NOISE MRG-CON)
"
  start-cluster LLOBJ CLS WA WB FRAC-FN NOISE MRG-CON --
     Start a new cluster by merging rows WA and WB of LLOBJ into a
     combined row CLS.

  In the prototypical use case, each row corresponds to a WordNode,
  and the result of summing them results in a WordClassNode. Thus,
  by convention, it is assumed that the pairs are (word, disjunct)
  pairs, and LLOBJ was made by `make-pseudo-cset-api` or by
  `add-shape-vec-api`. The code itself is generic, and might work on
  other kinds of LLOBJ's too. (It might work, but has not been tested.)

  LLOBJ is used to access pairs.
  WA and WB should both be of `(LLOBJ 'left-type)`. They should
     designate two different rows in LLOBJ that will be merged,
     column-by-column.
  CLS denotes a new row in LLOBJ, that will contain the merged counts.
     MemberLinks will be created from WA and WB to CLS.
  FRAC-FN should be a function taking WA and WB as arguments, and
     returning a floating point number between zero and one, indicating
     the fraction of a non-shared count to be used.
     Returning 1.0 gives the sum of the union of supports;
     Returning 0.0 gives the sum of the intersection of supports.
  NOISE is the smallest observation count, below which counts will
     not be divided up, when the merge is performed. (All of the
     count will be merged, when it is less than NOISE)
  MRG-CON boolean flag; if #t then connectors will be merged.

  The merger of rows WA and WB are performed, using the 'projection
  merge' strategy described above. To recap, this is done as follows.
  If counts on a given column of both WA and WB are non-zero, they are
  summed, and the total is placed on the matching column of CLS. The
  contributing columns are removed (as thier count is now zero).
  If one is zero, and the other is not, then only a FRAC of the count
  is transfered.

  Accumulated row totals are stored in the two MemberLinks that attach
  WA and WB to CLS.

  This assumes that storage is connected; the updated counts are written
  to storage.
"
	; set-count ATOM CNT - Set the raw observational count on ATOM.
	; XXX FIXME there should be a set-count on the LLOBJ...
	; Strange but true, there is no setter, currently!
	(define (set-count ATOM CNT) (cog-set-tv! ATOM (CountTruthValue 1 0 CNT)))

	; Fraction of non-overlapping disjuncts to merge
	(define frac-to-merge (FRAC-FN WA WB))

	(define monitor-rate (make-rate-monitor))

	; Perform a loop over all the disjuncts on WA and WB.
	; Call ACCUM-FUN on these, as they are found.
	(define (loop-over-disjuncts ACCUM-FUN)
		; Use the tuple-math object to provide a pair of rows that
		; are aligned with one-another.
		(define (bogus a b) (format #t "Its ~A and ~A\n" a b))
		(define ptu (add-tuple-math LLOBJ bogus))

		; Loop over the sections above, merging them into one cluster.
		(for-each
			(lambda (PRL)
				(define PAIR-A (first PRL))
				(define PAIR-B (second PRL))

				(define null-a (null? PAIR-A))
				(define null-b (null? PAIR-B))

				; The target into which to accumulate counts. This is
				; an entry in the same column that PAIR-A and PAIR-B
				; are in. (TODO maybe we could check that both PAIR-A
				; and PAIR-B really are in the same column. They should be.)
				(define col (if null-a
						(LLOBJ 'right-element PAIR-B)
						(LLOBJ 'right-element PAIR-A)))

				; The place where the merge counts should be written
				(define mrg (LLOBJ 'make-pair CLS col))

				; Now perform the merge. Overlapping entries are
				; completely merged (frac=1.0). Non-overlapping ones
				; contribute only FRAC.
				(cond
					(null-a (ACCUM-FUN mrg WB PAIR-B frac-to-merge))
					(null-b (ACCUM-FUN mrg WA PAIR-A frac-to-merge))
					(else ; AKA (not (or null-a null-b))
						(begin
							(ACCUM-FUN mrg WA PAIR-A 1.0)
							(ACCUM-FUN mrg WB PAIR-B 1.0))))

				(monitor-rate #f)
			)
			; A list of pairs of sections to merge.
			; This is a list of pairs of columns from LLOBJ, where either
			; one or the other or both rows have non-zero elements in them.
			(ptu 'right-stars (list WA WB)))
	)

	; Accumulated counts for the two MemberLinks.
	(define accum-acnt 0)
	(define accum-bcnt 0)

	; Accumulate counts from the individual words onto the cluster.
	(define (accum-counts MRG W PR WEI)
		(define cnt	(accumulate-count LLOBJ MRG PR WEI NOISE))
		(if (equal? W WA)
			(set! accum-acnt (+ accum-acnt cnt))
			(set! accum-bcnt (+ accum-bcnt cnt))))

	(loop-over-disjuncts accum-counts)

	(monitor-rate
		"------ Create: Merged ~A sections in ~5F secs; ~6F scts/sec\n")

	; Create MemberLinks. Do this before the connector-merge step,
	; as they are examined during that phase.
	(define memb-a (MemberLink WA CLS))
	(define memb-b (MemberLink WB CLS))

	; Track the number of observations moved from the two items
	; into the combined class. This tracks the individual
	; contributions.
	(set-count memb-a accum-acnt)
	(set-count memb-b accum-bcnt)

	; If merging connectors, then make a second pass. We can't do this
	; in the first pass, because the connector-merge logic needs to
	; manipulate the merged Sections. (There's no obvious way to do
	; this in a single pass; I tried.)
	(define (reshape-crosses MRG W PR WEI)
		(reshape-merge LLOBJ CLS MRG W PR WEI NOISE))
	(when MRG-CON
		(set! monitor-rate (make-rate-monitor))
		(loop-over-disjuncts reshape-crosses)
		(monitor-rate
			"------ Create: Revised ~A shapes in ~5F secs; ~6F scts/sec\n")
	)

	(set! monitor-rate (make-rate-monitor))
	(monitor-rate #f)

	; Store the counts on the MemberLinks.
	(store-atom memb-a)
	(store-atom memb-b)

	; Cleanup after merging.
	; The LLOBJ is assumed to be just a stars object, and so the
	; intent of this clobber is to force it to recompute it's left
	; and right basis.
	(LLOBJ 'clobber)
	(remove-empty-sections LLOBJ WA)
	(remove-empty-sections LLOBJ WB)
	(remove-empty-sections LLOBJ CLS)

	; Clobber the left and right caches; the cog-delete! changed things.
	(LLOBJ 'clobber)

	(monitor-rate
		"------ Create: cleanup ~A in ~5F secs; ~6F ops/sec\n")
)

; ---------------------------------------------------------------------

(define-public (merge-into-cluster LLOBJ CLS WA FRAC-FN NOISE MRG-CON)
"
  merge-into-cluster LLOBJ CLS WA FRAC-FN NOISE MRG-CON --
     Merge WA into cluster CLS. These are two rows in LLOBJ,
     the merge is done column-by-column. A MemberLink from
     WA to CLS will be created.

  See start-cluster for additional details.

  LLOBJ is used to access pairs.
  WA should be of `(LLOBJ 'left-type)`
  CLS should be interpretable as a row in LLOBJ.

  FRAC-FN should be a function taking CLS and WA as arguments, and
     returning a floating point number between zero and one, indicating
     the fraction of a non-shared count to be used.
     Returning 1.0 gives the sum of the union of supports;
     Returning 0.0 gives the sum of the intersection of supports.
  NOISE is the smallest observation count, below which counts will
     not be divided up, when the merge is performed. (All of the
     count will be merged, when it is less than NOISE)
  MRG-CON boolean flag; if #t then connectors will be merged.

  The merger of row WA into CLS is performed, using the 'projection
  merge' strategy described above. To recap, this is done as follows.
  If counts on a given column of both CLS and WA are non-zero, then
  all of the count from WA is transfered to CLS. That column in WA
  is removed (as it's count is now zero). If the count on CLS is zero,
  then only a FRAC of WA's count is transfered.

  Accumulated row totals are stored in the MemberLink that attaches
  WA to CLS.

  This assumes that storage is connected; the updated counts are written
  to storage.
"
	; set-count ATOM CNT - Set the raw observational count on ATOM.
	; XXX FIXME there should be a set-count on the LLOBJ...
	; Strange but true, there is no setter, currently!
	(define (set-count ATOM CNT) (cog-set-tv! ATOM (CountTruthValue 1 0 CNT)))

	; Fraction of non-overlapping disjuncts to merge
	(define frac-to-merge (FRAC-FN CLS WA))

	; Caution: there's a "feature" bug in projection merging when used
	; with connector merging. The code below will create sections with
	; dangling connectors that may be unwanted. Easiest to explain by
	; example. Consider a section (f, abe) being merged into a cluster
	; {e,j} to form a cluster {e,j,f}. The code below will create a
	; section ({ej}, abe) as the C-section, and transfer some counts
	; to it. But, when connector merging is desired, it should have gone
	; to ({ej}, ab{ej}). There are two possible solutions: have the
	; connector merging try to detect this, and clean it up, or have
	; the tuple object pair up (f, abe) to ({ej}, ab{ej}). There is no
	; "natural" way for the tuple object to create this pairing (it is
	; "naturally" linear, by design) so we must clean up during connector
	; merging.
	(define (loop-over-disjuncts ACCUM-FUN)
		(for-each
			(lambda (PAIR-A)
				(define DJ (LLOBJ 'right-element PAIR-A))
				(define PAIR-C (LLOBJ 'get-pair CLS DJ))

				; Two different tasks, depending on whether PAIR-C
				; exists or not - we merge all, or just some.
				(if (nil? PAIR-C)

					; Accumulate just a fraction into the new column.
					(ACCUM-FUN (LLOBJ 'make-pair CLS DJ) PAIR-A frac-to-merge)

					; PAIR-C exists already. Merge 100% of A into it.
					(ACCUM-FUN PAIR-C PAIR-A 1.0))
			)
			(LLOBJ 'right-stars WA))
	)

	(define monitor-rate (make-rate-monitor))

	; Accumulated count on the MemberLink.
	(define accum-cnt 0)

	; Accumulate counts from PAIR-A onto PAIR-C
	(define (accum-sections PAIR-C PAIR-A WEI)
		(monitor-rate #f)
		(set! accum-cnt (+ accum-cnt
			(accumulate-count LLOBJ PAIR-C PAIR-A WEI NOISE))))

	(loop-over-disjuncts accum-sections)

	; Create MemberLinks. Do this before the connector-merge step,
	; as they are examined during that phase.
	(define memb-a (MemberLink WA CLS))
	(set-count memb-a accum-cnt)

	(monitor-rate
		"------ Extend: Merged ~A sections in ~5F secs; ~6F scts/sec\n")

	; Perform the connector merge.
	(define (reshape-crosses PAIR-C PAIR-A WEI)
		(monitor-rate #f)
		(reshape-merge LLOBJ CLS PAIR-C WA PAIR-A WEI NOISE))
	(when MRG-CON
		(set! monitor-rate (make-rate-monitor))
		(loop-over-disjuncts reshape-crosses)
		(monitor-rate
			"------ Extend: Revised ~A shapes in ~5F secs; ~6F scts/sec\n")
	)

	(set! monitor-rate (make-rate-monitor))
	(monitor-rate #f)

	; Track the number of observations moved from WA to the class.
	; Store the updated count.
	(store-atom memb-a)

	; Cleanup after merging.
	; The LLOBJ is assumed to be just a stars object, and so the
	; intent of this clobber is to force it to recompute it's left
	; and right basis.
	(LLOBJ 'clobber)
	(remove-empty-sections LLOBJ WA)
	(remove-empty-sections LLOBJ CLS)

	; Clobber the left and right caches; the cog-delete! changed things.
	(LLOBJ 'clobber)

	(monitor-rate
		"------ Extend: Cleanup ~A in ~5F secs; ~6F ops/sec\n")
)

; ---------------------------------------------------------------------

(define-public (merge-clusters LLOBJ CLA CLB NOISE MRG-CON)
"
  merge-clusters LLOBJ CLA CLB FRAC-FN NOISE MRG-CON --
     Merge clusters CLA and CLB. These are two rows in LLOBJ,
     the merge is done column-by-column.

  This will perform a \"union merge\" -- all disjuncts on CLB will
  be transfered to CLA, and CLB will be removed.

  See start-cluster for additional details.
"
	; set-count ATOM CNT - Set the raw observational count on ATOM.
	; XXX FIXME there should be a set-count on the LLOBJ...
	; Strange but true, there is no setter, currently!
	(define (set-count ATOM CNT) (cog-set-tv! ATOM (CountTruthValue 1 0 CNT)))

	(define monitor-rate (make-rate-monitor))

	(define (loop-over-disjuncts ACCUM-FUN)
		(for-each
			(lambda (PAIR-B)

				; The disjunct on PAIR-B
				(define DJ (LLOBJ 'right-element PAIR-B))

				; The place where the merge counts should be written
				(define mrg (LLOBJ 'make-pair CLA DJ))

				; Now perform the merge.
				(ACCUM-FUN mrg PAIR-B)

				(monitor-rate #f)
			)
			(LLOBJ 'right-stars CLB))
	)

	(define (accum-counts MRG PAIR)
		(accumulate-count LLOBJ MRG PAIR 1.0 NOISE))

	; Run the main merge loop
	(loop-over-disjuncts accum-counts)

	; Copy all counts from MemberLinks on CLB to CLA.
	; Delete MemberLinks on CLB.
	(for-each
		(lambda (MEMB-B)
			; Get the word
			(define WRD (gar MEMB-B))

			; Get the count
			(define CNT-A 0)
			(define CNT-B (LLOBJ 'get-count MEMB-B))

			; Does a corresponding word exist on class A?
			(define MEMB-A (cog-link 'MemberLink WRD CLA))

			(if (not (nil? MEMB-A))
				(set! CNT-A (LLOBJ 'get-count MEMB-A)))

			; Create the MmeberLink on A, and update the count.
			(define MBA (MemberLink WRD CLA))
			(set-count MBA (+ CNT-A CNT-B))
			(store-atom MBA)

			; Delete the B-MemberLink.  If its not deleteable,
			; then wipe out the count on it.
			(if (not (cog-delete! MEMB-B))
				(set-count MEMB-B 0))
		)
		(cog-incoming-by-type CLB 'MemberLink))

	(monitor-rate
		"------ Combine: Merged ~A sections in ~5F secs; ~6F scts/sec\n")

	; If merging connectors, then make a second pass.
	(define (merge-crosses MRG PAIR)
		(reshape-merge LLOBJ CLA MRG CLB PAIR 1.0 NOISE))

	(when MRG-CON
		(set! monitor-rate (make-rate-monitor))
		; Run the main merge loop and merge the connnectors
		(loop-over-disjuncts merge-crosses)
		(monitor-rate
			"------ Combine: Revised ~A shapes in ~5F secs; ~6F scts/sec\n")
	)

	(set! monitor-rate (make-rate-monitor))
	(monitor-rate #f)

	; Cleanup after merging.
	; The LLOBJ is assumed to be just a stars object, and so the
	; intent of this clobber is to force it to recompute it's left
	; and right basis.
	(LLOBJ 'clobber)
	(remove-empty-sections LLOBJ CLA)
	(remove-empty-sections LLOBJ CLB) ; This should remove ALL of them!

	; Clobber the left and right caches; the cog-delete! changed things.
	(LLOBJ 'clobber)

	; Delete the old class... But first, let's make sure it is
	; really is empty!  It should not appear in any sections or
	; cross-sections!  It might appear in Connectors that are in
	; ConnectorSeqs that are in marginals, and we cannot control
	; that. XXX FIXME These need to be cleaned up!
	; So check the types we can control.
	(if (or
			(not (equal? 0 (cog-incoming-size-by-type CLB 'Section)))
			(not (equal? 0 (cog-incoming-size-by-type CLB 'CrossSection)))
			(not (equal? 0 (cog-incoming-size-by-type CLB 'Shape))))
		(throw 'non-empy-class 'merge-clusters "we expect it to be empty!"))

	(cog-delete! CLB)

	(monitor-rate
		"------ Combine: cleanup ~A in ~5F secs; ~6F ops/sec\n")
)

; ---------------------------------------------------------------
; Is it OK to merge WORD-A and WORD-B into a common vector?
;
; Return #t if the two should be merged, else return #f
; WORD-A might be a WordClassNode or a WordNode.
; WORD-B should be a WordNode.
;
; SIM-FUNC must be a function that takes two words (or word-classes)
; and returns the similarity between them.
;
; The CUTOFF is used to make the ok-to-merge decision; if the similarity
; is greater than CUTOFF, then this returns #t else it returns #f.
;
; The is effectively the same as saying
;    (< CUTOFF (SIM-FUNC WORD-A WORD-B))
; which is only a single trivial line of code ... but ...
; The below is a mass of print statements to show forward progress.
; The current infrastructure is sufficiently slow, that the prints are
; reassuring that the system is not hung.
;
(define (is-similar? SIM-FUNC CUTOFF WORD-A WORD-B)

	(define (report-progress)
		(let* (
				(start-time (get-internal-real-time))
				(sim (SIM-FUNC WORD-A WORD-B))
				(now (get-internal-real-time))
				(elapsed-time (* 1.0e-9 (- now start-time))))

			; Only print if its time-consuming.
			(if (< 2.0 elapsed-time)
				(format #t "Dist=~6F for ~A \"~A\" -- \"~A\" in ~5F secs\n"
					sim
					(if (eq? 'WordNode (cog-type WORD-A)) "word" "class")
					(cog-name WORD-A) (cog-name WORD-B)
					elapsed-time))

			; Print mergers.
			(if (< CUTOFF sim)
				(format #t "---------Bingo! Dist=~6F for ~A \"~A\" -- \"~A\"\n"
					sim
					(if (eq? 'WordNode (cog-type WORD-A)) "word" "class")
					(cog-name WORD-A) (cog-name WORD-B)
					))
			sim))

	; True, if similarity is larger than the cutoff.
	(< CUTOFF (report-progress))
)

; ---------------------------------------------------------------

(define (recompute-support LLOBJ WRD)
"
  recompute-support LLOBJ WRD - Recompute support marginals for WRD

  This recomputes the marginals for support and counts, which is
  what coine distance and Jaccard overlap need to do thier stuff.
  It is NOT enough for MI/MMT calculations!
"
	(define psu (add-support-compute LLOBJ))
	(store-atom (psu 'set-right-marginals WRD))
)

(define (recompute-mmt LLOBJ WRD)
"
  recompute-mmt LLOBJ WRD - Recompute MMT marginals for WRD

  This recomputes the marginals for support and counts for both
  the word and the disjuncts on that word. In particular, this
  recompute N(*,d) which is needed by MM^T.
"
	(define psu (add-support-compute LLOBJ))
	(define atc (add-transpose-compute LLOBJ))

	; This for-each loop accounts for 98% of the CPU time in typical cases.
	; 'right-duals returns both ConnectorSeqs and Shapes.
	(for-each
		(lambda (DJ) (store-atom (psu 'set-left-marginals DJ)))
		(LLOBJ 'right-duals WRD))
	(store-atom (psu 'set-right-marginals WRD))
	(store-atom (atc 'set-mmt-marginals WRD))
)

(define (recompute-mmt-final LLOBJ)
"
  recompute-mmt-final LLOBJ -- recompute grand totals for the MM^T case
"
	(define asc (add-support-compute LLOBJ))
	(define atc (add-transpose-compute LLOBJ))

	; Computing the 'set-left-totals takes about 97% of the total
	; time in this function, and about 8% of the grand-total time
	; (of merging words). Yet I suspect that it is not needed...
	(store-atom (asc 'set-left-totals))   ;; is this needed? Its slow.
	(store-atom (asc 'set-right-totals))  ;; is this needed?
	(store-atom (atc 'set-mmt-totals))
)

; ---------------------------------------------------------------

(define-public (make-merger STARS MPRED FRAC-FN NOISE MIN-CNT STORE FIN MRG-CON)
"
  make-merger STARS MPRED FRAC-FN NOISE MIN-CNT STORE FIN MRG-CON --
  Return object that implements the `merge-project` merge style
  (as described at the top of this file).

  STARS is the object holding the disjuncts. For example, it could
  be (add-dynamic-stars (make-pseudo-cset-api))

  MPRED is a predicate that takes two rows in STARS (two Atoms that are
  left-elements, i.e. row-indicators, in STARS) and returns #t/#f i.e.
  a yes/no value as to whether the corresponding rows in STARS should
  be merged or not.

  FRAC-FUN is a function that takes two rows in STARS and returns a
  number between 0.0 and 1.0 indicating what fraction of a row to merge,
  when the corresponding matrix element in the other row is null.

  NOISE is the smallest observation count, below which counts
  will not be divided up, if a merge is performed.

  MIN-CNT is the minimum count (l1-norm) of the observations of
  disjuncts that a row is allowed to have, to even be considered for
  merging.

  STORE is an extra function called, after the merge is to completed,
  and may be used to compute and store additional needed data that
  the algo here is unaware of. This include computation of supports,
  marginal MI and similar. It is called with an argument of the altered
  row.

  FIN is an extra function called, after the merge is to completed.
  It is called without an argument.

  MRG-CON is #t if Connectors should also be merged.  This requires
  that the STARS object have shapes on it.

  This object provides the following methods:

  'merge-predicate -- a wrapper around MPRED above.
  'merge-function -- the function that actually performs the merge.
  'discard-margin? -- Return #t if count on word is below MIN-CNT.
                      Uses the marginal counts for this decision.
                      Used by `trim-and-rank` to ignore this word.
                      (`trim-and-rank` prepares the list of words to
                      cluster.)
  'discard? --        Same as above, but  count is recomputed, instead
                      of being pulled from the margin. This is required
                      when a word has been merged, as then the margin
                      count will be stale (aka wrong, invalid). Used
                      by `greedy-grow` to ignore the stub of a word
                      after merging. That is, if all that remains in a
                      word after merging is some cruft with a count less
                      than MIN-CNT, it won't be further merged into
                      anything; it will be ignored.
"
	(define pss (add-support-api STARS))
	(define psu (add-support-compute STARS))

	; Return a WordClassNode that is the result of the merge.
	(define (merge WA WB)
		(define wa-is-cls (equal? (STARS 'cluster-type) (Type (cog-type WA))))
		(define wb-is-cls (equal? (STARS 'cluster-type) (Type (cog-type WB))))
		(define cls (STARS 'make-cluster WA WB))

		; Cluster - either create a new cluster, or add to an existing
		; one. Afterwards, need to recompute selected marginals. This
		; is required so that future similarity judgements work correctly.
		; The mergers altered the counts, and so the marginals on
		; those words and disjuncts are wrong. Specifically, they're
		; wrong only for WA, WB and cls. Here, we'll just recompute the
		; most basic support for WA, WB and cls and thier disjuncts.
		; The MI similarity also needs MM^T to be recomputed; the STORE
		; callback provides an opporunity to do that.
		; The results are stored, so that everything is on disk in
		; case of a restart.
		; Clobber first, since Sections were probably deleted.
		(cond
			((and wa-is-cls wb-is-cls)
				(merge-clusters STARS WA WB NOISE MRG-CON))
			((and (not wa-is-cls) (not wb-is-cls))
				(begin
					(start-cluster STARS cls WA WB FRAC-FN NOISE MRG-CON)
					(STORE cls)))
			(wa-is-cls
				(merge-into-cluster STARS WA WB FRAC-FN NOISE MRG-CON))
			(wb-is-cls
				(merge-into-cluster STARS WB WA FRAC-FN NOISE MRG-CON))
		)

		(STORE WA)
		(STORE WB)
		(FIN)
		cls
	)

	(define (is-small-margin? WORD)
		(< (pss 'right-count WORD) MIN-CNT))

	(define (is-small? WORD)
		(< (psu 'right-count WORD) MIN-CNT))

	; ------------------
	; Methods on this class.

	(lambda (message . args)
		(case message
			((merge-predicate)  (apply MPRED args))
			((merge-function)   (apply merge args))
			((discard-margin?)  (apply is-small-margin? args))
			((discard?)         (apply is-small? args))
			(else               (apply STARS (cons message args)))
		))
)

; ---------------------------------------------------------------

(define-public (make-fuzz STARS CUTOFF UNION-FRAC NOISE MIN-CNT)
"
  make-fuzz -- Return an object that can perform a cosine-distance
               projection-merge, with a fixed union-merge fraction.

  Uses the `merge-project` merge style. This implements a fixed
  linear interpolation between overlap-merge and union merge. Recall
  that the overlap-merge merges all disjuncts that the two parts have
  in common, while the union merge merges all disjuncts.

  Deprecated, because cosine doesn't work well, and the projection
  merge to a non-zero union fraction also gives poor results.

  Caution: this has been hacked to assume shapes (the #t flag is
  passed) and so this is not backwards compat with earlier behavior!

  See `make-merger` for the methods supplied by this object.

  STARS is the object holding the disjuncts. For example, it could
  be (add-dynamic-stars (make-pseudo-cset-api))

  CUTOFF is the min acceptable cosine, for words to be considered
  mergable.

  UNION-FRAC is the fixed fraction of the union-set of the disjuncts
  that will be merged.

  NOISE is the smallest observation count, below which counts
  will not be divided up, if a marge is performed.

  MIN-CNT is the minimum count (l1-norm) of the observations of
  disjuncts that a word is allowed to have, to even be considered.
"
	(define pcos (add-similarity-compute STARS))
	(define (get-cosine wa wb) (pcos 'right-cosine wa wb))
	(define (mpred WORD-A WORD-B)
		(is-similar? get-cosine CUTOFF WORD-A WORD-B))

	(define (fixed-frac WA WB) UNION-FRAC)
	(define (recomp W) (recompute-support STARS W))
	(define (noop) #f)

	(make-merger STARS mpred fixed-frac NOISE MIN-CNT recomp noop #t)
)

; ---------------------------------------------------------------

(define-public (make-discrim STARS CUTOFF NOISE MIN-CNT)
"
  make-discrim -- Return an object that can perform a \"discriminating\"
  merge. When a word is to be merged into a word class, the fraction
  to be merged will depend on the cosine angle between the two.
  Effectively, there is a sigmoid taper between the union-merge and
  the intersection-merge. The more similar they are, the more of a
  union merge; the less similar the more of an intersection merge.

  The idea is that if two words are highly similar, they really should
  be taken together. If they are only kind-of similar, then maybe one
  word has multiple senses, and we only want to merge the fraction that
  shares a common word-sense, and leave the other word-sense out of it.

  Uses the `merge-discrim` merge style; the merge fraction is a sigmoid
  taper.

  Deprecated, because cosine doesn't work well, and the projection
  merge to a non-zero union fraction also gives poor results.

  Caution: this has been hacked to assume shapes (the #t flag is
  passed) and so this is not backwards compat with earlier behavior!

  See `make-merger` for the methods supplied by this object.

  STARS is the object holding the disjuncts. For example, it could
  be (add-dynamic-stars (make-pseudo-cset-api))

  CUTOFF is the min acceptable cosine, for words to be considered
  mergable.

  NOISE is the smallest observation count, below which counts
  will not be divided up, if a merge is performed.

  MIN-CNT is the minimum count (l1-norm) of the observations of
  disjuncts that a word is allowed to have, to even be considered.
"
	(define pcos (add-similarity-compute STARS))
	(define (get-cosine wa wb) (pcos 'right-cosine wa wb))
	(define (mpred WORD-A WORD-B)
		(is-similar? get-cosine CUTOFF WORD-A WORD-B))

	; The fractional amount to merge will be proportional
	; to the cosine between them. The more similar they are,
	; the more they are merged together.
	(define (cos-fraction WA WB)
		(define cosi (pcos 'right-cosine WA WB))
		(/ (- cosi CUTOFF)  (- 1.0 CUTOFF)))

	(define (recomp W) (recompute-support STARS W))
	(define (noop) #f)

	(make-merger STARS mpred cos-fraction NOISE MIN-CNT recomp noop #t)
)

; ---------------------------------------------------------------

(define-public (make-mifuzz STARS CUTOFF UNION-FRAC NOISE MIN-CNT)
"
  make-mifuzz -- Return an object that can perform a mutual-information
                 projection-merge, with a fixed union-merge fraction.

  Uses the `merge-project` merge style. This implements a fixed
  linear interpolation between overlap-merge and union merge. Recall
  that the overlap-merge merges all disjuncts that the two parts have
  in common, while the union merge merges all disjuncts.

  Deprecated, because the projection merge to a non-zero union
  fraction gives poor results.

  Caution: this has been hacked to assume shapes (the #t flag is
  passed) and so this is not backwards compat with earlier behavior!

  See `make-merger` for the methods supplied by this object.

  STARS is the object holding the disjuncts. For example, it could
  be (add-dynamic-stars (make-pseudo-cset-api))

  CUTOFF is the min acceptable MI, for words to be considered
  mergable.

  UNION-FRAC is the fixed fraction of the union-set of the disjuncts
  that will be merged.

  NOISE is the smallest observation count, below which counts
  will not be divided up, if a marge is performed.

  MIN-CNT is the minimum count (l1-norm) of the observations of
  disjuncts that a word is allowed to have, to even be considered.
"
	(define pmi (add-symmetric-mi-compute STARS))

	(define (get-mi wa wb) (pmi 'mmt-fmi wa wb))
	(define (mpred WORD-A WORD-B)
		(is-similar? get-mi CUTOFF WORD-A WORD-B))

	; The fraction to merge is fixed.
	(define (mi-fract WA WB) UNION-FRAC)
	(define (redo-mmt WRD) (recompute-mmt STARS WRD))
	(define (finish)
		(define ptc (add-transpose-compute STARS))
		(store-atom (ptc 'set-mmt-totals)))

	(make-merger pmi mpred mi-fract NOISE MIN-CNT redo-mmt finish #t)
)

; ---------------------------------------------------------------

(define-public (make-midisc STARS CUTOFF NOISE MIN-CNT)
"
  make-midisc -- Return an object that can perform a mutual-information
                 projection-merge, with a tapered union-merge fraction.

  Uses the `merge-project` merge style. This adds a very small amount
  of the union-merge to the overlap-merge.  Recall that the
  overlap-merge merges all disjuncts that the two parts have in
  common, while the union merge merges all disjuncts.

  The tapering uses a merge fraction of
      1/2**(max(MI(a,a), MI(b,b))-CUTOFF)
  where MI(a,a) and MI(b,b) is the self-mutual information of the two
  items a and b to be merged.  This merge fraction is chosen such that,
  very roughly, the MI between the cluster, and the remainder of a and b
  after merging will be less than CUTOFF ... roughly. The formula is
  an inexact guesstimate. This could be improved.

  Deprecated, because the projection merge to a non-zero union
  fraction gives poor results.

  Caution: this has been hacked to assume shapes (the #t flag is
  passed) and so this is not backwards compat with earlier behavior!

  See `make-merger` for the methods supplied by this object.

  STARS is the object holding the disjuncts. For example, it could
  be (add-dynamic-stars (make-pseudo-cset-api))

  CUTOFF is the min acceptable MI, for words to be considered
  mergable.

  NOISE is the smallest observation count, below which counts
  will not be divided up, if a marge is performed.

  MIN-CNT is the minimum count (l1-norm) of the observations of
  disjuncts that a word is allowed to have, to even be considered.
"
	(define pss (add-support-api STARS))
	(define pmi (add-symmetric-mi-compute STARS))
	(define pti (add-transpose-api STARS))

	(define (get-mi wa wb) (pmi 'mmt-fmi wa wb))
	(define (mpred WORD-A WORD-B)
		(is-similar? get-mi CUTOFF WORD-A WORD-B))

	(define total-mmt-count (pti 'total-mmt-count))
	(define ol2 (/ 1.0 (log 2.0)))
	(define (log2 x) (* (log x) ol2))

	; The self-MI is just the same as (get-mi wrd wrd).
	; The below is faster than calling `get-mi`; it uses
	; cached values. Still, it would be better if we
	; stored a cached self-mi value.
	(define (get-self-mi wrd)
		(define len (pss 'right-length wrd))
		(define mmt (pti 'mmt-count wrd))
		(log2 (/ (* len len total-mmt-count) (* mmt mmt))))

	; The fraction to merge is a ballpark estimate that attempts
	; to make sure that the MI between the new cluster and the
	; excluded bits is less than the cutoff.
	(define (mi-fraction WA WB)
		(define mihi (max (get-self-mi WA) (get-self-mi WB)))
		(expt 2.0 (- CUTOFF mihi)))

	(define (redo-mmt WRD) (recompute-mmt STARS WRD))
	(define (finish)
		(define ptc (add-transpose-compute STARS))
		(store-atom (ptc 'set-mmt-totals)))

	(make-merger pmi mpred mi-fraction NOISE MIN-CNT redo-mmt finish #t)
)

; ---------------------------------------------------------------

(define-public (make-disinfo STARS CUTOFF NOISE MIN-CNT)
"
  make-disinfo -- Return an object that can perform a \"discriminating\"
                  merge, using MI for similarity.

  Deprecated. Based on diary results, this appears to give poor results.
  Suggest using either `make-mifuzz` with a zero or a very small union
  frac, or to use  `make-midisc`.

  Use `merge-project` style merging, with linear taper of the union-merge.
  This is the same as `merge-discrim` above, but using MI instead
  of cosine similarity.

  Caution: this has been hacked to assume shapes (the #t flag is
  passed) and so this is not backwards compat with earlier behavior!

  See `make-merger` for the methods supplied by this object.

  STARS is the object holding the disjuncts. For example, it could
  be (add-dynamic-stars (make-pseudo-cset-api))

  CUTOFF is the min acceptable MI, for words to be considered
  mergable.

  NOISE is the smallest observation count, below which counts
  will not be divided up, if a merge is performed.

  MIN-CNT is the minimum count (l1-norm) of the observations of
  disjuncts that a word is allowed to have, to even be considered.
"
	(define pss (add-support-api STARS))
	(define pmi (add-symmetric-mi-compute STARS))
	(define pti (add-transpose-api STARS))

	(define (get-mi wa wb) (pmi 'mmt-fmi wa wb))
	(define (mpred WORD-A WORD-B)
		(is-similar? get-mi CUTOFF WORD-A WORD-B))

	(define total-mmt-count (pti 'total-mmt-count))
	(define ol2 (/ 1.0 (log 2.0)))
	(define (log2 x) (* (log x) ol2))

	; The self-MI is just the same as (get-mi wrd wrd).
	; The below is faster than calling `get-mi`; it uses
	; cached values. Still, it would be better if we
	; stored a cached self-mi value.
	(define (get-self-mi wrd)
		(define len (pss 'right-length wrd))
		(define mmt (pti 'mmt-count wrd))
		(log2 (/ (* len len total-mmt-count) (* mmt mmt))))

	; The fraction to merge is a linear ramp, starting at zero
	; at the cutoff, and ramping up to one when these are very
	; similar.
	(define (mi-fraction WA WB)
		(define milo (min (get-self-mi WA) (get-self-mi WB)))
		(define fmi (get-mi WA WB))
		(/ (- fmi CUTOFF) (- milo CUTOFF)))

	(define (redo-mmt WRD) (recompute-mmt STARS WRD))
	(define (finish)
		(define ptc (add-transpose-compute STARS))
		(store-atom (ptc 'set-mmt-totals)))

	(make-merger pmi mpred mi-fraction NOISE MIN-CNT redo-mmt finish #t)
)

; ---------------------------------------------------------------
; Example usage
;
; (load-atoms-of-type 'WordNode)          ; Typically about 80 seconds
; (define pca (make-pseudo-cset-api))
; (define psa (add-dynamic-stars pca))
;
; Verify that support is correctly computed.
; cit-vil is a vector of pairs for matching sections for "city" "village".
; Note that the null list '() means 'no such section'
;
; (define (bogus a b) (format #t "Its ~A and ~A\n" a b))
; (define ptu (add-tuple-math psa bogus))
; (define cit-vil (ptu 'right-stars (list (Word "city") (Word "village"))))
; (length cit-vil)
;
; Show the first three values of the vector:
; (ptu 'get-count (car cit-vil))
; (ptu 'get-count (cadr cit-vil))
; (ptu 'get-count (caddr cit-vil))
;
; print the whole vector:
; (for-each (lambda (pr) (ptu 'get-count pr)) cit-vil)
;
; Is it OK to merge?
; (define pcos (add-similarity-compute psa))
; (is-cosine-similar? pcos (Word "run") (Word "jump"))
; (is-cosine-similar? pcos (Word "city") (Word "village"))
;
; Perform the actual merge
; (define (frac WA WB) 0.3)
; (define cls (WordClass "city-village"))
; (start-cluster psa cls (Word "city") (Word "village") frac 4.0 #t)
;
; Verify presence in the database:
; select count(*) from atoms where type=22;
