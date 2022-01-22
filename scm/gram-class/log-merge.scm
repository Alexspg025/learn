;
; log-merge.scm
;
; Create a log, in the atomspace, of assorted data collected during 
; the merge.
;
; Copyright (c) 2021 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; Data is recorded in the AtomSpace, so that it doesn't get lost.
;
; ---------------------------------------------------------------

(define (make-logger LLOBJ)
"
  make-logger LLOBJ -- create logger to record assorted info in AtomSpace
"
	(define *-log-anchor-* (LLOBJ 'wild-wild))

	(define log-mmt-q (make-data-logger *-log-anchor-* (Predicate "mmt-q")))
	(define log-ranked-mi (make-data-logger *-log-anchor-* (Predicate "ranked-mi")))
	(define log-sparsity (make-data-logger *-log-anchor-* (Predicate "sparsity")))
	(define log-entropy (make-data-logger *-log-anchor-* (Predicate "entropy")))
	(define log-left-dim (make-data-logger *-log-anchor-* (Predicate "left dim")))
	(define log-right-dim (make-data-logger *-log-anchor-* (Predicate "right dim")))
	(define log-left-cnt (make-data-logger *-log-anchor-* (Predicate "left-count")))
	(define log-right-cnt (make-data-logger *-log-anchor-* (Predicate "right-count")))
	(define log-size (make-data-logger *-log-anchor-* (Predicate "total entries")))

	(define (log2 x) (if (< 0 x) (/ (log x) (log 2)) -inf.0))

	(define (get-sparsity)
		(define sup (add-support-api LLOBJ))
		(define nrows (sup 'left-dim))
		(define ncols (sup 'right-dim))
		(define tot (* nrows ncols))
		(define lsize (sup 'total-support-left)) ; equal to total-support-right
		(log2 (/ tot lsize)))

	(define (get-mmt-entropy)
		(define tsr (add-transpose-api LLOBJ))
		(define mmt-support (tsr 'total-mmt-support))
		(define mmt-count (tsr 'total-mmt-count))
		(- (log2 (/ mmt-count (* mmt-support mmt-support)))))

	(define (get-ranked-mi PAIR)
		(define sap (add-similarity-api LLOBJ #f SIM-ID))
		(define miv (sap 'get-count PAIR))
		(if miv (cog-value-ref miv 1) -inf.0))

	; Log some maybe-useful data...
	(lambda (top-pair)
		(log-mmt-q ((add-symmetric-mi-compute LLOBJ) 'mmt-q))
		(log-ranked-mi (get-ranked-mi top-pair))

		(log-sparsity (get-sparsity))
		(log-entropy (get-mmt-entropy))

		; The left and right count should be always equal,
		; and should never change.  This is a sanity check.
		(define sup (add-support-api LLOBJ))
		(log-left-cnt (sup 'total-count-left))
		(log-right-cnt (sup 'total-count-right))

		; left and right dimensions (number of rows, columns)
		(log-left-dim (sup 'left-dim))
		(log-right-dim (sup 'right-dim))

		; Total number of non-zero entries
		(log-size (sup 'total-support-left))

		; Save to the DB
		(store-atom *-log-anchor-*)
	)
)

(define (make-class-logger LLOBJ)
"
  make-class-logger LLOBJ -- create logger to record merge details.
"
	(define *-log-anchor-* (LLOBJ 'wild-wild))

	; Record the classes as they are created.
	(define log-class (make-data-logger *-log-anchor-* (Predicate "class")))
	(define log-class-size (make-data-logger *-log-anchor-* (Predicate "class-size")))
	(define log-self-mi (make-data-logger *-log-anchor-* (Predicate "self-mi")))
	(define log-self-rmi (make-data-logger *-log-anchor-* (Predicate "self-ranked-mi")))

	; General setup of things we need
	(define sap (add-similarity-api LLOBJ #f SIM-ID))

	; The MI similarity of two words
	(define (mi-sim WA WB)
		(define miv (sap 'pair-count WA WB))
		(if miv (cog-value-ref miv 0) -inf.0))

	; The ranked MI similarity of two words
	(define (ranked-mi-sim WA WB)
		(define miv (sap 'pair-count WA WB))
		(if miv (cog-value-ref miv 1) -inf.0))

	(lambda (WCLASS)
		(log-class WCLASS)
		(log-class-size (cog-incoming-size-by-type WCLASS 'MemberLink))
		(log-self-mi (mi-sim WCLASS WCLASS))
		(log-self-rmi (ranked-mi-sim WCLASS WCLASS))
		(store-atom *-log-anchor-*)
	)
)

; ---------------------------------------------------------------

(define (print-params LLOBJ PORT)
"
  print-params LLOBJ PORT -- print parameters header.
"
	(define *-log-anchor-* (LLOBJ 'wild-wild))

	(define params (cog-value->list
		(cog-value *-log-anchor-* (Predicate "quorum-comm-noise"))))
	(define quorum (list-ref params 0))
	(define commonality (list-ref params 1))
	(define noise (list-ref params 2))
	(define nrank (list-ref params 3))

	(format PORT "# quorum=~6F commonality=~6F noise=~D nrank=~A\n#\n"
		quorum commonality noise nrank)
)

(define-public (print-log LLOBJ PORT)
"
  print-log LLOBJ PORT -- Dump log contents as CSV
  Set PORT to #t to get output to stdout
"
	(define key-mmt-q (Predicate "mmt-q"))
	(define key-ranked-mi (Predicate "ranked-mi"))
	(define key-sparsity (Predicate "sparsity"))
	(define key-entropy (Predicate "entropy"))
	(define key-left-dim (Predicate "left dim"))
	(define key-right-dim (Predicate "right dim"))
	(define key-left-cnt (Predicate "left-count"))
	(define key-right-cnt (Predicate "right-count"))
	(define key-size (Predicate "total entries"))
	(define key-class (Predicate "class"))

	(define *-log-anchor-* (LLOBJ 'wild-wild))
	(define rows (cog-value->list (cog-value *-log-anchor-* key-left-dim)))
	(define cols (cog-value->list (cog-value *-log-anchor-* key-right-dim)))
	(define lcnt (cog-value->list (cog-value *-log-anchor-* key-left-cnt)))
	(define rcnt (cog-value->list (cog-value *-log-anchor-* key-right-cnt)))
	(define size (cog-value->list (cog-value *-log-anchor-* key-size)))
	(define spar (cog-value->list (cog-value *-log-anchor-* key-sparsity)))
	(define entr (cog-value->list (cog-value *-log-anchor-* key-entropy)))
	(define rami (cog-value->list (cog-value *-log-anchor-* key-ranked-mi)))
	(define mmtq (cog-value->list (cog-value *-log-anchor-* key-mmt-q)))
	; (define clas (cog-value->list (cog-value *-log-anchor-* key-class)))

	(define len (length rows))

	(format PORT "#\n# Log of merge statistics\n#\n")
	(print-params LLOBJ PORT)
	(format PORT "# N,rows,cols,lcnt,rcnt,size,sparsity,entropy,ranked-mi,mmt-q\n")
	(for-each (lambda (N)
		(format PORT "~D\t~A\t~A\t~A\t~A\t~A\t~9F\t~9F\t~9F\t~9F\n"
			(+ N 1)
			(inexact->exact (list-ref rows N))
			(inexact->exact (list-ref cols N))
			(inexact->exact (list-ref lcnt N))
			(inexact->exact (list-ref rcnt N))
			(inexact->exact (list-ref size N))
			(list-ref spar N)
			(list-ref entr N)
			(list-ref rami N)
			(list-ref mmtq N)))
		(iota len))
)

(define-public (print-merges LLOBJ PORT)
"
  print-merges LLOBJ PORT -- Dump merge log contents as CSV
  Set PORT to #t to get output to stdout
"
	(define key-class (Predicate "class"))
	(define key-class-size (Predicate "class-size"))
	(define key-self-mi (Predicate "self-mi"))
	(define key-self-rmi (Predicate "self-ranked-mi"))

	(define *-log-anchor-* (LLOBJ 'wild-wild))
	(define classes (cog-value->list (cog-value *-log-anchor-* key-class)))
	(define class-size (cog-value->list (cog-value *-log-anchor-* key-class-size)))
	(define self-mi (cog-value->list (cog-value *-log-anchor-* key-self-mi)))
	(define self-rmi (cog-value->list (cog-value *-log-anchor-* key-self-rmi)))

	(define len (length classes))

	(format PORT "#\n# Log of merge statistics\n#\n")
	(print-params LLOBJ PORT)
	(format PORT "# N,words,class-size,self-mi,self-rmi\n")
	(for-each (lambda (N)
		(format PORT "~D\t\"~A\"\t~D\t~9F\t~9F\n"
			(+ N 1)
			(cog-name (list-ref classes N))
			(list-ref class-size N)
			(list-ref self-mi N)
			(list-ref self-rmi N)))
		(iota len))
)

; ---------------------------------------------------------------

(define-public (dump-log LLOBJ DIR)
"
  dump-log LLOBJ DIR -- print log file to DIR.
  Example: (dump-log \"/tmp\")
  Result: \"/tmp/log-0.5-0.2.dat\" where 0.5 is the quorum, and 0.2
  the commonality.
"
	(define *-log-anchor-* (LLOBJ 'wild-wild))
	(define params (cog-value->list
		(cog-value *-log-anchor-* (Predicate "quorum-comm-noise"))))
	(define quorum (list-ref params 0))
	(define commonality (list-ref params 1))
	(define FILENAME (format #f "~A/log-~A-~A.dat" DIR quorum commonality))
	(define port (open FILENAME (logior O_CREAT O_WRONLY)))
	(print-log LLOBJ port)
	(close port)
)

(define-public (dump-merges LLOBJ DIR)
"
  dump-merges LLOBJ DIR -- print merge file to DIR.
  Example: (dump-merges \"/tmp\")
  Result: \"/tmp/merge-0.5-0.2.dat\" where 0.5 is the quorum, and 0.2
  the commonality.
"
	(define *-log-anchor-* (LLOBJ 'wild-wild))
	(define params (cog-value->list
		(cog-value *-log-anchor-* (Predicate "quorum-comm-noise"))))
	(define quorum (list-ref params 0))
	(define commonality (list-ref params 1))
	(define FILENAME (format #f "~A/merges-~A-~A.dat" DIR quorum commonality))
	(define port (open FILENAME (logior O_CREAT O_WRONLY)))
	(print-merges LLOBJ port)
	(close port)
)

; ---------------------------------------------------------------
#! ========
;
; Example usage

(print-log #t)
(print-merges #t)

==== !#
