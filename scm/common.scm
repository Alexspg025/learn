;
; common.scm
;
; Common functions shared between multpile functional units.
;
; Copyright (c) 2017 Linas Vepstas
;
; ---------------------------------------------------------------------
;
(use-modules (srfi srfi-1))
(use-modules (opencog) (opencog persist))

; XXX TODO FIXME All users of the three functions below need to be
; converted into users of the add-count-api, add-storage-count and
; add-marginal-count API's. The three functions below are
; deprecated/obsolete.
; ---------------------------------------------------------------------

; get-count ATOM - return the raw observational count on ATOM.
(define-public (get-count ATOM) (cog-count ATOM))

; set-count ATOM CNT - Set the raw observational count on ATOM.
(define (set-count ATOM CNT) (cog-set-tv! ATOM (CountTruthValue 1 0 CNT)))

; ---------------------------------------------------------------------

(define (count-inc-atom ATM CNT)
"
  count-inc-atom ATM CNT -- increment the count by CNT on ATM, and
  update storage to hold that count.

  This will also automatically fetch the previous count from storage,
  so that counting will work correctly, when picking up from a previous
  point.

  Warning: this is NOT SAFE for distributed processing! That is
  because this does NOT grab the count from the database every time,
  so if some other process updates the database, this will miss that
  update. Multiple distributed counters will continue to clobber
  each-other indefinitely; the system will NOT settle-down long-term.

  See also: count-one-atom
"
	(define (incr-one atom)
		; If the atom doesn't yet have a count TV attached to it,
		; then its probably a freshly created atom. Go fetch it
		; from storage. Otherwise, assume that what we've got here,
		; in the atomspace, is the current copy.  This works if
		; there is only one process updating the counts.
		(if (not (cog-ctv? (cog-tv atom)))
			(fetch-atom atom)) ; get from storage
		(cog-inc-count! atom INC) ; increment
	)
	(begin
		(incr-one ATM) ; increment the count on ATM
		(store-atom ATM)) ; save to storage
)

(define (count-one-atom ATM)
"
  count-one-atom ATM -- increment the count by one on ATM, and
  update storage to hold that count.

  This will also automatically fetch the previous count from storage,
  so that counting will work correctly, when picking up from a previous
  point.

  Warning: this is NOT SAFE for distributed processing! That is
  because this does NOT grab the count from the database every time,
  so if some other process updates the database, this will miss that
  update. Multiple distributed counters will continue to clobber
  each-other indefinitely; the system will NOT settle-down long-term.

  See also: count-inc-atom
"
	(count-inc-atom ATM 1)
)

; ---------------------------------------------------------------------
